use std::collections::HashMap;

use analyzer::utils::*;

#[test]
fn test_only_batch() {
  let mut map = HashMap::new();
  for i in 0..10 {
    map.insert(i, (0..i).collect());
  }
  assert_eq!(map.num_elements(), 45, "Map should contain 45 elements");

  let mut iter_count = 0;
  for (i, batch) in map.batches(false, 10000) {
    iter_count += 1;
  }
  assert_eq!(iter_count, 1, "Only one batch should be generated");
}

#[test]
fn test_many_batches() {
  let mut map = HashMap::new();
  for i in 0..10 {
    map.insert(i, (0..i).collect());
  }
  assert_eq!(map.num_elements(), 45, "Map should contain 45 elements");

  let mut iter_count = 0;
  for (i, batch) in map.batches(true, 5) {
    // println!("{:?}", batch);
    assert_eq!(batch.num_elements(), 5, "Each batch should contain 5 elements");
    iter_count += 1;
  }
  assert_eq!(iter_count, 9, "9 batches should be generated");
}

#[test]
fn test_lots_of_batches() {
  let mut map = HashMap::new();
  let mut sum = 0;
  for i in 0..1000 {
    sum += i;
    map.insert(i, (0..i).collect());
  }
  assert_eq!(map.num_elements(), sum, "Map should contain {} elements", sum);

  let batch_size = 500;
  let num_batches = sum / batch_size;
  let mut iter_count = 0;
  for (i, batch) in map.batches(true, batch_size) {
    // println!("{:?}", batch);
    assert_eq!(batch.num_elements(), batch_size, "Each batch should contain {} elements", batch_size);
    iter_count += 1;
  }
  assert_eq!(iter_count, num_batches, "{} batches should be generated", num_batches);
}