use clap::{App, Arg, ArgMatches};
use llir::values::*;
use petgraph::{
  graph::{EdgeIndex, NodeIndex},
  Direction,
};
use rayon::prelude::*;
use regex::Regex;
use std::collections::HashSet;
use std::slice::Chunks;

use crate::call_graph::*;
use crate::context::AnalyzerContext;
// use crate::ll_utils::*;
use crate::options::Options;

pub struct SlicerOptions {
  pub depth: u8,
  pub target_inclusion_filter: Option<String>,
  pub target_exclusion_filter: Option<String>,
  pub entry_filter: Option<String>,
  pub reduce_slice: bool,
  pub use_batch: bool,
  pub batch_size: u32,
  pub use_regex_filter: bool,
}

impl Options for SlicerOptions {
  fn setup_parser<'a>(app: App<'a>) -> App<'a> {
    app.args(&[
      Arg::new("depth")
        .value_name("DEPTH")
        .takes_value(true)
        .short('d')
        .long("depth")
        .about("Slice depth")
        .default_value("1"),
      Arg::new("target_inclusion_filter")
        .value_name("INCLUDE_TARGET")
        .takes_value(true)
        .long("include-target")
        .about("Include target functions. In the form of Regex"),
      Arg::new("use_regex_filter")
        .long("use-regex-filter")
        .about("Use Regex in inclusion/exclusion filter"),
      Arg::new("target_exclusion_filter")
        .value_name("EXCLUDE_TARGET")
        .takes_value(true)
        .long("exclude-target")
        .about("Exclude target functions. In the form of Regex"),
      Arg::new("entry_filter")
        .value_name("ENTRY_LOCATION")
        .takes_value(true)
        .long("entry-location")
        .about("Entry location filters. In the form of Regex"),
      Arg::new("reduce_slice")
        .long("reduce-slice")
        .about("Reduce slice using relevancy test"),
      Arg::new("use_batch").long("use-batch").about("Use batched execution"),
      Arg::new("batch_size")
        .value_name("BATCH_SIZE")
        .takes_value(true)
        .default_value("100")
        .long("batch-size"),
    ])
  }

  fn from_matches(matches: &ArgMatches) -> Result<Self, String> {
    Ok(Self {
      depth: matches
        .value_of_t::<u8>("depth")
        .map_err(|_| String::from("Cannot parse depth"))?,
      target_inclusion_filter: matches.value_of("target_inclusion_filter").map(String::from),
      target_exclusion_filter: matches.value_of("target_exclusion_filter").map(String::from),
      entry_filter: matches.value_of("entry_filter").map(String::from),
      reduce_slice: matches.is_present("reduce_slice"),
      use_batch: matches.is_present("use_batch"),
      batch_size: matches
        .value_of_t::<u32>("batch_size")
        .map_err(|_| String::from("Cannot parse batch size"))?,
      use_regex_filter: matches.is_present("use_regex_filter"),
    })
  }
}

pub struct Slice<'ctx> {
  pub entry: Function<'ctx>,
  pub caller: Function<'ctx>,
  pub callee: Function<'ctx>,
  pub instr: Instruction<'ctx>,
  pub functions: HashSet<Function<'ctx>>,
}

unsafe impl<'ctx> Send for Slice<'ctx> {}

impl<'ctx> Slice<'ctx> {
  pub fn _dump(&self) {
    print!(
      "Entry: {}, Caller: {}, Functions: {{",
      self.entry.name(),
      self.caller.name()
    );
    for (id, f) in self.functions.iter().enumerate() {
      if id == self.functions.len() - 1 {
        print!("{}", f.name());
      } else {
        print!("{}, ", f.name());
      }
    }
    println!("}}");
  }

