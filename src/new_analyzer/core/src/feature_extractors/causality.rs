use std::collections::HashMap;
use llir::types::*;
use serde_json::json;
use crate::semantics::boxed::*;

use crate::feature_extraction::*;

pub struct CausalityFeatureExtractor {
  pub forward: bool,
  pub dictionary: HashMap<String, f32>,
}

impl CausalityFeatureExtractor {
  pub fn pre() -> Self {
    Self { forward: false, dictionary: HashMap::new() }
  }

  pub fn post() -> Self {
    Self { forward: true, dictionary: HashMap::new() }
  }
}

impl FeatureExtractor for CausalityFeatureExtractor {
  fn name(&self) -> String {
    if self.forward {
      format!("post")
    } else {
      format!("pre")
    }
  }

  fn filter<'ctx>(&self, _: &String, _: FunctionType<'ctx>) -> bool {
    true
  }

  fn init(&mut self, _: &Slice, _: &Trace) {

  }

  fn finalize(&mut self) {

  }

  fn extract(&self, _: &Slice, _: &Trace) -> serde_json::Value {
    json!({})
  }
}

fn find_caused_functions(trace: &Trace, forward: bool) -> HashMap<String, usize> {
  let iter = if forward { trace.instrs.iter().skip(trace.target).collect::<Vec<_>>() } else {
    trace.instrs.iter().skip(trace.instrs.len() - trace.target).rev().collect::<Vec<_>>()
  };
  let mut result = HashMap::new();
  for instr in iter {
    match &instr.sem {
      Semantics::Call { func, args } => {

      }
      _ => {}
    }
  }
  result
}
