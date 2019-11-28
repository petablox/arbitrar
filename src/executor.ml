open Semantics

module Worklist = struct
  type t = (Llvm.llbasicblock * State.t) list

  and instr_iterator = (Llvm.llbasicblock, Llvm.llvalue) Llvm.llpos

  let empty = []

  let push x s = s @ [x]

  let pop = function x :: s -> (x, s) | [] -> failwith "empty worklist"

  let is_empty s = s = []

  let length = List.length
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

module Metadata = struct
  type t = {num_explored: int; num_target_unvisited: int; num_duplicated: int}

  let empty = {num_explored= 0; num_target_unvisited= 0; num_duplicated= 0}

  let incr_explored meta = {meta with num_explored= meta.num_explored + 1}

  let incr_duplicated meta =
    { meta with
      num_duplicated= meta.num_duplicated + 1
    ; num_explored= meta.num_explored + 1 }

  let incr_target_unvisited meta =
    { meta with
      num_target_unvisited= meta.num_target_unvisited + 1
    ; num_explored= meta.num_explored + 1 }

  let merge m1 m2 =
    { num_explored= m1.num_explored + m2.num_explored
    ; num_target_unvisited= m1.num_target_unvisited + m2.num_target_unvisited
    ; num_duplicated= m1.num_duplicated + m2.num_duplicated }

  let to_json meta =
    `Assoc
      [ ("num_traces", `Int meta.num_explored)
      ; ("target_unvisited", `Int meta.num_target_unvisited)
      ; ("duplicated", `Int meta.num_duplicated) ]

  let print oc meta =
    let viable =
      meta.num_explored - meta.num_target_unvisited - meta.num_duplicated
    in
    Printf.fprintf oc "Metadata:\n" ;
    Printf.fprintf oc "# Explored Traces: %d\n" meta.num_explored ;
    Printf.fprintf oc "# Viable Traces: %d\n" viable ;
    Printf.fprintf oc "# Target-Unvisited Traces: %d\n"
      meta.num_target_unvisited ;
    Printf.fprintf oc "# Duplicated Traces: %d\n" meta.num_duplicated
end

module GraphViz = Graph.Graphviz.Dot (DUGraph)
module Path = Graph.Path.Check (DUGraph)

module Environment = struct
  type t =
    { metadata: Metadata.t
    ; initial_state: State.t
    ; worklist: Worklist.t
    ; traces: Traces.t
    ; dugraphs: DUGraph.t list
    ; boundaries: Llvm.llvalue list }

  let empty =
    { metadata= Metadata.empty
    ; initial_state= State.empty
    ; worklist= Worklist.empty
    ; traces= Traces.empty
    ; dugraphs= []
    ; boundaries= [] }

  let add_trace trace env = {env with traces= Traces.add trace env.traces}

  let add_work work env = {env with worklist= Worklist.push work env.worklist}

  let add_dugraph g env = {env with dugraphs= g :: env.dugraphs}

  let should_include g1 env : bool =
    if not !Options.no_control_flow then true
    else if !Options.no_filter_duplication then true
    else
      List.find_opt
        (fun g2 ->
          (* Check if the size are equal and if not, directly return false *)
          if DUGraph.nb_vertex g1 = DUGraph.nb_vertex g2 then
            (* Check if every vertex in g1 is contained in g2 *)
            DUGraph.fold_vertex
              (fun g1_vertex acc -> acc && DUGraph.mem_vertex g2 g1_vertex)
              g1 true
          else false)
        env.dugraphs
      |> Option.is_none
end

let initialize llctx llm state =
  Llvm.fold_left_functions
    (fun state func ->
      State.add_memory (Location.variable func) (Value.func func) state)
    state llm

let need_step_into_function boundaries f : bool =
  let dec_only = Llvm.is_declaration f in
  let in_bound = List.find_opt (( == ) f) boundaries |> Option.is_some in
  let is_debug = Utils.is_llvm_function f in
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
  | Argument | GlobalVariable ->
      Location.variable exp
  | _ ->
      Location.unknown

