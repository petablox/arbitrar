use clap::{App, Arg, ArgMatches};
use inkwell::{basic_block::BasicBlock, values::*};
use std::rc::Rc;
// use petgraph::graph::{DiGraph, NodeIndex};
use rayon::prelude::*;
// use serde_json::Value as Json;
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};

use crate::context::AnalyzerContext;
use crate::ll_utils::*;
use crate::options::Options;
use crate::semantics::*;
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
      max_explored_trace_per_slice: matches.value_of_t::<usize>("max_explored_trace_per_slice").unwrap(),
      max_node_per_trace: matches.value_of_t::<usize>("max_node_per_trace").unwrap(),
      no_trace_reduction: matches.is_present("no-reduce-trace"),
    })
  }
}

#[derive(Debug)]
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
      branch_explored_trace_count: self.branch_explored_trace_count + other.branch_explored_trace_count,
      duplicate_trace_count: self.duplicate_trace_count + other.duplicate_trace_count,
      no_target_trace_count: self.no_target_trace_count + other.no_target_trace_count,
      exceeding_length_trace_count: self.exceeding_length_trace_count + other.exceeding_length_trace_count,
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

pub type LocalMemory<'ctx> = HashMap<InstructionValue<'ctx>, Rc<Value>>;

#[derive(Clone)]
pub struct StackFrame<'ctx> {
  pub function: FunctionValue<'ctx>,
  pub instr: Option<(usize, InstructionValue<'ctx>)>,
  pub memory: LocalMemory<'ctx>,
  pub arguments: Vec<Rc<Value>>,
}

impl<'ctx> StackFrame<'ctx> {
  pub fn entry(function: FunctionValue<'ctx>) -> Self {
    Self {
      function,
      instr: None,
      memory: LocalMemory::new(),
      arguments: (0..function.count_params())
        .map(|i| Rc::new(Value::Argument(i as usize)))
        .collect(),
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

pub type Memory = HashMap<Rc<Location>, Rc<Value>>;

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
  pub result: Option<Rc<Value>>,
}

impl<'ctx> std::fmt::Debug for TraceNode<'ctx> {
  fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
    std::fmt::Debug::fmt(&self.semantics, f)
  }
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

pub type BlockTrace<'ctx> = Vec<BasicBlock<'ctx>>;

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

pub type Trace<'ctx> = Vec<TraceNode<'ctx>>;

pub trait TraceTrait<'ctx> {
  fn block_trace(&self) -> Vec<BasicBlock<'ctx>>;

  fn print(&self);
}

impl<'ctx> TraceTrait<'ctx> for Trace<'ctx> {
  fn block_trace(&self) -> Vec<BasicBlock<'ctx>> {
    let mut blocks = Vec::new();
    for node in self.iter() {
      let instr = node.instr;
      match instr.get_parent() {
        Some(block) => {
          let needs_insert = match blocks.last() {
            Some(last_block) => block != *last_block,
            None => true,
          };
          if needs_insert {
            blocks.push(block);
          }
        }
        None => (),
      }
    }
    blocks
  }

  fn print(&self) {
    for node in self.iter() {
      match &node.result {
        Some(result) => println!("{:?} -> {:?}", node.semantics, result),
        None => println!("{:?}", node.semantics),
      }
    }
  }
}

#[derive(Clone)]
pub enum FinishState {
  ProperlyReturned,
  BranchExplored,
  ExceedingMaxTraceLength,
  Unreachable,
}

#[derive(Debug, Clone)]
pub struct Constraint {
  pub cond: Comparison,
  pub branch: bool,
}

