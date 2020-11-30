use petgraph::*;
use serde_json::json;
use std::collections::HashMap;
use std::path::PathBuf;
use structopt::StructOpt;

use analyzer::{call_graph::*, options::*, utils::*};
use llir::values::*;

#[derive(StructOpt, Debug, Clone)]
#[structopt(name = "occurrence")]
pub struct Options {
  #[structopt(index = 1, required = true, value_name = "INPUT")]
  pub input: String,

  #[structopt(index = 2, required = true, value_name = "OUTPUT")]
  pub output: String,

  #[structopt(long, value_name = "LOCATION")]
  pub location: Option<String>,
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

impl CallGraphOptions for Options {
  fn remove_llvm_funcs(&self) -> bool {
    true
  }
}

impl Options {
  pub fn input_bc_name(&self) -> String {
    format!("{}", self.input_path().file_name().unwrap().to_str().unwrap())
  }

  fn occurrence_path(&self) -> PathBuf {
    self.output_path().join("occurrences")
  }

  fn occurrence_file_path(&self) -> PathBuf {
    let name = match &self.location {
      Some(l) => format!("{}_{}.json", self.input_bc_name(), l),
      None => format!("{}.json", self.input_bc_name())
    };
    self.occurrence_path().join(name)
  }
}

fn include_function<'ctx>(f: &Function<'ctx>, options: &Options) -> bool {
  match &options.location {
    Some(l) => {
      f.debug_loc_string().contains(l)
    }
    _ => true
  }
}

fn main() -> Result<(), String> {
  let options = Options::from_args();
  let mut logging_ctx = LoggingContext::new(&options)?;

  // Load the byte code module and generate analyzer context
  logging_ctx.log_loading_bc()?;
  let llctx = llir::Context::create();
  let llmod = llctx
    .load_module(&options.input_path())
    .map_err(|err| err.to_string())?;

  // Generate call graph
  logging_ctx.log_generating_call_graph()?;
  let call_graph = CallGraph::from_module(&llmod, &options);

  // Generate occurrence map
  let mut map = HashMap::new();
  for node_id in call_graph.graph.node_indices() {
    let func = call_graph.graph[node_id];
    if include_function(&func, &options) {
      let num_call_sites = call_graph.graph.edges_directed(node_id, Direction::Incoming).count();
      *map.entry(func).or_insert(0) += num_call_sites;
    }
  }

  // Transform occurrence map into json
  std::fs::create_dir_all(options.occurrence_path()).expect("Cannot create occurrence path");
  let json_map: serde_json::Map<_, _> = map
    .into_iter()
    .map(|(func, num_call_sites)| (func.simp_name(), json!(num_call_sites)))
    .collect();
  let json_obj = serde_json::Value::Object(json_map);
  dump_json(&json_obj, options.occurrence_file_path())
}
