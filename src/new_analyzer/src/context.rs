use std::path::Path;
use std::fs::File;
use std::io::prelude::*;
use chrono::{DateTime, Local};
use clap::ArgMatches;
use inkwell::context::*;
use inkwell::module::Module;

pub struct LoggingContext {
    pub log_file: File
}

impl LoggingContext {
    pub fn new(args: &ArgMatches) -> Result<Self, String> {

        // Create the output directory
        let out_dir_path = Path::new(args.value_of("output").unwrap());
        std::fs::create_dir_all(out_dir_path).map_err(|_| String::from("Cannot create output directory"))?;

        // Create the log file
        let log_path = Path::new(Path::new(args.value_of("output").unwrap())).join("log.txt");
        let log_file = File::create(log_path).map_err(|_| String::from("Cannot create log file"))?;
        Ok(Self { log_file })
    }

    pub fn log(&mut self, s: &str) -> Result<(), String> {
        let now: DateTime<Local> = Local::now();
        let log_str = format!("[{}] {}\n", now, s);
        self.log_file.write_all(log_str.as_bytes()).map_err(|_| String::from("Cannot write to byte code file"))?;
        print!("{}", log_str);
        Ok(())
    }
}

pub struct AnalyzerContext<'ctx> {
    pub args: ArgMatches,
    pub llmod: Module<'ctx>,
}

impl<'ctx> AnalyzerContext<'ctx> {
    pub fn new(args: ArgMatches, llctx: &'ctx Context) -> Result<Self, String> {
        // Create the input LLVM byte code directory
        let bc_file_path = Path::new(args.value_of("input").unwrap());

        // Create LL Module by reading in the byte code file
        let llmod = Module::parse_bitcode_from_path(&bc_file_path, &llctx).map_err(|err| err.to_string())?;
        Ok(Self { args, llmod })
    }
}