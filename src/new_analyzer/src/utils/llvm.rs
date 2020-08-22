use llir::values::*;

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