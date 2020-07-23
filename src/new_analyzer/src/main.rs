use std::path::Path;
use inkwell::context::*;
use inkwell::module::Module;

mod ll_utils;
mod context;
mod call_graph;
mod slicer;

use context::*;
use call_graph::*;
use slicer::*;

fn main() -> Result<(), String> {
    let path = Path::new("/home/aspire/ll_analyzer/src/analyzer/tests/kernel/rsi_probe.bc");
    let context = Context::create();
    let llmod = Module::parse_bitcode_from_path(&path, &context).map_err(|err| err.to_string())?;
    let analyzer_ctx = AnalyzerContext::new(llmod);
    let call_graph_ctx = CallGraphContext::new(&analyzer_ctx);
    let call_graph = call_graph_ctx.call_graph();
    let slicer_ctx = SlicerContext::new(&analyzer_ctx, &call_graph);
    let _slices = slicer_ctx.slice();
    Ok(())
}
