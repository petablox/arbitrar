use llir::{types::*, Module};
use rayon::prelude::*;
use serde::Deserialize;
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;

use crate::feature_extractors::*;
use crate::options::*;
use crate::semantics::boxed::*;
use crate::utils::*;

#[derive(Deserialize)]
pub struct Slice {
  pub instr: String,
  pub entry: String,
  pub caller: String,
  pub callee: String,
  pub functions: Vec<String>,
}

impl Slice {}

#[derive(Deserialize)]
pub struct Instr {
  pub loc: String,
  pub sem: Semantics,
  pub res: Option<Value>,
}

#[derive(Deserialize)]
pub struct Trace {
  pub target: usize,
  pub instrs: Vec<Instr>,
}

#[derive(Copy, Clone, PartialEq, Eq)]
pub enum TraceIterDirection {
  Forward,
  Backward,
}

impl TraceIterDirection {
  pub fn is_forward(&self) -> bool {
    self == &Self::Forward
  }
}

impl Trace {
  pub fn target_result(&self) -> &Option<Value> {
    &self.target_instr().res
  }

  pub fn target_instr(&self) -> &Instr {
    &self.instrs[self.target]
  }

  pub fn target_args(&self) -> Vec<&Value> {
    self.target_instr().sem.call_args()
  }

  pub fn target_arg(&self, index: usize) -> Option<&Value> {
    self.target_instr().sem.call_arg(index)
  }

  pub fn target_index(&self) -> usize {
    self.target
  }

  pub fn iter_instrs(&self, dir: TraceIterDirection) -> Vec<(usize, &Instr)> {
    if dir.is_forward() {
      self.instrs.iter().enumerate().collect()
    } else {
      self.instrs.iter().rev().enumerate().collect()
    }
  }

  pub fn iter_instrs_from_target(&self, dir: TraceIterDirection) -> Vec<(usize, &Instr)> {
    self.iter_instrs_from(dir, self.target)
  }

  pub fn iter_instrs_from(&self, dir: TraceIterDirection, from: usize) -> Vec<(usize, &Instr)> {
    if dir.is_forward() {
      self.instrs.iter().enumerate().skip(from + 1).collect::<Vec<_>>()
    } else {
      self.instrs.iter().enumerate().take(from).rev().collect::<Vec<_>>()
    }
  }
}

pub trait FeatureExtractorOptions: IOOptions + Send + Sync {
  fn causality_dictionary_size(&self) -> usize;
}

pub trait FeatureExtractor: Send + Sync {
  fn name(&self) -> String;

  fn filter<'ctx>(&self, target: &String, target_type: FunctionType<'ctx>) -> bool;

  fn init(&mut self, slice_id: usize, slice: &Slice, num_traces: usize, trace: &Trace);

  fn finalize(&mut self);

  fn extract(&self, slice_id: usize, slice: &Slice, trace: &Trace) -> serde_json::Value;
}

pub struct FeatureExtractors {
  extractors: Vec<Box<dyn FeatureExtractor>>,
}

impl FeatureExtractors {
  pub fn all(options: &impl FeatureExtractorOptions) -> Self {
    Self {
      extractors: vec![
        Box::new(ReturnValueFeatureExtractor::new()),
        Box::new(ReturnValueCheckFeatureExtractor::new()),
        Box::new(ArgumentPreconditionFeatureExtractor::new(0)),
        Box::new(ArgumentPreconditionFeatureExtractor::new(1)),
        Box::new(ArgumentPreconditionFeatureExtractor::new(2)),
        Box::new(ArgumentPreconditionFeatureExtractor::new(3)),
        Box::new(ArgumentPreconditionFeatureExtractor::new(4)),
        Box::new(ArgumentPreconditionFeatureExtractor::new(5)),
        Box::new(ArgumentPreconditionFeatureExtractor::new(6)),
        Box::new(ArgumentPostconditionFeatureExtractor::new(0)),
        Box::new(ArgumentPostconditionFeatureExtractor::new(1)),
        Box::new(ArgumentPostconditionFeatureExtractor::new(2)),
        Box::new(ArgumentPostconditionFeatureExtractor::new(3)),
        Box::new(ArgumentPostconditionFeatureExtractor::new(4)),
        Box::new(ArgumentPostconditionFeatureExtractor::new(5)),
        Box::new(ArgumentPostconditionFeatureExtractor::new(6)),
        Box::new(CausalityFeatureExtractor::pre(options.causality_dictionary_size())),
        Box::new(CausalityFeatureExtractor::post(options.causality_dictionary_size())),
        Box::new(ControlFlowFeaturesExtractor::new()),
      ],
    }
  }

