use std::collections::HashMap;

use llir::values::*;

use super::block_tracer::*;
use super::constraints::*;
use super::memory::*;
use super::trace::*;
use crate::semantics::rced::*;
use crate::slicer::*;

#[derive(Clone, Debug)]
pub enum FinishState {
  ProperlyReturned,
  BranchExplored,
  ExceedingMaxTraceLength,
  Unreachable,
}

#[derive(Clone, Debug)]
pub struct State<'ctx> {
  pub stack: Stack<'ctx>,
  pub memory: Memory,
  pub block_trace_iter: BlockTraceIterator<'ctx>,
  pub visited_branch: VisitedBranch<'ctx>,
  pub trace: Trace<'ctx>,
  pub target_node: Option<usize>,
  pub statically_checked: bool,
  pub prev_block: Option<Block<'ctx>>,
  pub finish_state: FinishState,
  pub pointer_value_id_map: HashMap<GenericValue<'ctx>, usize>,
  pub constraints: Constraints,

  // Identifiers
  alloca_id: usize,
  symbol_id: usize,
  pointer_value_id: usize,
}

impl<'ctx> State<'ctx> {
  pub fn new(slice: &Slice<'ctx>) -> Self {
    Self {
      stack: vec![StackFrame::entry(slice.entry)],
      memory: Memory::new(),
      block_trace_iter: BlockTraceIterator::empty(),
      visited_branch: VisitedBranch::new(),
      trace: Vec::new(),
      target_node: None,
      statically_checked: false,
      prev_block: None,
      finish_state: FinishState::ProperlyReturned,
      pointer_value_id_map: HashMap::new(),
      constraints: Vec::new(),
      alloca_id: 0,
      symbol_id: 0,
      pointer_value_id: 0,
    }
  }

  pub fn from_block_trace(slice: &Slice<'ctx>, block_trace: BlockTrace<'ctx>) -> Self {
    Self {
      stack: vec![StackFrame::entry(slice.entry)],
      memory: Memory::new(),
      block_trace_iter: BlockTraceIterator::from_block_trace(block_trace),
      visited_branch: VisitedBranch::new(),
      trace: Vec::new(),
      target_node: None,
      statically_checked: false,
      prev_block: None,
      finish_state: FinishState::ProperlyReturned,
      pointer_value_id_map: HashMap::new(),
      constraints: Vec::new(),
      alloca_id: 0,
      symbol_id: 0,
      pointer_value_id: 0,
    }
  }

  pub fn new_alloca_id(&mut self) -> usize {
    let result = self.alloca_id;
    self.alloca_id += 1;
    result
  }

  pub fn new_symbol_id(&mut self) -> usize {
    let result = self.symbol_id;
    self.symbol_id += 1;
    result
  }

  pub fn add_constraint(&mut self, cond: Comparison, branch: bool) {
    self.constraints.push(Constraint { cond, branch });
  }
}
