use std::collections::HashMap;
use petgraph::graph::{Graph, DiGraph, EdgeIndex, NodeIndex};
use inkwell::values::*;

use crate::context::*;
use crate::ll_utils::*;

pub struct CallEdge<'ctx> {
    pub caller: FunctionValue<'ctx>,
    pub callee: FunctionValue<'ctx>,
    pub instr: InstructionValue<'ctx>,
}

/// CallGraph is defined by function vertices + instruction edges connecting caller & callee
pub type CallGraph<'ctx> = DiGraph<FunctionValue<'ctx>, InstructionValue<'ctx>>;

pub trait CallGraphTrait<'ctx> {
    type Edge;

    fn remove_llvm_funcs(&mut self);

    fn call_edge(&self, edge_id: EdgeIndex) -> Option<CallEdge>;

    fn dump(&self);
}

impl<'ctx> CallGraphTrait<'ctx> for CallGraph<'ctx> {
    type Edge = EdgeIndex;

    fn remove_llvm_funcs(&mut self) {
        self.retain_nodes(move |this, node_id| {
            let node_name = this[node_id].get_name().to_string_lossy();
            let is_llvm_intrinsics = node_name.contains("llvm.");
            !is_llvm_intrinsics
        });
    }

    fn call_edge(&self, edge_id: EdgeIndex) -> Option<CallEdge> {
        self.edge_endpoints(edge_id).map(|(caller_id, callee_id)| {
            let instr = self[edge_id];
            let caller = self[caller_id];
            let callee = self[callee_id];
            CallEdge { caller, callee, instr }
        })
    }

    fn dump(&self) {
        for edge_id in self.edge_indices() {
            match self.call_edge(edge_id) {
                Some(ce) => {
                    println!("{:?} -> {:?}", ce.caller.get_name(), ce.callee.get_name());
                },
                None => {}
            }
        }
    }
}

pub struct CallGraphContext<'a, 'ctx> {
    pub parent: &'a AnalyzerContext<'ctx>,
    pub remove_llvm_funcs: bool
}

impl<'a, 'ctx> CallGraphContext<'a, 'ctx> {
    pub fn new(ctx: &'a AnalyzerContext<'ctx>) -> Self {
        Self {
            parent: ctx,
            remove_llvm_funcs: true // TODO: Make this take in cmd line arguments
        }
    }

    pub fn call_graph(&self) -> CallGraph<'ctx> {
        let mut value_edge_map : HashMap<FunctionValue<'ctx>, NodeIndex> = HashMap::new();

        // Generate Call Graph by iterating through all blocks & instructions for each function
        let mut cg = Graph::new();
        for caller in self.parent.llmod.iter_functions() {
            let caller_id = value_edge_map.entry(caller).or_insert_with(|| cg.add_node(caller)).clone();
            for b in caller.get_basic_blocks() {
                for i in b.iter_instructions() {
                    match callee_of_call_instr(&self.parent.llmod, i) {
                        Some(callee) => {
                            let callee_id = value_edge_map.entry(callee).or_insert_with(|| cg.add_node(callee)).clone();
                            cg.add_edge(caller_id, callee_id, i);
                        },
                        None => {}
                    }
                }
            }
        }

        // Remove unrelated llvm functions
        if self.remove_llvm_funcs {
            cg.remove_llvm_funcs();
        }

        // Return the call graph
        cg
    }
}