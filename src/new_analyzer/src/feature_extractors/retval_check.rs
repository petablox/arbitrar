use llir::types::*;
use serde::{Deserialize, Serialize};

use crate::feature_extraction::*;

#[derive(Debug, Serialize, Deserialize)]
pub struct ReturnValueCheckFeatures {
  pub used_as_location: bool,
}

pub struct ReturnValueCheckFeatureExtractor;

impl ReturnValueCheckFeatureExtractor {
  pub fn new() -> Self {
    Self
  }
}

impl ReturnValueCheckFeatureExtractor {
  fn extract_features(&self, _: &Slice, _: &Trace) -> ReturnValueCheckFeatures {
    ReturnValueCheckFeatures {
      used_as_location: false,
    }
  }
}

impl FeatureExtractor for ReturnValueCheckFeatureExtractor {
  fn name(&self) -> String {
    "retval".to_string()
  }

  /// Return value check feature should only present when the return type
  /// is a pointer type
  fn filter<'ctx>(&self, _: &String, target_type: FunctionType<'ctx>) -> bool {
    match target_type.return_type() {
      Type::Pointer(_) => true,
      _ => false,
    }
  }

  fn init(&mut self, _: &Slice, _: &Trace) {}

  fn extract(&self, slice: &Slice, trace: &Trace) -> serde_json::Value {
    serde_json::to_value(self.extract_features(slice, trace)).unwrap()
  }
}
