open Semantics

module Worklist = struct
  type t = (Llvm.llbasicblock * State.t) list

  and instr_iterator = (Llvm.llbasicblock, Llvm.llvalue) Llvm.llpos

  let empty = []

  let push x s = x :: s

  let pop = function x :: s -> (x, s) | [] -> failwith "empty worklist"

  let is_empty s = s = []
end

module Traces = struct
  type t = Trace.t list

  let empty = []

  let add x s = x :: s

  let length = List.length

  let to_json llctx t =
    let l = List.map (Trace.to_json llctx) t in
    `List l
end

module DUGraph = struct
  include Graph.Persistent.Digraph.ConcreteBidirectional (Stmt)
end

module Environment = struct
  type t = {worklist: Worklist.t; traces: Trace.t list; dugraph: DUGraph.t}

  let empty =
    {worklist= Worklist.empty; traces= Traces.empty; dugraph= DUGraph.empty}

  let add_trace trace env = {env with traces= Traces.add trace env.traces}

  let add_work work env = {env with worklist= Worklist.push work env.worklist}
end

let initialize llm state =
  Llvm.fold_left_functions
    (fun state func -> State.add_memory func (Value.func func) state)
    state llm

let skip_function f =
  let r = Str.regexp "llvm\\.dbg\\..+" in
  Str.string_match r (Llvm.value_name f) 0

let rec execute_function llctx f env state =
  let entry = Llvm.entry_block f in
  execute_block llctx entry env state

and execute_block llctx blk env state =
  let instr = Llvm.instr_begin blk in
  execute_instr llctx instr env state

and execute_instr llctx instr env state =
  match instr with
  | Llvm.At_end _ ->
      let env = Environment.add_trace state.State.trace env in
      if Worklist.is_empty env.worklist then env
      else
        let (blk, state), wl = Worklist.pop env.worklist in
        execute_block llctx blk {env with worklist= wl} state
  | Llvm.Before instr ->
      transfer llctx instr env state

and transfer llctx instr env state =
  let opcode = Llvm.instr_opcode instr in
  match opcode with
  | Llvm.Opcode.Ret -> (
      let state = State.add_trace instr state in
      match State.pop_stack state with
      | Some (callsite, state) ->
          execute_instr llctx (Llvm.instr_succ callsite) env state
      | None ->
          execute_instr llctx (Llvm.instr_succ instr) env state )
  | Br -> (
      let state = State.add_trace instr state in
      match Llvm.get_branch instr with
      | Some (`Conditional (_, b1, b2)) ->
          let env = Environment.add_work (b2, state) env in
          execute_block llctx b1 env state
      | Some (`Unconditional b) ->
          execute_block llctx b env state
      | _ ->
          prerr_endline "warning: unknown branch" ;
          execute_instr llctx (Llvm.instr_succ instr) env state )
  | Switch ->
      let state = State.add_trace instr state in
      execute_instr llctx (Llvm.instr_succ instr) env state
  | Call -> (
      let callee_expr = Llvm.operand instr (Llvm.num_operands instr - 1) in
      match Memory.find callee_expr state.State.memory with
      | Value.Function f when not (Llvm.is_declaration f) ->
          let state = State.add_trace instr state in
          let state = State.push_stack instr state in
          execute_function llctx f env state
      | Value.Function f when skip_function f ->
          execute_instr llctx (Llvm.instr_succ instr) env state
      | _ ->
          let state = State.add_trace instr state in
          execute_instr llctx (Llvm.instr_succ instr) env state
      | exception Not_found ->
          Llvm.dump_value callee_expr ;
          failwith "not found" )
  | x ->
      let state = State.add_trace instr state in
      execute_instr llctx (Llvm.instr_succ instr) env state

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

let print_report env =
  Printf.printf "# Traces: %d\n" (Traces.length env.Environment.traces)

let dump_traces llctx env =
  let json = Traces.to_json llctx env.Environment.traces in
  let oc = open_out "traces.json" in
  Yojson.Safe.pretty_to_channel oc json

let main input_file =
  let llctx = Llvm.create_context () in
  let llmem = Llvm.MemoryBuffer.of_file input_file in
  let llm = Llvm_bitreader.parse_bitcode llctx llmem in
  let initial_state = initialize llm State.empty in
  let main_function = find_starting_point initial_state in
  let env =
    execute_function llctx main_function Environment.empty initial_state
  in
  print_report env ; dump_traces llctx env
