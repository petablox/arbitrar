use either::Either;
use inkwell::basic_block::BasicBlock;
use inkwell::context::ContextRef;
use inkwell::module::Module;
use inkwell::values::*;

#[derive(Copy, Clone)]
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

  fn str_is_llvm_function(s: &str) -> bool {
    s.contains("llvm.")
  }
}

impl<'ctx> FunctionValueTrait<'ctx> for FunctionValue<'ctx> {
  fn is_declare_only(&self) -> bool {
    self.get_first_basic_block().is_none()
  }

  fn is_llvm_function(&self) -> bool {
    Self::str_is_llvm_function(self.function_name().as_str())
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
    self.get_first_basic_block().and_then(|blk| blk.get_first_instruction())
  }
}

#[derive(Copy, Clone)]
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

#[derive(Copy, Clone)]
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

pub trait BasicBlockTrait<'ctx> {
  fn is_loop_block(&self, llctx: &ContextRef<'ctx>) -> bool;
}

impl<'ctx> BasicBlockTrait<'ctx> for BasicBlock<'ctx> {
  fn is_loop_block(&self, llctx: &ContextRef<'ctx>) -> bool {
    let func = self.get_parent().unwrap();
    for blk in func.get_basic_blocks().iter() {
      match blk.get_terminator() {
        Some(instr) => match instr.get_opcode() {
          InstructionOpcode::Br => match instr.get_num_operands() {
            1 => match instr.get_operand(0) {
              Some(Either::Right(blk)) => if *self == blk {
                if instr.is_loop(&llctx) {
                  return true;
                }
              }
              _ => {}
            }
            _ => {}
          }
          _ => {}
        }
        None => {}
      }
    }
    false
  }
}

#[derive(Clone)]
pub struct CallInstruction<'ctx> {
  pub callee_name: String,
  pub callee: Option<FunctionValue<'ctx>>,
  pub args: Vec<BasicValueEnum<'ctx>>,
}

pub trait CallInstructionTrait<'ctx> {
  fn callee_name(&self) -> Option<String>;

  fn callee(&self, module: &Module<'ctx>) -> Option<FunctionValue<'ctx>>;

  fn as_call_instruction(&self, module: &Module<'ctx>) -> Option<CallInstruction<'ctx>>;
}

impl<'ctx> CallInstructionTrait<'ctx> for InstructionValue<'ctx> {
  fn callee_name(&self) -> Option<String> {
    let maybe_callee = self.get_operand(self.get_num_operands() - 1);
    match maybe_callee {
      Some(Either::Left(BasicValueEnum::PointerValue(pt))) => {
        let fname = pt.get_name();
        Some(fname.to_string_lossy().to_string())
      }
      _ => None,
    }
  }

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
          let callee_name = pt.get_name().to_string_lossy().to_string();
          let args = (0..self.get_num_operands() - 1)
            .map(|i| match self.get_operand(i) {
              Some(Either::Left(v)) => v,
              _ => panic!("Invalid call instruction"),
            })
            .collect();
          let callee = module.get_function(callee_name.as_str());
          Some(CallInstruction {
            callee_name,
            callee,
            args,
          })
        }
        _ => None,
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
      Add | FAdd | Sub | FSub | Mul | FMul | UDiv | SDiv | FDiv | URem | SRem | FRem | Shl | LShr | AShr | And | Or
      | Xor | ICmp | FCmp => true,
      _ => false,
    }
  }

  fn is_unary(&self) -> bool {
    use InstructionOpcode::*;
    match self {
      Trunc | ZExt | SExt | FPToUI | FPToSI | UIToFP | SIToFP | FPTrunc | FPExt | PtrToInt | IntToPtr | BitCast => true,
      _ => false,
    }
  }
}

pub trait BasicValueEnumTrait<'ctx> {
  fn as_instruction(&self) -> Option<InstructionValue<'ctx>>;

  fn argument_index(&self, func: FunctionValue<'ctx>) -> Option<usize>;
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

  fn argument_index(&self, func: FunctionValue<'ctx>) -> Option<usize> {
    func.get_params().iter().position(|arg| arg == self)
  }
}

#[derive(Copy, Clone)]
pub struct ReturnInstruction<'ctx> {
  pub val: Option<BasicValueEnum<'ctx>>,
}

pub trait ReturnInstructionTrait<'ctx> {
  fn as_return_instruction(&self) -> Option<ReturnInstruction<'ctx>>;
}

