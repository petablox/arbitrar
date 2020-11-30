use llir::types::*;
use serde_json::json;

use crate::feature_extraction::*;
use crate::semantics::{boxed::*, *};

pub struct ArgumentPreconditionFeatureExtractor {
  pub index: usize,
}

impl ArgumentPreconditionFeatureExtractor {
  pub fn new(index: usize) -> Self {
    Self { index }
  }
}

impl FeatureExtractor for ArgumentPreconditionFeatureExtractor {
  fn name(&self) -> String {
    format!("arg.{}.pre", self.index)
  }

  fn filter<'ctx>(&self, _: &String, target_type: FunctionType<'ctx>) -> bool {
    self.index < target_type.num_argument_types()
  }

  fn init(&mut self, _: usize, _: &Slice, _: usize, _: &Trace) {}

  fn finalize(&mut self) {}

  fn extract(&self, _: usize, _: &Slice, trace: &Trace) -> serde_json::Value {
    let mut checked = false;
    let mut compared_with_zero = false;
    let mut arg_check_not_zero = false;
    let mut arg_check_is_zero = false;
    let mut is_constant = false;
    let mut is_global = false;
    let mut is_alloca = false;
    let mut is_arg = false;

    let arg = trace.target_arg(self.index);

    if let Some(arg) = arg {
      let args_to_check = args_to_check(arg);

      for arg in args_to_check {
        // Setup kind of argument
        arg_type(&arg, &mut is_global, &mut is_arg, &mut is_constant, &mut is_alloca);

        // We don't do check if the argument is constant
        if is_constant {
          continue;
        }

        // Checks
        for (i, instr) in trace.iter_instrs_from_target(TraceIterDirection::Backward) {
          match &instr.sem {
            Semantics::ICmp { pred, op0, op1 } => {
              let arg_is_op0 = **op0 == arg;
              let arg_is_op1 = **op1 == arg;
              if arg_is_op0 || arg_is_op1 {
                checked = true;

                let other_op = if arg_is_op0 { &**op1 } else { &**op0 };
                match other_op {
                  Value::Int(0) | Value::Null => {
                    compared_with_zero = true;

                    // Search for a branch instruction after the icmp
                    // Only go 5 steps forward
                    for (_, maybe_br) in trace.iter_instrs_from(TraceIterDirection::Forward, i).iter().take(5) {
                      match &maybe_br.sem {
                        Semantics::CondBr { cond, br, .. } => {
                          if &**cond == &instr.res.clone().unwrap() {
                            match (pred, br) {
                              (Predicate::EQ, Branch::Then) | (Predicate::NE, Branch::Else) => {
                                arg_check_is_zero = true;
                              }
                              (Predicate::EQ, Branch::Else) | (Predicate::NE, Branch::Then) => {
                                arg_check_not_zero = true;
                              }
                              _ => {}
                            }
                          }
                        }
                        _ => {}
                      }
                    }
                  }
                  _ => {}
                }
              }
            }
            _ => {}
          }
        }
      }
    }

    json!({
      "checked": checked,
      "compared_with_zero": compared_with_zero,
      "arg_check_is_zero": arg_check_is_zero,
      "arg_check_not_zero": arg_check_not_zero,
      "is_arg": is_arg,
      "is_constant": is_constant,
      "is_global": is_global,
      "is_alloca": is_alloca,
    })
  }
}

fn args_to_check(arg: &Value) -> Vec<Value> {
  match arg {
    Value::AllocOf(v) => vec![vec![arg.clone()], args_to_check(v)].concat(),
    // Value::Int(_) | Value::Null => vec![],
    _ => vec![arg.clone()],
  }
}

fn arg_type(arg: &Value, is_global: &mut bool, is_arg: &mut bool, is_constant: &mut bool, is_alloca: &mut bool) {
  // Setup kind of argument
  match arg {
    Value::Glob(_) => {
      *is_global = true;
    }
    Value::Arg(_) => {
      *is_arg = true;
    }
    Value::ConstSym(_) | Value::Null | Value::Int(_) | Value::Func(_) | Value::Asm => {
      *is_constant = true;
    }
    Value::GEP { loc, .. } => {
      arg_type(&*loc, is_global, is_arg, is_constant, is_alloca);
    }
    Value::Alloc(_) => {
      *is_alloca = true;
    }
    Value::AllocOf(v) => {
      *is_alloca = true;
      arg_type(&*v, is_global, is_arg, is_constant, is_alloca);
    }
    _ => {}
  }
}
