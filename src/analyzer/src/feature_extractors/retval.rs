use llir::types::*;
use serde_json::json;
use std::collections::HashSet;

use crate::feature_extraction::*;
use crate::semantics::boxed::*;

pub struct ReturnValueFeatureExtractor;

impl ReturnValueFeatureExtractor {
  pub fn new() -> Self {
    Self
  }
}

impl FeatureExtractor for ReturnValueFeatureExtractor {
  fn name(&self) -> String {
    "ret".to_string()
  }

  fn filter<'ctx>(&self, _: &String, target_type: FunctionType<'ctx>) -> bool {
    target_type.has_return_type()
  }

  fn init(&mut self, _: usize, _: &Slice, _: usize, _: &Trace) {}

  fn finalize(&mut self) {}

  fn extract(&self, _: usize, _: &Slice, trace: &Trace) -> serde_json::Value {
    let mut used = false;
    let mut used_in_call = false;
    let mut used_in_bin = false;
    let mut derefed = false;
    let mut returned = false;
    let mut indir_returned = false;

    // States
    let mut child_ptrs: HashSet<Value> = HashSet::new();
    let mut tracked_values: HashSet<Value> = HashSet::new();
    let retval = trace.target_result().clone().unwrap();

    // Start iterating from the target node
    for (i, instr) in trace.iter_instrs_from_target(TraceIterDirection::Forward) {
      match &instr.sem {
        Semantics::Call { args, .. } => {
          if args.iter().find(|a| &***a == &retval).is_some() {
            used = true;
            used_in_call = true;
          }
        }
        Semantics::Load { loc } => {
          if **loc == retval || child_ptrs.contains(&**loc) {
            derefed = true;
          }
        }
        Semantics::Store { loc, val } => {
          if **loc == retval {
            derefed = true;
          } else if **val == retval {
            let loc = *loc.clone();
            match &loc {
              Value::Arg(_) | Value::Sym(_) | Value::Glob(_) | Value::Alloc(_) => {
                tracked_values.insert(loc);
              }
              Value::GEP { loc, .. } => {
                tracked_values.insert(*loc.clone());
              }
              _ => {}
            }
          } else if child_ptrs.contains(&**loc) {
            derefed = true;
          }
        }
        Semantics::GEP { loc, .. } => {
          if **loc == retval {
            child_ptrs.insert(instr.res.clone().unwrap());
          }
        }
        Semantics::Ret { op } => {
          // We only care about the last return statement
          if i == trace.instrs.len() - 1 {
            if let Some(op) = op {
              if retval == **op {
                returned = true;
              } else if tracked_values.contains(&**op) {
                indir_returned = true;
              }
            }
          }
        }
        Semantics::Bin { op0, op1, .. } => {
          let arg_is_op0 = &**op0 == &retval;
          let arg_is_op1 = &**op1 == &retval;
          if arg_is_op0 || arg_is_op1 {
            used_in_bin = true;
            used = true;
          }
        }
        _ => {}
      }
    }

    json!({
      "used": used,
      "used_in_call": used_in_call,
      "used_in_bin": used_in_bin,
      "derefed": derefed,
      "returned": returned,
      "indir_returned": indir_returned,
    })
  }
}