#[derive(Clone)]
pub struct State<'ctx> {
  pub stack: Stack<'ctx>,
  pub memory: Memory,
  pub visited_branch: VisitedBranch<'ctx>,
  pub global_usage: GlobalUsage<'ctx>,
  pub trace: Trace<'ctx>,
  pub target_node: Option<usize>,
  pub prev_block: Option<BasicBlock<'ctx>>,
  pub finish_state: FinishState,
  pub pointer_value_id_map: HashMap<PointerValue<'ctx>, usize>,
  pub constraints: HashMap<InstructionValue<'ctx>, Constraint>,

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
      visited_branch: VisitedBranch::new(),
      global_usage: GlobalUsage::new(),
      trace: Vec::new(),
      target_node: None,
      prev_block: None,
      finish_state: FinishState::ProperlyReturned,
      pointer_value_id_map: HashMap::new(),
      constraints: HashMap::new(),
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

  pub fn new_pointer_value_id(&mut self, pv: PointerValue<'ctx>) -> usize {
    let result = self.pointer_value_id;
    self.pointer_value_id += 1;
    self.pointer_value_id_map.insert(pv, result);
    result
  }

  pub fn add_constraint(&mut self, instr: &InstructionValue<'ctx>, comparison: Option<Comparison>, branch: bool) {
    match comparison {
      Some(cond) => {
        if self.constraints.contains_key(instr) {
          self.constraints.remove(instr);
        } else {
          self.constraints.insert(instr.clone(), Constraint { cond, branch });
        }
      }
      None => {}
    }
  }

  pub fn path_satisfactory(&self, z3_ctx: &z3::Context) -> bool {
    use z3::*;
    let solver = Solver::new(&z3_ctx);
    let mut symbol_map = HashMap::new();
    let mut symbol_id = 0;
    for (_, Constraint { cond, branch }) in self.constraints.iter() {
      match cond.into_z3_ast(&mut symbol_map, &mut symbol_id, z3_ctx) {
        Some(cond) => {
          let formula = if *branch { cond } else { cond.not() };
          solver.assert(&formula);
        }
        _ => (),
      }
    }
    match solver.check() {
      SatResult::Sat | SatResult::Unknown => true,
      _ => false,
    }
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
  pub block_traces: Vec<BlockTrace<'ctx>>,
  pub call_id: usize,
}

