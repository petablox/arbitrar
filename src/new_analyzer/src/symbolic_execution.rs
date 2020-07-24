use clap::{App, Arg, ArgMatches};
use inkwell::{basic_block::BasicBlock, values::*};
use petgraph::graph::{DiGraph, NodeIndex};
use rayon::prelude::*;
use serde_json::Value as Json;
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};

use crate::context::AnalyzerContext;
use crate::options::Options;
use crate::slicer::Slice;

pub struct SymbolicExecutionOptions {
  pub max_trace_per_slice: usize,
  pub max_explored_trace_per_slice: usize,
  pub no_trace_reduction: bool,
}

impl Options for SymbolicExecutionOptions {
  fn setup_parser<'a>(app: App<'a>) -> App<'a> {
    app.args(&[
      Arg::new("max_trace_per_slice")
        .value_name("MAX_TRACE_PER_SLICE")
        .takes_value(true)
        .long("max-trace-per-slice")
        .about("The maximum number of generated trace per slice")
        .default_value("50"),
      Arg::new("max_explored_trace_per_slice")
        .value_name("MAX_EXPLORED_TRACE_PER_SLICE")
        .takes_value(true)
        .long("max-explored-trace-per-slice")
        .about("The maximum number of explroed trace per slice")
        .default_value("1000"),
      Arg::new("no_reduce_trace")
        .long("no-reduce-trace")
        .about("No trace reduction"),
    ])
  }

  fn from_matches(matches: &ArgMatches) -> Result<Self, String> {
    Ok(Self {
      max_trace_per_slice: matches.value_of_t::<usize>("max_trace_per_slice").unwrap(),
      max_explored_trace_per_slice: matches
        .value_of_t::<usize>("max_explored_trace_per_slice")
        .unwrap(),
      no_trace_reduction: matches.is_present("no-reduce-trace"),
    })
  }
}

#[derive(Clone)]
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

#[derive(Clone)]
pub enum Predicate {
  Eq,
  Ne,
  Ge,
  Geq,
  Le,
  Leq,
}

#[derive(Clone)]
pub enum Value<'ctx> {
  Argument(BasicValueEnum<'ctx>),
  Global(GlobalValue<'ctx>),
  ConstInt(i32),
  Location(Box<Location<'ctx>>),
  BinaryOperation(BinOp, Box<Value<'ctx>>, Box<Value<'ctx>>),
  Call(i32, FunctionValue<'ctx>, Vec<Value<'ctx>>),
  Comparison(Predicate, Box<Value<'ctx>>, Box<Value<'ctx>>),
  Unknown,
}

#[derive(Clone)]
pub enum Location<'ctx> {
  Argument(BasicValueEnum<'ctx>),
  Alloca(InstructionValue<'ctx>),
  Global(GlobalValue<'ctx>),
  GetElementPtr(Box<Location<'ctx>>, Vec<u32>),
  Value(Box<Value<'ctx>>),
  Unknown,
}

pub type LocalMemory<'ctx> = HashMap<InstructionValue<'ctx>, Value<'ctx>>;

#[derive(Clone)]
pub struct StackFrame<'ctx> {
  pub function: FunctionValue<'ctx>,
  pub instr: Option<InstructionValue<'ctx>>,
  pub memory: LocalMemory<'ctx>,
}

impl<'ctx> StackFrame<'ctx> {
  pub fn entry(function: FunctionValue<'ctx>) -> Self {
    Self {
      function,
      instr: None,
      memory: LocalMemory::new(),
    }
  }
}

pub type Stack<'ctx> = Vec<StackFrame<'ctx>>;

pub type Memory<'ctx> = HashMap<Location<'ctx>, Value<'ctx>>;

#[derive(Clone)]
pub struct Branch<'ctx> {
  pub from: BasicBlock<'ctx>,
  pub to: BasicBlock<'ctx>,
}

pub type VisitedBranch<'ctx> = HashSet<Branch<'ctx>>;

pub type GlobalUsage<'ctx> = HashMap<GlobalValue<'ctx>, InstructionValue<'ctx>>;

#[derive(Clone)]
pub struct TraceNode<'ctx> {
  pub instr: InstructionValue<'ctx>,
  pub result: Option<Value<'ctx>>,
}

#[derive(Clone)]
pub enum TraceGraphEdge {
  DefUse,
  ControlFlow,
}

pub type TraceGraph<'ctx> = DiGraph<TraceNode<'ctx>, TraceGraphEdge>;

pub trait TraceGraphTrait<'ctx> {
  fn to_json(&self) -> Json;

  fn reduce(self, target: NodeIndex) -> Self;
}

impl<'ctx> TraceGraphTrait<'ctx> for TraceGraph<'ctx> {
  fn to_json(&self) -> Json {
    Json::Null
  }

  fn reduce(self, target: NodeIndex) -> Self {
    self
  }
}

#[derive(Clone)]
pub enum FinishState {
  ProperlyReturned,
  BranchExplored,
  ExceedingMaxTraceLength,
  Unreachable,
}

#[derive(Clone)]
pub struct State<'ctx> {
  pub stack: Stack<'ctx>,
  pub memory: Memory<'ctx>,
  pub visited_branch: HashSet<Branch<'ctx>>,
  pub global_usage: GlobalUsage<'ctx>,
  pub trace_graph: TraceGraph<'ctx>,
  pub target_node: Option<NodeIndex>,
  pub finish_state: FinishState,
}

