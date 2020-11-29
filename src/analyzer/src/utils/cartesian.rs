pub fn cartesian(v: &Vec<usize>) -> Vec<Vec<usize>> {
  if v.len() == 0 {
    vec![]
  } else if v.len() == 1 {
    (0..v[0]).map(|i| vec![i]).collect()
  } else if v.len() == 2 {
    let mut r = Vec::with_capacity(v[0] * v[1]);
    for i in 0..v[0] {
      for j in 0..v[1] {
        r.push(vec![i, j]);
      }
    }
    r
  } else if v.len() == 3 {
    let mut r = Vec::with_capacity(v[0] * v[1] * v[2]);
    for i in 0..v[0] {
      for j in 0..v[1] {
        for k in 0..v[2] {
          r.push(vec![i, j, k]);
        }
      }
    }
    r
  } else if v.len() == 4 {
    let mut r = Vec::with_capacity(v[0] * v[1] * v[2] * v[3]);
    for i in 0..v[0] {
      for j in 0..v[1] {
        for k in 0..v[2] {
          for l in 0..v[3] {
            r.push(vec![i, j, k, l]);
          }
        }
      }
    }
    r
  } else {
    cartesian_array(&v.iter().map(|i| (0..*i).collect()).collect::<Vec<_>>())
  }
}

pub fn cartesian_array<T: Copy + Clone>(v: &Vec<Vec<T>>) -> Vec<Vec<T>> {
  if v.len() == 0 {
    vec![]
  } else if v.len() == 1 {
    v.clone()
  } else {
    let mut curr_prod = cartesian_two(&singleton(&v[0]), &singleton(&v[1]));
    for i in 2..v.len() {
      curr_prod = cartesian_two(&curr_prod, &singleton(&v[i]));
    }
    curr_prod
  }
}

pub fn singleton<T: Copy + Clone>(v: &Vec<T>) -> Vec<Vec<T>> {
  v.iter().map(|i| vec![i.clone()]).collect()
}

pub fn cartesian_two<T: Copy + Clone>(l1: &Vec<Vec<T>>, l2: &Vec<Vec<T>>) -> Vec<Vec<T>> {
  let mut res = Vec::with_capacity(l1.len() * l2.len());
  for v1 in l1 {
    for v2 in l2 {
      res.push(vec![v1.clone(), v2.clone()].concat());
    }
  }
  res
}