impl<'ctx> ReturnInstructionTrait<'ctx> for InstructionValue<'ctx> {
  fn as_return_instruction(&self) -> Option<ReturnInstruction<'ctx>> {
    if self.get_opcode() == InstructionOpcode::Return {
      match self.get_operand(0) {
        Some(Either::Left(val)) => Some(ReturnInstruction { val: Some(val) }),
        None => Some(ReturnInstruction { val: None }),
        _ => None,
      }
    } else {
      None
    }
  }
}

#[derive(Copy, Clone)]
pub enum BranchInstruction<'ctx> {
  ConditionalBranch {
    cond: IntValue<'ctx>,
    then_blk: BasicBlock<'ctx>,
    else_blk: BasicBlock<'ctx>,
  },
  UnconditionalBranch(BasicBlock<'ctx>),
}

pub trait BranchInstructionTrait<'ctx> {
  fn as_branch_instruction(&self) -> Option<BranchInstruction<'ctx>>;

  fn is_loop(&self, llctx: &ContextRef<'ctx>) -> bool;
}

impl<'ctx> BranchInstructionTrait<'ctx> for InstructionValue<'ctx> {
  fn as_branch_instruction(&self) -> Option<BranchInstruction<'ctx>> {
    if self.get_opcode() == InstructionOpcode::Br {
      match self.get_num_operands() {
        1 => match self.get_operand(0) {
          Some(Either::Right(blk)) => Some(BranchInstruction::UnconditionalBranch(blk)),
          _ => None,
        },
        3 => match (self.get_operand(0), self.get_operand(2), self.get_operand(1)) {
          (
            Some(Either::Left(BasicValueEnum::IntValue(cond))),
            Some(Either::Right(then_blk)),
            Some(Either::Right(else_blk)),
          ) => Some(BranchInstruction::ConditionalBranch {
            cond,
            then_blk,
            else_blk,
          }),
          _ => None,
        },
        _ => None,
      }
    } else {
      None
    }
  }

  fn is_loop(&self, llctx: &ContextRef<'ctx>) -> bool {
    let kind = llctx.get_kind_id("llvm.loop");
    self.get_metadata(kind).is_some()
  }
}

#[derive(Clone)]
pub struct SwitchInstruction<'ctx> {
  pub cond: IntValue<'ctx>,
  pub default_blk: BasicBlock<'ctx>,
  pub branches: Vec<(IntValue<'ctx>, BasicBlock<'ctx>)>,
}

pub trait SwitchInstructionTrait<'ctx> {
  fn as_switch_instruction(&self) -> Option<SwitchInstruction<'ctx>>;
}

impl<'ctx> SwitchInstructionTrait<'ctx> for InstructionValue<'ctx> {
  fn as_switch_instruction(&self) -> Option<SwitchInstruction<'ctx>> {
    let num_operands = self.get_num_operands();
    let num_branches = (num_operands - 2) / 2;
    match (self.get_operand(0), self.get_operand(1)) {
      (Some(Either::Left(BasicValueEnum::IntValue(cond))), Some(Either::Right(default_blk))) => {
        let mut branches = Vec::with_capacity(num_branches as usize);
        for i in 0..num_branches {
          let compare_idx = 2 + 2 * i;
          let blk_idx = 3 + 2 * i;
          match (self.get_operand(compare_idx), self.get_operand(blk_idx)) {
            (Some(Either::Left(BasicValueEnum::IntValue(comp))), Some(Either::Right(br))) => {
              branches.push((comp, br));
            }
            _ => return None,
          }
        }
        Some(SwitchInstruction {
          cond,
          default_blk,
          branches,
        })
      }
      _ => None,
    }
  }
}

#[derive(Copy, Clone)]
pub struct StoreInstruction<'ctx> {
  pub location: BasicValueEnum<'ctx>,
  pub value: BasicValueEnum<'ctx>,
}

pub trait StoreInstructionTrait<'ctx> {
  fn as_store_instruction(&self) -> Option<StoreInstruction<'ctx>>;
}

impl<'ctx> StoreInstructionTrait<'ctx> for InstructionValue<'ctx> {
  fn as_store_instruction(&self) -> Option<StoreInstruction<'ctx>> {
    if self.get_opcode() == InstructionOpcode::Store {
      match (self.get_operand(0), self.get_operand(1)) {
        (Some(Either::Left(value)), Some(Either::Left(location))) => Some(StoreInstruction { value, location }),
        _ => None,
      }
    } else {
      None
    }
  }
}

