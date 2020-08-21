use llir::values::*;

use crate::call_graph::CallGraph;
use crate::slicer::Slice;

pub type BlockTrace<'ctx> = Vec<Block<'ctx>>;

pub trait BlockTraceTrait<'ctx> {
  fn equals(&self, other: &Self) -> bool;
}

impl<'ctx> BlockTraceTrait<'ctx> for BlockTrace<'ctx> {
  fn equals(&self, other: &Self) -> bool {
    if self.len() == other.len() {
      for i in 0..self.len() {
        if self[i] != other[i] {
          return false;
        }
      }
      true
    } else {
      false
    }
  }
}

pub struct BlockTraceIterator<'ctx> {
  pub trace: BlockTrace<'ctx>,
  pub curr_pointer: usize,
}

impl<'ctx> BlockTraceIterator<'ctx> {
  pub fn new(trace: BlockTrace<'ctx>) -> Self {
    Self { trace, curr_pointer: 0 }
  }

  // pub fn peek_curr(&self) -> &Block<'ctx> {
  //   &self.trace[self.curr_pointer]
  // }

  // pub fn peek_next(&self) -> Option<&Block<'ctx>> {
  //   self.trace.get(self.curr_pointer + 1)
  // }

  // pub fn next(&mut self) -> Option<&Block<'ctx>> {
  //   self.curr_pointer += 1;
  //   self.trace.get(self.curr_pointer)
  // }

  // pub fn has_next(&self) -> bool {
  //   self.curr_pointer < self.trace.len()
  // }
}

pub struct BlockTracer<'a, 'ctx> {
  pub call_graph: &'a CallGraph<'ctx>
}

impl<'a, 'ctx> BlockTracer<'a, 'ctx> {
  pub fn block_traces(&self, slice: Slice<'ctx>) -> Vec<BlockTrace<'ctx>> {
    vec![]
  }
}
