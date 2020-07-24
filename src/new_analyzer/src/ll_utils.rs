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

  fn location(&self, llctx: ContextRef<'ctx>) -> String;

  fn function_name(&self) -> String;

  fn first_instruction(&self) -> Option<InstructionValue<'ctx>>;
}

impl<'ctx> FunctionValueTrait<'ctx> for FunctionValue<'ctx> {
  fn is_declare_only(&self) -> bool {
    self.get_first_basic_block().is_none()
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
    self.get_first_basic_block().and_then(|blk| blk.get_first_instruction())
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

pub fn callee_of_call_instr<'ctx>(module: &Module<'ctx>, i: InstructionValue<'ctx>) -> Option<FunctionValue<'ctx>> {
  if i.get_opcode() == InstructionOpcode::Call {
    let maybe_callee = i.get_operand(i.get_num_operands() - 1);
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
