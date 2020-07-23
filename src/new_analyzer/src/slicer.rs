use std::collections::HashSet;
use inkwell::values::*;
use petgraph::graph::{EdgeIndex};

use crate::context::AnalyzerContext;
use crate::call_graph::CallGraph;

pub struct Slice<'ctx> {
    pub entry: FunctionValue<'ctx>,
    pub caller: FunctionValue<'ctx>,
    pub callee: FunctionValue<'ctx>,
    pub instr: InstructionValue<'ctx>,
    pub functions: HashSet<FunctionValue<'ctx>>,
}

pub struct SlicerContext<'a, 'ctx> {
    pub parent: &'a AnalyzerContext<'ctx>,
    pub call_graph: &'a CallGraph<'ctx>,
    pub depth: u8,
}

impl<'a, 'ctx> SlicerContext<'a, 'ctx> {
    pub fn new(ctx: &'a AnalyzerContext<'ctx>, call_graph: &'a CallGraph<'ctx>) -> Self {
        SlicerContext { parent: ctx, call_graph, depth: 1 }
    }

    pub fn _slice_of_call_edge(&self, _edge_id: EdgeIndex) -> Vec<Slice<'ctx>> {
        // let instr = self.call_graph[edge_id];
        // match self.call_graph.edge_endpoints(edge_id) {
        //     Some((caller_id, callee_id)) => {
        //         // let caller = self[caller_id]
        //     }
        //     None => {}
        // }
        vec![]
    }

    pub fn slice(&self) -> Vec<Slice<'ctx>> {
        vec![]
    }
}