impl<'ctx> Environment<'ctx> {
  pub fn new(slice: Slice<'ctx>) -> Self {
    let initial_work = Work::entry(&slice);
    Self {
      slice,
      work_list: vec![initial_work],
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

  pub fn has_duplicate(&self, block_trace: &BlockTrace<'ctx>) -> bool {
    for other_block_trace in self.block_traces.iter() {
      if block_trace.equals(other_block_trace) {
        return true;
      }
    }
    false
  }
}

pub struct SymbolicExecutionContext<'a, 'ctx> {
  pub ctx: &'a AnalyzerContext<'ctx>,
  pub z3_ctx: z3::Context,
  pub options: SymbolicExecutionOptions,
}

unsafe impl<'a, 'ctx> Sync for SymbolicExecutionContext<'a, 'ctx> {}

impl<'a, 'ctx> SymbolicExecutionContext<'a, 'ctx> {
  pub fn new(ctx: &'a AnalyzerContext<'ctx>) -> Result<Self, String> {
    let options = SymbolicExecutionOptions::from_matches(&ctx.args)?;
    let z3_ctx = z3::Context::new(&z3::Config::default());
    Ok(Self { ctx, options, z3_ctx })
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
    instr_node_id: usize,
    instr: InstructionValue<'ctx>,
    func: FunctionValue<'ctx>,
    args: Vec<Rc<Value>>,
    state: &mut State<'ctx>,
    env: &mut Environment<'ctx>,
  ) {
    match func.get_first_basic_block() {
      Some(block) => {
        let stack_frame = StackFrame {
          function: func,
          instr: Some((instr_node_id, instr)),
          memory: LocalMemory::new(),
          arguments: args,
        };
        state.stack.push(stack_frame);
        self.execute_block(block, state, env);
      }
      None => {}
    }
  }

  pub fn execute_block(&self, block: BasicBlock<'ctx>, state: &mut State<'ctx>, env: &mut Environment<'ctx>) {
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

  pub fn eval_operand_value(&self, state: &mut State<'ctx>, value: BasicValueEnum<'ctx>) -> Rc<Value> {
    match value.as_instruction() {
      Some(instr) => match state.stack.top().memory.get(&instr) {
        Some(value) => value.clone(),
        None => match instr.get_opcode() {
          InstructionOpcode::Alloca => {
            let alloca_id = state.new_alloca_id();
            let loc = Rc::new(Location::Alloca(alloca_id));
            let val = Rc::new(Value::Location(loc.clone()));
            state.stack.top_mut().memory.insert(instr, val.clone());
            val
          }
          _ => {
            println!("stack memory has no value for instruction {:?}", instr);
            Rc::new(Value::Unknown)
          }
        },
      },
      _ => match value.argument_index(state.stack.top().function) {
        Some(arg_id) => state.stack.top().arguments[arg_id].clone(),
        None => match value {
          BasicValueEnum::IntValue(iv) => match iv.get_sign_extended_constant() {
            Some(const_int) => Rc::new(Value::ConstInt(const_int)),
            None => Rc::new(Value::Unknown),
          },
          BasicValueEnum::PointerValue(pv) => {
            if pv.is_null() {
              Rc::new(Value::NullPtr)
            } else {
              let name = String::from(pv.get_name().to_string_lossy());
              match self.ctx.llmod.get_global(name.as_str()) {
                Some(_) => Rc::new(Value::Global(name)),
                _ => match self.ctx.llmod.get_function(name.as_str()) {
                  Some(_) => Rc::new(Value::FunctionPointer(name)),
                  _ => {
                    if pv.is_const() {
                      let pv_id = state.new_pointer_value_id(pv);
                      Rc::new(Value::ConstPtr(pv_id))
                    } else {
                      println!("Pointer Value not null, global, function, or const ptr");
                      Rc::new(Value::Unknown)
                    }
                  }
                },
              }
            }
          }
          _ => {
            println!("Not instruction, not int value or pointer value {:?}", value);
            Rc::new(Value::Unknown)
          }
        },
      },
    }
  }

  pub fn eval_operand_location(&self, state: &mut State<'ctx>, value: BasicValueEnum<'ctx>) -> Rc<Location> {
    match value.as_instruction() {
      Some(instr) => match state.stack.top().memory.get(&instr) {
        Some(value) => match &*value.clone() {
          Value::Location(loc) => loc.clone(),
          Value::ConstPtr(ptr_id) => Rc::new(Location::ConstPtr(*ptr_id)),
          _ => Rc::new(Location::Value(value.clone())),
        },
        _ => match instr.get_opcode() {
          InstructionOpcode::Alloca => {
            let alloca_id = state.new_alloca_id();
            let loc = Rc::new(Location::Alloca(alloca_id));
            let val = Rc::new(Value::Location(loc.clone()));
            state.stack.top_mut().memory.insert(instr, val);
            loc
          }
          _ => {
            println!("Nothing in memory for instr: {:?}", instr);
            Rc::new(Location::Unknown)
          }
        },
      },
      None => match value {
        BasicValueEnum::PointerValue(pv) => {
          let name = String::from(pv.get_name().to_string_lossy());
          match self.ctx.llmod.get_global(name.as_str()) {
            Some(_) => Rc::new(Location::Global(name)),
            _ => {
              let pv_id = state.new_pointer_value_id(pv);
              Rc::new(Location::ConstPtr(pv_id))
            }
          }
        }
        _ => {
          println!("Not an instruction, nor pointer value");
          Rc::new(Location::Unknown)
        }
      },
    }
  }

  pub fn load_from_memory(&self, state: &mut State<'ctx>, location: Rc<Location>) -> Rc<Value> {
    match &*location {
      Location::Unknown => Rc::new(Value::Unknown),
      _ => match state.memory.get(&location) {
        Some(value) => value.clone(),
        None => {
          let symbol_id = state.new_symbol_id();
          let value = Rc::new(Value::Symbol(symbol_id));
          state.memory.insert(location, value.clone());
          value
        }
      },
    }
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
    state.trace.push(TraceNode {
      instr,
      semantics: Instruction::Return(val.clone()),
      result: None,
    });

    // Then we peek the stack frame
    let stack_frame = state.stack.pop().unwrap(); // There has to be a stack on the top
    match stack_frame.instr {
      Some((node_id, call_site)) => {
        let call_site_frame = state.stack.top_mut(); // If call site exists then there must be a stack top
        if let Some(op0) = val {
          state.trace[node_id].result = Some(op0.clone());
          call_site_frame.memory.insert(call_site, op0);
        }
        self.execute_instr(call_site.get_next_instruction(), state, env);
      }

      // If no call site then we are in the entry function. We will end the execution
      None => {
        state.finish_state = FinishState::ProperlyReturned;
      }
    }
  }

  pub fn transfer_br_instr(&self, instr: InstructionValue<'ctx>, state: &mut State<'ctx>, env: &mut Environment<'ctx>) {
    let curr_blk = instr.get_parent().unwrap(); // We assume instruction always has parent block
    state.prev_block = Some(curr_blk);
    match instr.as_branch_instruction().unwrap() {
      // We assume instr is branch instruction
      BranchInstruction::ConditionalBranch {
        cond,
        then_blk,
        else_blk,
      } => {
        let cond = self.eval_operand_value(state, cond.into());
        let comparison = cond.as_comparison();
        let is_loop_blk = curr_blk.is_loop_block(&self.ctx.llcontext());
        let then_br = BranchDirection {
          from: curr_blk,
          to: then_blk,
        };
        let else_br = BranchDirection {
          from: curr_blk,
          to: else_blk,
        };
        let visited_then = state.visited_branch.contains(&then_br);
        let visited_else = state.visited_branch.contains(&else_br);
        if !visited_then {
          // Check if we need to add a work for else branch
          if !visited_else {
            // First add else branch into work
            let mut else_state = state.clone();
            if !is_loop_blk {
              else_state.add_constraint(&instr, comparison.clone(), false);
            }
            else_state.visited_branch.insert(else_br);
            else_state.trace.push(TraceNode {
              instr,
              result: None,
              semantics: Instruction::ConditionalBr {
                cond: cond.clone(),
                br: Branch::Else,
              },
            });
            let else_work = Work {
              block: else_blk,
              state: else_state,
            };
            env.add_work(else_work);
          }

          // Then execute the then branch
          if !is_loop_blk {
            state.add_constraint(&instr, comparison, true);
          }
          state.visited_branch.insert(then_br);
          state.trace.push(TraceNode {
            instr: instr,
            result: None,
            semantics: Instruction::ConditionalBr { cond, br: Branch::Then },
          });
          self.execute_block(then_blk, state, env);
        } else if !visited_else {
          // Execute the else branch
          if !is_loop_blk {
            state.add_constraint(&instr, comparison.clone(), false);
          }
          state.visited_branch.insert(else_br);
          state.trace.push(TraceNode {
            instr: instr,
            semantics: Instruction::ConditionalBr { cond, br: Branch::Else },
            result: None,
          });
          self.execute_block(else_blk, state, env);
        } else {
          // If both then and else are visited, stop the execution with BranchExplored
          state.finish_state = FinishState::BranchExplored;
        }
      }
      BranchInstruction::UnconditionalBranch(blk) => {
        state.trace.push(TraceNode {
          instr: instr,
          semantics: Instruction::UnconditionalBr {
            is_loop: instr.is_loop(&self.ctx.llmod.get_context()),
          },
          result: None,
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
    let curr_blk = instr.get_parent().unwrap();
    state.prev_block = Some(curr_blk);
    let switch_instr = instr.as_switch_instruction().unwrap();
    let cond = self.eval_operand_value(state, switch_instr.cond.into());
    let default_br = BranchDirection {
      from: curr_blk,
      to: switch_instr.default_blk,
    };
    let branches = switch_instr
      .branches
      .iter()
      .map(|(_, to)| BranchDirection {
        from: curr_blk,
        to: *to,
      })
      .collect::<Vec<_>>();
    let node = TraceNode {
      instr,
      semantics: Instruction::Switch { cond },
      result: None,
    };
    state.trace.push(node);

    // Insert branches as work if not visited
    for bd in branches {
      if !state.visited_branch.contains(&bd) {
        let mut br_state = state.clone();
        br_state.visited_branch.insert(bd);
        let br_work = Work {
          block: bd.to,
          state: br_state,
        };
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
    let callee_name = instr.callee_name().unwrap();
    if FunctionValue::str_is_llvm_function(callee_name.as_str()) {
      self.execute_instr(instr.get_next_instruction(), state, env);
    } else {
      let call = instr.as_call_instruction(&self.ctx.llmod).unwrap();
      let args: Vec<Rc<Value>> = call
        .args
        .into_iter()
        .map(|v| self.eval_operand_value(state, v))
        .collect();

      // Store call node id
      let node_id = state.trace.len() - 1;

      // Add the node into the trace
      let semantics = Instruction::Call {
        func: callee_name.clone(),
        args: args.clone(),
      };
      let node = TraceNode {
        instr,
        semantics,
        result: None,
      };
      state.trace.push(node);

      // Check if this is the target function call
      if instr == env.slice.instr && state.target_node.is_none() {
        state.target_node = Some(node_id);
      }

      // Check if we need to go into the function
      match call.callee {
        Some(callee) if !callee.is_declare_only() && env.slice.functions.contains(&callee) => {
          self.execute_function(node_id, instr, callee, args, state, env);
        }
        _ => {
          let call_id = env.new_call_id();
          let result = Rc::new(Value::Call {
            id: call_id,
            func: call.callee_name,
            args,
          });
          state.stack.top_mut().memory.insert(instr, result);
          self.execute_instr(instr.get_next_instruction(), state, env);
        }
      }
    }
  }

  pub fn transfer_alloca_instr(
    &self,
    instr: InstructionValue<'ctx>,
    state: &mut State<'ctx>,
    env: &mut Environment<'ctx>,
  ) {
    // Lazy evaluate alloca instructions
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
    let node = TraceNode {
      instr: instr,
      semantics: Instruction::Store { loc, val },
      result: None,
    };
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
    let res = self.load_from_memory(state, loc.clone());
    let node = TraceNode {
      instr: instr,
      semantics: Instruction::Load { loc },
      result: Some(res.clone()),
    };
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
    let res = Rc::new(Value::Comparison {
      pred,
      op0: op0.clone(),
      op1: op1.clone(),
    });
    let semantics = Instruction::Assume { pred, op0, op1 };
    let node = TraceNode {
      instr,
      semantics,
      result: Some(res.clone()),
    };
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
    let prev_blk = state.prev_block.unwrap();
    let phi_instr = instr.as_phi_instruction().unwrap();
    let incoming_val = phi_instr.incomings.iter().find(|(_, blk)| *blk == prev_blk).unwrap().0;
    let res = self.eval_operand_value(state, incoming_val);
    state.stack.top_mut().memory.insert(instr, res);
    self.execute_instr(instr.get_next_instruction(), state, env);
  }

  pub fn transfer_gep_instr(
    &self,
    instr: InstructionValue<'ctx>,
    state: &mut State<'ctx>,
    env: &mut Environment<'ctx>,
  ) {
    let gep_instr = instr.as_gep_instruction().unwrap();
    let loc = self.eval_operand_location(state, gep_instr.loc);
    let indices = gep_instr
      .indices
      .iter()
      .map(|index| self.eval_operand_value(state, *index))
      .collect::<Vec<_>>();
    let res = Rc::new(Value::Location(Rc::new(Location::GetElementPtr(
      loc.clone(),
      indices.clone(),
    ))));
    let node = TraceNode {
      instr,
      semantics: Instruction::GetElementPtr {
        loc: loc.clone(),
        indices,
      },
      result: Some(res.clone()),
    };
    state.trace.push(node);
    state.stack.top_mut().memory.insert(instr, res);
    self.execute_instr(instr.get_next_instruction(), state, env);
  }

  pub fn transfer_binary_instr(
    &self,
    instr: InstructionValue<'ctx>,
    state: &mut State<'ctx>,
    env: &mut Environment<'ctx>,
  ) {
    let binary_instr = instr.as_binary_instruction().unwrap();
    let op = binary_instr.op;
    let v0 = self.eval_operand_value(state, binary_instr.op0);
    let v1 = self.eval_operand_value(state, binary_instr.op1);
    let res = Rc::new(Value::BinaryOperation {
      op,
      op0: v0.clone(),
      op1: v1.clone(),
    });
    let node = TraceNode {
      instr,
      semantics: Instruction::BinaryOperation { op, op0: v0, op1: v1 },
      result: Some(res.clone()),
    };
    state.trace.push(node);
    state.stack.top_mut().memory.insert(instr, res);
    self.execute_instr(instr.get_next_instruction(), state, env);
  }

  pub fn transfer_unary_instr(
    &self,
    instr: InstructionValue<'ctx>,
    state: &mut State<'ctx>,
    env: &mut Environment<'ctx>,
  ) {
    let unary_instr = instr.as_unary_instruction().unwrap();
    let op = unary_instr.op;
    let op0 = self.eval_operand_value(state, unary_instr.op0);
    let node = TraceNode {
      instr,
      semantics: Instruction::UnaryOperation { op, op0: op0.clone() },
      result: Some(op0.clone()),
    };
    state.trace.push(node);
    state.stack.top_mut().memory.insert(instr, op0);
    self.execute_instr(instr.get_next_instruction(), state, env);
  }

  pub fn transfer_unreachable_instr(
    &self,
    _: InstructionValue<'ctx>,
    state: &mut State<'ctx>,
    _: &mut Environment<'ctx>,
  ) {
    state.finish_state = FinishState::Unreachable;
  }

  pub fn transfer_instr(&self, instr: InstructionValue<'ctx>, state: &mut State<'ctx>, env: &mut Environment<'ctx>) {
    self.execute_instr(instr.get_next_instruction(), state, env);
  }

  pub fn continue_execution(&self, metadata: &MetaData) -> bool {
    metadata.explored_trace_count < self.options.max_explored_trace_per_slice
      && metadata.proper_trace_count < self.options.max_trace_per_slice
  }

  pub fn execute_slice(&self, slice: Slice<'ctx>, slice_id: usize) -> MetaData {
    let mut metadata = MetaData::new();
    let mut env = Environment::new(slice);
    while env.has_work() && self.continue_execution(&metadata) {
      println!("=========== {} ==========", metadata.explored_trace_count);

      let mut work = env.pop_work();
      self.execute_block(work.block, &mut work.state, &mut env);
      match work.state.target_node {
        Some(_target_id) => match work.state.finish_state {
          FinishState::ProperlyReturned => {
            // if !self.options.no_trace_reduction {
            //   work.state.trace_graph = work.state.trace_graph.reduce(target_id);
            // }
            let block_trace = work.state.trace.block_trace();
            if !env.has_duplicate(&block_trace) {
              if work.state.path_satisfactory(&self.z3_ctx) {
                let trace_id = metadata.proper_trace_count;
                let path = self.trace_file_name(env.slice.target_function_name(), slice_id, trace_id);
                work.state.trace.print();
                work.state.dump_json(path);
                metadata.incr_proper();
              } else {
                for (_, cons) in work.state.constraints {
                  println!("{:?}", cons);
                }
                println!("Path unsat");
                metadata.incr_path_unsat()
              }
            } else {
              println!("Duplicated");
              metadata.incr_duplicated()
            }
          }
          FinishState::BranchExplored => {
            println!("Branch explored");
            metadata.incr_branch_explored()
          }
          FinishState::ExceedingMaxTraceLength => {
            println!("Exceeding Length");
            metadata.incr_exceeding_length()
          }
          FinishState::Unreachable => {
            println!("Unreachable");
            metadata.incr_unreachable()
          }
        },
        None => metadata.incr_no_target(),
      }
    }
    metadata
  }

  pub fn execute_slices(&self, slices: Vec<Slice<'ctx>>) -> MetaData {
    let f = |meta: MetaData, (slice_id, slice): (usize, Slice<'ctx>)| meta.combine(self.execute_slice(slice, slice_id));
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
