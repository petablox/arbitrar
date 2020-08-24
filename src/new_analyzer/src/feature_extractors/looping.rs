use llir::types::*;
use serde::{Deserialize, Serialize};

use crate::semantics::boxed::*;
use crate::feature_extraction::*;

#[derive(Debug, Serialize, Deserialize)]
pub struct LoopFeatures {
  pub has_loop: bool,
  pub target_in_a_loop: bool,
}

pub struct LoopFeaturesExtractor;

impl LoopFeaturesExtractor {
  pub fn new() -> Self {
    Self
  }
}

impl LoopFeaturesExtractor {
  fn extract_features(&self, _: &Slice, trace: &Trace) -> LoopFeatures {
    let mut loop_stack = 0;
    let mut has_loop = false;
    let mut target_in_a_loop = false;
    for (i, instr) in trace.instrs.iter().enumerate() {
      match instr.sem {
        Semantics::CondBr { beg_loop, .. } => {
          if beg_loop {
            has_loop = true;
            loop_stack += 1;
          }
        },
        Semantics::UncondBr { end_loop } => {
          if end_loop {
            loop_stack -= 1;
          }
        },
        Semantics::Call { .. } => {
          if i == trace.target && loop_stack > 0 {
            target_in_a_loop = true;
          }
        }
        _ => {}
      }
    }
    LoopFeatures { has_loop, target_in_a_loop }
  }
}

impl FeatureExtractor for LoopFeaturesExtractor {
  fn name(&self) -> String {
    "loop".to_string()
  }

  fn filter<'ctx>(&self, _: &String, _: FunctionType<'ctx>) -> bool {
    true
  }

  fn init(&mut self, _: &Slice, _: &Trace) {}

  fn extract(&self, slice: &Slice, trace: &Trace) -> serde_json::Value {
    serde_json::to_value(self.extract_features(slice, trace)).unwrap()
  }
}
