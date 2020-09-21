use std::collections::HashMap;
use std::fs;
use std::fs::File;
use std::path::PathBuf;
use rayon::prelude::*;
use llir::{*, types::*};

use analyzer::feature_extraction::*;
use analyzer::utils::*;

pub struct Options {

}

impl Options {
  pub fn new() -> Self {
    Self {}
  }
}

impl FeatureExtractorOptions for Options {
  fn causality_dictionary_size(&self) -> usize {
    10
  }
}

pub type TargetPackageNumSlicesMap = HashMap<String, Vec<(String, usize)>>;

pub type Packages<'a, 'ctx> = HashMap<String, (&'a Module<'ctx>, HashMap<String, FunctionType<'ctx>>)>;

fn load_slices(target: &str, package: &str, num_slices: usize) -> Vec<Slice> {
  vec![]
}

fn load_trace_file_paths(target: &str, package: &str, slice_id: usize) -> Vec<(usize, PathBuf)> {
  vec![]
}

fn features_target_slice_dir_path(target: &str, package: &str, slice_id: usize) -> PathBuf {
  PathBuf::new()
}

fn features_file_path(target: &str, package: &str, slice_id: usize, trace_id: usize) -> PathBuf {
  features_target_slice_dir_path(target, package, slice_id).join(format!("{}.json", trace_id))
}

pub fn load_trace(path: PathBuf) -> Trace {
  let trace_file = File::open(path).expect("Could not open trace file");
  serde_json::from_reader(trace_file).expect("Cannot parse trace file")
}

fn main() -> Result<(), String> {
  let options = Options::new();
  // let options = Options::from_matches(&arg_parser().get_matches())?;

  let llctx = Context::create();
  let packages = Packages::new();

  if packages.is_empty() {
    return Err("No packages included".to_string())
  }

  let target_map = TargetPackageNumSlicesMap::new();
  target_map.into_par_iter().for_each(|(target, package_num_slices)| {
    let (_, func_types) = &packages[&package_num_slices[0].0];
    let func_type = func_types[&target];

    let mut extractors = FeatureExtractors::extractors_for_target(&target, func_type, &options);

    for (package, num_slices) in &package_num_slices {
      let slices = load_slices(&target, &package, num_slices.clone());
      (0..num_slices.clone()).for_each(|slice_id| {
        let slice = &slices[slice_id];
        let traces = load_trace_file_paths(&target, &package, slice_id)
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

    package_num_slices.into_par_iter().for_each(|(package, num_slices)| {
      let slices = load_slices(&target, &package, num_slices);
      slices.into_par_iter().enumerate().for_each(|(slice_id, slice)| {
        // First create directory
        fs::create_dir_all(features_target_slice_dir_path(&target, &package, slice_id))
          .expect("Cannot create features target slice directory");

        // Then load trace file directories
        load_trace_file_paths(&target, &package, slice_id)
          .into_par_iter()
          .for_each(|(trace_id, dir_entry)| {
            let trace = load_trace(dir_entry);
            let features = extractors.extract_features(&slice, &trace);
            let path = features_file_path(&target, &package, slice_id, trace_id);
            dump_json(&features, path).expect("Cannot dump features json");
          });
      })
    })
  });

  Ok(())
}