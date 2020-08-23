use llir::values::*;
use petgraph::graph::{DiGraph, NodeIndex};
use std::collections::HashMap;

use crate::call_graph::*;
use crate::semantics::*;
use crate::slicer::*;
use crate::utils;

/// The block trace inside a function.
///
/// Fields:
/// - function: The function that contains all the blocks
/// - block_traces: The list of traces that can go from starting block to the
///   block that contains the target call
/// - call: The final Call Instruction that leads us to the next function
///   or the target function call
pub struct CompositeFunctionBlockTraces<'ctx> {
  function: Function<'ctx>,
  block_traces: Vec<Vec<Block<'ctx>>>,
  call_instr: CallInstruction<'ctx>,
}

/// A block trace is a list of FunctionBlockTrace. When finally
pub type CompositeBlockTrace<'ctx> = Vec<CompositeFunctionBlockTraces<'ctx>>;

/// One block trace inside a function leading to the call instruction
#[derive(Debug)]
pub struct FunctionBlockTrace<'ctx> {
  pub function: Function<'ctx>,
  pub block_trace: Vec<Block<'ctx>>,
  pub call_instr: CallInstruction<'ctx>,
}

/// Block trace is an array of function block trace
pub type BlockTrace<'ctx> = Vec<FunctionBlockTrace<'ctx>>;

pub trait GenerateBlockTraceTrait<'ctx> {
  fn block_traces(&self) -> Vec<BlockTrace<'ctx>>;
}

impl<'ctx> GenerateBlockTraceTrait<'ctx> for CompositeBlockTrace<'ctx> {
  fn block_traces(&self) -> Vec<BlockTrace<'ctx>> {
    let func_num_block_traces: Vec<usize> = self
      .iter()
      .map(|func_blk_trace| func_blk_trace.block_traces.len())
      .collect();
    let num_block_traces = func_num_block_traces.iter().product();
    let mut block_traces = Vec::with_capacity(num_block_traces);
    for indices in utils::cartesian(&func_num_block_traces) {
      println!("{:?}", indices);
      let block_trace = indices
        .iter()
        .enumerate()
        .map(|(i, j)| FunctionBlockTrace {
          function: self[i].function,
          block_trace: self[i].block_traces[*j].clone(),
          call_instr: self[i].call_instr,
        })
        .collect();
      block_traces.push(block_trace);
    }
    block_traces
  }
}

pub struct BlockTraceIterator<'ctx> {
  pub block_trace: BlockTrace<'ctx>,
  pub function_id: usize,
  pub block_id: usize,
}

impl<'ctx> BlockTraceIterator<'ctx> {
  pub fn from_block_trace(block_trace: BlockTrace<'ctx>) -> Self {
    Self {
      block_trace,
      function_id: 0,
      block_id: 0,
    }
  }

  pub fn visit_call(&mut self, instr: CallInstruction<'ctx>) -> bool {
    if self.block_trace[self.function_id].call_instr == instr {
      self.function_id += 1;
      true
    } else {
      false
    }
  }

  pub fn cond_branch(&self, instr: ConditionalBranchInstruction<'ctx>) -> Option<(Branch, Block<'ctx>)> {
    let block_trace = &self.block_trace[self.function_id].block_trace;
    if self.block_id < block_trace.len() && block_trace[self.block_id] == instr.parent_block() {
      let next_block = block_trace[self.block_id + 1];
      if next_block == instr.then_block() {
        return Some((Branch::Then, next_block));
      } else if next_block == instr.else_block() {
        return Some((Branch::Else, next_block));
      }
    }
    None
  }

  pub fn visit_block(&mut self, prev_block: Block<'ctx>, next_block: Block<'ctx>) -> bool {
    let block_trace = &self.block_trace[self.function_id].block_trace;
    if self.block_id < block_trace.len() - 1
      && block_trace[self.block_id] == prev_block
      && block_trace[self.block_id + 1] == next_block
    {
      self.block_id += 1;
      true
    } else {
      false
    }
  }
}

