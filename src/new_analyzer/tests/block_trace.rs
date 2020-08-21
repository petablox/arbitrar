extern crate analyzer;

use std::path::{Path};
use llir::{*, values::*};

use analyzer::call_graph::call_graph_from_module;
use analyzer::slicer::Slice;
use analyzer::block_tracer::BlockTracer;

#[test]
fn test_slice_function_trace() -> Result<(), String> {
  let ctx = Context::create();
  let module = ctx.load_module(Path::new("tests/c_files/br/br_1.bc"))?;

  // Build call graph
  let call_graph = call_graph_from_module(&module, false);
  let bt = BlockTracer { call_graph: &call_graph };

  // Build the slice
  let main_func = module.get_function("main").unwrap();
  let call_instr = {
    let mut call_instr = None;
    for block in main_func.iter_blocks() {
      for instr in block.iter_instructions() {
        match instr {
          Instruction::Call(call) => if !call.is_intrinsic_call() {
            call_instr = Some(call);
          },
          _ => {}
        }
      }
    }
    call_instr.unwrap()
  };
  let target_func = call_instr.callee_function().unwrap();
  let slice = Slice {
    entry: main_func,
    caller: main_func,
    callee: target_func,
    instr: call_instr.as_instruction(),
    functions: vec![main_func, target_func].iter().cloned().collect(),
  };

  // Get the function traces
  let function_traces = bt.function_traces(&slice);
  println!("{:?}", function_traces);

  Ok(())
}