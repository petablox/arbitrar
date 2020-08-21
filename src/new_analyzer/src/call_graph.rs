use clap::{App, Arg, ArgMatches};
use llir::{*, values::*};
use petgraph::graph::{DiGraph, EdgeIndex, Graph, NodeIndex};
use std::collections::HashMap;

use crate::context::*;
use crate::options::Options;
use crate::utils::*;

pub struct CallEdge<'ctx> {
  pub caller: Function<'ctx>,
  pub callee: Function<'ctx>,
  pub instr: Instruction<'ctx>,
}

impl<'ctx> CallEdge<'ctx> {
  pub fn dump(&self) {
    println!("{} -> {}", self.caller.simp_name(), self.callee.simp_name());
  }
}

/// CallGraph is defined by function vertices + instruction edges connecting caller & callee
pub type CallGraphRaw<'ctx> = DiGraph<Function<'ctx>, Instruction<'ctx>>;

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

pub struct CallGraph<'ctx> {
  pub graph: CallGraphRaw<'ctx>,
  pub function_id_map: FunctionIdMap<'ctx>,
}

pub struct CallGraphOptions {
  pub no_remove_llvm_funcs: bool,
}

impl Options for CallGraphOptions {
  fn setup_parser<'a>(app: App<'a>) -> App<'a> {
    app.args(&[Arg::new("no_remove_llvm_funcs")
      .long("--no-remove-llvm-funcs")
      .about("Do not remove llvm functions")])
  }

  fn from_matches(args: &ArgMatches) -> Result<Self, String> {
    Ok(Self {
      no_remove_llvm_funcs: args.is_present("no_remove_llvm_funcs"),
    })
  }
}

pub struct CallGraphContext<'a, 'ctx> {
  pub ctx: &'a AnalyzerContext<'ctx>,
  pub options: CallGraphOptions,
}

impl<'a, 'ctx> CallGraphContext<'a, 'ctx> {
  pub fn new(ctx: &'a AnalyzerContext<'ctx>) -> Result<Self, String> {
    let options = CallGraphOptions::from_matches(&ctx.args)?;
    Ok(Self { ctx, options })
  }

  pub fn call_graph(&self) -> CallGraph<'ctx> {
    call_graph_from_module(&self.ctx.llmod, self.options.no_remove_llvm_funcs)
  }
}

pub fn call_graph_from_module<'ctx>(
  module: &Module<'ctx>,
  no_remove_llvm_funcs: bool
) -> CallGraph<'ctx>
{
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
            if no_remove_llvm_funcs || !call_instr.is_intrinsic_call() {
              match call_instr.callee_function() {
                Some(callee) => {
                  let callee_id = value_id_map
                    .entry(callee)
                    .or_insert_with(|| cg.add_node(callee))
                    .clone();
                  cg.add_edge(caller_id, callee_id, i);
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
  CallGraph { graph: cg, function_id_map: value_id_map }
}
