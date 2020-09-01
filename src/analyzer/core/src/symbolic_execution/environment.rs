use llir::values::*;
use rand::{rngs::StdRng, Rng, SeedableRng};

use crate::slicer::*;
use crate::symbolic_execution::*;
use crate::utils::*;

pub struct Environment<'ctx> {
  pub slice: Slice<'ctx>,
  pub work_list: Vec<Work<'ctx>>,
  pub block_traces: Vec<Vec<Block<'ctx>>>,
  pub call_id: usize,
  pub max_work: usize,
  pub rng: StdRng,
}

impl<'ctx> Environment<'ctx> {
  pub fn new(slice: &Slice<'ctx>, max_work: usize, seed: u8) -> Self {
    Self {
      slice: slice.clone(),
      work_list: vec![],
      block_traces: vec![],
      call_id: 0,
      max_work: max_work,
      rng: StdRng::from_seed([seed; 32]),
    }
  }

  pub fn num_works(&self) -> usize {
    self.work_list.len()
  }

  pub fn has_work(&self) -> bool {
    !self.work_list.is_empty()
  }

  pub fn pop_work(&mut self, random: bool) -> Work<'ctx> {
    if random {
      let idx = self.rng.gen_range(0, self.work_list.len());
      let last_idx = self.work_list.len() - 1;
      self.work_list.swap(idx, last_idx);
    }
    self.work_list.pop().unwrap()
  }

  pub fn can_add_work(&self) -> bool {
    self.work_list.len() < self.max_work
  }

  pub fn add_work(&mut self, work: Work<'ctx>) -> bool {
    if self.work_list.len() >= self.max_work {
      false
    } else {
      self.work_list.push(work);
      true
    }
  }

  pub fn new_call_id(&mut self) -> usize {
    let result = self.call_id;
    self.call_id += 1;
    result
  }

  pub fn add_block_trace(&mut self, block_trace: Vec<Block<'ctx>>) {
    self.block_traces.push(block_trace)
  }

  pub fn has_duplicate(&self, block_trace: &Vec<Block<'ctx>>) -> bool {
    for other_block_trace in self.block_traces.iter() {
      if block_trace.equals(other_block_trace) {
        return true;
      }
    }
    false
  }
}
