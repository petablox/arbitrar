#[macro_use] extern crate lazy_static;

use clap::{App, Arg, ArgMatches};

mod utils;
mod ll_utils;
mod context;
mod call_graph;
mod slicer;

use utils::*;
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
    let analyzer_ctx = AnalyzerContext::new(args, &llctx)?;
    let call_graph_ctx = CallGraphContext::new(&analyzer_ctx)?;
    let call_graph = call_graph_ctx.call_graph();
    let slicer_ctx = SlicerContext::new(&analyzer_ctx, &call_graph)?;
    let edges = slicer_ctx.relavant_edges()?;
    for edge in edges {
        match slicer_ctx.call_graph.call_edge(edge) {
            Some(ce) => ce.dump(),
            None => ()
        }
    }
    // let _slices = slicer_ctx.slice();
    Ok(())
}