pub struct BlockGraph<'ctx> {
  graph: DiGraph<Block<'ctx>, Instruction<'ctx>>,
  block_id_map: HashMap<Block<'ctx>, NodeIndex>,
}

pub trait FunctionBlockGraphTrait<'ctx> {
  fn block_graph(&self) -> BlockGraph<'ctx>;

  fn block_traces_to_instr(&self, instr: Instruction<'ctx>) -> Vec<Vec<Block<'ctx>>>;
}

impl<'ctx> FunctionBlockGraphTrait<'ctx> for Function<'ctx> {
  fn block_graph(&self) -> BlockGraph<'ctx> {
    let mut block_id_map = HashMap::new();
    let mut graph = DiGraph::new();
    for block in self.iter_blocks() {
      let block_id = block_id_map
        .entry(block)
        .or_insert_with(|| graph.add_node(block))
        .clone();
      let terminator = block.last_instruction().unwrap();
      let next_blocks = block.destination_blocks();
      for next_block in next_blocks {
        let next_block_id = block_id_map
          .entry(next_block)
          .or_insert_with(|| graph.add_node(next_block))
          .clone();
        graph.add_edge(block_id, next_block_id, terminator);
      }
    }
    BlockGraph { graph, block_id_map }
  }

  fn block_traces_to_instr(&self, instr: Instruction<'ctx>) -> Vec<Vec<Block<'ctx>>> {
    let entry_block = self.first_block().unwrap();
    if entry_block == instr.parent_block() {
      vec![vec![entry_block]]
    } else {
      let block_graph = self.block_graph();
      petgraph::algo::all_simple_paths(
        &block_graph.graph,
        block_graph.block_id_map[&entry_block],
        block_graph.block_id_map[&instr.parent_block()],
        0,
        None,
      )
      .map(|path: Vec<_>| path.into_iter().map(|ni| block_graph.graph[ni]).collect())
      .collect()
    }
  }
}

pub trait BlockTracesFromCallGraphPath<'ctx> {
  fn block_traces(&self) -> Vec<BlockTrace<'ctx>>;
}

impl<'ctx> BlockTracesFromCallGraphPath<'ctx> for CallGraphPath<'ctx> {
  fn block_traces(&self) -> Vec<BlockTrace<'ctx>> {
    let mut curr_func = self.begin;
    let mut comp_trace = vec![];
    for (call_instr, next_func) in &self.succ {
      let block_traces = curr_func.block_traces_to_instr(call_instr.as_instruction());
      comp_trace.push(CompositeFunctionBlockTraces {
        function: curr_func,
        block_traces,
        call_instr: call_instr.clone(),
      });
      curr_func = next_func.clone();
    }
    comp_trace.block_traces()
  }
}

pub trait BlockTracesFromSlice<'ctx> {
  fn function_traces(&self, cg: &CallGraph<'ctx>, d: usize) -> Vec<CallGraphPath<'ctx>>;

  fn block_traces(&self, cg: &CallGraph<'ctx>, d: usize) -> Vec<BlockTrace<'ctx>>;
}

impl<'ctx> BlockTracesFromSlice<'ctx> for Slice<'ctx> {
  fn function_traces(&self, call_graph: &CallGraph<'ctx>, max_depth: usize) -> Vec<CallGraphPath<'ctx>> {
    if self.entry == self.caller {
      vec![CallGraphPath {
        begin: self.entry,
        succ: vec![(self.instr, self.callee)],
      }]
    } else {
      call_graph
        .paths(self.entry, self.callee, max_depth * 2)
        .into_iter()
        .filter(|path| {
          for i in 0..path.succ.len() - 1 {
            if !self.contains(path.succ[i].1) {
              return false;
            }
          }
          true
        })
        .collect()
    }
  }

  fn block_traces(&self, call_graph: &CallGraph<'ctx>, max_func_depth: usize) -> Vec<BlockTrace<'ctx>> {
    let mut traces = vec![];
    for func_trace in self.function_traces(call_graph, max_func_depth) {
      traces.extend(func_trace.block_traces());
    }
    traces
  }
}
