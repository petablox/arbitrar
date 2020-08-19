use serde_json::json;

use crate::feature_extraction::*;

pub struct ReturnValueFeatures;

impl FeatureExtractor for ReturnValueFeatures {
  fn name(&self) -> String { "retval".to_string() }

  fn filter(&self, slice: &Slice) -> bool { true }

  fn init(&mut self, _: &Slice, trace: &Trace) {}

  fn extract(&self, slice: &Slice, trace: &Trace) -> serde_json::Value {
    json!({})
  }
}