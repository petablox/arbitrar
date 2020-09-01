//! Generate Batches for a HashMap<A, Vec<B>>, producing offset map HashMap<A, (usize, Vec<B>)>
//!
//! ```
//! for (i, batch) in map.batches(true, 3) {
//!   // Do things to batch
//! }
//! ```

use std::collections::{HashMap, HashSet};
use std::hash::Hash;

pub type BatchableMap<A, B> = HashMap<A, Vec<B>>;

pub type OffsetBatchableMap<A, B> = HashMap<A, (usize, Vec<B>)>;

pub trait SizedBatchableMap<A> {
  fn num_elements(&self) -> usize;

  fn keyed_num_elements(&self) -> HashMap<A, usize>;
}

impl<A, B> SizedBatchableMap<A> for BatchableMap<A, B>
where
  A: Clone + Hash + Eq,
{
  fn num_elements(&self) -> usize {
    let mut sum = 0;
    for value in self.values() {
      sum += value.len();
    }
    sum
  }

  fn keyed_num_elements(&self) -> HashMap<A, usize> {
    let mut result = HashMap::new();
    for (key, value) in self {
      result.insert(key.clone(), value.len());
    }
    result
  }
}

impl<A, B> SizedBatchableMap<A> for OffsetBatchableMap<A, B>
where
  A: Clone + Hash + Eq,
{
  fn num_elements(&self) -> usize {
    let mut sum = 0;
    for (_, value) in self.values() {
      sum += value.len();
    }
    sum
  }

  fn keyed_num_elements(&self) -> HashMap<A, usize> {
    let mut result = HashMap::new();
    for (key, (_, value)) in self {
      result.insert(key.clone(), value.len());
    }
    result
  }
}

pub struct BatchedMapIterator<A, B> {
  pub base: BatchableMap<A, B>,
  pub offsets: HashMap<A, usize>,
  pub finished: HashSet<A>,
  pub batch_size: usize,
  pub only_one: bool,
  pub index: usize,
}

impl<A, B> Iterator for BatchedMapIterator<A, B>
where
  A: Clone + Hash + Eq,
  B: Clone,
{
  type Item = (usize, OffsetBatchableMap<A, B>);

  fn next(&mut self) -> Option<Self::Item> {
    if self.only_one {
      if self.index > 0 {
        None
      } else {
        let batch_id = self.index;
        self.index += 1;
        let mut map = HashMap::new();
        for (target, edges) in self.base.iter() {
          map.insert(target.clone(), (0, edges.clone()));
        }
        Some((batch_id, map))
      }
    } else {
      let mut map = HashMap::new();
      let mut count = 0;
      for (target, edges) in self.base.iter() {
        if count >= self.batch_size {
          break;
        } else if self.finished.contains(target) {
          continue;
        } else {
          let offset = self.offsets.entry(target.clone()).or_insert(0);
          let original_offset = offset.clone();
          let num_edges = edges.len() - original_offset;
          if num_edges == 0 {
            continue;
          } else {
            let amount_to_insert = num_edges.min(self.batch_size - count);
            count += amount_to_insert;
            *offset += amount_to_insert;
            let current_offset = offset.clone();
            let slice = &edges[original_offset..current_offset];
            map.insert(target.clone(), (original_offset, slice.iter().cloned().collect()));
            if current_offset >= edges.len() {
              self.finished.insert(target.clone());
            }
          }
        }
      }
      if map.num_elements() == 0 {
        None
      } else {
        let batch_id = self.index;
        self.index += 1;
        Some((batch_id, map))
      }
    }
  }
}

pub trait Batching<A, B> {
  fn batches(self, use_batch: bool, batch_size: usize) -> BatchedMapIterator<A, B>;
}

impl<A, B> Batching<A, B> for BatchableMap<A, B> {
  fn batches(self, use_batch: bool, batch_size: usize) -> BatchedMapIterator<A, B> {
    BatchedMapIterator {
      base: self,
      offsets: HashMap::new(),
      finished: HashSet::new(),
      batch_size: batch_size,
      only_one: !use_batch,
      index: 0,
    }
  }
}
