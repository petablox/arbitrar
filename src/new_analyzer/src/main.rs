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

fn args() -> ArgMatches {
  let app = App::new("analyzer");
  let app = GeneralOptions::setup_parser(app);
  let app = CallGraphOptions::setup_parser(app);
  let app = SlicerOptions::setup_parser(app);
  let app = SymbolicExecutionOptions::setup_parser(app);
  app.get_matches()
}

fn main() -> Result<(), String> {
  let args = args();
  let options = GeneralOptions::from_matches(&args)?;
  let mut logging_ctx = LoggingContext::new(&options)?;

  // Load the byte code module and generate analyzer context
  logging_ctx.log("Loading byte code file and creating context...")?;
  let bc_file_path = Path::new(options.input_path.as_str());
  let llctx = llir::Context::create();
  let llmod = llctx.load_module(&bc_file_path).map_err(|err| err.to_string())?;

  // Generate call graph
  logging_ctx.log("Generating call graph...")?;
  let call_graph_options = CallGraphOptions::from_matches(&args)?;
  let call_graph = CallGraph::from_module(&llmod, &call_graph_options);

  // Finding call edges
  logging_ctx.log("Finding relevant call edges...")?;
  let slicer_options = SlicerOptions::from_matches(&args)?;
  let target_edges_map = TargetEdgesMap::from_call_graph(&call_graph, &slicer_options)?;

  // Generate slices
  let target_slices_map = TargetSlicesMap::from_target_edges_map(&target_edges_map, &slicer_options);

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
