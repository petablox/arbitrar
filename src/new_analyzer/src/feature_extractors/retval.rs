use serde::{Deserialize, Serialize};

use crate::feature_extraction::*;

#[derive(Debug, Serialize, Deserialize)]
pub struct ReturnValueFeatures {
  pub used_as_location: bool,
}

pub struct ReturnValueFeatureExtractor;

impl ReturnValueFeatureExtractor {
  pub fn new() -> Self {
    Self
  }
}

impl ReturnValueFeatureExtractor {
  fn extract_features(&self, _: &Slice, _: &Trace) -> ReturnValueFeatures {
    ReturnValueFeatures {
      used_as_location: false,
    }
  }
}

impl FeatureExtractor for ReturnValueFeatureExtractor {
  fn name(&self) -> String {
    "retval".to_string()
  }

  fn filter(&self, _: &Slice) -> bool {
    true
  }

  fn init(&mut self, _: &Slice, _: &Trace) {}

  fn extract(&self, slice: &Slice, trace: &Trace) -> serde_json::Value {
    serde_json::to_value(self.extract_features(slice, trace)).unwrap()
  }
}
