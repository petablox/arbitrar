use std::collections::HashSet;
use inkwell::values::*;

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
    pub call_graph: CallGraph<'ctx>
}

impl<'a, 'ctx> SlicerContext<'a, 'ctx> {
    pub fn new(ctx: &'a AnalyzerContext<'ctx>, call_graph: CallGraph<'ctx>) -> Self {
        SlicerContext { parent: ctx, call_graph }
    }
}
