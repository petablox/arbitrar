use crate::options::Options;
use serde::{Deserialize};
use std::path::{Path, PathBuf};
use std::fs;
use std::fs::File;
use std::{io::Write};
use clap::{App, Arg, ArgMatches};

use crate::context::AnalyzerContext;
use crate::semantics::*;
use crate::feature_extractors::*;

pub struct Slice {
  pub slice_id: usize,
  pub loc: String,
}

impl Slice {
  pub fn target_name(&self) -> String {
    "".to_string()
  }
}

#[derive(Deserialize)]
pub struct Instr {
  pub loc: String,
  pub sem: Semantics,
  pub res: Option<Value>,
}

#[derive(Deserialize)]
pub struct Trace {
  pub trace_id: usize,
  pub target: usize,
  pub instrs: Vec<Instr>,
}

pub trait FeatureExtractor {
  fn name(&self) -> String;

  fn filter(&self, slice: &Slice) -> bool;

  fn init(&mut self, slice: &Slice, trace: &Trace);

  fn extract(&self, slice: &Slice, trace: &Trace) -> serde_json::Value;
}

#[derive(Debug)]
pub struct FeatureExtractionOptions {

}

impl Options for FeatureExtractionOptions {
  fn setup_parser<'a>(app: App<'a>) -> App<'a> {
    app
  }

  fn from_matches(_: &ArgMatches) -> Result<Self, String> {
    Ok(Self {})
  }
}

pub type Extractors = Vec<Box<dyn FeatureExtractor>>;

pub struct FeatureExtractionContext<'a, 'ctx> {
  pub ctx: &'a AnalyzerContext<'ctx>,
  pub options: FeatureExtractionOptions,
}

impl<'a, 'ctx> FeatureExtractionContext<'a, 'ctx> {
  pub fn new(ctx: &'a AnalyzerContext<'ctx>) -> Result<Self, String> {
    Ok(Self { ctx, options: FeatureExtractionOptions::from_matches(&ctx.args)? })
  }

  pub fn load_mut<F>(&self, _: F)
  where
    F : FnMut(Slice, Trace),
  {

  }

  pub fn load<F>(&self, _: F) where F : Fn(Slice, Trace) {

  }

  pub fn init(&self) -> Extractors {
    let mut extractors : Extractors = vec![Box::new(ReturnValueFeatures)];
    self.load_mut(|slice, trace| {
      for extractor in &mut extractors {
        if extractor.filter(&slice) {
          extractor.init(&slice, &trace);
        }
      }
    });
    extractors
  }

  pub fn extract(&self, extractors: Extractors) {
    self.load(|slice, trace| {
      let mut map = serde_json::Map::new();
      for extractor in &extractors {
        if extractor.filter(&slice) {
          map.insert(extractor.name(), extractor.extract(&slice, &trace));
        }
      }
      let json = serde_json::Value::Object(map);
      let path = self.feature_file_path(slice, trace);
      self.dump_json(json, path).unwrap()
    });
  }

  pub fn feature_file_path(&self, slice: Slice, trace: Trace) -> PathBuf {
    Path::new(self.ctx.options.output_path.as_str())
      .join("features")
      .join(slice.target_name().as_str())
      .join(slice.slice_id.to_string())
      .join(format!("{}.json", trace.trace_id))
  }

  pub fn dump_json(&self, json: serde_json::Value, path: PathBuf) -> Result<(), String> {
    let json_str = serde_json::to_string(&json).map_err(|_| "Cannot write features into json string".to_string())?;
    let mut file = File::create(path).map_err(|_| "Cannot create feature file".to_string())?;
    file
      .write_all(json_str.as_bytes())
      .map_err(|_| "Cannot write to feature file".to_string())?;
    Ok(())
  }
}
