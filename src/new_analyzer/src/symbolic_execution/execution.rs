use indicatif::*;
use llir::{values::*, Module};
use rayon::prelude::*;
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::rc::Rc;

use crate::call_graph::*;
use crate::options::*;
use crate::semantics::*;
use crate::slicer::*;
use crate::utils::*;

use super::*;

pub struct SymbolicExecutionContext<'a, 'ctx> {
  pub module: &'a Module<'ctx>,
  pub call_graph: &'a CallGraph<'ctx>,
  pub options: &'a Options,
}

impl<'a, 'ctx> SymbolicExecutionContext<'a, 'ctx> {
  pub fn new(module: &'a Module<'ctx>, call_graph: &'a CallGraph<'ctx>, options: &'a Options) -> Result<Self, String> {
    Ok(Self {
      module,
      call_graph,
      options,
    })
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
    match state.prev_block {
      Some(prev_block) => {
        state.block_trace_iter.visit_block(prev_block, block);
      }
      _ => {}
    }
    block.first_instruction()
  }

  pub fn execute_instr(
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

  pub fn transfer_unconditional_br_instr(
    &self,
    instr: UnconditionalBranchInstruction<'ctx>,
    state: &mut State<'ctx>,
    env: &mut Environment<'ctx>,
  ) -> Option<Instruction<'ctx>> {
    let curr_blk = instr.parent_block(); // We assume instruction always has parent block
    state.prev_block = Some(curr_blk);
    state.trace.push(TraceNode {
      instr: instr.as_instruction(),
      semantics: Semantics::UncondBr {
        end_loop: instr.is_loop_jump().unwrap_or(false),
      },
      result: None,
    });
    self.execute_block(instr.destination(), state, env)
  }

  pub fn transfer_conditional_br_instr(
    &self,
    instr: ConditionalBranchInstruction<'ctx>,
    state: &mut State<'ctx>,
    env: &mut Environment<'ctx>,
  ) -> Option<Instruction<'ctx>> {

    // Set previous block
    let curr_blk = instr.parent_block(); // We assume instruction always has parent block
    state.prev_block = Some(curr_blk);

    // Check condition
    let cond = self.eval_operand_value(state, instr.condition().into());
    let comparison = cond.as_comparison();
    let is_loop_blk = curr_blk.is_loop_entry_block();

