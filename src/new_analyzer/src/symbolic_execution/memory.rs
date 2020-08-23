use llir::values::*;
use std::collections::{HashMap, HashSet};
use std::rc::Rc;

use crate::semantics::*;

pub type LocalMemory<'ctx> = HashMap<Instruction<'ctx>, Rc<Value>>;

#[derive(Clone)]
pub struct StackFrame<'ctx> {
  pub function: Function<'ctx>,
  pub instr: Option<(usize, CallInstruction<'ctx>)>,
  pub memory: LocalMemory<'ctx>,
  pub arguments: Vec<Rc<Value>>,
}

impl<'ctx> StackFrame<'ctx> {
  pub fn entry(function: Function<'ctx>) -> Self {
    Self {
      function,
      instr: None,
      memory: LocalMemory::new(),
      arguments: (0..function.num_arguments())
        .map(|i| Rc::new(Value::Arg(i as usize)))
        .collect(),
    }
  }
}

pub type Stack<'ctx> = Vec<StackFrame<'ctx>>;

pub trait StackTrait<'ctx> {
  fn top(&self) -> &StackFrame<'ctx>;

  fn top_mut(&mut self) -> &mut StackFrame<'ctx>;

  fn has_function(&self, func: Function<'ctx>) -> bool;
}

impl<'ctx> StackTrait<'ctx> for Stack<'ctx> {
  fn top(&self) -> &StackFrame<'ctx> {
    &self[self.len() - 1]
  }

  fn top_mut(&mut self) -> &mut StackFrame<'ctx> {
    let id = self.len() - 1;
    &mut self[id]
  }

  fn has_function(&self, func: Function<'ctx>) -> bool {
    self.iter().find(|frame| frame.function == func).is_some()
  }
}

pub type Memory = HashMap<Rc<Value>, Rc<Value>>;

#[derive(Clone, Copy, PartialEq, Eq, Hash)]
pub struct BranchDirection<'ctx> {
  pub from: Block<'ctx>,
  pub to: Block<'ctx>,
}

pub type VisitedBranch<'ctx> = HashSet<BranchDirection<'ctx>>;

#[derive(Debug, Clone)]
pub struct Constraint {
  pub cond: Comparison,
  pub branch: bool,
}