  pub fn extractors_for_target<'ctx>(
    target: &String,
    target_type: FunctionType<'ctx>,
    options: &impl FeatureExtractorOptions,
  ) -> Self {
    Self {
      extractors: Self::all(options)
        .extractors
        .into_iter()
        .filter(|extractor| extractor.filter(target, target_type))
        .collect(),
    }
  }

  pub fn initialize(&mut self, slice_id: usize, slice: &Slice, num_traces: usize, trace: &Trace) {
    for extractor in &mut self.extractors {
      extractor.init(slice_id, slice, num_traces, trace);
    }
  }

  pub fn finalize(&mut self) {
    for extractor in &mut self.extractors {
      extractor.finalize();
    }
  }

  pub fn extract_features(&self, slice_id: usize, slice: &Slice, trace: &Trace) -> serde_json::Value {
    let mut map = serde_json::Map::new();
    for extractor in &self.extractors {
      map.insert(extractor.name(), extractor.extract(slice_id, &slice, &trace));
    }
    serde_json::Value::Object(map)
  }
}

pub struct FeatureExtractionContext<'a, 'ctx, O>
where
  O: FeatureExtractorOptions + IOOptions,
{
  pub modules: &'a Module<'ctx>,
  pub options: &'a O,
  pub target_num_slices_map: HashMap<String, usize>,
  pub func_types: HashMap<String, FunctionType<'ctx>>,
}

impl<'a, 'ctx, O> FeatureExtractionContext<'a, 'ctx, O>
where
  O: FeatureExtractorOptions + IOOptions,
{
  pub fn new(
    module: &'a Module<'ctx>,
    target_num_slices_map: HashMap<String, usize>,
    options: &'a O,
  ) -> Result<Self, String> {
    let func_types = module.function_types();
    Ok(Self {
      modules: module,
      options,
      target_num_slices_map,
      func_types,
    })
  }

  pub fn load_slices(&self, target: &String, num_slices: usize) -> Vec<Slice> {
    (0..num_slices)
      .collect::<Vec<_>>()
      .into_par_iter()
      .map(|slice_id| {
        let path = self.options.slice_target_file_path(target.as_str(), slice_id);
        load_json_t(&path).expect("Cannot load slice files")
      })
      .collect::<Vec<_>>()
  }

  pub fn load_trace_file_paths(&self, target: &String, slice_id: usize) -> Vec<(usize, PathBuf)> {
    match fs::read_dir(self.options.trace_target_slice_dir(target.as_str(), slice_id)) {
      Ok(paths) => paths.map(|path| {
        let path = path.expect("Cannot read traces folder path").path();
        let trace_id = path.file_stem().unwrap().to_str().unwrap().parse::<usize>().unwrap();
        (trace_id, path)
      })
      .collect::<Vec<_>>(),
      _ => vec![]
    }
  }

  pub fn load_trace(&self, path: &PathBuf) -> Result<Trace, String> {
    load_json_t(path)
  }

  pub fn extract_features(&self, _: &mut LoggingContext) {
    fs::create_dir_all(self.options.feature_dir()).expect("Cannot create features directory");

    self.target_num_slices_map.par_iter().for_each(|(target, &num_slices)| {
      // Initialize extractors
      let func_type = self.func_types[target];
      let mut extractors = FeatureExtractors::extractors_for_target(&target, func_type, self.options);

      // logging_ctx.log(&format!("[{}]", extractors.extractors.iter().map(|e| e.name()).collect::<Vec<_>>().join(", "))).unwrap();

      // Load slices
      let slices = self.load_slices(&target, num_slices);

      // logging_ctx.log("Loaded all slices").unwrap();

      // Initialize while loading traces
      (0..num_slices).for_each(|slice_id| {
        let slice = &slices[slice_id];
        let traces = self
          .load_trace_file_paths(&target, slice_id)
          .into_iter()
          .map(|(trace_id, dir_entry)| {
            use std::io::Write;
            print!("Loading slice {} trace {}\r", slice_id, trace_id);
            std::io::stdout().flush().unwrap();

            let trace = self.load_trace(&dir_entry);
            trace
          })
          .collect::<Vec<_>>();
        let num_traces = traces.len();

        for trace in traces {
          match trace {
            Ok(trace) => extractors.initialize(slice_id, slice, num_traces, &trace),
            _ => {}
          }
        }
      });

      // logging_ctx.log("Initialized extractors").unwrap();

      // Finalize feature extractor initialization
      extractors.finalize();

      // logging_ctx.log("Finalized extractors").unwrap();

      // Extract features
      slices.par_iter().enumerate().for_each(|(slice_id, slice)| {
        // First create directory
        fs::create_dir_all(self.options.feature_target_slice_dir(target.as_str(), slice_id))
          .expect("Cannot create features target slice directory");

        // Then load trace file directories
        self
          .load_trace_file_paths(&target, slice_id)
          .into_par_iter()
          .for_each(|(trace_id, dir_entry)| {
            // Load trace json
            let trace = self.load_trace(&dir_entry);

            match trace {
              Ok(trace) => {
                // Extract and dump features
                let features = extractors.extract_features(slice_id, slice, &trace);
                let path = self
                  .options
                  .feature_target_slice_file_path(target.as_str(), slice_id, trace_id);
                dump_json(&features, path).expect("Cannot dump features json");
              }
              _ => {}
            }
          })
      });
    });
  }
}
