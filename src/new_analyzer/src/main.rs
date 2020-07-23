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

fn main() {
    let path = Path::new("/home/aspire/ll_analyzer/src/analyzer/tests/kernel/rsi_probe.bc");
    let context = Context::create();
    let res = Module::parse_bitcode_from_path(&path, &context);
    match res {
        Ok(llmod) => {
            let analyzer_ctx = AnalyzerContext { llctx: llmod.get_context(), llmod: llmod };
            let _call_graph = CallGraphContext::new(analyzer_ctx).call_graph();
        },
        Err(err) => {
            println!("{:?}", err);
        }
    }
}