#[derive(Copy, Clone)]
pub struct LoadInstruction<'ctx> {
  pub location: BasicValueEnum<'ctx>,
}

pub trait LoadInstructionTrait<'ctx> {
  fn as_load_instruction(&self) -> Option<LoadInstruction<'ctx>>;
}

impl<'ctx> LoadInstructionTrait<'ctx> for InstructionValue<'ctx> {
  fn as_load_instruction(&self) -> Option<LoadInstruction<'ctx>> {
    if self.get_opcode() == InstructionOpcode::Load {
      match self.get_operand(0) {
        Some(Either::Left(location)) => Some(LoadInstruction { location }),
        _ => None,
      }
    } else {
      None
    }
  }
}

#[derive(Copy, Clone)]
pub struct UnaryInstruction<'ctx> {
  pub op: InstructionOpcode,
  pub op0: BasicValueEnum<'ctx>,
}

pub trait UnaryInstructionTrait<'ctx> {
  fn as_unary_instruction(&self) -> Option<UnaryInstruction<'ctx>>;
}

impl<'ctx> UnaryInstructionTrait<'ctx> for InstructionValue<'ctx> {
  fn as_unary_instruction(&self) -> Option<UnaryInstruction<'ctx>> {
    match self.get_operand(0) {
      Some(Either::Left(op0)) => {
        let op = self.get_opcode();
        Some(UnaryInstruction { op, op0 })
      }
      _ => None,
    }
  }
}

#[derive(Copy, Clone)]
pub struct BinaryInstruction<'ctx> {
  pub op: InstructionOpcode,
  pub op0: BasicValueEnum<'ctx>,
  pub op1: BasicValueEnum<'ctx>,
}

pub trait BinaryInstructionTrait<'ctx> {
  fn as_binary_instruction(&self) -> Option<BinaryInstruction<'ctx>>;
}

impl<'ctx> BinaryInstructionTrait<'ctx> for InstructionValue<'ctx> {
  fn as_binary_instruction(&self) -> Option<BinaryInstruction<'ctx>> {
    match (self.get_operand(0), self.get_operand(1)) {
      (Some(Either::Left(op0)), Some(Either::Left(op1))) => Some(BinaryInstruction {
        op: self.get_opcode(),
        op0,
        op1,
      }),
      _ => None,
    }
  }
}

pub struct PhiInstruction<'ctx> {
  pub incomings: Vec<(BasicValueEnum<'ctx>, BasicBlock<'ctx>)>,
}

pub trait PhiInstructionTrait<'ctx> {
  fn as_phi_instruction(&self) -> Option<PhiInstruction<'ctx>>;
}

impl<'ctx> PhiInstructionTrait<'ctx> for InstructionValue<'ctx> {
  fn as_phi_instruction(&self) -> Option<PhiInstruction<'ctx>> {
    let num_incomings = self.get_num_operands();
    let mut incomings = Vec::with_capacity(num_incomings as usize);
    for i in 0..num_incomings {
      match (self.get_operand(i * 2), self.get_operand(i * 2 + 1)) {
        (Some(Either::Left(val)), Some(Either::Right(blk))) => {
          incomings.push((val, blk));
        }
        _ => return None,
      }
    }
    Some(PhiInstruction { incomings })
  }
}

pub struct GEPInstruction<'ctx> {
  pub loc: BasicValueEnum<'ctx>,
  pub indices: Vec<BasicValueEnum<'ctx>>,
}

pub trait GEPInstructionTrait<'ctx> {
  fn as_gep_instruction(&self) -> Option<GEPInstruction<'ctx>>;
}

impl<'ctx> GEPInstructionTrait<'ctx> for InstructionValue<'ctx> {
  fn as_gep_instruction(&self) -> Option<GEPInstruction<'ctx>> {
    match self.get_operand(0) {
      Some(Either::Left(loc)) => {
        let num_indices = self.get_num_operands() - 1;
        let mut indices = Vec::with_capacity(num_indices as usize);
        for i in 1..=num_indices {
          match self.get_operand(i) {
            Some(Either::Left(bv)) => indices.push(bv),
            _ => return None,
          }
        }
        Some(GEPInstruction { loc, indices })
      }
      _ => None,
    }
  }
}
