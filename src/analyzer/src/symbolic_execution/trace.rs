// use std::collections::HashSet;
use llir::values::*;
use serde_json::json;
use std::rc::Rc;

use crate::semantics::rced::*;

#[derive(Clone, Debug)]
pub struct TraceNode<'ctx> {
  pub instr: Instruction<'ctx>,
  pub semantics: Semantics,
  pub result: Option<Rc<Value>>,
}

pub type Trace<'ctx> = Vec<TraceNode<'ctx>>;

pub struct TraceWithTarget<'ctx> {
  pub trace: Trace<'ctx>,
  pub target_index: usize,
  pub statically_checked: bool,
}

impl<'ctx> TraceWithTarget<'ctx> {
  pub fn new(trace: Trace<'ctx>, target_index: usize, statically_checked: bool) -> Self {
    Self { trace, target_index, statically_checked }
  }

  pub fn target(&self) -> &TraceNode<'ctx> {
    &self.trace[self.target_index]
  }

  pub fn reduce(self) -> Self {
    self
  }

  pub fn to_json(&self) -> serde_json::Value {
    json!({
      "instrs": self.trace.iter().map(|node| json!({
        "loc": node.instr.debug_loc_string(),
        "sem": node.semantics,
        "res": node.result
      })).collect::<Vec<_>>(),
      "target": self.target_index,
      "statically_checked": self.statically_checked,
    })
  }

  pub fn block_trace(&self) -> Vec<Block<'ctx>> {
    let mut bt = vec![];
    for node in &self.trace {
      let curr_block = node.instr.parent_block();
      if bt.is_empty() || curr_block != bt[bt.len() - 1] {
        bt.push(curr_block);
      }
    }
    bt
  }

  pub fn print(&self) {
    for (i, node) in self.trace.iter().enumerate() {
      if i == self.target_index {
        print!("-> TARGET ");
      }
      match &node.result {
        Some(result) => println!("{} {:?} -> {:?}", node.instr.debug_loc_string(), node.semantics, result),
        None => println!("{} {:?}", node.instr.debug_loc_string(), node.semantics),
      }
    }
  }
}
