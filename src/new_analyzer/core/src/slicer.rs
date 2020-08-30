use llir::values::*;
use petgraph::{graph::*, visit::*, Direction};
use rayon::prelude::*;
use regex::Regex;
use serde_json::json;
use std::collections::HashMap;
use std::collections::HashSet;
use std::fs;
use std::fs::File;
use std::io::Write;

use crate::call_graph::*;
use crate::options::*;
use crate::utils::*;

#[derive(Clone)]
pub struct Slice<'ctx> {
  pub entry: Function<'ctx>,
  pub caller: Function<'ctx>,
  pub callee: Function<'ctx>,
  pub instr: CallInstruction<'ctx>,
  pub functions: HashSet<Function<'ctx>>,
}

impl<'ctx> Slice<'ctx> {
  pub fn contains(&self, f: Function<'ctx>) -> bool {
    self.functions.contains(&f)
  }

  pub fn to_json(&self) -> serde_json::Value {
    json!({
      "entry": self.entry.simp_name(),
      "caller": self.caller.simp_name(),
      "callee": self.callee.simp_name(),
      "instr": self.instr.debug_loc_string(),
      "functions": self.functions.iter().map(|f| f.simp_name()).collect::<Vec<_>>(),
    })
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

pub trait TargetEdgesMapTrait: Sized {
  fn from_call_graph<'ctx>(call_graph: &CallGraph<'ctx>, options: &Options) -> Result<Self, String>;
}

impl TargetEdgesMapTrait for TargetEdgesMap {
  fn from_call_graph<'ctx>(call_graph: &CallGraph<'ctx>, options: &Options) -> Result<Self, String> {
    let inclusion_filter = TargetFilter::new(options.target_inclusion_filter.clone(), options.use_regex_filter, true)?;
    let exclusion_filter = TargetFilter::new(options.target_exclusion_filter.clone(), options.use_regex_filter, false)?;
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
        for edge in call_graph.graph.edges_directed(callee_id, Direction::Incoming) {
          target_edges_map
            .entry(func_name.clone())
            .or_insert(Vec::new())
            .push(edge.id());
        }
      }
    }
    Ok(target_edges_map)
  }
}

/// Map frmo function name to Slices
pub type TargetSlicesMap<'ctx> = HashMap<String, Vec<Slice<'ctx>>>;

pub trait TargetSlicesMapTrait<'ctx>: Sized {
  fn from_target_edges_map(target_edges_map: &TargetEdgesMap, call_graph: &CallGraph<'ctx>, options: &Options) -> Self;

  fn dump(&self, options: &Options);
}

impl<'ctx> TargetSlicesMapTrait<'ctx> for TargetSlicesMap<'ctx> {
  fn from_target_edges_map(target_edges_map: &TargetEdgesMap, call_graph: &CallGraph<'ctx>, options: &Options) -> Self {
    let mut result = HashMap::new();
    for (target, edges) in target_edges_map {
      let slices = call_graph.slices_of_call_edges(&edges[..], options);
      result.insert(target.clone(), slices);
    }
    result
  }

  fn dump(&self, options: &Options) {
    for (target, slices) in self {
      fs::create_dir_all(options.slice_target_dir_path(target.as_str())).expect("Cannot create slice folder");
      slices.par_iter().enumerate().for_each(|(i, slice)| {
        let path = options.slice_file_path(target.as_str(), i);
        let slice_json = slice.to_json();
        let json_str = serde_json::to_string(&slice_json).expect("Cannot turn json into string");
        let mut file = File::create(path).expect("Cannot create slice file");
        file.write_all(json_str.as_bytes()).expect("Cannot write to slice file")
      });
    }
  }
}

pub trait Slicer<'ctx> {
  fn reduce_slice(
    &self,
    entry_id: NodeIndex,
    target_id: NodeIndex,
    functions: HashSet<NodeIndex>,
  ) -> HashSet<NodeIndex>;

  fn find_entries(&self, edge_id: EdgeIndex, options: &Options) -> Vec<NodeIndex>;

  fn slice_of_entry(&self, entry_id: NodeIndex, edge_id: EdgeIndex, options: &Options) -> Slice<'ctx>;

  fn slices_of_call_edge(&self, edge_id: EdgeIndex, options: &Options) -> Vec<Slice<'ctx>>;

  fn slices_of_call_edges(&self, edges: &[EdgeIndex], options: &Options) -> Vec<Slice<'ctx>>;
}