impl<'ctx> State<'ctx> {
  pub fn new(slice: &Slice<'ctx>) -> Self {
    Self {
      stack: vec![StackFrame::entry(slice.entry)],
      memory: Memory::new(),
      visited_branch: VisitedBranch::new(),
      global_usage: GlobalUsage::new(),
      trace_graph: TraceGraph::new(),
      target_node: None,
      finish_state: FinishState::ProperlyReturned,
    }
  }

  pub fn passed_target(&self) -> bool {
    self.target_node.is_some()
  }

  pub fn path_satisfactory(&self) -> bool {
    // TODO
    true
  }

  pub fn dump_json(&self, path: PathBuf) {}
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

  pub fn has_duplicate(&self, state: &State<'ctx>) -> bool {
    // TODO
    false
  }
}

pub struct MetaData {
  pub proper_trace_count: usize,
  pub path_unsat_trace_count: usize,
  pub branch_explored_trace_count: usize,
  pub duplicate_trace_count: usize,
  pub no_target_trace_count: usize,
  pub exceeding_length_trace_count: usize,
  pub unreachable_trace_count: usize,
  pub explored_trace_count: usize,
}

impl MetaData {
  pub fn new() -> Self {
    MetaData {
      proper_trace_count: 0,
      path_unsat_trace_count: 0,
      branch_explored_trace_count: 0,
      duplicate_trace_count: 0,
      no_target_trace_count: 0,
      exceeding_length_trace_count: 0,
      unreachable_trace_count: 0,
      explored_trace_count: 0,
    }
  }

  pub fn combine(self, other: Self) -> Self {
    MetaData {
      proper_trace_count: self.proper_trace_count + other.proper_trace_count,
      path_unsat_trace_count: self.path_unsat_trace_count + other.path_unsat_trace_count,
      branch_explored_trace_count: self.branch_explored_trace_count
        + other.branch_explored_trace_count,
      duplicate_trace_count: self.duplicate_trace_count + other.duplicate_trace_count,
      no_target_trace_count: self.no_target_trace_count + other.no_target_trace_count,
      exceeding_length_trace_count: self.exceeding_length_trace_count
        + other.exceeding_length_trace_count,
      unreachable_trace_count: self.unreachable_trace_count + other.unreachable_trace_count,
      explored_trace_count: self.explored_trace_count + other.explored_trace_count,
    }
  }

  pub fn incr_proper(&mut self) {
    self.proper_trace_count += 1;
    self.explored_trace_count += 1;
  }

