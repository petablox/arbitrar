use clap::{App, Arg, ArgMatches};
use indicatif::{ParallelProgressIterator, ProgressIterator};
use llir::values::*;
use rayon::iter::ParallelIterator;
use rayon::prelude::*;
use serde_json::json;
use std::collections::{HashMap, HashSet};
use std::fs;
use std::fs::File;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::rc::Rc;

use crate::context::AnalyzerContext;
use crate::block_tracer::*;
use crate::options::Options;
use crate::semantics::*;
use crate::slicer::Slice;
use crate::utils::*;

#[derive(Debug)]
pub struct SymbolicExecutionOptions {
  pub max_trace_per_slice: usize,
  pub max_explored_trace_per_slice: usize,
  pub max_node_per_trace: usize,
  pub no_trace_reduction: bool,
  pub print_trace: bool,
  pub precompute_block_trace: bool,
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
        .default_value("5000"),
      Arg::new("no_reduce_trace")
        .long("no-reduce-trace")
        .about("No trace reduction"),
      Arg::new("print_trace").long("print-trace").about("Print out trace"),
      Arg::new("precompute_block_trace").long("precompute-block-trace"),
    ])
  }

  fn from_matches(matches: &ArgMatches) -> Result<Self, String> {
    Ok(Self {
      max_trace_per_slice: matches.value_of_t::<usize>("max_trace_per_slice").unwrap(),
      max_explored_trace_per_slice: matches.value_of_t::<usize>("max_explored_trace_per_slice").unwrap(),
      max_node_per_trace: matches.value_of_t::<usize>("max_node_per_trace").unwrap(),
      no_trace_reduction: matches.is_present("no_reduce_trace"),
      print_trace: matches.is_present("print_trace"),
      precompute_block_trace: matches.is_present("precompute_block_trace"),
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

#[derive(Clone)]
pub struct TraceNode<'ctx> {
  pub instr: Instruction<'ctx>,
  pub semantics: Semantics,
  pub result: Option<Rc<Value>>,
}

pub type Trace<'ctx> = Vec<TraceNode<'ctx>>;

pub trait TraceTrait {
  fn print(&self);
}

impl<'ctx> TraceTrait for Trace<'ctx> {
  fn print(&self) {
    for node in self.iter() {
      match &node.result {
        Some(result) => println!("{} {:?} -> {:?}", node.instr.debug_loc_string(), node.semantics, result),
        None => println!("{} {:?}", node.instr.debug_loc_string(), node.semantics),
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
  // pub global_usage: GlobalUsage<'ctx>,
  pub block_trace: BlockTrace<'ctx>,
  pub trace: Trace<'ctx>,
  pub target_node: Option<usize>,
  pub prev_block: Option<Block<'ctx>>,
  pub finish_state: FinishState,
  pub pointer_value_id_map: HashMap<GenericValue<'ctx>, usize>,
  pub constraints: Vec<Constraint>,

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
      // global_usage: GlobalUsage::new(),
      block_trace: BlockTrace::new(),
      trace: Vec::new(),
      target_node: None,
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

  pub fn path_satisfactory(&self) -> bool {
    use z3::*;
    let z3_ctx = Context::new(&z3::Config::default());
    let solver = Solver::new(&z3_ctx);
    let mut symbol_map = HashMap::new();
    let mut symbol_id = 0;
    for Constraint { cond, branch } in self.constraints.iter() {
      match cond.into_z3_ast(&mut symbol_map, &mut symbol_id, &z3_ctx) {
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

  pub fn dump_json(&self, path: PathBuf) -> Result<(), String> {
    let trace_json = json!({
      "instrs": self.trace.iter().map(|node| json!({
        "loc": node.instr.debug_loc_string(),
        "sem": node.semantics,
        "res": node.result
      })).collect::<Vec<_>>(),
      "target": self.target_node,
    });
    let json_str = serde_json::to_string(&trace_json).map_err(|_| "Cannot turn trace into json".to_string())?;
    let mut file = File::create(path).map_err(|_| "Cannot create trace file".to_string())?;
    file
      .write_all(json_str.as_bytes())
      .map_err(|_| "Cannot write to trace file".to_string())?;
    Ok(())
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

  pub fn add_block_trace(&mut self, block_trace: &BlockTrace<'ctx>) {
    self.block_traces.push(block_trace.clone())
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
  pub options: SymbolicExecutionOptions,
}

impl<'a, 'ctx> SymbolicExecutionContext<'a, 'ctx> {
  pub fn new(ctx: &'a AnalyzerContext<'ctx>) -> Result<Self, String> {
    let options = SymbolicExecutionOptions::from_matches(&ctx.args)?;
    Ok(Self { ctx, options })
  }

  pub fn execute_function(
    &self,
    instr_node_id: usize,
    instr: CallInstruction<'ctx>,
    func: Function<'ctx>,
    args: Vec<Rc<Value>>,
    state: &mut State<'ctx>,
    env: &mut Environment<'ctx>,
  ) -> Option<Instruction<'ctx>> {
    match func.first_block() {
      Some(block) => {
        let stack_frame = StackFrame {
          function: func,
          instr: Some((instr_node_id, instr)),
          memory: LocalMemory::new(),
          arguments: args,
        };
        state.stack.push(stack_frame);
        self.execute_block(block, state, env)
      }
      None => panic!("The executed function is empty"),
    }
  }

  pub fn execute_block(
    &self,
    block: Block<'ctx>,
    state: &mut State<'ctx>,
    _: &mut Environment<'ctx>,
  ) -> Option<Instruction<'ctx>> {
    state.block_trace.push(block);
    block.first_instruction()
  }

  pub fn execute_instr_and_add_work(
    &self,
    instr: Option<Instruction<'ctx>>,
    state: &mut State<'ctx>,
    env: &mut Environment<'ctx>,
  ) -> Option<Instruction<'ctx>> {
    if state.trace.len() > self.options.max_node_per_trace {
      state.finish_state = FinishState::ExceedingMaxTraceLength;
      None
    } else {
      match instr {
        Some(instr) => {
          use Instruction::*;
          match instr {
            Return(ret) => self.transfer_ret_instr(ret, state, env),
            Branch(br) => self.transfer_br_instr(br, state, env),
            Switch(swi) => self.transfer_switch_instr(swi, state, env),
            Call(call) => self.transfer_call_instr(call, state, env),
            Alloca(alloca) => self.transfer_alloca_instr(alloca, state, env),
            Store(st) => self.transfer_store_instr(st, state, env),
            ICmp(icmp) => self.transfer_icmp_instr(icmp, state, env),
            Load(ld) => self.transfer_load_instr(ld, state, env),
            Phi(phi) => self.transfer_phi_instr(phi, state, env),
            GetElementPtr(gep) => self.transfer_gep_instr(gep, state, env),
            Unreachable(unr) => self.transfer_unreachable_instr(unr, state, env),
            Binary(bin) => self.transfer_binary_instr(bin, state, env),
            Unary(una) => self.transfer_unary_instr(una, state, env),
            _ => self.transfer_instr(instr, state, env),
          }
        }
        None => None,
      }
    }
  }

  pub fn eval_constant_value(&self, state: &mut State<'ctx>, constant: Constant<'ctx>) -> Rc<Value> {
    match constant {
      Constant::Int(i) => Rc::new(Value::Int(i.sext_value())),
      Constant::Null(_) => Rc::new(Value::Null),
      Constant::Float(_) | Constant::Struct(_) | Constant::Array(_) | Constant::Vector(_) => {
        Rc::new(Value::Sym(state.new_symbol_id()))
      }
      Constant::Global(glob) => Rc::new(Value::Glob(glob.name())),
      Constant::Function(func) => Rc::new(Value::Func(func.simp_name())),
      Constant::ConstExpr(ce) => match ce {
        ConstExpr::Binary(b) => {
          let op = b.opcode();
          let op0 = self.eval_constant_value(state, b.op0());
          let op1 = self.eval_constant_value(state, b.op1());
          Rc::new(Value::Bin { op, op0, op1 })
        }
        ConstExpr::Unary(u) => self.eval_constant_value(state, u.op0()),
        ConstExpr::GetElementPtr(g) => {
          let loc = self.eval_constant_value(state, g.location());
          let indices = g
            .indices()
            .into_iter()
            .map(|i| self.eval_constant_value(state, i))
            .collect();
          Rc::new(Value::GEP { loc, indices })
        }
        _ => Rc::new(Value::Unknown),
      },
      _ => Rc::new(Value::Unknown),
    }
  }

  pub fn eval_operand_value(&self, state: &mut State<'ctx>, operand: Operand<'ctx>) -> Rc<Value> {
    match operand {
      Operand::Instruction(instr) => {
        if state.stack.top().memory.contains_key(&instr) {
          state.stack.top().memory[&instr].clone()
        } else {
          match instr {
            Instruction::Alloca(_) => {
              let alloca_id = state.new_alloca_id();
              let value = Rc::new(Value::Alloca(alloca_id));
              state.stack.top_mut().memory.insert(instr, value.clone());
              value
            }
            _ => Rc::new(Value::Unknown),
          }
        }
      }
      Operand::Argument(arg) => state.stack.top().arguments[arg.index()].clone(),
      Operand::Constant(cons) => self.eval_constant_value(state, cons),
      Operand::InlineAsm(_) => Rc::new(Value::Asm),
      _ => Rc::new(Value::Unknown),
    }
  }

  pub fn load_from_memory(&self, state: &mut State<'ctx>, location: Rc<Value>) -> Rc<Value> {
    match &*location {
      Value::Unknown => Rc::new(Value::Unknown),
      _ => match state.memory.get(&location) {
        Some(value) => value.clone(),
        None => {
          let symbol_id = state.new_symbol_id();
          let value = Rc::new(Value::Sym(symbol_id));
          state.memory.insert(location, value.clone());
          value
        }
      },
    }
  }

  pub fn transfer_ret_instr(
    &self,
    instr: ReturnInstruction<'ctx>,
    state: &mut State<'ctx>,
    _: &mut Environment<'ctx>,
  ) -> Option<Instruction<'ctx>> {
    // First evaluate the return operand. There might not be one
    let val = instr.op().map(|val| self.eval_operand_value(state, val));
    state.trace.push(TraceNode {
      instr: instr.as_instruction(),
      semantics: Semantics::Ret { op: val.clone() },
      result: None,
    });

    // Then we peek the stack frame
    let stack_frame = state.stack.pop().unwrap(); // There has to be a stack on the top
    match stack_frame.instr {
      Some((node_id, call_site)) => {
        let call_site_frame = state.stack.top_mut(); // If call site exists then there must be a stack top
        if let Some(op0) = val {
          if stack_frame.function.get_function_type().has_return_type() {
            state.trace[node_id].result = Some(op0.clone());
            call_site_frame.memory.insert(call_site.as_instruction(), op0);
          }
        }
        call_site.next_instruction()
      }

      // If no call site then we are in the entry function. We will end the execution
      None => {
        state.finish_state = FinishState::ProperlyReturned;
        None
      }
    }
  }

  pub fn transfer_br_instr(
    &self,
    instr: BranchInstruction<'ctx>,
    state: &mut State<'ctx>,
    env: &mut Environment<'ctx>,
  ) -> Option<Instruction<'ctx>> {
    let curr_blk = instr.parent_block(); // We assume instruction always has parent block
    state.prev_block = Some(curr_blk);
    match instr {
      // We assume instr is branch instruction
      BranchInstruction::Conditional(cb) => {
        let cond = self.eval_operand_value(state, cb.condition().into());
        let comparison = cond.as_comparison();
        let is_loop_blk = curr_blk.is_loop_entry_block();
        let then_br = BranchDirection {
          from: curr_blk,
          to: cb.then_block(),
        };
        let else_br = BranchDirection {
          from: curr_blk,
          to: cb.else_block(),
        };
        let visited_then = state.visited_branch.contains(&then_br);
        let visited_else = state.visited_branch.contains(&else_br);
        if !visited_then {
          // Check if we need to add a work for else branch
          if !visited_else {
            // First add else branch into work
            let mut else_state = state.clone();
            if let Some(comparison) = comparison.clone() {
              if !is_loop_blk {
                else_state.add_constraint(comparison, false);
              }
            }
            else_state.visited_branch.insert(else_br);
            else_state.trace.push(TraceNode {
              instr: instr.as_instruction(),
              result: None,
              semantics: Semantics::CondBr {
                cond: cond.clone(),
                br: Branch::Else,
                beg_loop: false,
              },
            });
            let else_work = Work {
              block: cb.else_block(),
              state: else_state,
            };
            env.add_work(else_work);
          }

          // Then execute the then branch
          if let Some(comparison) = comparison {
            if !is_loop_blk {
              state.add_constraint(comparison, true);
            }
          }
          state.visited_branch.insert(then_br);
          state.trace.push(TraceNode {
            instr: instr.as_instruction(),
            result: None,
            semantics: Semantics::CondBr {
              cond,
              br: Branch::Then,
              beg_loop: is_loop_blk,
            },
          });
          self.execute_block(cb.then_block(), state, env)
        } else if !visited_else {
          // Execute the else branch
          if let Some(comparison) = comparison {
            if !is_loop_blk {
              state.add_constraint(comparison.clone(), false);
            }
          }
          state.visited_branch.insert(else_br);
          state.trace.push(TraceNode {
            instr: instr.as_instruction(),
            semantics: Semantics::CondBr {
              cond,
              br: Branch::Else,
              beg_loop: false,
            },
            result: None,
          });
          self.execute_block(cb.else_block(), state, env)
        } else {
          // If both then and else are visited, stop the execution with BranchExplored
          state.finish_state = FinishState::BranchExplored;
          None
        }
      }
      BranchInstruction::Unconditional(ub) => {
        state.trace.push(TraceNode {
          instr: instr.as_instruction(),
          semantics: Semantics::UncondBr {
            end_loop: ub.is_loop_jump().unwrap_or(false),
          },
          result: None,
        });
        self.execute_block(ub.destination(), state, env)
      }
    }
  }

  pub fn transfer_switch_instr(
    &self,
    instr: SwitchInstruction<'ctx>,
    state: &mut State<'ctx>,
    env: &mut Environment<'ctx>,
  ) -> Option<Instruction<'ctx>> {
    let curr_blk = instr.parent_block();
    state.prev_block = Some(curr_blk);
    let cond = self.eval_operand_value(state, instr.condition().into());
    let default_br = BranchDirection {
      from: curr_blk,
      to: instr.default_destination(),
    };
    let branches = instr
      .cases()
      .iter()
      .map(|case| BranchDirection {
        from: curr_blk,
        to: case.destination,
      })
      .collect::<Vec<_>>();
    let node = TraceNode {
      instr: instr.as_instruction(),
      semantics: Semantics::Switch { cond },
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
      self.execute_block(instr.default_destination(), state, env)
    } else {
      state.finish_state = FinishState::BranchExplored;
      None
    }
  }

  pub fn transfer_call_instr(
    &self,
    instr: CallInstruction<'ctx>,
    state: &mut State<'ctx>,
    env: &mut Environment<'ctx>,
  ) -> Option<Instruction<'ctx>> {
    // If is intrinsic call, skip the instruction
    if instr.is_intrinsic_call() {
      instr.next_instruction()
    } else {
      // Check if stepping in the function, and get the function Value and also
      // maybe function reference
      let (step_in, func_value, func) = match instr.callee_function() {
        Some(func) => {
          let step_in = !state.stack.has_function(func)
            && func != env.slice.callee
            && !func.is_declaration_only()
            && env.slice.functions.contains(&func);
          (step_in, Rc::new(Value::Func(func.simp_name())), Some(func))
        }
        None => {
          if instr.is_inline_asm_call() {
            (false, Rc::new(Value::Asm), None)
          } else {
            (false, Rc::new(Value::FuncPtr), None)
          }
        }
      };

      // Evaluate the arguments
      let args = instr
        .arguments()
        .into_iter()
        .map(|v| self.eval_operand_value(state, v))
        .collect::<Vec<_>>();

      // Cache the node id for this call
      let node_id = state.trace.len();

      // Generate a semantics and push to the trace
      let semantics = Semantics::Call {
        func: func_value.clone(),
        args: args.clone(),
      };
      let node = TraceNode {
        instr: instr.as_instruction(),
        semantics,
        result: None,
      };
      state.trace.push(node);

      // Update the target_node in state if the target is now visited
      if instr.as_instruction() == env.slice.instr && state.target_node.is_none() {
        state.target_node = Some(node_id);
      }

      // Check if we need to get into the function
      if step_in {
        // If so, execute the function with all the information
        self.execute_function(node_id, instr, func.unwrap(), args, state, env)
      } else {
        // We only add call result if the callee function has return type
        if instr.callee_function_type().has_return_type() {
          // We create a function call result with a call_id associated
          let call_id = env.new_call_id();
          let result = Rc::new(Value::Call {
            id: call_id,
            func: func_value.clone(),
            args: args.clone(),
          });

          // Update the result stored in the trace
          state.trace[node_id].result = Some(result.clone());

          // Insert a result to the stack frame memory
          state.stack.top_mut().memory.insert(instr.as_instruction(), result);
        }

        // Execute the next instruction directly
        instr.next_instruction()
      }
    }
  }

  pub fn transfer_alloca_instr(
    &self,
    instr: AllocaInstruction<'ctx>,
    _: &mut State<'ctx>,
    _: &mut Environment<'ctx>,
  ) -> Option<Instruction<'ctx>> {
    // Lazy evaluate alloca instructions
    instr.next_instruction()
  }

  pub fn transfer_store_instr(
    &self,
    instr: StoreInstruction<'ctx>,
    state: &mut State<'ctx>,
    _: &mut Environment<'ctx>,
  ) -> Option<Instruction<'ctx>> {
    let loc = self.eval_operand_value(state, instr.location());
    let val = self.eval_operand_value(state, instr.value());
    state.memory.insert(loc.clone(), val.clone());
    let node = TraceNode {
      instr: instr.as_instruction(),
      semantics: Semantics::Store { loc, val },
      result: None,
    };
    state.trace.push(node);
    instr.next_instruction()
  }

  pub fn transfer_load_instr(
    &self,
    instr: LoadInstruction<'ctx>,
    state: &mut State<'ctx>,
    _: &mut Environment<'ctx>,
  ) -> Option<Instruction<'ctx>> {
    let loc = self.eval_operand_value(state, instr.location());
    let res = self.load_from_memory(state, loc.clone());
    let node = TraceNode {
      instr: instr.as_instruction(),
      semantics: Semantics::Load { loc },
      result: Some(res.clone()),
    };
    state.trace.push(node);
    state.stack.top_mut().memory.insert(instr.as_instruction(), res);
    instr.next_instruction()
  }

  pub fn transfer_icmp_instr(
    &self,
    instr: ICmpInstruction<'ctx>,
    state: &mut State<'ctx>,
    _: &mut Environment<'ctx>,
  ) -> Option<Instruction<'ctx>> {
    let pred = instr.predicate(); // ICMP must have a predicate
    let op0 = self.eval_operand_value(state, instr.op0());
    let op1 = self.eval_operand_value(state, instr.op1());
    let res = Rc::new(Value::ICmp {
      pred,
      op0: op0.clone(),
      op1: op1.clone(),
    });
    let semantics = Semantics::ICmp { pred, op0, op1 };
    let node = TraceNode {
      instr: instr.as_instruction(),
      semantics,
      result: Some(res.clone()),
    };
    state.trace.push(node);
    state.stack.top_mut().memory.insert(instr.as_instruction(), res);
    instr.next_instruction()
  }

  pub fn transfer_phi_instr(
    &self,
    instr: PhiInstruction<'ctx>,
    state: &mut State<'ctx>,
    _: &mut Environment<'ctx>,
  ) -> Option<Instruction<'ctx>> {
    let prev_blk = state.prev_block.unwrap();
    let incoming_val = instr
      .incomings()
      .iter()
      .find(|incoming| incoming.block == prev_blk)
      .unwrap()
      .value;
    let res = self.eval_operand_value(state, incoming_val);
    state.stack.top_mut().memory.insert(instr.as_instruction(), res);
    instr.next_instruction()
  }

  pub fn transfer_gep_instr(
    &self,
    instr: GetElementPtrInstruction<'ctx>,
    state: &mut State<'ctx>,
    _: &mut Environment<'ctx>,
  ) -> Option<Instruction<'ctx>> {
    let loc = self.eval_operand_value(state, instr.location());
    let indices = instr
      .indices()
      .iter()
      .map(|index| self.eval_operand_value(state, *index))
      .collect::<Vec<_>>();
    let res = Rc::new(Value::GEP {
      loc: loc.clone(),
      indices: indices.clone(),
    });
    let node = TraceNode {
      instr: instr.as_instruction(),
      semantics: Semantics::GEP {
        loc: loc.clone(),
        indices,
      },
      result: Some(res.clone()),
    };
    state.trace.push(node);
    state.stack.top_mut().memory.insert(instr.as_instruction(), res);
    instr.next_instruction()
  }

  pub fn transfer_binary_instr(
    &self,
    instr: BinaryInstruction<'ctx>,
    state: &mut State<'ctx>,
    _: &mut Environment<'ctx>,
  ) -> Option<Instruction<'ctx>> {
    let op = instr.opcode();
    let v0 = self.eval_operand_value(state, instr.op0());
    let v1 = self.eval_operand_value(state, instr.op1());
    let res = Rc::new(Value::Bin {
      op,
      op0: v0.clone(),
      op1: v1.clone(),
    });
    let node = TraceNode {
      instr: instr.as_instruction(),
      semantics: Semantics::Bin { op, op0: v0, op1: v1 },
      result: Some(res.clone()),
    };
    state.trace.push(node);
    state.stack.top_mut().memory.insert(instr.as_instruction(), res);
    instr.next_instruction()
  }

  pub fn transfer_unary_instr(
    &self,
    instr: UnaryInstruction<'ctx>,
    state: &mut State<'ctx>,
    _: &mut Environment<'ctx>,
  ) -> Option<Instruction<'ctx>> {
    let op = instr.opcode();
    let op0 = self.eval_operand_value(state, instr.op0());
    let node = TraceNode {
      instr: instr.as_instruction(),
      semantics: Semantics::Una { op, op0: op0.clone() },
      result: Some(op0.clone()),
    };
    state.trace.push(node);
    state.stack.top_mut().memory.insert(instr.as_instruction(), op0);
    instr.next_instruction()
  }

  pub fn transfer_unreachable_instr(
    &self,
    _: UnreachableInstruction<'ctx>,
    state: &mut State<'ctx>,
    _: &mut Environment<'ctx>,
  ) -> Option<Instruction<'ctx>> {
    state.finish_state = FinishState::Unreachable;
    None
  }

  pub fn transfer_instr(
    &self,
    instr: Instruction<'ctx>,
    _: &mut State<'ctx>,
    _: &mut Environment<'ctx>,
  ) -> Option<Instruction<'ctx>> {
    instr.next_instruction()
  }

  pub fn continue_execution(&self, metadata: &MetaData) -> bool {
    metadata.explored_trace_count < self.options.max_explored_trace_per_slice
      && metadata.proper_trace_count < self.options.max_trace_per_slice
  }

  // pub fn execute_block_trace(
  //   &self,
  //   slice: &Slice<'ctx>,
  //   block_trace_iter: BlockTraceIterator<'ctx>,
  //   slice_id: usize,
  // ) -> State<'ctx> {
  //   State::new(&slice)
  // }

  // pub fn get_block_traces(&self, slice: &Slice<'ctx>) -> Vec<BlockTrace<'ctx>> {
  //   vec![]
  // }

  pub fn execute_slice_with_precomputed_block_trace(&self, slice: Slice<'ctx>, slice_id: usize) -> MetaData {
    let mut metadata = MetaData::new();
    // let mut env = Environment::new(slice);
    // let block_traces = self.get_block_traces(&env.slice);
    // for block_trace in block_traces {
    //   let block_trace_iter = BlockTraceIterator::new(block_trace);
    //   let end_state = self.execute_block_trace(&env.slice, block_trace_iter, slice_id);
    //   self.finish_execution(end_state, slice_id, &mut metadata, &mut env);
    // }
    metadata
  }

  pub fn execute_slice_normal(&self, slice: Slice<'ctx>, slice_id: usize) -> MetaData {
    let mut metadata = MetaData::new();
    let mut env = Environment::new(slice);
    while env.has_work() && self.continue_execution(&metadata) {
      let mut work = env.pop_work();

      // Start the execution by iterating through instructions
      let mut curr_instr = self.execute_block(work.block, &mut work.state, &mut env);
      while curr_instr.is_some() {
        curr_instr = self.execute_instr_and_add_work(curr_instr, &mut work.state, &mut env);
      }

      // Finish the instruction and settle down the states
      self.finish_execution(work.state, slice_id, &mut metadata, &mut env);
    }
    metadata
  }

  pub fn finish_execution(
    &self,
    state: State<'ctx>,
    slice_id: usize,
    metadata: &mut MetaData,
    env: &mut Environment<'ctx>,
  ) {
    match state.target_node {
      Some(_target_id) => match state.finish_state {
        FinishState::ProperlyReturned => {
          // if !self.options.no_trace_reduction {
          //   work.state.trace_graph = work.state.trace_graph.reduce(target_id);
          // }
          if !env.has_duplicate(&state.block_trace) {
            // Add block trace into environment
            env.add_block_trace(&state.block_trace);

            if state.path_satisfactory() {
              let trace_id = metadata.proper_trace_count;
              let path = self.trace_file_path(env.slice.target_function_name(), slice_id, trace_id);

              // If printing trace
              if self.options.print_trace && self.ctx.options.use_serial {
                println!("\nSlice {} Trace {} Log", slice_id, trace_id);
                state.trace.print();
              }

              // Dump the json
              state.dump_json(path).unwrap();
              metadata.incr_proper();
            } else {
              if cfg!(debug_assertions) {
                for cons in state.constraints {
                  println!("{:?}", cons);
                }
                println!("Path unsat");
              }
              metadata.incr_path_unsat()
            }
          } else {
            if cfg!(debug_assertions) {
              println!("Duplicated");
            }
            metadata.incr_duplicated()
          }
        }
        FinishState::BranchExplored => {
          if cfg!(debug_assertions) {
            println!("Branch explored");
          }
          metadata.incr_branch_explored()
        }
        FinishState::ExceedingMaxTraceLength => {
          if cfg!(debug_assertions) {
            println!("Exceeding Length");
          }
          metadata.incr_exceeding_length()
        }
        FinishState::Unreachable => {
          if cfg!(debug_assertions) {
            println!("Unreachable");
          }
          metadata.incr_unreachable()
        }
      },
      None => metadata.incr_no_target(),
    }
  }

  pub fn trace_file_path(&self, func_name: String, slice_id: usize, trace_id: usize) -> PathBuf {
    Path::new(self.ctx.options.output_path.as_str())
      .join("traces")
      .join(func_name.as_str())
      .join(slice_id.to_string())
      .join(format!("{}.json", trace_id))
  }

  fn initialize_traces_function_slice_folder(&self, func_name: &String, slice_id: usize) -> Result<(), String> {
    let path = Path::new(self.ctx.options.output_path.as_str())
      .join("traces")
      .join(func_name.as_str())
      .join(slice_id.to_string());
    fs::create_dir_all(path).map_err(|_| "Cannot create trace function slice folder".to_string())
  }

  pub fn execute_slices(&self, slices: Vec<Slice<'ctx>>) -> MetaData {
    let execute = if self.options.precompute_block_trace {
      Self::execute_slice_with_precomputed_block_trace
    } else {
      Self::execute_slice_normal
    };

    if self.ctx.options.use_serial {
      slices.into_iter().progress().enumerate().fold(
        MetaData::new(),
        |meta: MetaData, (slice_id, slice): (usize, Slice<'ctx>)| {
          let func_name = slice.callee.simp_name();
          self
            .initialize_traces_function_slice_folder(&func_name, slice_id)
            .unwrap();
          meta.combine(execute(self, slice, slice_id))
        },
      )
    } else {
      slices
        .into_par_iter()
        .enumerate()
        .fold(
          || MetaData::new(),
          |meta: MetaData, (slice_id, slice): (usize, Slice<'ctx>)| {
            let func_name = slice.callee.simp_name();
            self
              .initialize_traces_function_slice_folder(&func_name, slice_id)
              .unwrap();
            meta.combine(execute(self, slice, slice_id))
          },
        )
        .progress()
        .reduce(|| MetaData::new(), MetaData::combine)
    }
  }
}
