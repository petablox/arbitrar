use inkwell::context::*;
use inkwell::module::Module;

pub struct AnalyzerContext<'ctx> {
    pub llctx: ContextRef<'ctx>,
    pub llmod: Module<'ctx>,
}