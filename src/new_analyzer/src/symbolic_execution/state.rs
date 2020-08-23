use std::collections::HashMap;
use std::path::PathBuf;
use std::fs::File;
use std::io::Write;

use serde_json::json;
use llir::values::*;

use crate::slicer::*;
use crate::semantics::*;
use super::memory::*;
use super::trace::*;

#[derive(Clone)]
pub enum FinishState {
  ProperlyReturned,
  BranchExplored,
  ExceedingMaxTraceLength,
  Unreachable,
}

#[derive(Clone)]
pub struct State<'ctx> {
  pub stack: Stack<'ctx>,
  pub memory: Memory,
  pub visited_branch: VisitedBranch<'ctx>,
  // pub global_usage: GlobalUsage<'ctx>,
  // pub block_trace: BlockTrace<'ctx>,
  pub trace: Trace<'ctx>,
  pub target_node: Option<usize>,
  pub prev_block: Option<Block<'ctx>>,
  pub finish_state: FinishState,
  pub pointer_value_id_map: HashMap<GenericValue<'ctx>, usize>,
  pub constraints: Vec<Constraint>,

  // Identifiers
  alloca_id: usize,
  symbol_id: usize,
  pointer_value_id: usize,
}

impl<'ctx> State<'ctx> {
  pub fn new(slice: &Slice<'ctx>) -> Self {
    Self {
      stack: vec![StackFrame::entry(slice.entry)],
      memory: Memory::new(),
      visited_branch: VisitedBranch::new(),
      // global_usage: GlobalUsage::new(),
      // block_trace: BlockTrace::new(),
      trace: Vec::new(),
      target_node: None,
      prev_block: None,
      finish_state: FinishState::ProperlyReturned,
      pointer_value_id_map: HashMap::new(),
      constraints: Vec::new(),
      alloca_id: 0,
      symbol_id: 0,
      pointer_value_id: 0,
    }
  }

  pub fn new_alloca_id(&mut self) -> usize {
    let result = self.alloca_id;
    self.alloca_id += 1;
    result
  }

  pub fn new_symbol_id(&mut self) -> usize {
    let result = self.symbol_id;
    self.symbol_id += 1;
    result
  }

  pub fn add_constraint(&mut self, cond: Comparison, branch: bool) {
    self.constraints.push(Constraint { cond, branch });
  }

  pub fn path_satisfactory(&self) -> bool {
    use z3::*;
    let z3_ctx = Context::new(&z3::Config::default());
    let solver = Solver::new(&z3_ctx);
    let mut symbol_map = HashMap::new();
    let mut symbol_id = 0;
    for Constraint { cond, branch } in self.constraints.iter() {
      match cond.into_z3_ast(&mut symbol_map, &mut symbol_id, &z3_ctx) {
        Some(cond) => {
          let formula = if *branch { cond } else { cond.not() };
          solver.assert(&formula);
        }
        _ => (),
      }
    }
    match solver.check() {
      SatResult::Sat | SatResult::Unknown => true,
      _ => false,
    }
  }

  pub fn dump_json(&self, path: PathBuf) -> Result<(), String> {
    let trace_json = json!({
      "instrs": self.trace.iter().map(|node| json!({
        "loc": node.instr.debug_loc_string(),
        "sem": node.semantics,
        "res": node.result
      })).collect::<Vec<_>>(),
      "target": self.target_node,
    });
    let json_str = serde_json::to_string(&trace_json).map_err(|_| "Cannot turn trace into json".to_string())?;
    let mut file = File::create(path).map_err(|_| "Cannot create trace file".to_string())?;
    file
      .write_all(json_str.as_bytes())
      .map_err(|_| "Cannot write to trace file".to_string())
  }
}