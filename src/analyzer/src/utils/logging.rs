use chrono::{DateTime, Local};
use std::fs::File;
use std::io::prelude::*;

use crate::options::*;
use crate::symbolic_execution::*;

pub struct LoggingContext {
  pub log_file: File,
}

impl LoggingContext {
  pub fn new(options: &impl IOOptions) -> Result<Self, String> {
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

  pub fn log_loading_bc(&mut self) -> Result<(), String> {
    self.log("Loading byte code file and creating context...")
  }

  pub fn log_generating_call_graph(&mut self) -> Result<(), String> {
    self.log("Generating call graph...")
  }

  pub fn log_finding_call_edges(&mut self) -> Result<(), String> {
    self.log("Finding relevant call edges...")
  }

  pub fn log_generated_call_edges(&mut self, num_call_edges: usize) -> Result<(), String> {
    self.log(format!("{} call edges found, generating slices", num_call_edges).as_str())
  }

  pub fn log_generated_slices(&mut self, num_slices: usize) -> Result<(), String> {
    self.log(format!("{} slices generated, dumping slices to json...", num_slices).as_str())
  }

  pub fn log_dividing_batches(&mut self, use_batch: bool) -> Result<(), String> {
    if use_batch {
      self.log("Slices dumped, dividing slices into batches")
    } else {
      Ok(())
    }
  }

  pub fn log_executing_batch(&mut self, batch_index: usize, use_batch: bool, num_slices: usize) -> Result<(), String> {
    if use_batch {
      self.log(
        format!(
          "Running symbolic execution on batch #{} with {} slices",
          batch_index, num_slices
        )
        .as_str(),
      )
    } else {
      self.log(format!("Running symbolic execution on {} slices", num_slices).as_str())
    }
  }

  pub fn log_finished_execution_batch(
    &mut self,
    batch_index: usize,
    use_batch: bool,
    metadata: MetaData,
  ) -> Result<(), String> {
    if use_batch {
      self.log(format!("Finished symbolic execution for batch {}; {:?}", batch_index, metadata).as_str())
    } else {
      self.log(format!("Finished symbolic execution; {:?}", metadata).as_str())
    }
  }

  pub fn log_finished_execution(&mut self, use_batch: bool, metadata: MetaData) -> Result<(), String> {
    if use_batch {
      self.log(format!("Finished symbolic execution for all; {:?}", metadata).as_str())
    } else {
      Ok(())
    }
  }

  pub fn log_extracting_features(&mut self) -> Result<(), String> {
    self.log("Extracting features...")
  }

  pub fn log_finished_extracting_features(&mut self) -> Result<(), String> {
    self.log("Feature extractor finished")
  }
}
