use llir::values::*;

use super::*;
use crate::slicer::*;

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

  pub fn entry_with_block_trace(slice: &Slice<'ctx>, block_trace: BlockTrace<'ctx>) -> Self {
    let block = slice.entry.first_block().unwrap();
    let state = State::from_block_trace(slice, block_trace);
    Self { block, state }
  }

  pub fn new(block: Block<'ctx>, state: State<'ctx>) -> Self {
    Self { block, state }
  }
}
