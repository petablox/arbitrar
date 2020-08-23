use llir::{values::*, *};
use std::path::Path;

use analyzer::symbolic_execution::*;
use analyzer::call_graph::*;
use analyzer::options::*;
use analyzer::slicer::*;

fn process_slice<F>(path: &Path, entry: &str, caller: &str, target: &str, f: F) -> Result<(), String>
where
  F: Fn(CallGraph, Slice),
{
  let ctx = Context::create();
  let module = ctx.load_module(path)?;

  // Build call graph
  let call_graph = CallGraph::from_module(&module, &Options::default());

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
    instr: call_instr,
    functions: vec![caller_func, caller_func, target_func].iter().cloned().collect(),
  };

  f(call_graph, slice);

  Ok(())
}

fn test_slice_function_trace(path: &Path, entry: &str, caller: &str, target: &str) -> Result<(), String> {
  process_slice(path, entry, caller, target, |cg, slice| {
    // Get the function traces
    let block_traces = slice.function_traces(&cg, 1);
    println!("{:?}", block_traces);
  })
}

fn test_block_trace(path: &Path, entry: &str, caller: &str, target: &str) -> Result<(), String> {
  process_slice(path, entry, caller, target, |cg, slice| {
    // Get the function traces
    let block_traces = slice.block_traces(&cg, 1);
    println!("{:?}", block_traces);
  })
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

#[test]
fn slice_block_trace_example_3() -> Result<(), String> {
  let path = Path::new("tests/c_files/basic/example_3.bc");
  test_block_trace(path, "main", "f", "malloc")
}

#[test]
fn slice_block_trace_example_temp() -> Result<(), String> {
  let path = Path::new("tests/c_files/trace/block_trace_2.bc");
  test_block_trace(path, "main", "f", "malloc")
}
