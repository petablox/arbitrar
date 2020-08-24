use llir::{types::*, Module};
use rayon::prelude::*;
use serde::Deserialize;
use std::collections::HashMap;
use std::fs;
use std::fs::File;
use std::io::Write;
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
  pub trace_id: usize,
  pub target: usize,
  pub instrs: Vec<Instr>,
}

pub trait FeatureExtractor: Send + Sync {
  fn name(&self) -> String;

  fn filter<'ctx>(&self, target: &String, target_type: FunctionType<'ctx>) -> bool;

  fn init(&mut self, slice: &Slice, trace: &Trace);

  fn extract(&self, slice: &Slice, trace: &Trace) -> serde_json::Value;
}

pub type FeatureExtractors = Vec<Box<dyn FeatureExtractor>>;

pub trait DefaultExtractorsTrait {
  fn all_extractors() -> FeatureExtractors;

  fn extractors_for_target<'ctx>(target: &String, target_type: FunctionType<'ctx>) -> FeatureExtractors;

  fn initialize(&mut self, slice: &Slice, trace: &Trace);

  fn extract_features(&self, slice: &Slice, trace: &Trace) -> serde_json::Value;
}

impl DefaultExtractorsTrait for FeatureExtractors {
  fn all_extractors() -> Self {
    vec![
      Box::new(ReturnValueFeatureExtractor::new()),
      Box::new(ArgumentValueFeatureExtractor::new(0)),
      Box::new(ArgumentValueFeatureExtractor::new(1)),
      Box::new(ArgumentValueFeatureExtractor::new(2)),
      Box::new(ArgumentValueFeatureExtractor::new(3)),
    ]
  }

  fn extractors_for_target<'ctx>(target: &String, target_type: FunctionType<'ctx>) -> Self {
    Self::all_extractors()
      .into_iter()
      .filter(|extractor| extractor.filter(target, target_type))
      .collect()
  }

  fn initialize(&mut self, slice: &Slice, trace: &Trace) {
    for extractor in self {
      extractor.init(slice, trace);
    }
  }

  fn extract_features(&self, slice: &Slice, trace: &Trace) -> serde_json::Value {
    let mut map = serde_json::Map::new();
    for extractor in self {
      map.insert(extractor.name(), extractor.extract(&slice, &trace));
    }
    serde_json::Value::Object(map)
  }
}

pub struct FeatureExtractionContext<'a, 'ctx> {
  pub module: &'a Module<'ctx>,
  pub options: &'a Options,
  pub target_num_slices_map: HashMap<String, usize>,
  pub func_types: HashMap<String, FunctionType<'ctx>>,
}

impl<'a, 'ctx> FeatureExtractionContext<'a, 'ctx> {
  pub fn new(
    module: &'a Module<'ctx>,
    target_num_slices_map: HashMap<String, usize>,
    options: &'a Options,
  ) -> Result<Self, String> {
    let func_types = module.function_types();
    Ok(Self {
      module,
      options,
      target_num_slices_map,
      func_types,
    })
  }

  pub fn load_slices(&self, target: &String, num_slices: usize) -> Vec<Slice> {
    (0..num_slices)
      .collect::<Vec<_>>()
      .par_iter()
      .map(|slice_id| {
        let path = self.options.slice_file_path(target.as_str(), *slice_id);
        let file = File::open(path).expect("Could not open slice file");
        serde_json::from_reader(file).expect("Cannot parse slice file")
      })
      .collect::<Vec<_>>()
  }

  pub fn load_trace_file_paths(&self, target: &String, slice_id: usize) -> Vec<PathBuf> {
    fs::read_dir(self.options.trace_target_slice_dir_path(target.as_str(), slice_id))
      .expect("Cannot read traces folder")
      .map(|path| path.expect("Cannot read traces folder path").path())
      .collect::<Vec<_>>()
  }

  pub fn extract_features(&self) {
    fs::create_dir_all(self.options.features_dir_path()).expect("Cannot create features directory");

    self.target_num_slices_map.par_iter().for_each(|(target, &num_slices)| {
      // Initialize extractors
      let func_type = self.func_types[target];
      let mut extractors = FeatureExtractors::extractors_for_target(&target, func_type);

      // Load slices
      let slices = self.load_slices(&target, num_slices);

      // Initialize while loading traces
      (0..num_slices).for_each(|slice_id| {
        let slice = &slices[slice_id];
        let traces = self
          .load_trace_file_paths(&target, slice_id)
          .par_iter()
          .map(|dir_entry| -> Trace {
            let file = File::open(dir_entry).expect("Could not open trace file");
            serde_json::from_reader(file).expect("Cannot parse trace file")
          })
          .collect::<Vec<_>>();
        for trace in traces {
          extractors.initialize(slice, &trace);
        }
      });

      // Extract features
      slices.par_iter().enumerate().for_each(|(slice_id, slice)| {
        // First create directory
        fs::create_dir_all(self.options.features_target_slice_dir_path(target.as_str(), slice_id))
          .expect("Cannot create features target slice directory");

        // Then load trace file directories
        self
          .load_trace_file_paths(&target, slice_id)
          .par_iter()
          .enumerate()
          .for_each(|(trace_id, dir_entry)| {
            // Load trace json
            let trace_file = File::open(dir_entry).expect("Could not open trace file");
            let trace: Trace = serde_json::from_reader(trace_file).expect("Cannot parse trace file");

            // Extract and dump features
            let features = extractors.extract_features(slice, &trace);
            let features_str = serde_json::to_string(&features).expect("Cannot stringify features json");
            let mut features_file = File::create(self.options.features_file_path(target.as_str(), slice_id, trace_id))
              .expect("Cannot create features file");
            features_file
              .write_all(features_str.as_bytes())
              .expect("Cannot write to features file");
          })
      });
    });
  }
}
