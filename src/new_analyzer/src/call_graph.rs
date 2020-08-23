use clap::{App, Arg, ArgMatches};
use llir::{values::*, *};
use petgraph::{
  graph::{DiGraph, EdgeIndex, Graph, NodeIndex},
  visit::EdgeRef,
};
use std::collections::{HashMap};

use crate::options::*;
use crate::utils::*;

pub struct CallEdge<'ctx> {
  pub caller: Function<'ctx>,
  pub callee: Function<'ctx>,
  pub instr: CallInstruction<'ctx>,
}

impl<'ctx> CallEdge<'ctx> {
  pub fn dump(&self) {
    println!("{} -> {}", self.caller.simp_name(), self.callee.simp_name());
  }
}

/// CallGraph is defined by function vertices + instruction edges connecting caller & callee
pub type CallGraphRaw<'ctx> = DiGraph<Function<'ctx>, CallInstruction<'ctx>>;

pub trait CallGraphTrait<'ctx> {
  type Edge;

  fn remove_llvm_funcs(&mut self);

  fn call_edge(&self, edge_id: EdgeIndex) -> Option<CallEdge>;

  fn dump(&self);
}

impl<'ctx> CallGraphTrait<'ctx> for CallGraphRaw<'ctx> {
  type Edge = EdgeIndex;

  fn remove_llvm_funcs(&mut self) {
    self.retain_nodes(move |this, node_id| {
      let node_name = this[node_id].simp_name();
      let is_llvm_intrinsics = node_name.contains("llvm.");
      !is_llvm_intrinsics
    });
  }

  fn call_edge(&self, edge_id: EdgeIndex) -> Option<CallEdge> {
    self.edge_endpoints(edge_id).map(|(caller_id, callee_id)| {
      let instr = self[edge_id];
      let caller = self[caller_id];
      let callee = self[callee_id];
      CallEdge { caller, callee, instr }
    })
  }

  fn dump(&self) {
    for edge_id in self.edge_indices() {
      match self.call_edge(edge_id) {
        Some(ce) => ce.dump(),
        None => {}
      }
    }
  }
}

pub type FunctionIdMap<'ctx> = HashMap<Function<'ctx>, NodeIndex>;

#[derive(Debug, Clone)]
pub struct GraphPath<N, E>
where
  N: Clone,
  E: Clone,
{
  pub begin: N,
  pub succ: Vec<(E, N)>,
}

impl<N, E> GraphPath<N, E>
where
  N: Clone,
  E: Clone,
{
  /// Get the last element in the path. Since
  pub fn last(&self) -> &N {
    if self.succ.is_empty() {
      &self.begin
    } else {
      &self.succ[self.succ.len() - 1].1
    }
  }

  pub fn visited(&self, n: N) -> bool
  where
    N: Eq,
  {
    if self.begin == n {
      true
    } else {
      self.succ.iter().find(|(_, other_n)| other_n.clone() == n).is_some()
    }
  }

  /// Push an element into the back of the path
  pub fn push(&mut self, e: E, n: N) {
    self.succ.push((e, n));
  }

  /// The length of the path. e.g. If a path contains 5 nodes, then the length is 4.
  pub fn len(&self) -> usize {
    self.succ.len()
  }
}

pub type IndexedGraphPath = GraphPath<NodeIndex, EdgeIndex>;

impl IndexedGraphPath {
  pub fn into_elements<N, E>(&self, graph: &Graph<N, E>) -> GraphPath<N, E>
  where
    N: Clone,
    E: Clone,
  {
    GraphPath {
      begin: graph[self.begin].clone(),
      succ: self
        .succ
        .iter()
        .map(|(e, n)| (graph[*e].clone(), graph[*n].clone()))
        .collect(),
    }
  }
}

pub trait GraphTrait {
  fn paths(&self, from: NodeIndex, to: NodeIndex, max_depth: usize) -> Vec<IndexedGraphPath>;
}

impl<N, E> GraphTrait for Graph<N, E> {
  fn paths(&self, from: NodeIndex, to: NodeIndex, max_depth: usize) -> Vec<IndexedGraphPath> {
    let mut fringe = vec![IndexedGraphPath {
      begin: from,
      succ: vec![],
    }];
    let mut paths = vec![];
    while !fringe.is_empty() {
      let curr_path = fringe.pop().unwrap();
      let prev_node_id = curr_path.last().clone();
      if curr_path.len() >= max_depth {
        continue;
      } else {
        for next_edge in self.edges(prev_node_id) {
          let next_edge_id = next_edge.id();
          let next_node_id = next_edge.target();
          if next_node_id == to {
            let mut new_path = curr_path.clone();
            new_path.push(next_edge_id, next_node_id);
            paths.push(new_path);
          } else {
            if !curr_path.visited(next_node_id) {
              let mut new_path = curr_path.clone();
              new_path.push(next_edge_id, next_node_id);
              fringe.push(new_path);
            }
          }
        }
      }
    }
    paths
  }
}

pub type CallGraphPath<'ctx> = GraphPath<Function<'ctx>, CallInstruction<'ctx>>;

pub struct CallGraph<'ctx> {
  pub graph: CallGraphRaw<'ctx>,
  pub function_id_map: FunctionIdMap<'ctx>,
}

impl<'ctx> CallGraph<'ctx> {
  pub fn paths(&self, from: Function<'ctx>, to: Function<'ctx>, max_depth: usize) -> Vec<CallGraphPath<'ctx>> {
    let from_id = self.function_id_map[&from];
    let to_id = self.function_id_map[&to];
    let paths = self.graph.paths(from_id, to_id, max_depth);
    paths.into_iter().map(|path| path.into_elements(&self.graph)).collect()
  }

  pub fn from_module(module: &Module<'ctx>, options: &Options) -> Self {
    let mut value_id_map: HashMap<Function<'ctx>, NodeIndex> = HashMap::new();

    // Generate Call Graph by iterating through all blocks & instructions for each function
    let mut cg = Graph::new();
    for caller in module.iter_functions() {
      let caller_id = value_id_map
        .entry(caller)
        .or_insert_with(|| cg.add_node(caller))
        .clone();
      for b in caller.iter_blocks() {
        for i in b.iter_instructions() {
          match i {
            Instruction::Call(call_instr) => {
              if options.no_remove_llvm_funcs || !call_instr.is_intrinsic_call() {
                match call_instr.callee_function() {
                  Some(callee) => {
                    let callee_id = value_id_map
                      .entry(callee)
                      .or_insert_with(|| cg.add_node(callee))
                      .clone();
                    cg.add_edge(caller_id, callee_id, call_instr);
                  }
                  None => {}
                }
              } else {
              }
            }
            _ => {}
          }
        }
      }
    }

    // Return the call graph
    Self {
      graph: cg,
      function_id_map: value_id_map,
    }
  }
}