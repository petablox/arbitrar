use clap::{App, ArgMatches};
use std::path::Path;

use analyzer::*;
use call_graph::*;
use context::*;
use feature_extraction::*;
use options::*;
use slicer::*;
use symbolic_execution::*;
use utils::*;

fn arg_parser<'a>() -> App<'a> {
  let app = App::new("analyzer");
  Options::setup_parser(app)
}

fn main() -> Result<(), String> {
  let options = Options::from_matches(&arg_parser().get_matches())?;
  let mut logging_ctx = LoggingContext::new(&options)?;

  // Load the byte code module and generate analyzer context
  logging_ctx.log("Loading byte code file and creating context...")?;
  let llctx = llir::Context::create();
  let llmod = llctx.load_module(&options.input_path()).map_err(|err| err.to_string())?;

  // Generate call graph
  logging_ctx.log("Generating call graph...")?;
  let call_graph = CallGraph::from_module(&llmod, &options);

  // Finding call edges
  logging_ctx.log("Finding relevant call edges...")?;
  let target_edges_map = TargetEdgesMap::from_call_graph(&call_graph, &options)?;

  // Generate slices
  let target_slices_map = TargetSlicesMap::from_target_edges_map(&target_edges_map, &options);

  // // Divide target edges into batches
  // logging_ctx.log("{} relevant call edges found...")?;
  // for (i, batched_target_edges_map) in target_edges_map.batches(slicer_options.use_batch, slicer_options.batch_size) {
  //   if slicer_options.use_batch {
  //     logging_ctx.log(format!("Analyzing batch #{} with {} call edges", i, batched_target_edges_map.num_elements()).as_str())?;
  //   }

  //   // Generate slices from the edges
  // }

  Ok(())
}
