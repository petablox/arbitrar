use serde::{Deserialize, Serialize};

use crate::feature_extraction::*;

#[derive(Debug, Serialize, Deserialize)]
pub struct ArgumentValueFeatures {
  pub used_as_location_after: bool,
}

pub struct ArgumentValueFeatureExtractor {
  pub index: usize,
}

impl ArgumentValueFeatureExtractor {
  pub fn new(index: usize) -> Self {
    Self { index }
  }

  fn extract_features(&self, _: &Slice, _: &Trace) -> ArgumentValueFeatures {
    ArgumentValueFeatures {
      used_as_location_after: false,
    }
  }
}

impl FeatureExtractor for ArgumentValueFeatureExtractor {
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
