use llir::{types::*, values::*, *};
use std::collections::HashMap;

pub trait FunctionNameUtil {
  fn simp_name(&self) -> String;
}

impl<'ctx> FunctionNameUtil for Function<'ctx> {
  fn simp_name(&self) -> String {
    let name = self.name();
    match name.find('.') {
      Some(i) => name[..i].to_string(),
      None => name,
    }
  }
}

pub trait FunctionTypesTrait<'ctx> {
  fn function_types(&self) -> HashMap<String, FunctionType<'ctx>>;
}

impl<'ctx> FunctionTypesTrait<'ctx> for Module<'ctx> {
  fn function_types(&self) -> HashMap<String, FunctionType<'ctx>> {
    let mut result = HashMap::new();
    for func in self.iter_functions() {
      result
        .entry(func.simp_name())
        .or_insert_with(|| func.get_function_type());
    }
    result
  }
}