impl<'ctx> Slicer<'ctx> for CallGraph<'ctx> {
  fn reduce_slice(
    &self,
    _entry_id: NodeIndex,
    _target_id: NodeIndex,
    functions: HashSet<NodeIndex>,
  ) -> HashSet<NodeIndex> {
    // TODO
    // let is_related_map = HashMap::new();
    // let queue = vec![(entry_id, None)];
    // while !queue.is_empty() {
    //   let (func_id, maybe_instr) = queue.pop().unwrap();
    // }
    functions
  }

  fn find_entries(&self, edge_id: EdgeIndex, options: &Options) -> Vec<NodeIndex> {
    let entry_location_filter = match &options.entry_filter {
      Some(filter) => Some(
        Regex::new(filter.as_str())
          .map_err(|_| String::from("Cannot parse entry filter regex"))
          .unwrap(),
      ),
      None => None,
    };
    let mut result = HashSet::new();
    match self.graph.edge_endpoints(edge_id) {
      Some((func_id, _)) => {
        let mut fringe = Vec::new();
        fringe.push((func_id, options.slice_depth));
        while !fringe.is_empty() {
          let (func_id, depth) = fringe.pop().unwrap();
          if depth == 0 {
            result.insert(func_id);
          } else {
            let mut contains_parent = false;
            for caller_id in self.graph.neighbors_directed(func_id, Direction::Incoming) {
              contains_parent = true;
              fringe.push((caller_id, depth - 1));
            }
            if !contains_parent {
              result.insert(func_id);
            }
          }
        }
      }
      None => (),
    }
    result
      .into_iter()
      .filter(|func_id| match &entry_location_filter {
        Some(regex) => {
          let func = self.graph.node_weight(*func_id).unwrap();
          match func.filename() {
            Some(name) => regex.is_match(name.as_str()),
            _ => true,
          }
        }
        None => true,
      })
      .collect()
  }

  fn slice_of_entry(&self, entry_id: NodeIndex, edge_id: EdgeIndex, options: &Options) -> Slice<'ctx> {
    // Get basic informations
    let entry = self.graph[entry_id];
    let instr = self.graph[edge_id];
    let (caller, callee_id, callee) = {
      let (caller_id, callee_id) = self.graph.edge_endpoints(edge_id).unwrap();
      (self.graph[caller_id], callee_id, self.graph[callee_id])
    };

    // Get included functions
    let mut fringe = vec![(entry_id, options.slice_depth * 2)];
    let mut visited = HashSet::new();
    let mut function_ids = HashSet::new();
    while !fringe.is_empty() {
      let (func_id, depth) = fringe.pop().unwrap();
      visited.insert(func_id);

      // We don't want to go into target
      if func_id != callee_id {
        // Add the function into functions
        function_ids.insert(func_id);

        // Iterate through callees
        if depth > 0 {
          for callee_id in self.graph.neighbors_directed(func_id, Direction::Outgoing) {
            if !visited.contains(&callee_id) {
              fringe.push((callee_id, depth - 1));
            }
          }
        }
      }
    }

    // Reduced function boundary
    let function_ids = if options.reduce_slice {
      self.reduce_slice(entry_id, callee_id, function_ids)
    } else {
      function_ids
    };

    // Generate slice
    let functions = function_ids.iter().map(|func_id| self.graph[*func_id]).collect();
    Slice {
      caller,
      callee,
      instr,
      entry,
      functions,
    }
  }

  fn slices_of_call_edge(&self, edge_id: EdgeIndex, options: &Options) -> Vec<Slice<'ctx>> {
    let entry_ids = self.find_entries(edge_id, options);
    entry_ids
      .into_iter()
      .map(|entry_id| self.slice_of_entry(entry_id, edge_id, options))
      .collect()
  }

  fn slices_of_call_edges(&self, edges: &[EdgeIndex], options: &Options) -> Vec<Slice<'ctx>> {
    let f = |edge_id: &EdgeIndex| -> Vec<Slice<'ctx>> { self.slices_of_call_edge(edge_id.clone(), options) };
    if options.use_serial {
      edges.iter().map(f).flatten().collect()
    } else {
      edges.par_iter().map(f).flatten().collect()
    }
  }
}
