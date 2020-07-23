use petgraph::graph::{Graph, DiGraph};
use inkwell::values::*;

use crate::context::*;
use crate::ll_utils::*;

pub type CallGraph<'ctx> = DiGraph<FunctionValue<'ctx>, InstructionValue<'ctx>>;

pub struct CallGraphContext<'ctx> {
    pub parent: AnalyzerContext<'ctx>,
}

impl<'ctx> CallGraphContext<'ctx> {
    pub fn new(ctx: AnalyzerContext<'ctx>) -> Self {
        Self { parent: ctx }
    }

    pub fn call_graph(&self) -> CallGraph<'ctx> {
        let mut cg = Graph::new();
        for caller in self.parent.llmod.iter_functions() {
            let caller_id = cg.add_node(caller);
            for b in caller.get_basic_blocks() {
                for i in b.iter_instructions() {
                    match callee_of_call_instr(&self.parent.llmod, i) {
                        Some(callee) => {
                            let callee_id = cg.add_node(callee);
                            println!("{:?} -> {:?}", caller.get_name(), callee.get_name());
                            cg.add_edge(caller_id, callee_id, i);
                        },
                        None => {}
                    }
                }
            }
        }
        cg
    }
}