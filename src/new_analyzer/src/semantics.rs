use std::rc::Rc;
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
  Global(String), // Global Value Name
  FunctionPointer(String), // Function Name
  ConstInt(i64),
  ConstPtr, // Pointer ID
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

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum Location {
  // Argument(usize),
  Alloca(usize),
  Global(String),
  GetElementPtr(Rc<Location>, Vec<Rc<Value>>),
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
  Alloca(usize),
  Phi,
}