    match state.block_trace_iter.cond_branch(instr) {
      Some((br, block)) => {
        let br_dir = BranchDirection {
          from: curr_blk,
          to: block,
        };
        let visited = state.visited_branch.contains(&br_dir);
        if !visited {
          if let Some(comparison) = comparison {
            if !is_loop_blk {
              state.add_constraint(comparison, br.is_then());
            }
          }
          state.visited_branch.insert(br_dir);
          state.trace.push(TraceNode {
            instr: instr.as_instruction(),
            result: None,
            semantics: Semantics::CondBr {
              cond,
              br,
              beg_loop: is_loop_blk,
            },
          });
          self.execute_block(block, state, env)
        } else {
          // If the guided block is visited, stop the execution with BranchExplored
          state.finish_state = FinishState::BranchExplored;
          None
        }
      }
      None => {
        let then_br = BranchDirection {
          from: curr_blk,
          to: instr.then_block(),
        };
        let else_br = BranchDirection {
          from: curr_blk,
          to: instr.else_block(),
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
            let else_work = Work::new(instr.else_block(), else_state);
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
          self.execute_block(instr.then_block(), state, env)
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
          self.execute_block(instr.else_block(), state, env)
        } else {
          // If both then and else are visited, stop the execution with BranchExplored
          state.finish_state = FinishState::BranchExplored;
          None
        }
      }
    }
  }

  pub fn transfer_br_instr(
    &self,
    instr: BranchInstruction<'ctx>,
    state: &mut State<'ctx>,
    env: &mut Environment<'ctx>,
  ) -> Option<Instruction<'ctx>> {
    match instr {
      BranchInstruction::Conditional(cb) => self.transfer_conditional_br_instr(cb, state, env),
      BranchInstruction::Unconditional(ub) => self.transfer_unconditional_br_instr(ub, state, env),
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
        let br_work = Work::new(bd.to, br_state);
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
      // Visit call for block trace guidance
      state.block_trace_iter.visit_call(instr);

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
      if instr == env.slice.instr && state.target_node.is_none() {
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
          let block_trace = state.trace.block_trace();
          if !env.has_duplicate(&block_trace) {
            // Add block trace into environment
            env.add_block_trace(block_trace);

            if state.path_satisfactory() {
              let trace_id = metadata.proper_trace_count;
              let path = self.trace_file_path(env.slice.target_function_name(), slice_id, trace_id);

              // If printing trace
              if self.options.print_trace && self.options.use_serial {
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

  pub fn execute_slice(&self, slice: &Slice<'ctx>, slice_id: usize) -> MetaData {
    let mut metadata = MetaData::new();
    let mut env = Environment::new(slice);

    // Add a work to the environment list
    if self.options.no_prefilter_block_trace {
      let first_work = Work::entry(&slice);
      env.add_work(first_work);
    } else {
      let block_traces = slice.block_traces(self.call_graph, self.options.slice_depth as usize * 2);
      for block_trace in block_traces {
        let work = Work::entry_with_block_trace(slice, block_trace);
        env.add_work(work);
      }
    }

    // Iterate till no more work to be done or should end execution
    while env.has_work() && self.continue_execution(&metadata) {
      let mut work = env.pop_work();

      // Start the execution by iterating through instructions
      let mut curr_instr = self.execute_block(work.block, &mut work.state, &mut env);
      while curr_instr.is_some() {
        curr_instr = self.execute_instr(curr_instr, &mut work.state, &mut env);
      }

      // Finish the instruction and settle down the states
      self.finish_execution(work.state, slice_id, &mut metadata, &mut env);
    }
    metadata
  }

  pub fn trace_file_path(&self, func_name: String, slice_id: usize, trace_id: usize) -> PathBuf {
    self
      .options
      .output_path()
      .join("traces")
      .join(func_name.as_str())
      .join(slice_id.to_string())
      .join(format!("{}.json", trace_id))
  }

  fn initialize_traces_function_slice_folder(&self, func_name: &String, slice_id: usize) -> Result<(), String> {
    let path = self
      .options
      .output_path()
      .join("traces")
      .join(func_name.as_str())
      .join(slice_id.to_string());
    fs::create_dir_all(path).map_err(|_| "Cannot create trace function slice folder".to_string())
  }

  pub fn execute_target_slices(
    &self,
    target_name: &String,
    slice_id_offset: usize,
    slices: &Vec<Slice<'ctx>>,
  ) -> MetaData {
    if self.options.use_serial {
      slices.into_iter().progress().enumerate().fold(
        MetaData::new(),
        |meta: MetaData, (id, slice): (usize, &Slice<'ctx>)| {
          let slice_id = slice_id_offset + id;
          self
            .initialize_traces_function_slice_folder(target_name, slice_id)
            .unwrap();
          meta.combine(self.execute_slice(slice, slice_id))
        },
      )
    } else {
      slices
        .into_par_iter()
        .enumerate()
        .fold(
          || MetaData::new(),
          |meta: MetaData, (id, slice): (usize, &Slice<'ctx>)| {
            let slice_id = slice_id_offset + id;
            self
              .initialize_traces_function_slice_folder(target_name, slice_id)
              .unwrap();
            meta.combine(self.execute_slice(slice, slice_id))
          },
        )
        .progress()
        .reduce(|| MetaData::new(), MetaData::combine)
    }
  }

  pub fn execute_target_slices_map(&self, target_slices_map: HashMap<String, (usize, Vec<Slice<'ctx>>)>) -> MetaData {
    if self.options.use_serial {
      target_slices_map
        .into_iter()
        .fold(MetaData::new(), |meta, (target_name, (offset, slices))| {
          meta.combine(self.execute_target_slices(&target_name, offset, &slices))
        })
    } else {
      target_slices_map
        .into_par_iter()
        .fold(
          || MetaData::new(),
          |meta, (target_name, (offset, slices))| {
            meta.combine(self.execute_target_slices(&target_name, offset, &slices))
          },
        )
        .progress()
        .reduce(|| MetaData::new(), MetaData::combine)
    }
  }
}
