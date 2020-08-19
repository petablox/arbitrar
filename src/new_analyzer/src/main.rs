use clap::{App, ArgMatches};

mod call_graph;
mod context;
mod options;
mod semantics;
mod slicer;
mod symbolic_execution;
mod feature_extraction;
mod feature_extractors;
mod utils;

use call_graph::*;
use context::*;
use options::*;
use slicer::*;
use symbolic_execution::*;
use feature_extraction::*;

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
  let llctx = llir::Context::create();
  let analyzer_ctx = AnalyzerContext::new(args, options, &llctx)?;

  // Generate call graph
  logging_ctx.log("Generating call graph...")?;
  let call_graph_ctx = CallGraphContext::new(&analyzer_ctx)?;
  let call_graph = call_graph_ctx.call_graph();

  // Finding call edges
  logging_ctx.log("Finding relevant call edges...")?;
  let slicer_ctx = SlicerContext::new(&analyzer_ctx, &call_graph)?;
  let edges = slicer_ctx.relavant_edges()?;

  // Checking if there are edges to run
  let num_edges = edges.len();
  if num_edges == 0 {
    Err("No relevant call edge found".to_string())
  } else {

    // Execute in batches
    let num_batches = slicer_ctx.num_batches(&edges);
    if num_batches > 1 {
      logging_ctx.log(format!("Found {} edges, dividing into {} batches...", num_edges, num_batches).as_str())?;
    } else {
      logging_ctx.log(format!("Found {} edges, running slicer...", num_edges).as_str())?;
    }
    for (batch_id, edges_batch) in slicer_ctx.batches(&edges).enumerate() {

      // Slicing
      if num_batches > 1 {
        logging_ctx.log(format!("Running slicer on batch #{}...", batch_id).as_str())?;
      }
      let slices = slicer_ctx.slices_of_call_edges(edges_batch);
      logging_ctx.log(format!("Slicer created {} slices. Running symbolic execution...", slices.len()).as_str())?;

      // Symbolic execution
      let sym_exec_ctx = SymbolicExecutionContext::new(&analyzer_ctx)?;
      let metadata = sym_exec_ctx.execute_slices(slices);
      logging_ctx.log(format!("Execution Stats: {:?}", metadata).as_str())?;

      // Feature Extraction
      let feat_extr_ctx = FeatureExtractionContext::new(&analyzer_ctx)?;
      let extrs = feat_extr_ctx.init();
      feat_extr_ctx.extract(extrs);
    }
    Ok(())
  }
}
