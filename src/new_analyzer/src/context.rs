use inkwell::context::*;
use inkwell::module::Module;

pub struct AnalyzerContext<'ctx> {
    pub llctx: ContextRef<'ctx>,
    pub llmod: Module<'ctx>,
}

impl<'ctx> AnalyzerContext<'ctx> {
    pub fn new(llmod: Module<'ctx>) -> Self {
        Self { llctx: llmod.get_context(), llmod }
    }
}