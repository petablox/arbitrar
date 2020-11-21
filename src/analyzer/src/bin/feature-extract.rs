use llir::{types::*, *};
use rayon::prelude::*;
use serde::Deserialize;
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use structopt::StructOpt;

use analyzer::feature_extraction::*;
use analyzer::options::*;
use analyzer::utils::*;

#[derive(StructOpt, Debug)]
#[structopt(name = "feature-extract")]
pub struct Options {
  #[structopt(index = 1, required = true, value_name = "INPUT")]
  input: String,

  #[structopt(index = 2, required = true, value_name = "OUTPUT")]
  output: String,

  #[structopt(long, default_value = "10")]
  causality_dictionary_size: usize,
}

impl IOOptions for Options {
  fn input_path(&self) -> PathBuf {
    PathBuf::from(&self.input)
  }

  fn output_path(&self) -> PathBuf {
    PathBuf::from(&self.output)
  }

  fn default_package(&self) -> Option<&str> {
    None
  }
}

impl FeatureExtractorOptions for Options {
  fn causality_dictionary_size(&self) -> usize {
    self.causality_dictionary_size
  }
}

/// Read input file
///
/// {
///   "packages": [
///     {
///       "name": "PACKAGE_NAME",
///       "dir": "PACKAGE_DIRECTORY",
///     },
///     ...
///   ],
///   "functions": [
///     {
///       "name": "FUNCTION_NAME"
///       "occurrences": [
///         ["PACKAGE_NAME_1", NUM_SLICES_1],
///         ["PACKAGE_NAME_2", NUM_SLICES_2],
///         ...
///       ],
///     }
///
///     ...
///   ]
/// }

#[derive(Deserialize)]
pub struct InputPackages {
  pub name: String,
  pub dir: String,
}

#[derive(Deserialize)]
pub struct InputFunction {
  pub name: String,

  /// (Package Name, Num Slices)
  pub occurrences: Vec<(String, usize)>,
}

#[derive(Deserialize)]
pub struct Input {
  pub packages: Vec<InputPackages>,
  pub functions: Vec<InputFunction>,
}

impl Input {
  pub fn from_options(options: &Options) -> Self {
    load_json_t(&options.input_path()).expect("Cannot load input")
  }
}

pub type TargetPackageNumSlicesMap = HashMap<String, Vec<(String, usize)>>;

pub type Packages<'ctx> = HashMap<String, (Module<'ctx>, HashMap<String, FunctionType<'ctx>>)>;

fn load_slice(path: PathBuf) -> Slice {
  load_json_t(&path).expect("Cannot load slice file")
}

fn load_slices(options: &Options, target: &str, package: &str, num_slices: usize) -> Vec<Slice> {
  (0..num_slices)
    .collect::<Vec<_>>()
    .into_par_iter()
    .map(|slice_id| {
      let path = options.slice_target_package_file_path(target, package, slice_id);
      load_slice(path)
    })
    .collect::<Vec<_>>()
}

fn load_trace_file_paths(options: &Options, target: &str, package: &str, slice_id: usize) -> Vec<(usize, PathBuf)> {
  fs::read_dir(options.trace_target_package_slice_dir(target, package, slice_id))
    .expect("Cannot read traces folder")
    .map(|path| {
      let path = path.expect("Cannot read traces folder path").path();
      let trace_id = path.file_stem().unwrap().to_str().unwrap().parse::<usize>().unwrap();
      (trace_id, path)
    })
    .collect::<Vec<_>>()
}

pub fn load_trace(path: PathBuf) -> Trace {
  load_json_t(&path).expect("Cannot load trace file")
}

pub fn func_types<'ctx>(packages: &Packages<'ctx>, target: &str) -> Option<FunctionType<'ctx>> {
  for (_, (_, types)) in packages.iter() {
    if types.contains_key(target) {
      return Some(types[target]);
    }
  }
  return None;
}

fn main() -> Result<(), String> {
  let options = Options::from_args();
  let input = Input::from_options(&options);

  println!("Loading modules...");

  let llctx = Context::create();
  let mut packages = Packages::new();
  for inp_pkg in input.packages {
    let module = llctx.load_module(inp_pkg.dir).expect("Cannot load module");
    let func_types = module.function_types();
    packages.insert(inp_pkg.name, (module, func_types));
  }

  if packages.is_empty() {
    return Err("No packages included".to_string());
  }

  println!("Building target map...");

  let mut target_map = TargetPackageNumSlicesMap::new();
  for input_function in input.functions {
    target_map.insert(input_function.name, input_function.occurrences);
  }

  target_map.into_par_iter().for_each(|(target, package_num_slices)| {
    let func_type = func_types(&packages, &target).unwrap();

    let mut extractors = FeatureExtractors::extractors_for_target(&target, func_type, &options);

    println!("Initializing feature extractors for {}...", target);

    for (package, num_slices) in &package_num_slices {
      let slices = load_slices(&options, &target, &package, num_slices.clone());
      (0..num_slices.clone()).for_each(|slice_id| {
        let slice = &slices[slice_id];
        let traces = load_trace_file_paths(&options, &target, &package, slice_id)
          .into_par_iter()
          .map(|(_, dir_entry)| load_trace(dir_entry))
          .collect::<Vec<_>>();
        let num_traces = traces.len();
        for trace in traces {
          extractors.initialize(slice, num_traces, &trace);
        }
      });
    }

    extractors.finalize();

    println!("Extracting features for {}...", target);

    package_num_slices.into_par_iter().for_each(|(package, num_slices)| {
      let slices = load_slices(&options, &target, &package, num_slices);
      slices.into_par_iter().enumerate().for_each(|(slice_id, slice)| {
        // First create directory
        fs::create_dir_all(options.feature_target_package_slice_dir(&target, &package, slice_id))
          .expect("Cannot create features target slice directory");

        // Then load trace file directories
        load_trace_file_paths(&options, &target, &package, slice_id)
          .into_par_iter()
          .for_each(|(trace_id, dir_entry)| {
            let trace = load_trace(dir_entry);
            let features = extractors.extract_features(&slice, &trace);
            let path = options.feature_target_package_slice_file_path(&target, &package, slice_id, trace_id);
            dump_json(&features, path).expect("Cannot dump features json");
          });
      })
    })
  });

  Ok(())
}
