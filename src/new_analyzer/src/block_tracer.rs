use llir::values::*;

use crate::call_graph::CallGraph;
use crate::slicer::{Slice, SlicerOptions};

pub struct FunctionTrace<'ctx> {
  begin: Function<'ctx>,
  functions: Vec<(CallInstruction<'ctx>, Function<'ctx>)>,
}

pub type BlockTrace<'ctx> = Vec<Block<'ctx>>;

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

pub struct BlockTraceIterator<'ctx> {
  pub trace: BlockTrace<'ctx>,
  pub curr_pointer: usize,
}

impl<'ctx> BlockTraceIterator<'ctx> {
  pub fn new(trace: BlockTrace<'ctx>) -> Self {
    Self { trace, curr_pointer: 0 }
  }

  // pub fn peek_curr(&self) -> &Block<'ctx> {
  //   &self.trace[self.curr_pointer]
  // }

  // pub fn peek_next(&self) -> Option<&Block<'ctx>> {
  //   self.trace.get(self.curr_pointer + 1)
  // }

  // pub fn next(&mut self) -> Option<&Block<'ctx>> {
  //   self.curr_pointer += 1;
  //   self.trace.get(self.curr_pointer)
  // }

  // pub fn has_next(&self) -> bool {
  //   self.curr_pointer < self.trace.len()
  // }
}

pub struct BlockTracer<'a, 'ctx> {
  pub slicer_options: &'a SlicerOptions,
  pub call_graph: &'a CallGraph<'ctx>,
}

impl<'a, 'ctx> BlockTracer<'a, 'ctx> {
  pub fn block_traces_of_function_call(
    &self,
    f1: Function<'ctx>,
    f2: Function<'ctx>,
    instr: CallInstruction<'ctx>,
  ) -> Vec<BlockTrace<'ctx>> {
    // TODO
    vec![]
  }

  pub fn block_traces_of_function_trace(
    &self,
    slice: &Slice<'ctx>,
    func_trace: FunctionTrace<'ctx>,
  ) -> Vec<BlockTrace<'ctx>> {
    // TODO
    vec![]
  }

  pub fn function_traces(&self, slice: &Slice<'ctx>) -> Vec<FunctionTrace<'ctx>> {
    if slice.entry == slice.caller {
      vec![vec![slice.entry, slice.callee]]
    } else {
      petgraph::algo::all_simple_paths(
        &self.call_graph.graph,
        self.call_graph.function_id_map[&slice.entry],
        self.call_graph.function_id_map[&slice.callee],
        0,
        Some(self.slicer_options.depth as usize * 2),
      )
      .map(|path: Vec<_>| {
        let begin = self.call_graph.graph[path[0]];
        let mut functions = vec![];
        for i in 0..path.len() - 1 {
          let edge_id = self.call_graph.graph.find_edge(path[i], path[i + 1]).unwrap();
          let call_instr = self.call_graph.graph[edge_id];
          functions.push((call_instr, self.call_graph.graph[path[i + 1]]));
        }
        FunctionTrace { begin, functions }
      })
      .collect()
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
