use clap::App;
use std::collections::HashMap;
use serde_json::json;
use petgraph::*;

use analyzer::{call_graph::*, options::*, utils::*};

fn arg_parser<'a>() -> App<'a> {
  let app = App::new("analyzer");
  Options::setup_parser(app)
}

fn main() -> Result<(), String> {
  let options = Options::from_matches(&arg_parser().get_matches())?;
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
    let num_call_sites = call_graph.graph.edges_directed(node_id, Direction::Incoming).count();
    *map.entry(func).or_insert(0) += num_call_sites;
  }

  // Transform occurrence map into json
  std::fs::create_dir_all(options.occurrence_path()).expect("Cannot create occurrence path");
  let json_map : serde_json::Map<_, _> = map.into_iter().map(|(func, num_call_sites)| (func.simp_name(), json!(num_call_sites))).collect();
  let json_obj = serde_json::Value::Object(json_map);
  dump_json(&json_obj, options.occurrence_file_path())
}
