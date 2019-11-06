open Semantics

let initialize llm state =
  Llvm.fold_left_functions
    (fun state func -> State.add_memory func (Value.func func) state)
    state llm

let rec execute_function f state =
  let entry = Llvm.entry_block f in
  execute_block entry state

and execute_block blk state =
  let instr = Llvm.instr_begin blk in
  execute_instr instr state

and execute_instr instr state =
  match instr with
  | Llvm.At_end _ ->
      state
  | Llvm.Before instr -> (
      let opcode = Llvm.instr_opcode instr in
      let state = State.add_trace instr state in
      match opcode with
      | Llvm.Opcode.Ret ->
          execute_instr (Llvm.instr_succ instr) state
      | Br ->
          execute_instr (Llvm.instr_succ instr) state
      | Switch ->
          execute_instr (Llvm.instr_succ instr) state
      | Call ->
          let callee_expr = Llvm.operand instr (Llvm.num_operands instr - 1) in
          let callee =
            match Memory.find callee_expr state.State.memory with
            | Value.Function f ->
                f
            | exception Not_found ->
                failwith "not found"
          in
          execute_function callee state
      | x ->
          execute_instr (Llvm.instr_succ instr) state )

let find_starting_point initial =
  let starting =
    Memory.find_first_opt
      (fun lv -> Llvm.value_name lv = "main")
      initial.State.memory
  in
  match starting with
  | Some (_, Value.Function f) ->
      f
  | _ ->
      failwith "starting point not found"

let main input_file =
  let llctx = Llvm.create_context () in
  let llmem = Llvm.MemoryBuffer.of_file input_file in
  let llm = Llvm_bitreader.parse_bitcode llctx llmem in
  let initial = initialize llm State.empty in
  let main_function = find_starting_point initial in
  let _ = execute_function main_function initial in
  ()
