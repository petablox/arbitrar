use llir::types::*;
use serde_json::json;

use crate::feature_extraction::*;

pub struct ArgumentValueFeatureExtractor {
  pub index: usize,
}

impl ArgumentValueFeatureExtractor {
  pub fn new(index: usize) -> Self {
    Self { index }
  }
}

impl FeatureExtractor for ArgumentValueFeatureExtractor {
  fn name(&self) -> String {
    format!("argval.{}", self.index)
  }

  fn filter<'ctx>(&self, _: &String, target_type: FunctionType<'ctx>) -> bool {
    self.index < target_type.num_argument_types()
  }

  fn init(&mut self, _: &Slice, _: &Trace) {}

  fn extract(&self, _: &Slice, _: &Trace) -> serde_json::Value {
    json!({})
  }
}
