use llir::{values::*, *};
use std::path::Path;

use analyzer::call_graph::*;
use analyzer::slicer::*;
use analyzer::symbolic_execution::*;
use analyzer::utils::*;

struct TempOptions;

impl CallGraphOptions for TempOptions {
  fn remove_llvm_funcs(&self) -> bool {
    false
  }
}

fn process_slice<F>(path: &Path, entry: &str, caller: &str, target: &str, f: F) -> Result<(), String>
where
  F: Fn(CallGraph, Slice),
{
  let ctx = Context::create();
  let module = ctx.load_module(path)?;

  // Build call graph
  let call_graph = CallGraph::from_module(&module, &TempOptions);

  // Build the slice
  let entry_func = module.get_function(entry).unwrap();
  let caller_func = module.get_function(caller).unwrap();
  // let target_func = module.get_function(target).unwrap();
  let (call_instr, target_func) = {
    let mut call_instr = None;
    let mut target_func = None;
    for instr in caller_func.iter_instructions() {
      match instr {
        Instruction::Call(call) => {
          if !call.is_intrinsic_call() {
            match call.callee_function() {
              Some(f) if f.simp_name() == target => {
                call_instr = Some(call);
                target_func = Some(f);
              }
              _ => {}
            }
          }
        }
        _ => {}
      }
    }
    (call_instr.unwrap(), target_func.unwrap())
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

fn test_block_trace(path: &Path, entry: &str, caller: &str, target: &str, max_traces: usize) -> Result<(), String> {
  process_slice(path, entry, caller, target, |cg, slice| {
    // Get the function traces
    let block_traces = slice.block_traces(&cg, 1, max_traces);
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
  test_block_trace(path, "main", "f", "malloc", 50)
}

#[test]
fn slice_block_trace_example_temp() -> Result<(), String> {
  let path = Path::new("tests/c_files/trace/block_trace_2.bc");
  test_block_trace(path, "main", "f", "malloc", 50)
}

// #[test]
// fn slice_block_trace_kernel_vbt_panel_init() -> Result<(), String> {
//   let path = Path::new("/home/aspire/programs/linux_kernel/linux-4.5-rc4/vmlinux.bc");
//   test_block_trace(path, "vbt_panel_init", "vbt_panel_init", "devm_kzalloc", 50)
// }
