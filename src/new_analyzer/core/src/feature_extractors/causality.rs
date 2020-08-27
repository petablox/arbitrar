use std::collections::{HashMap, BinaryHeap};
use llir::types::*;
use serde::Serialize;
use crate::semantics::boxed::*;

use crate::feature_extraction::*;

pub struct CausalityFeatureExtractor {
  pub forward: bool,
  pub dictionary_size: usize,
  pub dictionary: HashMap<String, f32>,
  pub most_occurred: Vec<String>,
}

impl CausalityFeatureExtractor {
  pub fn post(size: usize) -> Self {
    Self { forward: true, dictionary_size: size, dictionary: HashMap::new(), most_occurred: vec![] }
  }

  pub fn pre(size: usize) -> Self {
    Self { forward: false, dictionary_size: size, dictionary: HashMap::new(), most_occurred: vec![] }
  }
}

impl FeatureExtractor for CausalityFeatureExtractor {
  fn name(&self) -> String {
    if self.forward {
      format!("post")
    } else {
      format!("pre")
    }
  }

  fn filter<'ctx>(&self, _: &String, _: FunctionType<'ctx>) -> bool { true }

  fn init(&mut self, _: &Slice, num_traces: usize, trace: &Trace) {
    let funcs = find_caused_functions(trace, self.forward);
    for (func, count) in funcs {
      *self.dictionary.entry(func).or_insert(0.0) += count as f32 / num_traces as f32;
    }
  }

  fn finalize(&mut self) {
    self.most_occurred = find_mostly_used_functions(&self.dictionary, self.dictionary_size);
  }

  fn extract(&self, _: &Slice, trace: &Trace) -> serde_json::Value {
    let causalities = find_function_causality(trace, self.forward, &self.most_occurred);
    let mut map = serde_json::Map::new();
    for (func, causality_features) in self.most_occurred.iter().zip(causalities) {
      map[func] = serde_json::to_value(causality_features).expect("Cannot turn causality features into json");
    }
    serde_json::Value::Object(map)
  }
}

fn find_mostly_used_functions(map: &HashMap<String, f32>, k: usize) -> Vec<String> {
  struct SortItem<'a>(&'a String, f32);

  impl<'a> PartialEq for SortItem<'a> {
    fn eq(&self, other: &Self) -> bool {
      self.0 == other.0
    }
  }

  impl<'a> Eq for SortItem<'a> {}

  impl<'a> PartialOrd for SortItem<'a> {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
      self.1.partial_cmp(&other.1)
    }
  }

  impl<'a> Ord for SortItem<'a> {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
      self.1.partial_cmp(&other.1).unwrap()
    }
  }

  let mut heap = BinaryHeap::new();
  for (name, used) in map {
    heap.push(SortItem(name, used.clone()));
  }
  heap.iter().take(k).map(|si| si.0.clone()).collect()
}

fn iter_instrs(trace: &Trace, forward: bool) -> Vec<&Instr> {
  if forward { trace.instrs.iter().skip(trace.target).collect::<Vec<_>>() } else {
    trace.instrs.iter().skip(trace.instrs.len() - trace.target).rev().collect::<Vec<_>>()
  }
}

fn find_caused_functions(trace: &Trace, forward: bool) -> HashMap<String, usize> {
  let mut result = HashMap::new();
  for instr in iter_instrs(trace, forward) {
    match &instr.sem {
      Semantics::Call { func, .. } => {
        match &**func {
          Value::Func(f) => {
            *result.entry(f.clone()).or_insert(0) += 1;
          }
          _ => {}
        }
      }
      _ => {}
    }
  }
  result
}

#[derive(Clone, Serialize)]
struct FunctionCausalityFeatures {
  pub invoked: bool,
}

impl Default for  FunctionCausalityFeatures {
  fn default() -> Self {
    Self {
      invoked: false,
    }
  }
}

fn find_function_causality(trace: &Trace, forward: bool, funcs: &Vec<String>) -> Vec<FunctionCausalityFeatures> {
  let mut result = vec![FunctionCausalityFeatures::default(); funcs.len()];
  // let target_instr = &trace.instrs[trace.target];
  for instr in iter_instrs(trace, forward) {
    match &instr.sem {
      Semantics::Call { func, .. } => {
        match &**func {
          Value::Func(func_name) => {
            match funcs.iter().position(|f| f == func_name) {
              Some(id) => {
                let features = &mut result[id];
                features.invoked = true;
              }
              _ => {}
            }
          }
          _ => {}
        }
      }
      _ => {}
    }
  }
  result
}
