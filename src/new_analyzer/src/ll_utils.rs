use either::Either;
use inkwell::basic_block::BasicBlock;
use inkwell::context::ContextRef;
use inkwell::module::Module;
use inkwell::values::*;

pub struct FunctionInstructionIterator<'ctx> {
  curr_block: Option<BasicBlock<'ctx>>,
  next_instruction: Option<InstructionValue<'ctx>>,
}

impl<'ctx> Iterator for FunctionInstructionIterator<'ctx> {
  type Item = InstructionValue<'ctx>;

  fn next(&mut self) -> Option<Self::Item> {
    match self.next_instruction {
      Some(i) => {
        self.next_instruction = i.get_next_instruction();
        Some(i)
      }
      None => match self.curr_block {
        Some(curr_block) => match curr_block.get_next_basic_block() {
          Some(next_block) => match next_block.get_first_instruction() {
            Some(first_instr) => {
              self.curr_block = Some(next_block);
              self.next_instruction = first_instr.get_next_instruction();
              Some(first_instr)
            }
            None => None,
          },
          None => None,
        },
        None => None,
      },
    }
  }
}

pub trait CreateFunctionInstructionIterator<'ctx> {
  fn iter_instructions(&self) -> FunctionInstructionIterator<'ctx>;
}

impl<'ctx> CreateFunctionInstructionIterator<'ctx> for FunctionValue<'ctx> {
  fn iter_instructions(&self) -> FunctionInstructionIterator<'ctx> {
    let default = FunctionInstructionIterator {
      curr_block: None,
      next_instruction: None,
    };
    match self.get_first_basic_block() {
      Some(first_block) => match first_block.get_first_instruction() {
        Some(first_instruction) => FunctionInstructionIterator {
          curr_block: Some(first_block),
          next_instruction: Some(first_instruction),
        },
        None => default,
      },
      None => default,
    }
  }
}

pub trait FunctionValueTrait<'ctx> {
  fn is_declare_only(&self) -> bool;

  fn is_llvm_function(&self) -> bool;

  fn is_void_return_type(&self) -> bool;

  fn location(&self, llctx: ContextRef<'ctx>) -> String;

  fn function_name(&self) -> String;

  fn first_instruction(&self) -> Option<InstructionValue<'ctx>>;
}

impl<'ctx> FunctionValueTrait<'ctx> for FunctionValue<'ctx> {
  fn is_declare_only(&self) -> bool {
    self.get_first_basic_block().is_none()
  }

  fn is_llvm_function(&self) -> bool {
    self.function_name().contains("llvm.")
  }

  fn is_void_return_type(&self) -> bool {
    self.get_type().get_return_type().is_none()
  }

  fn location(&self, llctx: ContextRef<'ctx>) -> String {
    let kind = llctx.get_kind_id("dbg");
    for instr in self.iter_instructions() {
      match instr.get_metadata(kind) {
        Some(metadata) => {
          return format!("{:?}", metadata);
        }
        None => {}
      }
    }
    self.function_name()
  }

  fn function_name(&self) -> String {
    String::from(self.get_name().to_string_lossy())
  }

  fn first_instruction(&self) -> Option<InstructionValue<'ctx>> {
    self
      .get_first_basic_block()
      .and_then(|blk| blk.get_first_instruction())
  }
}

pub struct FunctionIterator<'ctx> {
  next_function: Option<FunctionValue<'ctx>>,
}

impl<'ctx> Iterator for FunctionIterator<'ctx> {
  type Item = FunctionValue<'ctx>;

  fn next(&mut self) -> Option<Self::Item> {
    match self.next_function {
      Some(f) => {
        self.next_function = f.get_next_function();
        Some(f)
      }
      None => None,
    }
  }
}

pub trait CreateFunctionIterator<'ctx> {
  fn iter_functions(&self) -> FunctionIterator<'ctx>;
}

impl<'ctx> CreateFunctionIterator<'ctx> for Module<'ctx> {
  fn iter_functions(&self) -> FunctionIterator<'ctx> {
    FunctionIterator {
      next_function: self.get_first_function(),
    }
  }
}

pub struct BlockInstructionIterator<'ctx> {
  next_instruction: Option<InstructionValue<'ctx>>,
}

impl<'ctx> Iterator for BlockInstructionIterator<'ctx> {
  type Item = InstructionValue<'ctx>;

  fn next(&mut self) -> Option<Self::Item> {
    match self.next_instruction {
      Some(i) => {
        self.next_instruction = i.get_next_instruction();
        Some(i)
      }
      None => None,
    }
  }
}

pub trait CreateBlockInstructionIterator<'ctx> {
  fn iter_instructions(&self) -> BlockInstructionIterator<'ctx>;
}

