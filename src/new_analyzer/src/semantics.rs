use std::rc::Rc;
use std::collections::HashMap;
// use serde_json::Value as Json;

// #[derive(Debug, Clone)]
// pub enum Type {
//   Void,
//   Half,
//   Float,
//   Double,
//   Integer,
//   Function { args: Vec<Type>, ret: Box<Type> },
//   NamedStruct(String),
//   Struct { fields: Vec<Type> },
//   Array { len: usize, ty: Box<Type> },
//   Pointer(Box<Type>),
//   Vector { len: usize, ty: Box<Type> },
//   Other,
// }

// #[derive(Debug, Clone)]
// pub struct FunctionType {
//   args: Vec<Type>,
//   ret: Box<Type>,
// }

// impl FunctionType {
//   pub fn from_type(ty: Type) -> Option<Self> {
//     match ty {
//       Type::Function { args, ret } => Some(Self { args, ret }),
//       _ => None,
//     }
//   }
// }

pub type UnaOp = inkwell::values::InstructionOpcode;

pub type BinOp = inkwell::values::InstructionOpcode;

pub type Predicate = inkwell::IntPredicate;

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum Value {
  Argument(usize), // Argument ID
  Symbol(usize), // Symbol ID
  ConstPtr(usize), // Pointer ID
  Global(String), // Global Value Name
  FunctionPointer(String), // Function Name
  ConstInt(i64),
  NullPtr,
  Location(Rc<Location>),
  BinaryOperation {
    op: BinOp,
    op0: Rc<Value>,
    op1: Rc<Value>,
  },
  Comparison {
    pred: Predicate,
    op0: Rc<Value>,
    op1: Rc<Value>,
  },
  Call {
    id: usize,
    func: String,
    args: Vec<Rc<Value>>,
  },
  Unknown,
}

impl Value {
  pub fn as_comparison(&self) -> Option<Comparison> {
    match self {
      Value::Comparison { pred, op0, op1 } => {
        Some(Comparison { pred: *pred, op0: op0.clone(), op1: op1.clone() })
      },
      _ => None
    }
  }

  pub fn into_z3_ast<'ctx>(
    &self,
    symbol_map: &mut HashMap<Value, z3::Symbol>,
    symbol_id: &mut u32,
    z3_ctx: &'ctx z3::Context
  ) -> Option<z3::ast::Int<'ctx>> {
    use z3::*;
    match self {
      Value::ConstInt(i) => Some(ast::Int::from_i64(z3_ctx, *i)),
      Value::NullPtr => Some(ast::Int::from_i64(z3_ctx, 0)),
      Value::BinaryOperation { op, op0, op1 } => {
        match (
          op0.into_z3_ast(symbol_map, symbol_id, z3_ctx),
          op1.into_z3_ast(symbol_map, symbol_id, z3_ctx)
        ) {
          (Some(op0), Some(op1)) => match op {
            BinOp::Add => Some(ast::Int::add(z3_ctx, &[&op0, &op1])),
            BinOp::Sub => Some(ast::Int::sub(z3_ctx, &[&op0, &op1])),
            BinOp::Mul => Some(ast::Int::mul(z3_ctx, &[&op0, &op1])),
            BinOp::UDiv | BinOp::SDiv => Some(op0.div(&op1)),
            BinOp::URem | BinOp::SRem => Some(op0.rem(&op1)),
            _ => None
          },
          _ => None
        }
      },
      Value::Unknown => None,
      _ => {
        let symbol = symbol_map.entry(self.clone()).or_insert_with(|| {
          let result = *symbol_id;
          *symbol_id += 1;
          Symbol::Int(result)
        });
        Some(ast::Int::new_const(z3_ctx, symbol.clone()))
      }
    }
  }
}

#[derive(Debug, Clone)]
pub struct Comparison {
  pred: Predicate,
  op0: Rc<Value>,
  op1: Rc<Value>,
}

impl Comparison {
  pub fn into_z3_ast<'ctx>(
    &self,
    symbol_map: &mut HashMap<Value, z3::Symbol>,
    symbol_id: &mut u32,
    z3_ctx: &'ctx z3::Context
  ) -> Option<z3::ast::Bool<'ctx>> {
    use z3::ast::Ast;
    let Comparison { pred, op0, op1 } = self;
    let z3_op0 = op0.into_z3_ast(symbol_map, symbol_id, z3_ctx);
    let z3_op1 = op1.into_z3_ast(symbol_map, symbol_id, z3_ctx);
    match (z3_op0, z3_op1) {
      (Some(op0), Some(op1)) => match pred {
        Predicate::EQ => Some(op0._eq(&op1)),
        Predicate::NE => Some(op0._eq(&op1).not()),
        Predicate::SGE | Predicate::UGE => Some(op0.ge(&op1)),
        Predicate::SGT | Predicate::UGT => Some(op0.gt(&op1)),
        Predicate::SLE | Predicate::ULE => Some(op0.le(&op1)),
        Predicate::SLT | Predicate::ULT => Some(op0.lt(&op1)),
      }
      _ => None
    }
  }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum Location {
  // Argument(usize),
  Alloca(usize),
  Global(String),
  GetElementPtr(Rc<Location>, Vec<Rc<Value>>),
  ConstPtr(usize),
  Value(Rc<Value>),
  Unknown,
}

#[derive(Debug, Clone)]
pub enum Branch {
  Then,
  Else,
}

#[derive(Debug, Clone)]
pub enum Instruction {
  Call {
    func: String,
    /* func_type: FunctionType, */ args: Vec<Rc<Value>>, /* arg_types: Vec<Type> */
  },
  Assume {
    pred: Predicate,
    op0: Rc<Value>,
    op1: Rc<Value>,
  },
  ConditionalBr {
    cond: Rc<Value>,
    br: Branch,
  },
  UnconditionalBr {
    is_loop: bool,
  },
  Switch {
    cond: Rc<Value>,
  },
  Return(Option<Rc<Value>>),
  Store {
    loc: Rc<Location>,
    val: Rc<Value>,
  },
  Load {
    loc: Rc<Location>,
  },
  GetElementPtr {
    loc: Rc<Location>,
    indices: Vec<Rc<Value>>,
  },
  UnaryOperation {
    op: UnaOp,
    op0: Rc<Value>,
  },
  BinaryOperation {
    op: BinOp,
    op0: Rc<Value>,
    op1: Rc<Value>,
  },
}
