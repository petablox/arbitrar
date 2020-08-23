use std::rc::Rc;

use llir::values::*;

use crate::semantics::*;

#[derive(Clone)]
pub struct TraceNode<'ctx> {
  pub instr: Instruction<'ctx>,
  pub semantics: Semantics,
  pub result: Option<Rc<Value>>,
}

pub type Trace<'ctx> = Vec<TraceNode<'ctx>>;

pub trait TraceTrait {
  fn print(&self);
}

impl<'ctx> TraceTrait for Trace<'ctx> {
  fn print(&self) {
    for node in self.iter() {
      match &node.result {
        Some(result) => println!("{} {:?} -> {:?}", node.instr.debug_loc_string(), node.semantics, result),
        None => println!("{} {:?}", node.instr.debug_loc_string(), node.semantics),
      }
    }
  }
}
