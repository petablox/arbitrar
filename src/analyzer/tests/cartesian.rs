use analyzer::utils::*;

#[test]
fn test_cartesian_1() {
  let result = cartesian(&vec![]);
  println!("{:?}", result);
  // assert_eq!(result, Vec::new::<Vec<_>>());
}

#[test]
fn test_cartesian_2() {
  let result = cartesian(&vec![1]);
  println!("{:?}", result);
  // assert_eq!(result, vec![vec![0]]);
}

#[test]
fn test_cartesian_3() {
  let result = cartesian(&vec![3]);
  println!("{:?}", result);
  // assert_eq!(result, vec![vec![0]]);
}