use llir::{types::*, values::*, *};
use std::collections::{HashMap, HashSet};

pub trait CallInstrUtil<'ctx> {
  fn is_dummy_intrinsic_call(&self) -> bool;
}

impl<'ctx> CallInstrUtil<'ctx> for CallInstruction<'ctx> {
  fn is_dummy_intrinsic_call(&self) -> bool {
    if self.is_intrinsic_call() {
      let callee_function = self.callee_function();
      match callee_function {
        Some(function) => {
          if function.name().contains("memset") {
            false
          } else {
            true
          }
        }
        None => true
      }
    } else {
      false
    }
  }
}

pub trait FunctionTypeUtil<'ctx> {
  fn used_types(&self) -> Vec<Type<'ctx>>;
}

impl<'ctx> FunctionTypeUtil<'ctx> for FunctionType<'ctx> {
  fn used_types(&self) -> Vec<Type<'ctx>> {
    vec![vec![self.return_type()], self.argument_types()].concat()
  }
}

pub trait FunctionUtil<'ctx> {
  fn simp_name(&self) -> String;

  fn used_types(&self) -> Vec<Type<'ctx>>;

  fn used_struct_names(&self) -> HashSet<String>;
}

impl<'ctx> FunctionUtil<'ctx> for Function<'ctx> {
  fn simp_name(&self) -> String {
    let name = self.name();
    match name.find('.') {
      Some(i) => {
        if &name[..i] == "llvm" {
          match name.chars().skip(i + 2).position(|c| c == '.') {
            Some(j) => name[i + 1..i + 2 + j].to_string(),
            None => name[i + 1..].to_string(),
          }
        } else {
          name[..i].to_string()
        }
      },
      None => name,
    }
  }

  fn used_types(&self) -> Vec<Type<'ctx>> {
    let func_type = self.get_function_type();
    func_type.used_types()
  }

  fn used_struct_names(&self) -> HashSet<String> {
    let mut types = self.used_types();
    let mut struct_names = HashSet::new();
    while !types.is_empty() {
      let t = types.pop().unwrap();
      match t {
        Type::Function(ft) => {
          for t in ft.used_types() {
            types.push(t);
          }
        }
        Type::Struct(StructType::NamedStruct(ns)) => {
          struct_names.insert(ns.name());
        }
        Type::Array(a) => {
          types.push(a.element_type());
        }
        Type::Pointer(p) => {
          types.push(p.element_type());
        }
        Type::Vector(v) => {
          types.push(v.element_type());
        }
        _ => {}
      }
    }
    struct_names
  }
}

pub trait BlockTraceComparison {
  fn equals(&self, other: &Self) -> bool;
}

impl<'ctx> BlockTraceComparison for Vec<Block<'ctx>> {
  fn equals(&self, other: &Self) -> bool {
    if self.len() != other.len() {
      false
    } else {
      for i in 0..self.len() {
        if self[i] != other[i] {
          return false;
        }
      }
      true
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
