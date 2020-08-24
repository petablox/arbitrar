use llir::values::*;

use crate::slicer::*;
use crate::symbolic_execution::*;
use crate::utils::*;

pub struct Environment<'ctx> {
  pub slice: Slice<'ctx>,
  pub work_list: Vec<Work<'ctx>>,
  pub block_traces: Vec<Vec<Block<'ctx>>>,
  pub call_id: usize,
}

impl<'ctx> Environment<'ctx> {
  pub fn new(slice: &Slice<'ctx>) -> Self {
    Self {
      slice: slice.clone(),
      work_list: vec![],
      block_traces: vec![],
      call_id: 0,
    }
  }

  pub fn has_work(&self) -> bool {
    !self.work_list.is_empty()
  }

  pub fn pop_work(&mut self) -> Work<'ctx> {
    self.work_list.pop().unwrap()
  }

  pub fn add_work(&mut self, work: Work<'ctx>) {
    self.work_list.push(work);
  }

  pub fn new_call_id(&mut self) -> usize {
    let result = self.call_id;
    self.call_id += 1;
    result
  }

  pub fn add_block_trace(&mut self, block_trace: &Vec<Block<'ctx>>) {
    self.block_traces.push(block_trace.clone())
  }

  pub fn has_duplicate(&self, block_trace: &Vec<Block<'ctx>>) -> bool {
    for other_block_trace in self.block_traces.iter() {
      if block_trace.equals(other_block_trace) {
        return true;
      }
    }
    false
  }
}
