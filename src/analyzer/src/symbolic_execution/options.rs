use crate::options::*;

pub trait SymbolicExecutionOptions: GeneralOptions + IOOptions + Send + Sync {
  fn slice_depth(&self) -> usize;

  fn max_work(&self) -> usize;

  fn no_random_work(&self) -> bool;

  fn max_node_per_trace(&self) -> usize;

  fn max_explored_trace_per_slice(&self) -> usize;

  fn max_trace_per_slice(&self) -> usize;

  fn no_trace_reduction(&self) -> bool;

  fn no_prefilter_block_trace(&self) -> bool;

  fn print_block_trace(&self) -> bool;

  fn print_trace(&self) -> bool;
}
