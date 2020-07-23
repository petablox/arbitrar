use clap::{App, Arg, ArgMatches};

mod options;
mod ll_utils;
mod context;
mod call_graph;
mod slicer;

use options::*;
use context::*;
use call_graph::*;
use slicer::*;

fn args() -> ArgMatches {
    let app =
        App::new("analyzer")
            .arg(Arg::new("input").value_name("INPUT").index(1).required(true))
            .arg(Arg::new("output").value_name("OUTPUT").index(2).required(true));
    let app = CallGraphOptions::setup_parser(app);
    let app = SlicerOptions::setup_parser(app);
    app.get_matches()
}

fn main() -> Result<(), String> {
    let args = args();
    let llctx = inkwell::context::Context::create();
    let mut logging_ctx = LoggingContext::new(&args)?;
    logging_ctx.log("Loading byte code file and creating context...")?;
    let analyzer_ctx = AnalyzerContext::new(args, &llctx)?;
    logging_ctx.log("Generating call graph...")?;
    let call_graph_ctx = CallGraphContext::new(&analyzer_ctx)?;
    let call_graph = call_graph_ctx.call_graph();
    logging_ctx.log("Finding relevant call edges...")?;
    let slicer_ctx = SlicerContext::new(&analyzer_ctx, &call_graph)?;
    let edges = slicer_ctx.relavant_edges()?;
    logging_ctx.log(format!("Found {} edges, dividing into {} batches...", edges.len(), slicer_ctx.num_batches(&edges)).as_str())?;
    for (batch_id, edges_batch) in slicer_ctx.batches(&edges).enumerate() {
        logging_ctx.log(format!("Running slicer on batch #{}...", batch_id).as_str())?;
        let _slices = slicer_ctx.slices_of_call_edges(edges_batch);
    }
    Ok(())
}