let add_syntactic_du_edge instr env state =
  let numop = Llvm.num_operands instr in
  let rec loop i state =
    if i < numop then
      let use = Llvm.operand_use instr i in
      let v = Llvm.used_value use in
      let state =
        if Llvm.is_constant v || Llvm.value_is_block v || Utils.is_argument v
        then state
        else try State.add_du_edge v instr state with Not_found -> state
      in
      loop (i + 1) state
    else state
  in
  loop 0 state

let mark_visit_target instr state =
  match state.State.target with
  | Some t when t = instr ->
      State.visit_target state
  | _ ->
      state

let rec execute_function llctx f env state =
  let entry = Llvm.entry_block f in
  execute_block llctx entry env state

and execute_block llctx blk env state =
  let instr = Llvm.instr_begin blk in
  execute_instr llctx instr env state

and execute_instr llctx instr env state =
  match instr with
  | Llvm.At_end _ ->
      finish_execution llctx env state
  | Llvm.Before instr ->
      transfer llctx instr env state

and transfer llctx instr env state =
  if !Options.verbose > 1 then prerr_endline (Utils.string_of_instr instr) ;
  if Trace.length state.State.trace > !Options.max_length then
    finish_execution llctx env state
  else
    let state = mark_visit_target instr state in
    match Llvm.instr_opcode instr with
    | Llvm.Opcode.Ret -> (
        let state =
          State.add_trace llctx instr state |> add_syntactic_du_edge instr env
        in
        match State.pop_stack state with
        | Some (callsite, state) ->
            let lv = eval_lv callsite state.State.memory in
            State.add_reaching_def lv instr state
            |> execute_instr llctx (Llvm.instr_succ callsite) env
        | None ->
            execute_instr llctx (Llvm.instr_succ instr) env state )
    | Br -> (
        let state =
          State.add_trace llctx instr state |> add_syntactic_du_edge instr env
        in
        match Llvm.get_branch instr with
        | Some (`Conditional (_, b1, b2)) ->
            let b1_visited = BlockSet.mem b1 state.State.visited_blocks in
            let b2_visited = BlockSet.mem b2 state.State.visited_blocks in
            if b1_visited && b2_visited then finish_execution llctx env state
            else if b1_visited then
              let state = State.visit_block b2 state in
              execute_block llctx b2 env state
            else if b2_visited then
              let state = State.visit_block b1 state in
              execute_block llctx b1 env state
            else
              let new_state = State.visit_block b2 state in
              let env = Environment.add_work (b2, new_state) env in
              let state = State.visit_block b1 state in
              execute_block llctx b1 env state
        | Some (`Unconditional b) ->
            let visited = BlockSet.mem b state.State.visited_blocks in
            if visited then finish_execution llctx env state
            else
              let state = State.visit_block b state in
              execute_block llctx b env state
        | _ ->
            prerr_endline "warning: unknown branch" ;
            execute_instr llctx (Llvm.instr_succ instr) env state )
    | Switch ->
        let state =
          State.add_trace llctx instr state |> add_syntactic_du_edge instr env
        in
        execute_instr llctx (Llvm.instr_succ instr) env state
    | Call ->
        transfer_call llctx instr env state
    | Alloca ->
        let var = Location.variable instr in
        let addr = Location.new_address () |> Value.location in
        State.add_trace llctx instr state
        |> add_syntactic_du_edge instr env
        |> State.add_memory_def var addr instr
        |> execute_instr llctx (Llvm.instr_succ instr) env
    | Store ->
        let exp0 = Llvm.operand instr 0 in
        let exp1 = Llvm.operand instr 1 in
        let v0, uses0 = eval exp0 state.State.memory in
        let v1, uses1 = eval exp1 state.State.memory in
        let lv =
          match v1 with Value.Location l -> l | _ -> Location.Unknown
        in
        State.add_trace llctx instr state
        |> add_syntactic_du_edge instr env
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
        |> add_syntactic_du_edge instr env
        |> State.add_memory_def lv v1 instr
        |> State.add_semantic_du_edges [lv1] instr
        |> execute_instr llctx (Llvm.instr_succ instr) env
    | x when Utils.is_binary_op x ->
        let exp0 = Llvm.operand instr 0 in
        let exp1 = Llvm.operand instr 1 in
        let _, uses0 = eval exp0 state.State.memory in
        let _, uses1 = eval exp1 state.State.memory in
        State.add_trace llctx instr state
        |> add_syntactic_du_edge instr env
        |> State.add_semantic_du_edges (uses0 @ uses1) instr
        |> execute_instr llctx (Llvm.instr_succ instr) env
    | x when Utils.is_unary_op x ->
        let exp0 = Llvm.operand instr 0 in
        let _, uses0 = eval exp0 state.State.memory in
        State.add_trace llctx instr state
        |> add_syntactic_du_edge instr env
        |> State.add_semantic_du_edges uses0 instr
        |> execute_instr llctx (Llvm.instr_succ instr) env
    | x ->
        State.add_trace llctx instr state
        |> add_syntactic_du_edge instr env
        (* Note: Maybe expand *)
        |> execute_instr llctx (Llvm.instr_succ instr) env

