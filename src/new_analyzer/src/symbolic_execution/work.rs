use llir::values::*;

use super::state::*;
use crate::slicer::*;

pub trait BlockTraceComparison {
  fn equals(&self, other: &Self) -> bool;
}

impl<'ctx> BlockTraceComparison for Vec<Block<'ctx>> {
  fn equals(&self, other: &Self) -> bool {
    if self.len() != other.len() {
      false
    } else {
      for i in 0..self.len() {
        if self[i] != other[i] {
          return false;
        }
      }
      true
    }
  }
}

pub struct Work<'ctx> {
  pub block: Block<'ctx>,
  pub state: State<'ctx>,
}

impl<'ctx> Work<'ctx> {
  pub fn entry(slice: &Slice<'ctx>) -> Self {
    let block = slice.entry.first_block().unwrap();
    let state = State::new(slice);
    Self { block, state }
  }
}
