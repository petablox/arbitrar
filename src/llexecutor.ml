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

module Environment = struct
  type t = {worklist: Worklist.t; traces: Traces.t; dugraphs: DUGraph.t list}

  let empty = {worklist= Worklist.empty; traces= Traces.empty; dugraphs= []}

  let add_trace trace env = {env with traces= Traces.add trace env.traces}

  let add_work work env = {env with worklist= Worklist.push work env.worklist}

  let add_dugraph g env = {env with dugraphs= g :: env.dugraphs}
end

let initialize llm state =
  Llvm.fold_left_functions
    (fun state func ->
      let state =
        State.add_memory (Location.variable func) (Value.func func) state
      in
      if Llvm.is_declaration func then state
      else
        Llvm.fold_left_blocks
          (fun state blk ->
            Llvm.fold_left_instrs
              (fun state instr -> State.add_instr_id instr state)
              state blk)
          state func)
    state llm

let skip_function f =
  let r = Str.regexp "llvm\\.dbg\\..+" in
  Str.string_match r (Llvm.value_name f) 0

let eval exp memory =
  let kind = Llvm.classify_value exp in
  match kind with
  | Llvm.ValueKind.ConstantInt -> (
    match Llvm.int64_of_const exp with
    | Some i ->
        Value.Int i
    | None ->
        Value.Unknown )
  | Instruction _ ->
      let lv = Location.variable exp in
      Memory.find lv memory
  | _ ->
      Value.Unknown

let eval_lv exp memory =
  let kind = Llvm.classify_value exp in
  match kind with
  | Llvm.ValueKind.Instruction _ ->
      Location.variable exp
  | _ ->
      failwith "unknown"

let rec execute_function llctx f env state =
  let entry = Llvm.entry_block f in
  execute_block llctx entry env state

and execute_block llctx blk env state =
  let instr = Llvm.instr_begin blk in
  execute_instr llctx instr env state

and execute_instr llctx instr env state =
  match instr with
  | Llvm.At_end _ ->
      let env =
        Environment.add_trace state.State.trace env
        |> Environment.add_dugraph state.State.dugraph
      in
      if Worklist.is_empty env.worklist then env
      else
        let (blk, state), wl = Worklist.pop env.worklist in
        execute_block llctx blk {env with worklist= wl} state
  | Llvm.Before instr ->
      transfer llctx instr env state

and transfer llctx instr env state =
  let opcode = Llvm.instr_opcode instr in
  let state =
    Llvm.fold_left_uses
      (fun env use -> State.add_du_edge instr (Llvm.user use) env)
      state instr
  in
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
      let var = Location.variable callee_expr in
      match Memory.find var state.State.memory with
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
  | Alloca ->
      let var = Location.variable instr in
      let addr = Location.new_address () |> Value.location in
      State.add_trace instr state
      |> State.add_memory_def var addr instr
      |> execute_instr llctx (Llvm.instr_succ instr) env
  | Store ->
      let exp0 = Llvm.operand instr 0 in
      let exp1 = Llvm.operand instr 1 in
      let v0 = eval exp0 state.State.memory in
      let v1 = eval exp1 state.State.memory in
      let lv = match v1 with Value.Location l -> l | _ -> Location.Unknown in
      State.add_trace instr state
      |> State.add_memory_def lv v0 instr
      |> execute_instr llctx (Llvm.instr_succ instr) env
  | Load ->
      let exp0 = Llvm.operand instr 0 in
      let lv0 = eval_lv exp0 state.State.memory in
      let v0 = Memory.find lv0 state.State.memory in
      let lv1 =
        match v0 with Value.Location l -> l | _ -> Location.Unknown
      in
      let v1 = Memory.find lv1 state.State.memory in
      let lv = eval_lv instr state.State.memory in
      State.add_trace instr state
      |> State.add_memory_def lv v1 instr
      |> State.add_semantic_du_edges [lv1] instr
      |> execute_instr llctx (Llvm.instr_succ instr) env
  | x ->
      let state = State.add_trace instr state in
      execute_instr llctx (Llvm.instr_succ instr) env state

let find_starting_point initial =
  let starting =
    Memory.find_first_opt
      (function
        | Location.Variable v -> Llvm.value_name v = "main" | _ -> false)
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

module GraphViz = Graph.Graphviz.Dot (DUGraph)

let dump_dugraph env =
  List.iteri
    (fun idx g ->
      let oc = open_out ("dugraph" ^ string_of_int idx ^ ".dot") in
      GraphViz.output_graph oc g)
    env.Environment.dugraphs

let main input_file =
  let llctx = Llvm.create_context () in
  let llmem = Llvm.MemoryBuffer.of_file input_file in
  let llm = Llvm_bitreader.parse_bitcode llctx llmem in
  let initial_state = initialize llm State.empty in
  let main_function = find_starting_point initial_state in
  let env =
    execute_function llctx main_function Environment.empty initial_state
  in
  print_report env ; dump_traces llctx env ; dump_dugraph env
