extern crate analyzer;

use llir::{values::*, *};
use std::path::Path;

use analyzer::block_tracer::*;
use analyzer::call_graph::*;
use analyzer::slicer::*;

fn test_slice_function_trace(path: &Path, entry: &str, caller: &str, target: &str) -> Result<(), String> {
  let ctx = Context::create();
  let module = ctx.load_module(path)?;

  // Build call graph
  let call_graph = call_graph_from_module(&module, false);
  call_graph.graph.dump();
  let bt = BlockTracer {
    call_graph: &call_graph,
    slicer_options: &SlicerOptions::default(),
  };

  // Build the slice
  let entry_func = module.get_function(entry).unwrap();
  let caller_func = module.get_function(caller).unwrap();
  let target_func = module.get_function(target).unwrap();
  let call_instr = {
    let mut call_instr = None;
    for instr in caller_func.iter_instructions() {
      match instr {
        Instruction::Call(call) => {
          if !call.is_intrinsic_call() {
            match call.callee_function() {
              Some(f) if f == target_func => {
                call_instr = Some(call);
              }
              _ => {}
            }
          }
        }
        _ => {}
      }
    }
    call_instr.unwrap()
  };
  let slice = Slice {
    entry: entry_func,
    caller: caller_func,
    callee: target_func,
    instr: call_instr.as_instruction(),
    functions: vec![caller_func, caller_func, target_func].iter().cloned().collect(),
  };

  // Get the function traces
  let function_traces = bt.function_traces(&slice);
  println!(
    "{:?}",
    function_traces
      .into_iter()
      .map(|fs| fs.into_iter().map(|f| f.name()).collect::<Vec<_>>())
      .collect::<Vec<_>>()
  );

  Ok(())
}

#[test]
fn slice_function_trace_br_1() -> Result<(), String> {
  let path = Path::new("tests/c_files/br/br_1.bc");
  test_slice_function_trace(path, "main", "main", "target")
}

#[test]
fn slice_function_trace_example_1() -> Result<(), String> {
  let path = Path::new("tests/c_files/basic/example_1.bc");
  test_slice_function_trace(path, "main", "f", "malloc")
}

#[test]
fn slice_function_trace_example_3() -> Result<(), String> {
  let path = Path::new("tests/c_files/basic/example_3.bc");
  test_slice_function_trace(path, "main", "f", "malloc")
}

#[test]
fn slice_function_trace_example_5() -> Result<(), String> {
  let path = Path::new("tests/c_files/basic/example_5.bc");
  test_slice_function_trace(path, "main", "f", "malloc")
}

#[test]
fn slice_function_trace_example_7() -> Result<(), String> {
  let path = Path::new("tests/c_files/basic/example_7.bc");
  test_slice_function_trace(path, "main", "f", "malloc")
}
