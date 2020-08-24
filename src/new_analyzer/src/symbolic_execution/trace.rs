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

pub trait TraceTrait<'ctx> {
  fn print(&self);

  fn block_trace(&self) -> Vec<Block<'ctx>>;
}

impl<'ctx> TraceTrait<'ctx> for Trace<'ctx> {
  fn print(&self) {
    for node in self.iter() {
      match &node.result {
        Some(result) => println!("{} {:?} -> {:?}", node.instr.debug_loc_string(), node.semantics, result),
        None => println!("{} {:?}", node.instr.debug_loc_string(), node.semantics),
      }
    }
  }

  fn block_trace(&self) -> Vec<Block<'ctx>> {
    let mut bt = vec![];
    for node in self {
      let curr_block = node.instr.parent_block();
      if bt.is_empty() || curr_block != bt[bt.len() - 1] {
        bt.push(curr_block);
      }
    }
    bt
  }
}
