use llir::types::*;
use serde_json::json;
use std::collections::HashSet;

use crate::feature_extraction::*;
use crate::semantics::boxed::*;

pub struct ArgumentPostconditionFeatureExtractor {
  pub index: usize,
}

impl ArgumentPostconditionFeatureExtractor {
  pub fn new(index: usize) -> Self {
    Self { index }
  }
}

impl FeatureExtractor for ArgumentPostconditionFeatureExtractor {
  fn name(&self) -> String {
    format!("arg.{}.post", self.index)
  }

  fn filter<'ctx>(&self, _: &String, target_type: FunctionType<'ctx>) -> bool {
    self.index < target_type.num_argument_types()
  }

  fn init(&mut self, _: usize, _: &Slice, _: usize, _: &Trace) {}

  fn finalize(&mut self) {}

  fn extract(&self, _: usize, _: &Slice, trace: &Trace) -> serde_json::Value {
    let mut used = false;
    let mut used_in_call = false;
    let mut used_in_bin = false;
    let mut used_in_check = false;
    let mut derefed = false;
    let mut returned = false;
    let mut indir_returned = false;

    // Helper structures
    let mut child_ptrs: HashSet<Value> = HashSet::new();
    let mut tracked_values: HashSet<Value> = HashSet::new();

    // Setup the argument
    let arg = trace.target_arg(self.index);

    if let Some(arg) = arg {
      let args_to_check = args_to_check(arg, 5);

      for arg in args_to_check {
        // Iterate forward
        for (i, instr) in trace.iter_instrs_from_target(TraceIterDirection::Forward) {
          match &instr.sem {
            Semantics::Call { args, .. } => {
              if args.iter().find(|a| ***a == arg).is_some() {
                used = true;
                used_in_call = true;
              }
            }
            Semantics::ICmp { op0, op1, .. } => {
              let arg_is_op0 = **op0 == arg;
              let arg_is_op1 = **op1 == arg;
              if arg_is_op0 || arg_is_op1 {
                used = true;
                used_in_check = true;
              }
            }
            Semantics::Ret { op } => {
              if i == trace.instrs.len() - 1 {
                if let Some(op) = op {
                  if arg == **op {
                    returned = true;
                  } else if op.contains(&arg) || tracked_values.contains(&**op) {
                    indir_returned = true;
                  }
                }
              }
            }
            Semantics::Store { loc, val } => {
              if **loc == arg {
                used = true;
                derefed = true;
              } else if **val == arg {
                let loc = *loc.clone();
                tracked_values.insert(Value::AllocOf(Box::new(loc.clone())));
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
                used = true;
                derefed = true;
              }
            }
            Semantics::Load { loc } => {
              if **loc == arg || child_ptrs.contains(&**loc) {
                used = true;
                derefed = true;
              }
            }
            Semantics::GEP { loc, .. } => {
              if **loc == arg {
                child_ptrs.insert(instr.res.clone().unwrap());
              }
            }
            Semantics::Bin { op0, op1, .. } => {
              let arg_is_op0 = **op0 == arg;
              let arg_is_op1 = **op1 == arg;
              if arg_is_op0 || arg_is_op1 {
                used_in_bin = true;
                used = true;
              }
            }
            _ => {}
          }
        }
      }
    }

    json!({
      "used": used,
      "used_in_call": used_in_call,
      "used_in_bin": used_in_bin,
      "used_in_check": used_in_check,
      "derefed": derefed,
      "returned": returned,
      "indir_returned": indir_returned,
    })
  }
}

fn args_to_check(arg: &Value, depth: usize) -> Vec<Value> {
  if depth == 0 {
    vec![]
  } else {
    match arg {
      Value::AllocOf(v) => vec![vec![arg.clone()], args_to_check(v, depth - 1)].concat(),
      _ => vec![arg.clone()],
    }
  }
}
