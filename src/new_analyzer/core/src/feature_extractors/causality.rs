use llir::types::*;
use serde::Serialize;
use std::collections::{BinaryHeap, HashMap};

use crate::feature_extraction::*;
use crate::semantics::boxed::*;

pub struct CausalityFeatureExtractor {
  pub direction: TraceIterDirection,
  pub dictionary_size: usize,
  pub dictionary: HashMap<String, f32>,
  pub most_occurred: Vec<String>,
}

impl CausalityFeatureExtractor {
  pub fn post(size: usize) -> Self {
    Self {
      direction: TraceIterDirection::Forward,
      dictionary_size: size,
      dictionary: HashMap::new(),
      most_occurred: vec![],
    }
  }

  pub fn pre(size: usize) -> Self {
    Self {
      direction: TraceIterDirection::Backward,
      dictionary_size: size,
      dictionary: HashMap::new(),
      most_occurred: vec![],
    }
  }
}

impl FeatureExtractor for CausalityFeatureExtractor {
  fn name(&self) -> String {
    if self.direction.is_forward() {
      format!("after")
    } else {
      format!("before")
    }
  }

  fn filter<'ctx>(&self, _: &String, _: FunctionType<'ctx>) -> bool {
    true
  }

  fn init(&mut self, _: &Slice, num_traces: usize, trace: &Trace) {
    let funcs = find_caused_functions(trace, self.direction);
    for (func, count) in funcs {
      *self.dictionary.entry(func).or_insert(0.0) += count as f32 / num_traces as f32;
    }
  }

  fn finalize(&mut self) {
    self.most_occurred = find_mostly_used_functions(&self.dictionary, self.dictionary_size);
  }

  fn extract(&self, _: &Slice, trace: &Trace) -> serde_json::Value {
    let causalities = find_function_causality(trace, self.direction, &self.most_occurred);
    let mut map = serde_json::Map::new();
    for (func, causality_features) in self.most_occurred.iter().zip(causalities) {
      map.insert(
        func.clone(),
        serde_json::to_value(causality_features).expect("Cannot turn causality features into json"),
      );
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

fn find_caused_functions(trace: &Trace, dir: TraceIterDirection) -> HashMap<String, usize> {
  let mut result = HashMap::new();
  for instr in trace.iter_instrs(dir) {
    match &instr.sem {
      Semantics::Call { func, .. } => match &**func {
        Value::Func(f) => {
          *result.entry(f.clone()).or_insert(0) += 1;
        }
        _ => {}
      },
      _ => {}
    }
  }
  result
}

#[derive(Clone, Serialize)]
struct FunctionCausalityFeatures {
  pub invoked: bool,

  /// Function is invoked more than once before/after the target
  ///
  /// ```
  /// target(...);
  /// f(...);
  /// f(...);
  /// ```
  pub invoked_more_than_once: bool,

  /// Share return value
  ///
  /// Example 1:
  ///
  /// If `f` is a function called before target,
  ///
  /// ```
  /// a = f(...);
  /// target(..., a, ...);
  /// ```
  ///
  /// Example 2:
  ///
  /// ```
  /// r = target(...);
  /// f(r, ...);
  /// ```
  pub share_return_value: bool,

  /// Share argument value
  pub share_argument_value: bool,
}

impl Default for FunctionCausalityFeatures {
  fn default() -> Self {
    Self {
      invoked: false,
      invoked_more_than_once: false,
      share_return_value: false,
      share_argument_value: false,
    }
  }
}

fn find_function_causality(
  trace: &Trace,
  dir: TraceIterDirection,
  funcs: &Vec<String>,
) -> Vec<FunctionCausalityFeatures> {
  let mut result = vec![FunctionCausalityFeatures::default(); funcs.len()];
  let target_instr = &trace.instrs[trace.target];
  for instr in trace.iter_instrs_from_target(dir) {
    match &instr.sem {
      Semantics::Call { func, .. } => {
        match &**func {
          Value::Func(func_name) => {
            match funcs.iter().position(|f| f == func_name) {
              Some(id) => {
                let features = &mut result[id];

                // Update invoked more than once
                if features.invoked {
                  features.invoked_more_than_once = true;
                }

                // Check if sharing return value
                if !features.share_return_value {
                  let retval = if dir.is_forward() {
                    (target_instr.res.clone(), instr.sem.call_args())
                  } else {
                    (instr.res.clone(), target_instr.sem.call_args())
                  };
                  if let (Some(retval), args) = retval {
                    if args.iter().find(|a| ***a == retval).is_some() {
                      features.share_return_value = true;
                    }
                  }
                }

                // Check if sharing argument value
                if !features.share_argument_value {
                  let args_1 = instr.sem.call_args();
                  let args_2 = target_instr.sem.call_args();
                  if args_1
                    .iter()
                    .find(|a| args_2.iter().find(|b| a == b).is_some())
                    .is_some()
                  {
                    features.share_argument_value = true;
                  }
                }

                // Invoked
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
