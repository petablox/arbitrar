use clap::{App, ArgMatches};
use inkwell::{basic_block::BasicBlock, values::*};
use petgraph::graph::DiGraph;
use rayon::prelude::*;
use std::collections::{HashMap, HashSet};

use crate::context::AnalyzerContext;
use crate::options::Options;
use crate::slicer::Slice;

pub struct SymbolicExecutionOptions {}

impl Options for SymbolicExecutionOptions {
  fn setup_parser<'a>(app: App<'a>) -> App<'a> {
    app
  }

  fn from_matches(_: &ArgMatches) -> Result<Self, String> {
    Ok(Self {})
  }
}

pub enum BinOp {
  Add,
  Sub,
  Mul,
  Div,
  Rem,
  Lshr,
  Ashr,
  Band,
  Bor,
  Bxor,
}

pub enum Predicate {
  Eq,
  Ne,
  Ge,
  Geq,
  Le,
  Leq,
}

pub enum Value<'ctx> {
  Argument(BasicValueEnum<'ctx>),
  Global(GlobalValue<'ctx>),
  ConstInt(i32),
  Location(Box<Location<'ctx>>),
  BinaryOperation(BinOp, Box<Value<'ctx>>, Box<Value<'ctx>>),
  Call(i32, FunctionValue<'ctx>, Vec<Value<'ctx>>),
  Comparison(Predicate, Box<Value<'ctx>>, Box<Value<'ctx>>),
}

pub enum Location<'ctx> {
  Argument(BasicValueEnum<'ctx>),
  Alloca(InstructionValue<'ctx>),
  Global(GlobalValue<'ctx>),
  GetElementPtr(Box<Location<'ctx>>, Vec<u32>),
  Value(Box<Value<'ctx>>),
  Unknown,
}

pub type LocalMemory<'ctx> = HashMap<InstructionValue<'ctx>, Value<'ctx>>;

pub struct StackFrame<'ctx> {
  pub function: FunctionValue<'ctx>,
  pub instr: Option<InstructionValue<'ctx>>,
  pub memory: LocalMemory<'ctx>,
}

impl<'ctx> StackFrame<'ctx> {
  pub fn entry(function: FunctionValue<'ctx>) -> Self {
    Self { function, instr: None, memory: LocalMemory::new() }
  }
}

pub type Stack<'ctx> = Vec<StackFrame<'ctx>>;

pub type Memory<'ctx> = HashMap<Location<'ctx>, Value<'ctx>>;

pub struct Branch<'ctx> {
  pub from: BasicBlock<'ctx>,
  pub to: BasicBlock<'ctx>,
}

pub type VisitedBranch<'ctx> = HashSet<Branch<'ctx>>;

pub type GlobalUsage<'ctx> = HashMap<GlobalValue<'ctx>, InstructionValue<'ctx>>;

pub struct TraceNode<'ctx> {
  pub instr: InstructionValue<'ctx>,
  pub result: Option<Value<'ctx>>,
}

pub enum TraceGraphEdge {
  DefUse,
  ControlFlow,
}

pub type TraceGraph<'ctx> = DiGraph<TraceNode<'ctx>, TraceGraphEdge>;

pub struct State<'ctx> {
  pub stack: Stack<'ctx>,
  pub memory: Memory<'ctx>,
  pub visited_branch: HashSet<Branch<'ctx>>,
  pub global_usage: GlobalUsage<'ctx>,
  // pub path_constraints
  pub trace_graph: TraceGraph<'ctx>,
}

impl<'ctx> State<'ctx> {
  pub fn new(slice: &Slice<'ctx>) -> Self {
    Self {
      stack: vec![StackFrame::entry(slice.entry)],
      memory: Memory::new(),
      visited_branch: VisitedBranch::new(),
      global_usage: GlobalUsage::new(),
      trace_graph: TraceGraph::new(),
    }
  }
}

pub struct Work<'ctx> {
  pub block: BasicBlock<'ctx>,
  pub state: State<'ctx>,
}

impl<'ctx> Work<'ctx> {
  pub fn entry(slice: &Slice<'ctx>) -> Self {
    let block = slice.entry.get_first_basic_block().unwrap();
    let state = State::new(slice);
    Self { block, state }
  }
}

pub struct Environment<'ctx> {
  pub slice: Slice<'ctx>,
  pub work_list: Vec<Work<'ctx>>,
}

impl<'ctx> Environment<'ctx> {
  pub fn new(slice: Slice<'ctx>) -> Self {
    let initial_work = Work::entry(&slice);
    Self {
      slice,
      work_list: vec![initial_work],
    }
  }

  pub fn has_work(&self) -> bool {
    !self.work_list.is_empty()
  }

  pub fn pop_work(&mut self) -> Work<'ctx> {
    self.work_list.pop().unwrap()
  }
}

pub struct SymbolicExecutionContext<'a, 'ctx> {
  pub ctx: &'a AnalyzerContext<'ctx>,
  pub options: SymbolicExecutionOptions,
}

unsafe impl<'a, 'ctx> Sync for SymbolicExecutionContext<'a, 'ctx> {}

impl<'a, 'ctx> SymbolicExecutionContext<'a, 'ctx> {
  pub fn new(ctx: &'a AnalyzerContext<'ctx>) -> Result<Self, String> {
    let options = SymbolicExecutionOptions::from_matches(&ctx.args)?;
    Ok(Self { ctx, options })
  }

  pub fn execute_function(&self, func: FunctionValue<'ctx>, args: Vec<Value<'ctx>>, state: State<'ctx>, env: &mut Environment<'ctx>) -> State<'ctx> {
    state
  }

  pub fn execute_block(&self, block: BasicBlock<'ctx>, state: State<'ctx>, env: &mut Environment<'ctx>) -> State<'ctx> {
    state
  }

  pub fn execute_instr(&self, instr: InstructionValue<'ctx>, state: State<'ctx>, env: &mut Environment<'ctx>) -> State<'ctx> {
    state
  }

  pub fn execute_slice(&self, slice: Slice<'ctx>) {
    let mut env = Environment::new(slice);
    while env.has_work() {
      let work = env.pop_work();
      let final_state = self.execute_block(work.block, work.state, &mut env);
    }
  }

  pub fn execute_slices(&self, slices: Vec<Slice<'ctx>>) {
    let f = |slice| self.execute_slice(slice);
    if self.ctx.options.use_serial {
      slices.into_iter().for_each(f);
    } else {
      slices.into_par_iter().for_each(f);
    }
  }
}
