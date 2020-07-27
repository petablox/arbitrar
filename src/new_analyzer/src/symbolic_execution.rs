use clap::{App, Arg, ArgMatches};
use inkwell::{basic_block::BasicBlock, values::*};
// use petgraph::graph::{DiGraph, NodeIndex};
use rayon::prelude::*;
// use serde_json::Value as Json;
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};

use crate::context::AnalyzerContext;
use crate::ll_utils::*;
use crate::semantics::*;
use crate::options::Options;
use crate::slicer::Slice;

pub struct SymbolicExecutionOptions {
  pub max_trace_per_slice: usize,
  pub max_explored_trace_per_slice: usize,
  pub max_node_per_trace: usize,
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
      Arg::new("max_node_per_trace")
        .value_name("MAX_NODE_PER_TRACE")
        .takes_value(true)
        .long("max-node-per-trace")
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
      max_node_per_trace: matches.value_of_t::<usize>("max_node_per_trace").unwrap(),
      no_trace_reduction: matches.is_present("no-reduce-trace"),
    })
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

pub type LocalMemory<'ctx> = HashMap<InstructionValue<'ctx>, Value>;

#[derive(Clone)]
pub struct StackFrame<'ctx> {
  pub function: FunctionValue<'ctx>,
  pub instr: Option<InstructionValue<'ctx>>,
  pub memory: LocalMemory<'ctx>,
  pub arguments: Vec<Value>,
}

impl<'ctx> StackFrame<'ctx> {
  pub fn entry(function: FunctionValue<'ctx>) -> Self {
    Self {
      function,
      instr: None,
      memory: LocalMemory::new(),
      arguments: vec![],
    }
  }
}

pub type Stack<'ctx> = Vec<StackFrame<'ctx>>;

pub trait StackTrait<'ctx> {
  fn top(&self) -> &StackFrame<'ctx>;

  fn top_mut(&mut self) -> &mut StackFrame<'ctx>;
}

impl<'ctx> StackTrait<'ctx> for Stack<'ctx> {
  fn top(&self) -> &StackFrame<'ctx> {
    &self[self.len() - 1]
  }

  fn top_mut(&mut self) -> &mut StackFrame<'ctx> {
    let id = self.len() - 1;
    &mut self[id]
  }
}

pub type Memory = HashMap<Location, Value>;

#[derive(Clone, Copy, PartialEq, Eq, Hash)]
pub struct BranchDirection<'ctx> {
  pub from: BasicBlock<'ctx>,
  pub to: BasicBlock<'ctx>,
}

pub type VisitedBranch<'ctx> = HashSet<BranchDirection<'ctx>>;

pub type GlobalUsage<'ctx> = HashMap<GlobalValue<'ctx>, InstructionValue<'ctx>>;

#[derive(Clone)]
pub struct TraceNode<'ctx> {
  pub instr: InstructionValue<'ctx>,
  pub semantics: Instruction,
}

// #[derive(Clone)]
// pub enum TraceGraphEdge {
//   DefUse,
//   ControlFlow,
// }

// pub type TraceGraph<'ctx> = DiGraph<TraceNode<'ctx>, TraceGraphEdge>;

// pub trait TraceGraphTrait<'ctx> {
//   fn to_json(&self) -> Json;

//   fn reduce(self, target: NodeIndex) -> Self;
// }

// impl<'ctx> TraceGraphTrait<'ctx> for TraceGraph<'ctx> {
//   fn to_json(&self) -> Json {
//     Json::Null
//   }

//   fn reduce(self, target: NodeIndex) -> Self {
//     self
//   }
// }

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
  pub memory: Memory,
  pub visited_branch: VisitedBranch<'ctx>,
  pub global_usage: GlobalUsage<'ctx>,
  pub trace: Vec<TraceNode<'ctx>>,
  // pub trace_graph: TraceGraph<'ctx>,
  pub target_node: Option<usize>,
  pub prev_block: Option<BasicBlock<'ctx>>,
  pub finish_state: FinishState,

  // Identifiers
  alloca_id: usize,
}

impl<'ctx> State<'ctx> {
  pub fn new(slice: &Slice<'ctx>) -> Self {
    Self {
      stack: vec![StackFrame::entry(slice.entry)],
      memory: Memory::new(),
      visited_branch: VisitedBranch::new(),
      global_usage: GlobalUsage::new(),
      // trace_graph: TraceGraph::new(),
      trace: Vec::new(),
      target_node: None,
      prev_block: None,
      finish_state: FinishState::ProperlyReturned,
      alloca_id: 0,
    }
  }

  pub fn new_alloca_id(&mut self) -> usize {
    let result = self.alloca_id;
    self.alloca_id += 1;
    result
  }

  pub fn _passed_target(&self) -> bool {
    self.target_node.is_some()
  }