  pub fn target_function_name(&self) -> String {
    self.callee.name()
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

pub struct SlicerContext<'a, 'ctx> {
  pub ctx: &'a AnalyzerContext<'ctx>,
  pub call_graph: &'a CallGraph<'ctx>,
  pub options: SlicerOptions,
}

unsafe impl<'a, 'ctx> Sync for SlicerContext<'a, 'ctx> {}

impl<'a, 'ctx> SlicerContext<'a, 'ctx> {
  pub fn new(ctx: &'a AnalyzerContext<'ctx>, call_graph: &'a CallGraph<'ctx>) -> Result<Self, String> {
    let options = SlicerOptions::from_matches(&ctx.args)?;
    Ok(SlicerContext {
      ctx,
      call_graph,
      options,
    })
  }

  pub fn relavant_edges(&self) -> Result<Vec<EdgeIndex>, String> {
    let inclusion_filter = TargetFilter::new(
      self.options.target_inclusion_filter.clone(),
      self.options.use_regex_filter,
      true,
    )?;
    let exclusion_filter = TargetFilter::new(
      self.options.target_exclusion_filter.clone(),
      self.options.use_regex_filter,
      false,
    )?;
    let mut edges = vec![];
    for callee_id in self.call_graph.node_indices() {
      let func = self.call_graph[callee_id];
      let func_name = func.name();
      let include_from_inclusion = inclusion_filter.matches(func_name.as_str());
      let include = if !include_from_inclusion {
        false
      } else {
        !exclusion_filter.matches(func_name.as_str())
      };
      if include {
        for caller_id in self.call_graph.neighbors_directed(callee_id, Direction::Incoming) {
          edges.push(self.call_graph.find_edge(caller_id, callee_id).unwrap());
        }
      }
    }
    Ok(edges)
  }

  pub fn num_batches<'b>(&self, edges: &'b Vec<EdgeIndex>) -> u32 {
    if self.options.use_batch {
      (edges.len() as f32 / self.options.batch_size as f32).ceil() as u32
    } else {
      1
    }
  }

  pub fn batches<'b>(&self, edges: &'b Vec<EdgeIndex>) -> Chunks<'b, EdgeIndex> {
    if self.options.use_batch {
      edges.chunks(self.options.batch_size as usize)
    } else {
      edges.chunks(edges.len())
    }
  }

  pub fn find_entries(&self, edge_id: EdgeIndex) -> Vec<NodeIndex> {
    let entry_location_filter = match &self.options.entry_filter {
      Some(filter) => Some(
        Regex::new(filter.as_str())
          .map_err(|_| String::from("Cannot parse entry filter regex"))
          .unwrap(),
      ),
      None => None,
    };
    let mut result = HashSet::new();
    match self.call_graph.edge_endpoints(edge_id) {
      Some((func_id, _)) => {
        let mut fringe = Vec::new();
        fringe.push((func_id, self.options.depth));
        while !fringe.is_empty() {
          let (func_id, depth) = fringe.pop().unwrap();
          if depth == 0 {
            result.insert(func_id);
          } else {
            let mut contains_parent = false;
            for caller_id in self.call_graph.neighbors_directed(func_id, Direction::Incoming) {
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
          let func = self.call_graph.node_weight(*func_id).unwrap();
          match func.filename() {
            Some(name) => regex.is_match(name.as_str()),
            _ => true,
          }
        }
        None => true,
      })
      .collect()
  }

  pub fn _directly_related(&self, _c1: CallInstruction<'ctx>, _c2: CallInstruction<'ctx>) -> bool {
    // TODO
    // let share_prefix = {
    //   let (c1_name, c2_name) = (f1.function_name(), f2.function_name());
    //   let common_len = c1_name.len().min(c2_name.len());
    //   if common_len == 0 {
    //     false
    //   } else {
    //     c1_name.chars().nth(0) == c2_name.chars().nth(0)
    //   }
    // };
    true
  }

  pub fn reduce(
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

  pub fn slice_of_entry(&self, entry_id: NodeIndex, edge_id: EdgeIndex) -> Slice<'ctx> {
    // Get basic informations
    let entry = self.call_graph[entry_id];
    let instr = self.call_graph[edge_id];
    let (caller, callee_id, callee) = {
      let (caller_id, callee_id) = self.call_graph.edge_endpoints(edge_id).unwrap();
      (self.call_graph[caller_id], callee_id, self.call_graph[callee_id])
    };

    // Get included functions
    let mut fringe = vec![(entry_id, self.options.depth * 2)];
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
          for callee_id in self.call_graph.neighbors_directed(func_id, Direction::Outgoing) {
            if !visited.contains(&callee_id) {
              fringe.push((callee_id, depth - 1));
            }
          }
        }
      }
    }

    // Reduced function boundary
    let function_ids = if self.options.reduce_slice {
      self.reduce(entry_id, callee_id, function_ids)
    } else {
      function_ids
    };

    // Generate slice
    let functions = function_ids.iter().map(|func_id| self.call_graph[*func_id]).collect();
    Slice {
      caller,
      callee,
      instr,
      entry,
      functions,
    }
  }

  pub fn slices_of_call_edge(&self, edge_id: EdgeIndex) -> Vec<Slice<'ctx>> {
    let entry_ids = self.find_entries(edge_id);
    entry_ids
      .iter()
      .map(|entry_id| self.slice_of_entry(*entry_id, edge_id))
      .collect()
  }

  pub fn slices_of_call_edges(&self, edges: &[EdgeIndex]) -> Vec<Slice<'ctx>> {
    let f = |edge_id: &EdgeIndex| -> Vec<Slice<'ctx>> { self.slices_of_call_edge(edge_id.clone()) };
    if self.ctx.options.use_serial {
      edges.iter().map(f).flatten().collect()
    } else {
      edges.par_iter().map(f).flatten().collect()
    }
  }
}
