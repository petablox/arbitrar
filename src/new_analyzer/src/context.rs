use chrono::{DateTime, Local};
use clap::{App, Arg, ArgMatches};
use std::fs::File;
use std::io::prelude::*;
use std::path::Path;

use crate::options::Options;

#[derive(Clone)]
pub struct GeneralOptions {
  pub input_path: String,
  pub output_path: String,
  pub use_serial: bool,
}

impl Options for GeneralOptions {
  fn setup_parser<'a>(app: App<'a>) -> App<'a> {
    app
      .arg(Arg::new("input").value_name("INPUT").index(1).required(true))
      .arg(Arg::new("output").value_name("OUTPUT").index(2).required(true))
      .arg(
        Arg::new("serial")
          .short('s')
          .long("serial")
          .about("Serialize execution rather than parallel"),
      )
  }

  fn from_matches(matches: &ArgMatches) -> Result<Self, String> {
    Ok(Self {
      input_path: String::from(matches.value_of("input").unwrap()),
      output_path: String::from(matches.value_of("output").unwrap()),
      use_serial: matches.is_present("serial"),
    })
  }
}

pub struct LoggingContext {
  pub log_file: File,
}

impl LoggingContext {
  pub fn new(options: &GeneralOptions) -> Result<Self, String> {
    // Create the output directory
    let out_dir_path = Path::new(options.output_path.as_str());
    std::fs::create_dir_all(out_dir_path).map_err(|_| String::from("Cannot create output directory"))?;

    // Create the log file
    let log_path = out_dir_path.join("log.txt");
    let log_file = File::create(log_path).map_err(|_| String::from("Cannot create log file"))?;
    Ok(Self { log_file })
  }

  pub fn log(&mut self, s: &str) -> Result<(), String> {
    let now: DateTime<Local> = Local::now();
    let log_str = format!("[{}] {}\n", now, s);
    self
      .log_file
      .write_all(log_str.as_bytes())
      .map_err(|_| String::from("Cannot write to byte code file"))?;
    print!("{}", log_str);
    Ok(())
  }
}

pub struct AnalyzerContext<'ctx> {
  pub args: ArgMatches,
  pub options: GeneralOptions,
  pub llmod: llir::Module<'ctx>,
}

impl<'ctx> AnalyzerContext<'ctx> {
  pub fn new(args: ArgMatches, options: GeneralOptions, llctx: &'ctx llir::Context) -> Result<Self, String> {
    // Create the input LLVM byte code directory
    let bc_file_path = Path::new(options.input_path.as_str());

    // Create LL Module by reading in the byte code file
    let llmod = llctx.load_module(&bc_file_path).map_err(|err| err.to_string())?;
    Ok(Self { args, options, llmod })
  }
}