impl<'ctx> CreateBlockInstructionIterator<'ctx> for BasicBlock<'ctx> {
  fn iter_instructions(&self) -> BlockInstructionIterator<'ctx> {
    BlockInstructionIterator {
      next_instruction: self.get_first_instruction(),
    }
  }
}

pub struct CallInstruction<'ctx> {
  pub callee: FunctionValue<'ctx>,
  pub args: Vec<BasicValueEnum<'ctx>>,
}

pub trait CallInstructionTrait<'ctx> {
  fn callee(&self, module: &Module<'ctx>) -> Option<FunctionValue<'ctx>>;

  fn as_call_instruction(&self, module: &Module<'ctx>) -> Option<CallInstruction<'ctx>>;
}

impl<'ctx> CallInstructionTrait<'ctx> for InstructionValue<'ctx> {
  fn callee(&self, module: &Module<'ctx>) -> Option<FunctionValue<'ctx>> {
    if self.get_opcode() == InstructionOpcode::Call {
      let maybe_callee = self.get_operand(self.get_num_operands() - 1);
      match maybe_callee {
        Some(Either::Left(BasicValueEnum::PointerValue(pt))) => {
          let fname = pt.get_name();
          module.get_function(&fname.to_string_lossy())
        }
        _ => None,
      }
    } else {
      None
    }
  }

  fn as_call_instruction(&self, module: &Module<'ctx>) -> Option<CallInstruction<'ctx>> {
    if self.get_opcode() == InstructionOpcode::Call {
      match self.get_operand(self.get_num_operands() - 1) {
        Some(Either::Left(BasicValueEnum::PointerValue(pt))) => {
          match module.get_function(&pt.get_name().to_string_lossy()){
            Some(callee) => {
              let args = (0..self.get_num_operands() - 1).map(|i| match self.get_operand(i) {
                Some(Either::Left(v)) => v,
                _ => panic!("Invalid call instruction")
              }).collect();
              Some(CallInstruction { callee, args })
            }
            None => None
          }
        }
        _ => None
      }
    } else {
      None
    }
  }
}

pub trait OpcodeTrait {
  fn is_binary(&self) -> bool;

  fn is_unary(&self) -> bool;
}

impl OpcodeTrait for InstructionOpcode {
  fn is_binary(&self) -> bool {
    use InstructionOpcode::*;
    match self {
      Add | FAdd | Sub | FSub | Mul | FMul | UDiv | SDiv | FDiv | URem | SRem | FRem | Shl
      | LShr | AShr | And | Or | Xor | ICmp | FCmp => true,
      _ => false,
    }
  }

  fn is_unary(&self) -> bool {
    use InstructionOpcode::*;
    match self {
      Trunc | ZExt | SExt | FPToUI | FPToSI | UIToFP | SIToFP | FPTrunc | FPExt | PtrToInt
      | IntToPtr | BitCast => true,
      _ => false,
    }
  }
}

pub trait BasicValueEnumTrait<'ctx> {
  fn as_instruction(&self) -> Option<InstructionValue<'ctx>>;
}

impl<'ctx> BasicValueEnumTrait<'ctx> for BasicValueEnum<'ctx> {
  fn as_instruction(&self) -> Option<InstructionValue<'ctx>> {
    match self {
      Self::ArrayValue(av) => av.as_instruction(),
      Self::IntValue(iv) => iv.as_instruction(),
      Self::FloatValue(fv) => fv.as_instruction(),
      Self::PointerValue(pv) => pv.as_instruction(),
      Self::StructValue(sv) => sv.as_instruction(),
      Self::VectorValue(vv) => vv.as_instruction(),
    }
  }
}

pub enum BranchInstruction<'ctx> {
  ConditionalBranch {
    cond: IntValue<'ctx>,
    then_blk: BasicBlock<'ctx>,
    else_blk: BasicBlock<'ctx>,
  },
  UnconditionalBranch(BasicBlock<'ctx>)
}

pub trait BranchInstructionTrait<'ctx> {
  fn as_branch_instruction(&self) -> Option<BranchInstruction<'ctx>>;
}

impl<'ctx> BranchInstructionTrait<'ctx> for InstructionValue<'ctx> {
  fn as_branch_instruction(&self) -> Option<BranchInstruction<'ctx>> {
    if self.get_opcode() == InstructionOpcode::Br {
      match self.get_num_operands() {
        1 => match self.get_operand(0) {
          Some(Either::Right(blk)) => Some(BranchInstruction::UnconditionalBranch(blk)),
          _ => None
        },
        3 => match (self.get_operand(0), self.get_operand(1), self.get_operand(2)) {
          (Some(Either::Left(BasicValueEnum::IntValue(cond))), Some(Either::Right(then_blk)), Some(Either::Right(else_blk))) => {
            Some(BranchInstruction::ConditionalBranch { cond, then_blk, else_blk })
          },
          _ => None
        },
        _ => None
      }
    } else {
      None
    }
  }
}