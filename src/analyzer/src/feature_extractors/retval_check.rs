use std::collections::HashMap;

use llir::types::*;
use serde_json::json;

use crate::feature_extraction::*;
use crate::semantics::boxed::*;
use crate::semantics::*;

pub struct ReturnValueCheckFeatureExtractor {
  slice_id_is_checked_map: HashMap<usize, bool>,
}

impl ReturnValueCheckFeatureExtractor {
  pub fn new() -> Self {
    Self {
      slice_id_is_checked_map: HashMap::new(),
    }
  }
}

impl FeatureExtractor for ReturnValueCheckFeatureExtractor {
  fn name(&self) -> String {
    "ret.check".to_string()
  }

  /// Return value check feature should only present when the return type
  /// is a pointer type
  fn filter<'ctx>(&self, _: &String, target_type: FunctionType<'ctx>) -> bool {
    target_type.has_return_type()
  }

  fn init(&mut self, slice_id: usize, _: &Slice, _: usize, trace: &Trace) {
    let mut checked = false;
    let mut br_eq_zero = false;
    let mut br_neq_zero = false;
    let mut compared_with_zero = false;
    let mut compared_with_non_const = false;

    check(trace, &mut checked, &mut br_eq_zero, &mut br_neq_zero, &mut compared_with_zero, &mut compared_with_non_const);

    self.slice_id_is_checked_map.entry(slice_id).and_modify(|c| *c |= checked).or_insert(checked);
  }

  fn finalize(&mut self) {}

  fn extract(&self, slice_id: usize, _: &Slice, trace: &Trace) -> serde_json::Value {
    let mut checked = false;
    let mut br_eq_zero = false;
    let mut br_neq_zero = false;
    let mut compared_with_zero = false;
    let mut compared_with_non_const = false;

    check(trace, &mut checked, &mut br_eq_zero, &mut br_neq_zero, &mut compared_with_zero, &mut compared_with_non_const);

    json!({
      "checked": checked,
      "slice_checked": self.slice_id_is_checked_map[&slice_id],
      "br_eq_zero": br_eq_zero,
      "br_neq_zero": br_neq_zero,
      "compared_with_zero": compared_with_zero,
      "compared_with_non_const": compared_with_non_const,
    })
  }
}

pub fn check(trace: &Trace, checked: &mut bool, br_eq_zero: &mut bool, br_neq_zero: &mut bool, compared_with_zero: &mut bool, compared_with_non_const: &mut bool) {
  let retval = trace.target_result().clone().unwrap();
  instr_res_check(trace, &retval, trace.target_index(), checked, br_eq_zero, br_neq_zero, compared_with_zero, compared_with_non_const);
}

pub fn instr_res_check(
  trace: &Trace,
  val: &Value,
  from: usize,
  checked: &mut bool,
  br_eq_zero: &mut bool,
  br_neq_zero: &mut bool,
  compared_with_zero: &mut bool,
  compared_with_non_const: &mut bool
) {

  let mut icmp = None;

  // Start iterating from the target onward
  for (_, instr) in trace.iter_instrs_from(TraceIterDirection::Forward, from) {
    match &instr.sem {
      Semantics::ICmp { op0, op1, .. } => {
        let retval_is_op0 = &**op0 == val;
        let retval_is_op1 = &**op1 == val;
        if retval_is_op0 || retval_is_op1 {
          *checked = true;
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
                  *compared_with_zero = true;
                  if pred == Predicate::EQ {
                    *br_eq_zero = *br == Branch::Then;
                    *br_neq_zero = !*br_eq_zero;
                  } else if pred == Predicate::NE {
                    *br_neq_zero = *br == Branch::Then;
                    *br_eq_zero = !*br_neq_zero;
                  }
                }
              } else {
                *compared_with_non_const = true;
              }
            }
          }
        }
      }
      _ => {}
    }
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
