use llir::values::*;
use petgraph::graph::{DiGraph, NodeIndex};
use std::collections::HashMap;

use crate::call_graph::*;
use crate::slicer::{Slice, SlicerOptions};
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

pub struct BlockGraph<'ctx> {
  graph: DiGraph<Block<'ctx>, Instruction<'ctx>>,
  block_id_map: HashMap<Block<'ctx>, NodeIndex>,
}

pub struct BlockTracer<'a, 'ctx> {
  pub slicer_options: &'a SlicerOptions,
  pub call_graph: &'a CallGraph<'ctx>,
}

impl<'a, 'ctx> BlockTracer<'a, 'ctx> {
  pub fn block_graph_of_function(&self, f: Function<'ctx>) -> BlockGraph<'ctx> {
    let mut block_id_map = HashMap::new();
    let mut graph = DiGraph::new();
    for block in f.iter_blocks() {
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

  pub fn block_traces_of_function_call(
    &self,
    func: Function<'ctx>,
    instr: CallInstruction<'ctx>,
  ) -> Vec<Vec<Block<'ctx>>> {
    let entry_block = func.first_block().unwrap();
    if entry_block == instr.parent_block() {
      vec![vec![entry_block]]
    } else {
      let block_graph = self.block_graph_of_function(func);
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

  pub fn block_traces_of_function_trace(
    &self,
    slice: &Slice<'ctx>,
    func_trace: CallGraphPath<'ctx>,
  ) -> Vec<BlockTrace<'ctx>> {
    let mut curr_func = func_trace.begin;
    let mut comp_trace = vec![];
    for (call_instr, next_func) in func_trace.succ {
      let block_traces = self.block_traces_of_function_call(curr_func, call_instr);
      comp_trace.push(CompositeFunctionBlockTraces {
        function: curr_func,
        block_traces,
        call_instr,
      });
      curr_func = next_func;
    }
    comp_trace.block_traces()
  }

  pub fn function_traces(&self, slice: &Slice<'ctx>) -> Vec<CallGraphPath<'ctx>> {
    if slice.entry == slice.caller {
      vec![CallGraphPath {
        begin: slice.entry,
        succ: vec![(slice.instr, slice.callee)],
      }]
    } else {
      self
        .call_graph
        .paths(slice.entry, slice.callee, self.slicer_options.depth as usize * 2)
    }
  }

  pub fn block_traces(&self, slice: &Slice<'ctx>) -> Vec<BlockTrace<'ctx>> {
    let mut traces = vec![];
    for func_trace in self.function_traces(slice) {
      traces.extend(self.block_traces_of_function_trace(slice, func_trace));
    }
    traces
  }
}
