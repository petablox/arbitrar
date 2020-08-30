use std::rc::Rc;
use std::fs::File;
use std::io::Write;
use std::path::PathBuf;
use serde_json::json;
use llir::values::*;

use crate::semantics::rced::*;

#[derive(Clone)]
pub struct TraceNode<'ctx> {
  pub instr: Instruction<'ctx>,
  pub semantics: Semantics,
  pub result: Option<Rc<Value>>,
}

pub type Trace<'ctx> = Vec<TraceNode<'ctx>>;

pub struct TraceWithTarget<'ctx> {
  pub trace: Trace<'ctx>,
  pub target_index: usize,
}

impl<'ctx> TraceWithTarget<'ctx> {
  pub fn new(trace: Trace<'ctx>, target_index: usize) -> Self {
    Self { trace, target_index }
  }

  pub fn reduce(&self) -> Self {
    panic!("Not implemented")
  }

  pub fn to_json(&self) -> serde_json::Value {
    json!({
      "instrs": self.trace.iter().map(|node| json!({
        "loc": node.instr.debug_loc_string(),
        "sem": node.semantics,
        "res": node.result
      })).collect::<Vec<_>>(),
      "target": self.target_index,
    })
  }

  pub fn dump_json(&self, path: PathBuf) -> Result<(), String> {
    let trace_json = self.to_json();
    let json_str = serde_json::to_string(&trace_json).map_err(|_| "Cannot turn trace into json".to_string())?;
    let mut file = File::create(path).map_err(|_| "Cannot create trace file".to_string())?;
    file
      .write_all(json_str.as_bytes())
      .map_err(|_| "Cannot write to trace file".to_string())
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