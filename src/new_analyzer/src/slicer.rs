use llir::values::*;
use petgraph::{graph::*, Direction};
use rayon::prelude::*;
use regex::Regex;
use std::collections::HashMap;
use std::collections::HashSet;
use std::fs;
use std::fs::File;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::slice::Chunks;

use crate::call_graph::*;
use crate::options::*;
use crate::utils::*;

pub struct Slice<'ctx> {
  pub entry: Function<'ctx>,
  pub caller: Function<'ctx>,
  pub callee: Function<'ctx>,
  pub instr: CallInstruction<'ctx>,
  pub functions: HashSet<Function<'ctx>>,
}

impl<'ctx> Slice<'ctx> {
  pub fn _dump(&self) {
    print!(
      "Entry: {}, Caller: {}, Functions: {{",
      self.entry.simp_name(),
      self.caller.simp_name()
    );
    for (id, f) in self.functions.iter().enumerate() {
      if id == self.functions.len() - 1 {
        print!("{}", f.simp_name());
      } else {
        print!("{}, ", f.simp_name());
      }
    }
    println!("}}");
  }

  pub fn contains(&self, f: Function<'ctx>) -> bool {
    self.functions.contains(&f)
  }

  pub fn dump_json(&self, path: PathBuf) -> Result<(), String> {
    Ok(())
  }

  pub fn target_function_name(&self) -> String {
    self.callee.simp_name()
  }
}

enum TargetFilter {
  Regex(Regex),
  Str(String),
  None(bool),
}

impl TargetFilter {
  pub fn new(filter_str: Option<String>, use_regex: bool, default: bool) -> Result<Self, String> {
    match filter_str {
      Some(s) => {
        if use_regex {
          let regex = Regex::new(s.as_str()).map_err(|_| "Cannot parse target filter".to_string())?;
          Ok(Self::Regex(regex))
        } else {
          Ok(Self::Str(s.clone()))
        }
      }
      _ => Ok(Self::None(default)),
    }
  }

  pub fn matches(&self, f: &str) -> bool {
    // Omitting the number after `.`
    let f = match f.find('.') {
      Some(i) => &f[..i],
      None => f,
    };
    match self {
      Self::Regex(r) => r.is_match(f),
      Self::Str(s) => s == f,
      Self::None(d) => d.clone(),
    }
  }
}

/// Map from function name to Edges (`Vec<Edge>`)
pub type TargetEdgesMap = HashMap<String, Vec<EdgeIndex>>;

pub trait TargetEdgesMapTrait : Sized {
  fn from_call_graph<'ctx>(call_graph: &CallGraph<'ctx>, options: &Options) -> Result<Self, String>;
}

impl TargetEdgesMapTrait for TargetEdgesMap {
  fn from_call_graph<'ctx>(call_graph: &CallGraph<'ctx>, options: &Options) -> Result<Self, String> {
    let inclusion_filter = TargetFilter::new(
      options.target_inclusion_filter.clone(),
      options.use_regex_filter,
      true,
    )?;
    let exclusion_filter = TargetFilter::new(
      options.target_exclusion_filter.clone(),
      options.use_regex_filter,
      false,
    )?;
    let mut target_edges_map = TargetEdgesMap::new();
    for callee_id in call_graph.graph.node_indices() {
      let func = call_graph.graph[callee_id];
      let func_name = func.simp_name();
      let include_from_inclusion = inclusion_filter.matches(func_name.as_str());
      let include = if !include_from_inclusion {
        false
      } else {
        !exclusion_filter.matches(func_name.as_str())
      };
      if include {
        for caller_id in call_graph.graph.neighbors_directed(callee_id, Direction::Incoming) {
          let edge = call_graph.graph.find_edge(caller_id, callee_id).unwrap();
          target_edges_map
            .entry(func_name.clone())
            .or_insert(Vec::new())
            .push(edge);
        }
      }
    }
    Ok(target_edges_map)
  }
}

/// Map frmo function name to Slices
pub type TargetSlicesMap<'ctx> = HashMap<String, Vec<Slice<'ctx>>>;

pub trait TargetSlicesMapTrait : Sized {
  fn from_target_edges_map(target_edges_map: &TargetEdgesMap, options: &Options) -> Self;
}

impl<'ctx> TargetSlicesMapTrait for TargetSlicesMap<'ctx> {
  fn from_target_edges_map(target_edges_map: &TargetEdgesMap, options: &Options) -> Self {
    let mut result = HashMap::new();
    for (target, edges) in target_edges_map {
      let slices = edges.iter().map(|_| vec![]).flatten().collect();
      result.insert(target.clone(), slices);
    }
    result
  }
}

// pub struct SlicerContext<'a, 'ctx> {
//   pub ctx: &'a AnalyzerContext<'ctx>,
//   pub call_graph: &'a CallGraph<'ctx>,
//   pub options: SlicerOptions,
// }

// impl<'a, 'ctx> SlicerContext<'a, 'ctx> {
//   pub fn new(ctx: &'a AnalyzerContext<'ctx>, call_graph: &'a CallGraph<'ctx>) -> Result<Self, String> {
//     let options = SlicerOptions::from_matches(&ctx.args)?;
//     Ok(SlicerContext {
//       ctx,
//       call_graph,
//       options,
//     })
//   }

//   pub fn num_batches<'b>(&self, edges: &'b Vec<EdgeIndex>) -> u32 {
//     if self.options.use_batch {
//       (edges.len() as f32 / self.options.batch_size as f32).ceil() as u32
//     } else {
//       1
//     }
//   }

