use chrono::{DateTime, Local};
use std::fs::File;
use std::io::prelude::*;

use crate::options::Options;

pub struct LoggingContext {
  pub log_file: File,
}

impl LoggingContext {
  pub fn new(options: &Options) -> Result<Self, String> {
    // Create the output directory
    let output_path = options.output_path();
    std::fs::create_dir_all(output_path.clone()).map_err(|_| String::from("Cannot create output directory"))?;

    // Create the log file
    let log_path = output_path.join("log.txt");
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
