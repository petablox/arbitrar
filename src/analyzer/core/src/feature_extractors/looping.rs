use llir::types::*;
use serde_json::json;

use crate::feature_extraction::*;
use crate::semantics::boxed::*;

pub struct LoopFeaturesExtractor;

impl LoopFeaturesExtractor {
  pub fn new() -> Self {
    Self
  }
}

impl FeatureExtractor for LoopFeaturesExtractor {
  fn name(&self) -> String {
    "loop".to_string()
  }

  fn filter<'ctx>(&self, _: &String, _: FunctionType<'ctx>) -> bool {
    true
  }

  fn init(&mut self, _: &Slice, _: usize, _: &Trace) {}

  fn finalize(&mut self) {}

  fn extract(&self, _: &Slice, trace: &Trace) -> serde_json::Value {
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
        }
        Semantics::UncondBr { end_loop } => {
          if end_loop {
            loop_stack -= 1;
          }
        }
        Semantics::Call { .. } => {
          if i == trace.target && loop_stack > 0 {
            target_in_a_loop = true;
          }
        }
        _ => {}
      }
    }
    json!({
      "has_loop": has_loop,
      "target_in_a_loop": target_in_a_loop
    })
  }
}
