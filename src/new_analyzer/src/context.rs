use std::path::Path;
use clap::ArgMatches;
use inkwell::context::*;
use inkwell::module::Module;

pub struct AnalyzerContext<'ctx> {
    pub args: ArgMatches,
    pub llmod: Module<'ctx>,
}

impl<'ctx> AnalyzerContext<'ctx> {
    pub fn new(args: ArgMatches, llctx: &'ctx Context) -> Result<Self, String> {
        let path = Path::new(args.value_of("input").unwrap());
        let llmod = Module::parse_bitcode_from_path(&path, &llctx).map_err(|err| err.to_string())?;
        Ok(Self { args, llmod })
    }
}