  pub fn path_satisfactory(&self) -> bool {
    // TODO
    true
  }

  pub fn dump_json(&self, _path: PathBuf) {
    // TODO
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
  call_id: usize,
}

impl<'ctx> Environment<'ctx> {
  pub fn new(slice: Slice<'ctx>) -> Self {
    let initial_work = Work::entry(&slice);
    Self {
      slice,
      work_list: vec![initial_work],
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

  pub fn has_duplicate(&self, state: &State<'ctx>) -> bool {
    // TODO
    false
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
    instr: InstructionValue<'ctx>,
    func: FunctionValue<'ctx>,
    args: Vec<Value>,
    state: &mut State<'ctx>,
    env: &mut Environment<'ctx>,
  ) {
    match func.get_first_basic_block() {
      Some(block) => {
        let stack_frame = StackFrame {
          function: func,
          instr: Some(instr),
          memory: LocalMemory::new(),
          arguments: args,
        };
        state.stack.push(stack_frame);
        self.execute_block(block, state, env);
      }
      None => {}
    }
  }

  pub fn execute_block(
    &self,
    block: BasicBlock<'ctx>,
    state: &mut State<'ctx>,
    env: &mut Environment<'ctx>,
  ) {
    self.execute_instr(block.get_first_instruction(), state, env)
  }

  pub fn execute_instr(
    &self,
    instr: Option<InstructionValue<'ctx>>,
    state: &mut State<'ctx>,
    env: &mut Environment<'ctx>,
  ) {
    if state.trace.len() > self.options.max_node_per_trace {
      state.finish_state = FinishState::ExceedingMaxTraceLength;
      return;
    }

    match instr {
      Some(instr) => {
        use InstructionOpcode::*;
        let transfer_function = match instr.get_opcode() {
          Return => Self::transfer_ret_instr,
          Br => Self::transfer_br_instr,
          Switch => Self::transfer_switch_instr,
          Call => Self::transfer_call_instr,
          Alloca => Self::transfer_alloca_instr,
          Store => Self::transfer_store_instr,
          ICmp => Self::transfer_icmp_instr,
          Load => Self::transfer_load_instr,
          Phi => Self::transfer_phi_instr,
          GetElementPtr => Self::transfer_gep_instr,
          Unreachable => Self::transfer_unreachable_instr,
          op if op.is_binary() => Self::transfer_binary_instr,
          op if op.is_unary() => Self::transfer_unary_instr,
          _ => Self::transfer_instr,
        };
        transfer_function(self, instr, state, env)
      }
      None => {
        state.finish_state = FinishState::ProperlyReturned;
      }
    }
  }

  pub fn eval_operand_value(&self, state: &mut State<'ctx>, value: BasicValueEnum<'ctx>) -> Value {
    // TODO
    Value::Unknown
  }

  pub fn eval_operand_location(&self, state: &mut State<'ctx>, value: BasicValueEnum<'ctx>) -> Location {
    // TODO
    Location::Unknown
  }

  pub fn load_from_memory(&self, state: &mut State<'ctx>, location: &Location) -> Value {
    // TODO
    Value::Unknown
  }

  pub fn transfer_ret_instr(
    &self,
    instr: InstructionValue<'ctx>,
    state: &mut State<'ctx>,
    env: &mut Environment<'ctx>,
  ) {

    // First evaluate the return operand. There might not be one
    let ret_instr = instr.as_return_instruction().unwrap();
    let val = ret_instr.val.map(|val| self.eval_operand_value(state, val));
    state.trace.push(TraceNode { instr: instr, semantics: Instruction::Return(val.clone()) });

    // Then we peek the stack frame
    let stack_frame = state.stack.pop().unwrap(); // There has to be a stack on the top
    match stack_frame.instr {
      Some(call_site) => {
        let call_site_frame = state.stack.top_mut(); // If call site exists then there must be a stack top
        if let Some(op0) = val {
          call_site_frame.memory.insert(call_site, op0);
        }
        self.execute_instr(call_site.get_next_instruction(), state, env);
      },

      // If no call site then we are in the entry function. We will end the execution
      None => {
        state.finish_state = FinishState::ProperlyReturned;
      }
    }
  }

  pub fn transfer_br_instr(
    &self,
    instr: InstructionValue<'ctx>,
    state: &mut State<'ctx>,
    env: &mut Environment<'ctx>,
  ) {
    match instr.as_branch_instruction().unwrap() { // We assume instr is branch instruction
      BranchInstruction::ConditionalBranch { cond, then_blk, else_blk } => {
        let cond = self.eval_operand_value(state, cond.into());
        let curr_blk = instr.get_parent().unwrap(); // We assume instruction always has parent block
        let then_br = BranchDirection { from: curr_blk, to: then_blk };
        let else_br = BranchDirection { from: curr_blk, to: else_blk };
        let visited_then = state.visited_branch.contains(&then_br);
        let visited_else = state.visited_branch.contains(&else_br);
        if !visited_then {

          // Check if we need to add a work for else branch
          if !visited_else {

            // First add else branch into work
            let mut else_state = state.clone();
            else_state.visited_branch.insert(else_br);
            else_state.trace.push(TraceNode {
              instr: instr,
              semantics: Instruction::ConditionalBr { cond: cond.clone(), br: Branch::Else }
            });
            let else_work = Work { block: else_blk, state: else_state };
            env.add_work(else_work);
          }

          // Then execute the then branch
          state.visited_branch.insert(then_br);
          state.trace.push(TraceNode {
            instr: instr,
            semantics: Instruction::ConditionalBr { cond, br: Branch::Then }
          });
          self.execute_block(then_blk, state, env);
        } else if !visited_else {

          // Execute the else branch
          state.visited_branch.insert(else_br);
          state.trace.push(TraceNode {
            instr: instr,
            semantics: Instruction::ConditionalBr { cond, br: Branch::Else }
          });
          self.execute_block(else_blk, state, env);
        } else {

          // If both then and else are visited, stop the execution with BranchExplored
          state.finish_state = FinishState::BranchExplored;
        }
      }
      BranchInstruction::UnconditionalBranch(blk) => {
        // TODO: is_loop
        state.trace.push(TraceNode {
          instr: instr,
          semantics: Instruction::UnconditionalBr { is_loop: false }
        });
        self.execute_block(blk, state, env);
      }
    }
  }

  pub fn transfer_switch_instr(
    &self,
    instr: InstructionValue<'ctx>,
    state: &mut State<'ctx>,
    env: &mut Environment<'ctx>,
  ) {
    let switch_instr = instr.as_switch_instruction().unwrap();
    let curr_blk = instr.get_parent().unwrap();
    let cond = self.eval_operand_value(state, switch_instr.cond.into());
    let default_br = BranchDirection { from: curr_blk, to: switch_instr.default_blk };
    let branches = switch_instr.branches.iter().map(|(_, to)| {
      BranchDirection { from: curr_blk, to: *to }
    }).collect::<Vec<_>>();
    let node = TraceNode { instr, semantics: Instruction::Switch { cond } };
    state.trace.push(node);

    // Insert branches as work if not visited
    for bd in branches {
      if !state.visited_branch.contains(&bd) {
        let mut br_state = state.clone();
        br_state.visited_branch.insert(bd);
        let br_work = Work { block: bd.to, state: br_state };
        env.add_work(br_work);
      }
    }

    // Execute default branch
    if !state.visited_branch.contains(&default_br) {
      state.visited_branch.insert(default_br);
      self.execute_block(switch_instr.default_blk, state, env);
    }
  }

  pub fn transfer_call_instr(
    &self,
    instr: InstructionValue<'ctx>,
    state: &mut State<'ctx>,
    env: &mut Environment<'ctx>,
  ) {
    let call = instr.as_call_instruction(&self.ctx.llmod).unwrap();
    if call.callee.is_llvm_function() {
      self.execute_instr(instr.get_next_instruction(), state, env);
    } else {
      let func = call.callee.function_name();
      let args : Vec<Value> = call.args.into_iter().map(|v| self.eval_operand_value(state, v)).collect();

      // Add the node into the trace
      let semantics = Instruction::Call { func: func.clone(), args: args.clone() };
      let node = TraceNode { instr, semantics };
      state.trace.push(node);

      // Check if this is the target function call
      if instr == env.slice.instr && state.target_node.is_none() {
        let node_id = state.trace.len() - 1;
        state.target_node = Some(node_id);
      }

      // Check if we need to go into the function
      if !call.callee.is_declare_only() && env.slice.functions.contains(&call.callee) {
        self.execute_function(instr, call.callee, args, state, env);
      } else {
        let call_id = env.new_call_id();
        let result = Value::Call { id: call_id, func, args };
        state.stack.top_mut().memory.insert(instr, result);
        self.execute_instr(instr.get_next_instruction(), state, env);
      }
    }
  }

  pub fn transfer_alloca_instr(
    &self,
    instr: InstructionValue<'ctx>,
    state: &mut State<'ctx>,
    env: &mut Environment<'ctx>,
  ) {
    let alloca_id = state.new_alloca_id();
    let res = Value::Location(Box::new(Location::Alloca(alloca_id)));
    let node = TraceNode { instr: instr, semantics: Instruction::Alloca(alloca_id) };
    state.trace.push(node);
    state.stack.top_mut().memory.insert(instr, res);
    self.execute_instr(instr.get_next_instruction(), state, env);
  }

  pub fn transfer_store_instr(
    &self,
    instr: InstructionValue<'ctx>,
    state: &mut State<'ctx>,
    env: &mut Environment<'ctx>,
  ) {
    let store_instr = instr.as_store_instruction().unwrap();
    let loc = self.eval_operand_location(state, store_instr.location);
    let val = self.eval_operand_value(state, store_instr.value);
    state.memory.insert(loc.clone(), val.clone());
    let node = TraceNode { instr: instr, semantics: Instruction::Store { loc, val }};
    state.trace.push(node);
    self.execute_instr(instr.get_next_instruction(), state, env);
  }

  pub fn transfer_load_instr(
    &self,
    instr: InstructionValue<'ctx>,
    state: &mut State<'ctx>,
    env: &mut Environment<'ctx>,
  ) {
    let load_instr = instr.as_load_instruction().unwrap();
    let loc = self.eval_operand_location(state, load_instr.location);
    let res = self.load_from_memory(state, &loc);
    let node = TraceNode { instr: instr, semantics: Instruction::Load { loc }};
    state.trace.push(node);
    state.stack.top_mut().memory.insert(instr, res);
    self.execute_instr(instr.get_next_instruction(), state, env);
  }

  pub fn transfer_icmp_instr(
    &self,
    instr: InstructionValue<'ctx>,
    state: &mut State<'ctx>,
    env: &mut Environment<'ctx>,
  ) {
    let bin_instr = instr.as_binary_instruction().unwrap();
    let pred = instr.get_icmp_predicate().unwrap(); // ICMP must have a predicate
    let op0 = self.eval_operand_value(state, bin_instr.op0);
    let op1 = self.eval_operand_value(state, bin_instr.op1);
    let res = Value::Comparison { pred, op0: Box::new(op0.clone()), op1: Box::new(op1.clone()) };
    let semantics = Instruction::Assume { pred, op0, op1 };
    let node = TraceNode { instr, semantics };
    state.trace.push(node);
    state.stack.top_mut().memory.insert(instr, res);
    self.execute_instr(instr.get_next_instruction(), state, env);
  }

  pub fn transfer_phi_instr(
    &self,
    instr: InstructionValue<'ctx>,
    state: &mut State<'ctx>,
    env: &mut Environment<'ctx>,
  ) {
  }

  pub fn transfer_gep_instr(
    &self,
    instr: InstructionValue<'ctx>,
    state: &mut State<'ctx>,
    env: &mut Environment<'ctx>,
  ) {
  }

  pub fn transfer_unreachable_instr(
    &self,
    instr: InstructionValue<'ctx>,
    state: &mut State<'ctx>,
    env: &mut Environment<'ctx>,
  ) {
  }

  pub fn transfer_binary_instr(
    &self,
    instr: InstructionValue<'ctx>,
    state: &mut State<'ctx>,
    env: &mut Environment<'ctx>,
  ) {
  }

  pub fn transfer_unary_instr(
    &self,
    instr: InstructionValue<'ctx>,
    state: &mut State<'ctx>,
    env: &mut Environment<'ctx>,
  ) {
  }

  pub fn transfer_instr(
    &self,
    instr: InstructionValue<'ctx>,
    state: &mut State<'ctx>,
    env: &mut Environment<'ctx>,
  ) {
  }

  pub fn continue_execution(&self, metadata: &MetaData) -> bool {
    metadata.explored_trace_count < self.options.max_explored_trace_per_slice
    && metadata.proper_trace_count < self.options.max_trace_per_slice
  }

  pub fn execute_slice(&self, slice: Slice<'ctx>, slice_id: usize) -> MetaData {
    let mut metadata = MetaData::new();
    let mut env = Environment::new(slice);
    while env.has_work() && self.continue_execution(&metadata) {
      let mut work = env.pop_work();
      self.execute_block(work.block, &mut work.state, &mut env);
      match work.state.target_node {
        Some(_target_id) => match work.state.finish_state {
          FinishState::ProperlyReturned => {
            // if !self.options.no_trace_reduction {
            //   work.state.trace_graph = work.state.trace_graph.reduce(target_id);
            // }
            if !env.has_duplicate(&work.state) {
              if work.state.path_satisfactory() {
                let trace_id = metadata.proper_trace_count;
                let path =
                  self.trace_file_name(env.slice.target_function_name(), slice_id, trace_id);
                work.state.dump_json(path);
                metadata.incr_proper();
              } else { metadata.incr_path_unsat() }
            } else { metadata.incr_duplicated() }
          }
          FinishState::BranchExplored => metadata.incr_branch_explored(),
          FinishState::ExceedingMaxTraceLength => metadata.incr_exceeding_length(),
          FinishState::Unreachable => metadata.incr_unreachable(),
        },
        None => metadata.incr_no_target(),
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