//   pub fn batches<'b>(&self, edges: &'b Vec<EdgeIndex>) -> Chunks<'b, EdgeIndex> {
//     if self.options.use_batch {
//       edges.chunks(self.options.batch_size as usize)
//     } else {
//       edges.chunks(edges.len())
//     }
//   }

//   pub fn find_entries(&self, edge_id: EdgeIndex) -> Vec<NodeIndex> {
//     let entry_location_filter = match &self.options.entry_filter {
//       Some(filter) => Some(
//         Regex::new(filter.as_str())
//           .map_err(|_| String::from("Cannot parse entry filter regex"))
//           .unwrap(),
//       ),
//       None => None,
//     };
//     let mut result = HashSet::new();
//     match self.call_graph.graph.edge_endpoints(edge_id) {
//       Some((func_id, _)) => {
//         let mut fringe = Vec::new();
//         fringe.push((func_id, self.options.depth));
//         while !fringe.is_empty() {
//           let (func_id, depth) = fringe.pop().unwrap();
//           if depth == 0 {
//             result.insert(func_id);
//           } else {
//             let mut contains_parent = false;
//             for caller_id in self.call_graph.graph.neighbors_directed(func_id, Direction::Incoming) {
//               contains_parent = true;
//               fringe.push((caller_id, depth - 1));
//             }
//             if !contains_parent {
//               result.insert(func_id);
//             }
//           }
//         }
//       }
//       None => (),
//     }
//     result
//       .into_iter()
//       .filter(|func_id| match &entry_location_filter {
//         Some(regex) => {
//           let func = self.call_graph.graph.node_weight(*func_id).unwrap();
//           match func.filename() {
//             Some(name) => regex.is_match(name.as_str()),
//             _ => true,
//           }
//         }
//         None => true,
//       })
//       .collect()
//   }

//   pub fn directly_related(&self, _c1: CallInstruction<'ctx>, _c2: CallInstruction<'ctx>) -> bool {
//     // TODO
//     // let share_prefix = {
//     //   let (c1_name, c2_name) = (f1.function_name(), f2.function_name());
//     //   let common_len = c1_name.len().min(c2_name.len());
//     //   if common_len == 0 {
//     //     false
//     //   } else {
//     //     c1_name.chars().nth(0) == c2_name.chars().nth(0)
//     //   }
//     // };
//     true
//   }

//   pub fn reduce(
//     &self,
//     _entry_id: NodeIndex,
//     _target_id: NodeIndex,
//     functions: HashSet<NodeIndex>,
//   ) -> HashSet<NodeIndex> {
//     // TODO
//     // let is_related_map = HashMap::new();
//     // let queue = vec![(entry_id, None)];
//     // while !queue.is_empty() {
//     //   let (func_id, maybe_instr) = queue.pop().unwrap();
//     // }
//     functions
//   }

//   pub fn slice_of_entry(&self, entry_id: NodeIndex, edge_id: EdgeIndex) -> Slice<'ctx> {
//     // Get basic informations
//     let entry = self.call_graph.graph[entry_id];
//     let instr = self.call_graph.graph[edge_id];
//     let (caller, callee_id, callee) = {
//       let (caller_id, callee_id) = self.call_graph.graph.edge_endpoints(edge_id).unwrap();
//       (
//         self.call_graph.graph[caller_id],
//         callee_id,
//         self.call_graph.graph[callee_id],
//       )
//     };

//     // Get included functions
//     let mut fringe = vec![(entry_id, self.options.depth * 2)];
//     let mut visited = HashSet::new();
//     let mut function_ids = HashSet::new();
//     while !fringe.is_empty() {
//       let (func_id, depth) = fringe.pop().unwrap();
//       visited.insert(func_id);

//       // We don't want to go into target
//       if func_id != callee_id {
//         // Add the function into functions
//         function_ids.insert(func_id);

//         // Iterate through callees
//         if depth > 0 {
//           for callee_id in self.call_graph.graph.neighbors_directed(func_id, Direction::Outgoing) {
//             if !visited.contains(&callee_id) {
//               fringe.push((callee_id, depth - 1));
//             }
//           }
//         }
//       }
//     }

//     // Reduced function boundary
//     let function_ids = if self.options.reduce_slice {
//       self.reduce(entry_id, callee_id, function_ids)
//     } else {
//       function_ids
//     };

//     // Generate slice
//     let functions = function_ids
//       .iter()
//       .map(|func_id| self.call_graph.graph[*func_id])
//       .collect();
//     Slice {
//       caller,
//       callee,
//       instr,
//       entry,
//       functions,
//     }
//   }

//   pub fn slices_of_call_edge(&self, edge_id: EdgeIndex) -> Vec<Slice<'ctx>> {
//     let entry_ids = self.find_entries(edge_id);
//     entry_ids
//       .iter()
//       .map(|entry_id| self.slice_of_entry(*entry_id, edge_id))
//       .collect()
//   }

//   pub fn slices_of_call_edges(&self, edges: &[EdgeIndex]) -> Vec<Slice<'ctx>> {
//     let f = |edge_id: &EdgeIndex| -> Vec<Slice<'ctx>> { self.slices_of_call_edge(edge_id.clone()) };
//     if self.ctx.options.use_serial {
//       edges.iter().map(f).flatten().collect()
//     } else {
//       edges.par_iter().map(f).flatten().collect()
//     }
//   }

//   // pub fn dump_slices(&self, slices: &Vec<Slice<'ctx>>) -> Result<(), String> {
//   //   slices.par_iter().enumerate().for_each(|slice_id, )
//   // }
// }
