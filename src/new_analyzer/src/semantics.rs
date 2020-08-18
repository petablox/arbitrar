use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::rc::Rc;
// use serde_json::Value as Json;

pub type UnaOp = llir::values::UnaryOpcode;

#[derive(Debug, Copy, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(remote = "llir::values::UnaryOpcode")]
pub enum UnaryOpcodeDef {
  FNeg,
  Trunc,
  ZExt,
  SExt,
  FPToUI,
  FPToSI,
  UIToFP,
  SIToFP,
  FPTrunc,
  FPExt,
  PtrToInt,
  IntToPtr,
  BitCast,
}

pub type BinOp = llir::values::BinaryOpcode;

#[derive(Debug, Copy, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(remote = "llir::values::BinaryOpcode")]
enum BinaryOpcodeDef {
  // Arithmatics
  Add,
  Sub,
  Mul,
  UDiv,
  SDiv,
  URem,
  SRem,
  // Floating point
  FAdd,
  FSub,
  FMul,
  FDiv,
  FRem,
  // Bitwise operation
  Shl,
  LShr,
  AShr,
  And,
  Or,
  Xor,
}

pub type Predicate = llir::values::ICmpPredicate;

#[derive(Debug, Copy, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(remote = "llir::values::ICmpPredicate")]
pub enum PredicateDef {
  EQ,
  NE,
  SGE,
  UGE,
  SGT,
  UGT,
  SLE,
  ULE,
  SLT,
  ULT,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Value {
  Arg(usize),   // Argument ID
  Sym(usize),   // Symbol ID
  Glob(String), // Global Value Name
  Func(String), // Function Name
  FuncPtr,
  Asm,
  Int(i64),
  Null,
  Alloca(usize),
  GEP {
    loc: Rc<Value>,
    indices: Vec<Rc<Value>>,
  },
  Bin {
    #[serde(with = "BinaryOpcodeDef")]
    op: BinOp,
    op0: Rc<Value>,
    op1: Rc<Value>,
  },
  ICmp {
    #[serde(with = "PredicateDef")]
    pred: Predicate,
    op0: Rc<Value>,
    op1: Rc<Value>,
  },
  Call {
    id: usize,
    func: Rc<Value>,
    args: Vec<Rc<Value>>,
  },
  Unknown,
}

impl Value {
  pub fn as_comparison(&self) -> Option<Comparison> {
    match self {
      Value::ICmp { pred, op0, op1 } => Some(Comparison {
        pred: *pred,
        op0: op0.clone(),
        op1: op1.clone(),
      }),
      _ => None,
    }
  }

  pub fn into_z3_ast<'ctx>(
    &self,
    symbol_map: &mut HashMap<Value, z3::Symbol>,
    symbol_id: &mut u32,
    z3_ctx: &'ctx z3::Context,
  ) -> Option<z3::ast::Int<'ctx>> {
    use z3::*;
    match self {
      Value::Int(i) => Some(ast::Int::from_i64(z3_ctx, *i)),
      Value::Null => Some(ast::Int::from_i64(z3_ctx, 0)),
      Value::Bin { op, op0, op1 } => {
        match (
          op0.into_z3_ast(symbol_map, symbol_id, z3_ctx),
          op1.into_z3_ast(symbol_map, symbol_id, z3_ctx),
        ) {
          (Some(op0), Some(op1)) => match op {
            BinOp::Add => Some(ast::Int::add(z3_ctx, &[&op0, &op1])),
            BinOp::Sub => Some(ast::Int::sub(z3_ctx, &[&op0, &op1])),
            BinOp::Mul => Some(ast::Int::mul(z3_ctx, &[&op0, &op1])),
            BinOp::UDiv | BinOp::SDiv => Some(op0.div(&op1)),
            BinOp::URem | BinOp::SRem => Some(op0.rem(&op1)),
            _ => None,
          },
          _ => None,
        }
      }
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
    z3_ctx: &'ctx z3::Context,
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
      },
      _ => None,
    }
  }
}

// #[derive(Debug, Clone, PartialEq, Eq, Hash)]
// pub enum Location {
//   // Argument(usize),
//   Alloca(usize),
//   GetElementPtr(Rc<Location>, Vec<Rc<Value>>),
//   ConstPtr(usize), // Pointer ID
//   Global(String),
//   Value(Rc<Value>),
//   NullPtr,
//   Unknown,
// }

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum Branch {
  Then,
  Else,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum Semantics {
  Call {
    func: Rc<Value>,
    args: Vec<Rc<Value>>,
  },
  ICmp {
    #[serde(with = "PredicateDef")]
    pred: Predicate,
    op0: Rc<Value>,
    op1: Rc<Value>,
  },
  CondBr {
    cond: Rc<Value>,
    br: Branch,
    beg_loop: bool,
  },
  UncondBr {
    end_loop: bool,
  },
  Switch {
    cond: Rc<Value>,
  },
  Ret {
    op: Option<Rc<Value>>,
  },
  Store {
    loc: Rc<Value>,
    val: Rc<Value>,
  },
  Load {
    loc: Rc<Value>,
  },
  GEP {
    loc: Rc<Value>,
    indices: Vec<Rc<Value>>,
  },
  Una {
    #[serde(with = "UnaryOpcodeDef")]
    op: UnaOp,
    op0: Rc<Value>,
  },
  Bin {
    #[serde(with = "BinaryOpcodeDef")]
    op: BinOp,
    op0: Rc<Value>,
    op1: Rc<Value>,
  },
}
