use llir::types::*;
use serde_json::json;

use crate::feature_extraction::*;
use crate::semantics::boxed::*;
use crate::semantics::*;

pub struct ReturnValueCheckFeatureExtractor;

impl ReturnValueCheckFeatureExtractor {
  pub fn new() -> Self {
    Self
  }
}

impl FeatureExtractor for ReturnValueCheckFeatureExtractor {
  fn name(&self) -> String {
    "retval_check".to_string()
  }

  /// Return value check feature should only present when the return type
  /// is a pointer type
  fn filter<'ctx>(&self, _: &String, target_type: FunctionType<'ctx>) -> bool {
    match target_type.return_type() {
      Type::Pointer(_) => true,
      _ => false,
    }
  }

  fn init(&mut self, _: &Slice, _: usize, _: &Trace) {}

  fn finalize(&mut self) {}

  fn extract(&self, _: &Slice, trace: &Trace) -> serde_json::Value {
    let mut checked = false;
    let mut br_eq_zero = false;
    let mut br_neq_zero = false;
    let mut compare_with_zero = false;
    let mut compare_with_non_const = false;
    let retval = trace.target_result().clone().unwrap();
    let mut icmp = None;

    // Start iterating from the target onward
    for instr in trace.iter_instrs_from_target(TraceIterDirection::Forward) {
      match &instr.sem {
        Semantics::ICmp { op0, op1, .. } => {
          let retval_is_op0 = **op0 == retval;
          let retval_is_op1 = **op1 == retval;
          if retval_is_op0 || retval_is_op1 {
            checked = true;
            icmp = Some(instr.res.clone().unwrap());
          }
        }
        Semantics::CondBr { cond, br, .. } => {
          if let Some(icmp) = &icmp {
            if &**cond == icmp {
              if let Some((pred, op0, op1)) = icmp_pred_op0_op1(icmp) {
                let op0_num = num_of_value(&op0);
                let op1_num = num_of_value(&op1);
                if let Some(num) = op0_num.or(op1_num) {
                  if num == 0 {
                    compare_with_zero = true;
                    if pred == Predicate::EQ {
                      br_eq_zero = *br == Branch::Then;
                      br_neq_zero = !br_eq_zero;
                    } else if pred == Predicate::NE {
                      br_neq_zero = *br == Branch::Then;
                      br_eq_zero = !br_neq_zero;
                    }
                  }
                } else {
                  compare_with_non_const = true;
                }
              }
            }
          }
        }
        _ => {}
      }
    }

    json!({
      "checked": checked,
      "br_eq_zero": br_eq_zero,
      "br_neq_zero": br_neq_zero,
      "compare_with_zero": compare_with_zero,
      "compare_with_non_const": compare_with_non_const,
    })
  }
}

fn num_of_value(v: &Value) -> Option<i64> {
  match v {
    Value::Int(i) => Some(i.clone()),
    Value::Null => Some(0),
    _ => None,
  }
}

fn icmp_pred_op0_op1(v: &Value) -> Option<(Predicate, Value, Value)> {
  match v {
    Value::ICmp { pred, op0, op1 } => Some((pred.clone(), *op0.clone(), *op1.clone())),
    _ => None,
  }
}