and transfer_call llctx instr env state =
  let callee_expr = Llvm.operand instr (Llvm.num_operands instr - 1) in
  let var = Location.variable callee_expr in
  let boundaries = env.boundaries in
  match Memory.find var state.State.memory with
  | Value.Function f when Utils.is_llvm_function f ->
      execute_instr llctx (Llvm.instr_succ instr) env state
  | Value.Function f
    when need_step_into_function boundaries f
         && not (FuncSet.mem callee_expr state.visited_funcs) ->
      let state = State.visit_func callee_expr state in
      let state = State.add_trace llctx instr state in
      let state, _ =
        Llvm.fold_left_params
          (fun (state, count) param ->
            let arg = Llvm.operand instr count in
            let v, uses = eval arg state.State.memory in
            let lv = eval_lv param state.State.memory in
            let state =
              State.add_memory_def lv v instr state
              |> State.add_semantic_du_edges uses instr
            in
            (state, count + 1))
          (state, 0) f
      in
      let state = State.push_stack instr state in
      execute_function llctx f env state
  | _ ->
      State.add_trace llctx instr state
      |> add_syntactic_du_edge instr env
      |> execute_instr llctx (Llvm.instr_succ instr) env
  | exception Not_found ->
      Llvm.dump_value callee_expr ;
      failwith "not found"

and finish_execution llctx env state =
  let target_visited = state.target_visited in
  let env =
    if target_visited then
      if Environment.should_include state.dugraph env then
        let env =
          Environment.add_trace state.State.trace env
          |> Environment.add_dugraph state.dugraph
        in
        {env with metadata= Metadata.incr_explored env.metadata}
      else {env with metadata= Metadata.incr_duplicated env.metadata}
    else {env with metadata= Metadata.incr_target_unvisited env.metadata}
  in
  if !Options.verbose > 2 then (
    Memory.pp F.err_formatter state.State.memory ;
    ReachingDef.pp F.err_formatter state.State.reachingdef ) ;
  let out_of_traces =
    Traces.length env.Environment.traces >= !Options.max_traces
  in
  let out_of_explored = env.metadata.num_explored > !Options.max_trials in
  if Worklist.is_empty env.worklist || out_of_traces || out_of_explored then
    env
  else
    let (blk, state), wl = Worklist.pop env.worklist in
    execute_block llctx blk {env with worklist= wl} state

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

let print_report oc env =
  Printf.fprintf oc "# Traces: %d\n" (Traces.length env.Environment.traces)

let dump_traces ?(prefix = "") env =
  let json = Traces.to_json env.Environment.traces in
  let oc = open_out (prefix ^ "traces.json") in
  Yojson.Safe.pretty_to_channel oc json ;
  close_out oc

let dump_dots ?(prefix = "") env =
  List.iteri
    (fun idx g ->
      let oc = open_out (prefix ^ string_of_int idx ^ "-" ^ "dugraph.dot") in
      GraphViz.output_graph oc g ; close_out oc)
    env.Environment.dugraphs

let dump_dugraphs ?(prefix = "") env =
  let json = List.map DUGraph.to_json env.Environment.dugraphs in
  let oc = open_out (prefix ^ "dugraph.json") in
  Yojson.Safe.pretty_to_channel oc (`List json) ;
  close_out oc
