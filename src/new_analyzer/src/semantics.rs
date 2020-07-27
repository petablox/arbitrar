use serde_json::Value as Json;

#[derive(Clone)]
pub enum Type {
  Void,
  Half,
  Float,
  Double,
  Integer,
  Function { args: Vec<Type>, ret: Box<Type> },
  NamedStruct(String),
  Struct { fields: Vec<Type> },
  Array { len: usize, ty: Box<Type> },
  Pointer(Box<Type>),
  Vector { len: usize, ty: Box<Type> },
  Other,
}

#[derive(Clone)]
pub struct FunctionType {
  args: Vec<Type>,
  ret: Box<Type>,
}

impl FunctionType {
  pub fn from_type(ty: Type) -> Option<Self> {
    match ty {
      Type::Function { args, ret } => Some(Self { args, ret }),
      _ => None
    }
  }
}

#[derive(Clone, PartialEq, Eq, Hash)]
pub enum BinOp {
  Add,
  Sub,
  Mul,
  Div,
  Rem,
  Lshr,
  Ashr,
  Band,
  Bor,
  Bxor,
}

pub type Predicate = inkwell::IntPredicate;

#[derive(Clone, PartialEq, Eq, Hash)]
pub enum Value {
  Argument(usize),
  Global(String),
  ConstInt(i32),
  Location(Box<Location>),
  BinaryOperation { op: BinOp, op0: Box<Value>, op1: Box<Value> },
  Comparison { pred: Predicate, op0: Box<Value>, op1: Box<Value> },
  Call { id: usize, func: String, args: Vec<Value> },
  Unknown,
}

#[derive(Clone, PartialEq, Eq, Hash)]
pub enum Location {
  Argument(usize),
  Alloca(usize),
  Global(String),
  GetElementPtr(Box<Location>, Vec<u32>),
  Value(Box<Value>),
  Unknown,
}

#[derive(Clone)]
pub enum Branch {
  Then,
  Else,
}

#[derive(Clone)]
pub enum Instruction {
  Call { func: String, /* func_type: FunctionType, */ args: Vec<Value>, /* arg_types: Vec<Type> */ },
  Assume { pred: Predicate, op0: Value, op1: Value },
  ConditionalBr { cond: Value, br: Branch },
  UnconditionalBr { is_loop: bool },
  Switch { cond: Value },
  Return(Option<Value>),
  Store { loc: Location, val: Value },
  Load { loc: Location },
  GetElementPtr { loc: Location },
  BinaryOperation { op: BinOp, op0: Value, op1: Value},
  Alloca(usize),
  Other
}