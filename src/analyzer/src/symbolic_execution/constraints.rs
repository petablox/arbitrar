use std::collections::HashMap;

use crate::semantics::rced::*;

#[derive(Debug, Clone)]
pub struct Constraint {
  pub cond: Comparison,
  pub branch: bool,
}

pub type Constraints = Vec<Constraint>;

pub trait ConstraintsTrait {
  fn sat(&self) -> bool;
}

impl ConstraintsTrait for Constraints {
  fn sat(&self) -> bool {
    use z3::*;
    let z3_ctx = Context::new(&z3::Config::default());
    let solver = Solver::new(&z3_ctx);
    let mut symbol_map = HashMap::new();
    let mut symbol_id = 0;
    for Constraint { cond, branch } in self.iter() {
      match cond.into_z3_ast(&mut symbol_map, &mut symbol_id, &z3_ctx) {
        Some(cond) => {
          let formula = if *branch { cond } else { cond.not() };
          println!("{:?}", formula);
          solver.assert(&formula);
        }
        _ => (),
      }
    }
    match solver.check() {
      SatResult::Sat | SatResult::Unknown => true,
      _ => false,
    }
  }
}
