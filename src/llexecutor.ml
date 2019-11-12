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

  let to_json t =
    let l = List.map Trace.to_json t in
    `List l
end

module Environment = struct
  type t =
    { worklist: Worklist.t
    ; traces: Traces.t
    ; dugraphs: DUGraph.t list
    ; boundaries: Llvm.llvalue list }

  let empty =
    { worklist= Worklist.empty
    ; traces= Traces.empty
    ; dugraphs= []
    ; boundaries= [] }

  let add_trace trace env = {env with traces= Traces.add trace env.traces}

  let add_work work env = {env with worklist= Worklist.push work env.worklist}

  let add_dugraph g env = {env with dugraphs= g :: env.dugraphs}
end

let initialize llctx llm state =
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
              (fun state instr ->
                let is_target =
                  match state.State.target with
                  | Some s ->
                      s = instr
                  | None ->
                      false
                in
                State.add_node llctx instr is_target state)
              state blk)
          state func)
    state llm

let is_debug_function f : bool =
  let r = Str.regexp "llvm\\.dbg\\..+" in
  Str.string_match r (Llvm.value_name f) 0

let need_step_into_function boundaries f : bool =
  let dec_only = Llvm.is_declaration f in
  let in_bound = List.find_opt (( == ) f) boundaries |> Option.is_some in
  let is_debug = is_debug_function f in
  (not dec_only) && in_bound && not is_debug

let eval exp memory =
  let kind = Llvm.classify_value exp in
  match kind with
  | Llvm.ValueKind.ConstantInt -> (
    match Llvm.int64_of_const exp with
    | Some i ->
        (Value.Int i, [])
    | None ->
        (Value.Unknown, []) )
  | Instruction _ | Argument ->
      let lv = Location.variable exp in
      (Memory.find lv memory, [lv])
  | _ ->
      (Value.Unknown, [])

let eval_lv exp memory =
  let kind = Llvm.classify_value exp in
  match kind with
  | Llvm.ValueKind.Instruction _ ->
      Location.variable exp
  | Argument ->
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
      if !Options.debug then (
        Memory.pp F.err_formatter state.State.memory ;
        ReachingDef.pp F.err_formatter state.State.reachingdef ) ;
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
      let state = State.add_trace llctx instr state in
      match State.pop_stack state with
      | Some (callsite, state) ->
          execute_instr llctx (Llvm.instr_succ callsite) env state
      | None ->
          execute_instr llctx (Llvm.instr_succ instr) env state )
  | Br -> (
      let state = State.add_trace llctx instr state in
      match Llvm.get_branch instr with
      | Some (`Conditional (_, b1, b2)) ->
          let b1_visited = BlockSet.mem b1 state.State.visited in
          let b2_visited = BlockSet.mem b2 state.State.visited in
          if b1_visited && b2_visited then env
          else if b1_visited then execute_block llctx b2 env state
          else if b2_visited then execute_block llctx b1 env state
          else
            let env = Environment.add_work (b2, state) env in
            let state = State.visit b1 state in
            execute_block llctx b1 env state
      | Some (`Unconditional b) ->
          execute_block llctx b env state
      | _ ->
          prerr_endline "warning: unknown branch" ;
          execute_instr llctx (Llvm.instr_succ instr) env state )
  | Switch ->
      let state = State.add_trace llctx instr state in
      execute_instr llctx (Llvm.instr_succ instr) env state
  | Call ->
      transfer_call llctx instr env state
  | Alloca ->
      let var = Location.variable instr in
      let addr = Location.new_address () |> Value.location in
      State.add_trace llctx instr state
      |> State.add_memory_def var addr instr
      |> execute_instr llctx (Llvm.instr_succ instr) env
  | Store ->
      let exp0 = Llvm.operand instr 0 in
      let exp1 = Llvm.operand instr 1 in
      let v0, uses0 = eval exp0 state.State.memory in
      let v1, uses1 = eval exp1 state.State.memory in
      let lv = match v1 with Value.Location l -> l | _ -> Location.Unknown in
      State.add_trace llctx instr state
      |> State.add_memory_def lv v0 instr
      |> State.add_semantic_du_edges (uses0 @ uses1) instr
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
      State.add_trace llctx instr state
      |> State.add_memory_def lv v1 instr
      |> State.add_semantic_du_edges [lv1] instr
      |> execute_instr llctx (Llvm.instr_succ instr) env
  | x ->
      let state = State.add_trace llctx instr state in
      execute_instr llctx (Llvm.instr_succ instr) env state

and transfer_call llctx instr env state =
  let callee_expr = Llvm.operand instr (Llvm.num_operands instr - 1) in
  let var = Location.variable callee_expr in
  let boundaries = env.boundaries in
  match Memory.find var state.State.memory with
  | Value.Function f when is_debug_function f ->
      execute_instr llctx (Llvm.instr_succ instr) env state
  | Value.Function f when need_step_into_function boundaries f ->
      let state, _ =
        Llvm.fold_left_params
          (fun (state, count) param ->
            let arg = Llvm.operand instr count in
            let v, uses = eval arg state.State.memory in
            let lv = eval_lv param state.State.memory in
            let state = State.add_memory_def lv v instr state in
            (state, count + 1))
          (state, 0) f
      in
      let state = State.add_trace llctx instr state in
      let state = State.push_stack instr state in
      execute_function llctx f env state
  | _ ->
      let state = State.add_trace llctx instr state in
      execute_instr llctx (Llvm.instr_succ instr) env state
  | exception Not_found ->
      Llvm.dump_value callee_expr ;
      failwith "not found"

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

let find_target_instr llm =
  let instrs =
    Utils.fold_left_all_instr
      (fun instrs instr ->
        let opcode = Llvm.instr_opcode instr in
        match opcode with
        | Llvm.Opcode.Call ->
            let callee = Llvm.operand instr (Llvm.num_operands instr - 1) in
            if Llvm.value_name callee = "malloc" then instr :: instrs
            else instrs
        | _ ->
            instrs)
      [] llm
  in
  match instrs with h :: t -> Some h | [] -> None

let print_report env =
  Printf.printf "# Traces: %d\n" (Traces.length env.Environment.traces)

let dump_traces ?(prefix = "") env =
  let json = Traces.to_json env.Environment.traces in
  let oc = open_out (prefix ^ "traces.json") in
  Yojson.Safe.pretty_to_channel oc json

module GraphViz = Graph.Graphviz.Dot (DUGraph)
module Path = Graph.Path.Check (DUGraph)

let slice target g =
  let checker = Path.create g in
  if not (DUGraph.mem_vertex g target) then g
  else
    DUGraph.fold_vertex
      (fun v g ->
        if Llvm.instr_opcode v.Node.stmt.Stmt.instr = Llvm.Opcode.Alloca then
          DUGraph.remove_vertex g v
        else if
          (not (Path.check_path checker v target))
          && not (Path.check_path checker target v)
        then DUGraph.remove_vertex g v
        else g)
      g g

let dump_dugraph ?(prefix = "") env =
  List.iteri
    (fun idx g ->
      let oc = open_out (prefix ^ string_of_int idx ^ "-" ^ "dugraph.dot") in
      GraphViz.output_graph oc g)
    env.Environment.dugraphs ;
  let json =
    List.fold_left
      (fun l g -> DUGraph.to_json g :: l)
      [] env.Environment.dugraphs
  in
  let oc = open_out (prefix ^ "dugraph.json") in
  Yojson.Safe.pretty_to_channel oc (`List json)

let main input_file =
  let llctx = Llvm.create_context () in
  let llmem = Llvm.MemoryBuffer.of_file input_file in
  let llm = Llvm_bitreader.parse_bitcode llctx llmem in
  let target = find_target_instr llm in
  let initial_state = initialize llctx llm {State.empty with target} in
  let main_function = find_starting_point initial_state in
  let env =
    execute_function llctx main_function Environment.empty initial_state
  in
  let dugraphs =
    match target with
    | Some instr ->
        let target_node = NodeMap.find instr initial_state.State.nodemap in
        List.map (slice target_node) env.dugraphs
    | None ->
        env.dugraphs
  in
  let env = {env with dugraphs} in
  print_report env ; dump_traces env ; dump_dugraph env
