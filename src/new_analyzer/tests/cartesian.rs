use analyzer::utils::*;

#[test]
fn test_cartesian_1() {
  let result = cartesian(&vec![]);
  assert_eq!(result, vec![]);
}

#[test]
fn test_cartesian_2() {
  let result = cartesian(&vec![1]);
  assert_eq!(result, vec![0]);
}