  pub fn incr_path_unsat(&mut self) {
    self.path_unsat_trace_count += 1;
    self.explored_trace_count += 1;
  }

  pub fn incr_branch_explored(&mut self) {
    self.branch_explored_trace_count += 1;
    self.explored_trace_count += 1;
  }

  pub fn incr_duplicated(&mut self) {
    self.duplicate_trace_count += 1;
    self.explored_trace_count += 1;
  }

  pub fn incr_no_target(&mut self) {
    self.no_target_trace_count += 1;
    self.explored_trace_count += 1;
  }

  pub fn incr_exceeding_length(&mut self) {
    self.exceeding_length_trace_count += 1;
    self.explored_trace_count += 1;
  }

  pub fn incr_unreachable(&mut self) {
    self.unreachable_trace_count += 1;
    self.explored_trace_count += 1;
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

  pub fn trace_file_name(&self, func_name: String, slice_id: usize, trace_id: usize) -> PathBuf {
    Path::new(self.ctx.options.output_path.as_str())
      .join("traces")
      .join(func_name.as_str())
      .join(slice_id.to_string())
      .join(trace_id.to_string())
  }

  pub fn execute_function(
    &self,
    func: FunctionValue<'ctx>,
    args: Vec<Value<'ctx>>,
    state: &mut State<'ctx>,
    env: &mut Environment<'ctx>,
  ) {
  }

  pub fn execute_block(
    &self,
    block: BasicBlock<'ctx>,
    state: &mut State<'ctx>,
    env: &mut Environment<'ctx>,
  ) {
  }

  pub fn execute_instr(
    &self,
    instr: InstructionValue<'ctx>,
    state: &mut State<'ctx>,
    env: &mut Environment<'ctx>,
  ) {

  }

  pub fn execute_slice(&self, slice: Slice<'ctx>, slice_id: usize) -> MetaData {
    let mut metadata = MetaData::new();
    let mut env = Environment::new(slice);
    while env.has_work() {
      let mut work = env.pop_work();
      self.execute_block(work.block, &mut work.state, &mut env);
      match work.state.target_node {
        Some(target_id) => {
          match work.state.finish_state {
            FinishState::ProperlyReturned => {
              if !env.has_duplicate(&work.state) {
                if work.state.path_satisfactory() {
                  if !self.options.no_trace_reduction {
                    work.state.trace_graph = work.state.trace_graph.reduce(target_id);
                  }
                  let trace_id = metadata.proper_trace_count;
                  let path =
                    self.trace_file_name(env.slice.target_function_name(), slice_id, trace_id);
                    work.state.dump_json(path);
                  metadata.incr_proper();
                } else {
                  metadata.incr_path_unsat();
                }
              } else {
                metadata.incr_duplicated();
              }
            }
            FinishState::BranchExplored => {
              metadata.incr_branch_explored();
            }
            FinishState::ExceedingMaxTraceLength => {
              metadata.incr_exceeding_length();
            }
            FinishState::Unreachable => {
              metadata.incr_unreachable();
            }
          }
        },
        None => {
          metadata.incr_no_target()
        }
      }

      // Stop when running out of fuel
      if metadata.explored_trace_count >= self.options.max_explored_trace_per_slice
        || metadata.proper_trace_count >= self.options.max_trace_per_slice
      {
        break;
      }
    }
    metadata
  }

  pub fn execute_slices(&self, slices: Vec<Slice<'ctx>>) -> MetaData {
    let f = |meta: MetaData, (slice_id, slice): (usize, Slice<'ctx>)| {
      meta.combine(self.execute_slice(slice, slice_id))
    };
    if self.ctx.options.use_serial {
      slices.into_iter().enumerate().fold(MetaData::new(), f)
    } else {
      slices
        .into_par_iter()
        .enumerate()
        .fold(|| MetaData::new(), f)
        .reduce(|| MetaData::new(), MetaData::combine)
    }
  }
}
