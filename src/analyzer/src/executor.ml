open Semantics

module Worklist = struct
  type t = (Llvm.llbasicblock * State.t) Queue.t

  let empty () = Queue.create ()

  let push x s = Queue.push x s ; s

  let pop s =
    let x = Queue.pop s in
    (x, s)

  let is_empty = Queue.is_empty

  let length = Queue.length
end

module Traces = struct
  type t = Trace.t list

  let empty = []

  let add x s = x :: s

  let length = List.length

  let to_json cache t =
    let l = List.map (Trace.to_json cache) t in
    `List l
end

module Metadata = struct
  type t =
    { num_explored: int
    ; num_target_unvisited: int
    ; num_duplicated: int
    ; num_graph_nodes: int
    ; num_graph_edges: int }

  let empty =
    { num_explored= 0
    ; num_target_unvisited= 0
    ; num_duplicated= 0
    ; num_graph_nodes= 0
    ; num_graph_edges= 0 }

  let incr_explored meta = {meta with num_explored= meta.num_explored + 1}

  let incr_graph g meta =
    { meta with
      num_graph_nodes= DUGraph.nb_vertex g + meta.num_graph_nodes
    ; num_graph_edges= DUGraph.nb_edges g + meta.num_graph_edges }

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
    ; num_duplicated= m1.num_duplicated + m2.num_duplicated
    ; num_graph_nodes= m1.num_graph_nodes + m2.num_graph_nodes
    ; num_graph_edges= m1.num_graph_edges + m2.num_graph_edges }

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
    Printf.fprintf oc "# Duplicated Traces: %d\n" meta.num_duplicated ;
    Printf.fprintf oc "# Avg # nodes: %d\n" (meta.num_graph_nodes / viable) ;
    Printf.fprintf oc "# Avg # edges: %d\n" (meta.num_graph_edges / viable)
end

module GraphViz = Graph.Graphviz.Dot (DUGraph)
module Path = Graph.Path.Check (DUGraph)

module Environment = struct
  type t =
    { metadata: Metadata.t
    ; initial_state: State.t
    ; worklist: Worklist.t
    ; traces: Traces.t
    ; target: Llvm.llvalue
    ; dugraphs: DUGraph.t list
    ; boundaries: Llvm.llvalue list
    ; cache: Utils.EnvCache.t }

  let empty target =
    { metadata= Metadata.empty
    ; initial_state= State.empty
    ; worklist= Worklist.empty ()
    ; traces= Traces.empty
    ; target
    ; dugraphs= []
    ; boundaries= []
    ; cache= Utils.EnvCache.empty () }

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

let need_step_into_function boundaries target f : bool =
  let dec_only = Llvm.is_declaration f in
  let in_bound = List.find_opt (( == ) f) boundaries |> Option.is_some in
  let is_debug = Utils.is_llvm_function f in
  let is_target = f == target in
  (not dec_only) && in_bound && (not is_debug) && not is_target

let eval cache exp memory =
  let kind = Llvm.classify_value exp in
  match kind with
  | Llvm.ValueKind.ConstantInt -> (
    match Llvm.int64_of_const exp with
    | Some i ->
        (Value.Int i, [])
    | None ->
        (Value.Unknown, []) )
  | Argument ->
      (Value.Argument (Utils.EnvCache.arg_id cache exp), [])
  | NullValue | ConstantPointerNull ->
      (Value.Int Int64.zero, [])
  | Instruction _ (* | Argument *) ->
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

let semantic_sig_of_binop cache res v0 v1 =
  let result_json = Value.to_json cache res in
  let v0_json = Value.to_json cache v0 in
  let v1_json = Value.to_json cache v1 in
  `Assoc
    [("result_sem", result_json); ("op0_sem", v0_json); ("op1_sem", v1_json)]

let semantic_sig_of_store cache v0 v1 =
  let v0_json = Value.to_json cache v0 in
  let v1_json = Value.to_json cache v1 in
  `Assoc [("op0_sem", v0_json); ("op1_sem", v1_json)]

let semantic_sig_of_unop cache result op0 =
  let result_json = Value.to_json cache result in
  let op0_json = Value.to_json cache op0 in
  `Assoc [("result_sem", result_json); ("op0_sem", op0_json)]

let semantic_sig_of_libcall cache v args =
  let ret_json =
    match v with Some s -> Value.to_json cache s | None -> `Null
  in
  let args_json = List.map (Value.to_json cache) args in
  `Assoc [("result_sem", ret_json); ("args_sem", `List args_json)]

let semantic_sig_of_call cache args =
  let args_json = List.map (Value.to_json cache) args in
  `Assoc [("args_sem", `List args_json)]

let semantic_sig_of_return cache i =
  match i with
  | Some v ->
      `Assoc [("op0_sem", Value.to_json cache v)]
  | None ->
      `Assoc [("op0_sem", `Null)]

let semantic_sig_of_br cache i =
  match i with
  | Some (v, br) ->
      `Assoc [("cond_sem", Value.to_json cache v); ("then_br", `Bool br)]
  | None ->
      `Assoc [("cond_sem", `Null)]

let semantic_sig_of_gep cache result op0 =
  let result_json = Value.to_json cache result in
  let op0_json = Value.to_json cache op0 in
  `Assoc [("result_sem", result_json); ("op0_sem", op0_json)]

let semantic_sig_of_phi cache ret =
  let ret_json = Value.to_json cache ret in
  `Assoc [("return_sem", ret_json)]

let rec find_viable_control_succ v orig newg =
  let succ_controls_old = DUGraph.succ_control orig v in
  if List.length succ_controls_old = 1 then
    let candidate = List.hd succ_controls_old in
    if DUGraph.mem_vertex newg candidate then Some candidate
    else find_viable_control_succ candidate orig newg
  else None

let reduce_dugraph target orig =
  let du_projection = DUGraph.du_project orig in
  let du_checker = Path.create du_projection in
  (* filter out du-unrechable nodes *)
  let directly_connected_g =
    DUGraph.fold_vertex
      (fun v g ->
        if
          Path.check_path du_checker v target
          || Path.check_path du_checker target v
        then g
        else DUGraph.remove_vertex g v)
      orig orig
  in
  (* add back nodes that are reachable from any current node *)
  let forward_connected_g =
    DUGraph.fold_vertex
      (fun v g ->
        let is_forward_connected =
          DUGraph.fold_vertex
            (fun v_p connected ->
              if connected then true else Path.check_path du_checker v_p v)
            g false
        in
        if is_forward_connected then DUGraph.add_vertex g v else g)
      orig directly_connected_g
  in
  (* restore du edges *)
  let du_restored_g =
    DUGraph.fold_edges_e
      (fun edge g ->
        match DUGraph.E.label edge with
        | DUGraph.Edge.Data ->
            let src = DUGraph.E.src edge in
            let dst = DUGraph.E.src edge in
            if DUGraph.mem_vertex g src && DUGraph.mem_vertex g dst then
              DUGraph.add_edge_e g edge
            else g
        | _ ->
            g)
      orig forward_connected_g
  in
  (* restore cf edges *)
  DUGraph.fold_vertex
    (fun v g ->
      let succ_controls_old = DUGraph.succ_control orig v in
      let succ_controls_new = DUGraph.succ_control g v in
      if List.length succ_controls_old = 1 && List.length succ_controls_new = 0
      then
        match find_viable_control_succ v orig g with
        | Some succ ->
            DUGraph.add_edge_e g (v, DUGraph.Edge.Control, succ)
        | None ->
            g
      else g)
    du_restored_g du_restored_g

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
  if !Options.verbose > 1 then
    prerr_endline (Utils.EnvCache.string_of_exp env.Environment.cache instr) ;
  if Trace.length state.State.trace > !Options.max_length then
    finish_execution llctx env state
  else
    match Llvm.instr_opcode instr with
    | Llvm.Opcode.Ret ->
        transfer_ret llctx instr env state
    | Br ->
        transfer_br llctx instr env state
    | Switch ->
        let semantic_sig = `Assoc [] in
        State.add_trace env.Environment.cache llctx instr semantic_sig state
        |> add_syntactic_du_edge instr env
        |> execute_instr llctx (Llvm.instr_succ instr) env
    | Call ->
        transfer_call llctx instr env state
    | Alloca ->
        let var = Location.variable instr in
        let addr = Location.new_address () |> Value.location in
        let semantic_sig = semantic_sig_of_unop env.cache addr Value.unknown in
        State.add_trace env.cache llctx instr semantic_sig state
        |> add_syntactic_du_edge instr env
        |> State.add_memory_def var addr instr
        |> execute_instr llctx (Llvm.instr_succ instr) env
    | Store ->
        let exp0 = Llvm.operand instr 0 in
        let exp1 = Llvm.operand instr 1 in
        let v0, uses0 = eval env.cache exp0 state.State.memory in
        let v1, uses1 = eval env.cache exp1 state.State.memory in
        let lv, v1, state =
          match v1 with
          | Value.Location l ->
              (l, v1, state)
          | Value.SymExpr s ->
              (Location.symexpr s, v1, state)
          | _ ->
              let l = Location.new_symbol () in
              ( l
              , Value.location l
              , State.add_memory
                  (eval_lv exp1 state.State.memory)
                  (Value.location l) state )
        in
        let semantic_sig = semantic_sig_of_store env.cache v0 v1 in
        State.add_trace env.cache llctx instr semantic_sig state
        |> add_syntactic_du_edge instr env
        |> State.add_memory_def lv v0 instr
        |> State.add_semantic_du_edges (uses0 @ uses1) instr
        |> execute_instr llctx (Llvm.instr_succ instr) env
    | Load ->
        let exp0 = Llvm.operand instr 0 in
        let lv0 = eval_lv exp0 state.State.memory in
        let v0 = Memory.find lv0 state.State.memory in
        let lv1, state =
          match v0 with
          | Value.Location l ->
              (l, state)
          | _ ->
              let l = Location.new_symbol () in
              (l, State.add_memory lv0 (Value.location l) state)
        in
        let v1 = Memory.find lv1 state.State.memory in
        let lv = eval_lv instr state.State.memory in
        let semantic_sig =
          semantic_sig_of_unop env.cache v1 (Value.location lv1)
        in
        State.add_trace env.cache llctx instr semantic_sig state
        |> add_syntactic_du_edge instr env
        |> State.add_memory_def lv v1 instr
        |> State.add_semantic_du_edges [lv1] instr
        |> execute_instr llctx (Llvm.instr_succ instr) env
    | PHI ->
        transfer_phi llctx instr env state
    | x when Utils.is_binary_op x ->
        transfer_binop llctx instr env state
    | x when Utils.is_unary_op x ->
        (* Casting operators *)
        let exp0 = Llvm.operand instr 0 in
        let v0, uses0 = eval env.cache exp0 state.State.memory in
        let lv = eval_lv instr state.State.memory in
        let semantic_sig = semantic_sig_of_unop env.cache v0 v0 in
        State.add_trace env.cache llctx instr semantic_sig state
        |> add_syntactic_du_edge instr env
        |> State.add_memory lv v0
        |> State.add_semantic_du_edges uses0 instr
        |> execute_instr llctx (Llvm.instr_succ instr) env
    | GetElementPtr ->
        let exp0 = Llvm.operand instr 0 in
        let v0, uses0 = eval env.cache exp0 state.State.memory in
        let lv = eval_lv instr state.State.memory in
        let v, state =
          match v0 with
          | Value.Location l ->
              (Location.gep_of l |> Value.location, state)
          | Value.SymExpr s ->
              (Location.symexpr s |> Location.gep_of |> Value.location, state)
          | Value.Argument i ->
              (Location.argument i |> Location.gep_of |> Value.location, state)
          | _ ->
              let l = Location.new_symbol () in
              ( Value.location l
              , State.add_memory
                  (eval_lv exp0 state.State.memory)
                  (Value.location l) state )
        in
        let semantic_sig = semantic_sig_of_gep env.cache v v0 in
        State.add_trace env.cache llctx instr semantic_sig state
        |> add_syntactic_du_edge instr env
        |> State.add_memory lv v
        |> State.add_semantic_du_edges uses0 instr
        |> execute_instr llctx (Llvm.instr_succ instr) env
    | x ->
        let semantic_sig = `Assoc [] in
        State.add_trace env.cache llctx instr semantic_sig state
        |> add_syntactic_du_edge instr env
        (* Note: Maybe expand *)
        |> execute_instr llctx (Llvm.instr_succ instr) env

and transfer_ret llctx instr env state =
  match State.pop_stack state with
  | Some (callsite, state) ->
      let lv = eval_lv callsite state.State.memory in
      let exp0 = Llvm.operand instr 0 in
      let v, _ = eval env.cache exp0 state.State.memory in
      let semantic_sig = semantic_sig_of_return env.cache (Some v) in
      State.add_trace env.cache llctx instr semantic_sig state
      |> add_syntactic_du_edge instr env
      |> State.add_memory_def lv v instr
      |> execute_instr llctx (Llvm.instr_succ callsite) env
  | None ->
      let semantic_sig =
        if Llvm.num_operands instr = 0 then
          semantic_sig_of_return env.cache None
        else
          let exp0 = Llvm.operand instr 0 in
          let v, _ = eval env.cache exp0 state.State.memory in
          semantic_sig_of_return env.cache (Some v)
      in
      State.add_trace env.cache llctx instr semantic_sig state
      |> add_syntactic_du_edge instr env
      |> execute_instr llctx (Llvm.instr_succ instr) env

and transfer_br llctx instr env state =
  let state = {state with State.prev_blk= Some (Llvm.instr_parent instr)} in
  match Llvm.get_branch instr with
  | Some (`Conditional (cond, b1, b2)) ->
      let v, _ = eval env.cache cond state.State.memory in
      let get_state br =
        let semantic_sig = semantic_sig_of_br env.cache (Some (v, br)) in
        State.add_trace env.cache llctx instr semantic_sig state
        |> add_syntactic_du_edge instr env
      in
      let b1_visited = BlockSet.mem b1 state.State.visited_blocks in
      let b2_visited = BlockSet.mem b2 state.State.visited_blocks in
      if b1_visited && b2_visited then finish_execution llctx env state
      else if b1_visited then
        let state = State.visit_block b2 (get_state false) in
        execute_block llctx b2 env state
      else if b2_visited then
        let state = State.visit_block b1 (get_state true) in
        execute_block llctx b1 env state
      else
        let b2_state = State.visit_block b2 (get_state false) in
        let env = Environment.add_work (b2, b2_state) env in
        let state = State.visit_block b1 (get_state true) in
        execute_block llctx b1 env state
  | Some (`Unconditional b) ->
      let semantic_sig = semantic_sig_of_br env.cache None in
      let state =
        State.add_trace env.cache llctx instr semantic_sig state
        |> add_syntactic_du_edge instr env
      in
      let visited = BlockSet.mem b state.State.visited_blocks in
      if visited then finish_execution llctx env state
      else
        let state = State.visit_block b state in
        execute_block llctx b env state
  | _ ->
      prerr_endline "warning: unknown branch" ;
      execute_instr llctx (Llvm.instr_succ instr) env state

and transfer_phi llctx instr env state =
  let prev_blk = Option.get state.State.prev_blk in
  let incoming =
    Llvm.incoming instr |> List.find (fun (v, blk) -> prev_blk == blk) |> fst
  in
  let v, uses = eval env.cache incoming state.State.memory in
  let lv = eval_lv instr state.State.memory in
  let semantic_sig = semantic_sig_of_phi env.cache v in
  State.add_trace env.cache llctx instr semantic_sig state
  |> add_syntactic_du_edge instr env
  |> State.add_memory lv v
  |> State.add_semantic_du_edges uses instr
  |> execute_instr llctx (Llvm.instr_succ instr) env

and transfer_call llctx instr env state =
  let callee_expr = Llvm.operand instr (Llvm.num_operands instr - 1) in
  let var = Location.variable callee_expr in
  let boundaries = env.boundaries in
  match Memory.find var state.State.memory with
  | Value.Function f when Utils.is_llvm_function f ->
      execute_instr llctx (Llvm.instr_succ instr) env state
  | Value.Function f
    when need_step_into_function boundaries env.target f
         && not (FuncSet.mem callee_expr state.visited_funcs) ->
      let state, args, uses, _ =
        Llvm.fold_left_params
          (fun (state, args, uses, count) param ->
            let arg = Llvm.operand instr count in
            let v, ul = eval env.cache arg state.State.memory in
            let lv = eval_lv param state.State.memory in
            let state = State.add_memory_def lv v instr state in
            (state, args @ [v], uses @ ul, count + 1))
          (state, [], [], 0) f
      in
      let semantic_sig = semantic_sig_of_call env.cache args in
      State.visit_func callee_expr state
      |> State.add_trace env.cache llctx instr semantic_sig
      |> State.add_semantic_du_edges uses instr
      |> add_syntactic_du_edge instr env
      |> State.push_stack instr
      |> execute_function llctx f env
  | Value.Function f
    when Llvm.type_of f |> Llvm.return_type |> Utils.is_void_type |> not ->
      let lv = eval_lv instr state.State.memory in
      let args =
        List.init
          (Llvm.num_operands instr - 1)
          (fun i ->
            let arg = Llvm.operand instr i in
            eval env.cache arg state.State.memory |> fst)
      in
      let v =
        SymExpr.new_ret (Llvm.value_name f) (List.map Value.to_symexpr args)
        |> Value.of_symexpr
      in
      let semantic_sig = semantic_sig_of_libcall env.cache (Some v) args in
      State.add_trace env.cache llctx instr semantic_sig state
      |> State.add_memory lv v
      |> add_syntactic_du_edge instr env
      |> execute_instr llctx (Llvm.instr_succ instr) env
  | _ ->
      let args =
        List.init
          (Llvm.num_operands instr - 1)
          (fun i ->
            let arg = Llvm.operand instr i in
            eval env.cache arg state.State.memory |> fst)
      in
      let semantic_sig = semantic_sig_of_libcall env.cache None args in
      State.add_trace env.cache llctx instr semantic_sig state
      |> add_syntactic_du_edge instr env
      |> execute_instr llctx (Llvm.instr_succ instr) env
  | exception Not_found ->
      Llvm.dump_value callee_expr ;
      failwith "not found"

and transfer_binop llctx instr env state =
  let exp0 = Llvm.operand instr 0 in
  let exp1 = Llvm.operand instr 1 in
  let v0, uses0 = eval env.cache exp0 state.State.memory in
  let v1, uses1 = eval env.cache exp1 state.State.memory in
  let res_lv = eval_lv instr state in
  let res = Value.binary_op (Llvm.instr_opcode instr) v0 v1 in
  let semantic_sig = semantic_sig_of_binop env.cache res v0 v1 in
  State.add_trace env.cache llctx instr semantic_sig state
  |> State.add_memory res_lv res
  |> add_syntactic_du_edge instr env
  |> State.add_semantic_du_edges (uses0 @ uses1) instr
  |> execute_instr llctx (Llvm.instr_succ instr) env

and finish_execution llctx env state =
  let target_visited = state.target_node <> None in
  let env =
    if target_visited then
      if Environment.should_include state.dugraph env then
        let target_node = Option.get state.target_node in
        let dug =
          if !Options.no_reduction then state.dugraph
          else reduce_dugraph target_node state.dugraph
        in
        let env =
          Environment.add_trace state.State.trace env
          |> Environment.add_dugraph dug
        in
        { env with
          metadata=
            Metadata.incr_explored env.metadata |> Metadata.incr_graph dug }
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
  if Worklist.is_empty env.worklist || out_of_traces || out_of_explored then env
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
  let json = Traces.to_json env.Environment.cache env.traces in
  let oc = open_out (prefix ^ ".json") in
  Options.json_to_channel oc json ;
  close_out oc

let dump_dots ?(prefix = "") env =
  List.iteri
    (fun idx g ->
      let oc = open_out (prefix ^ "-" ^ string_of_int idx ^ ".dot") in
      GraphViz.output_graph oc g ; close_out oc)
    env.Environment.dugraphs

let dump_dugraphs ?(prefix = "") env =
  let json = List.map (DUGraph.to_json env.Environment.cache) env.dugraphs in
  let oc = open_out (prefix ^ ".json") in
  Options.json_to_channel oc (`List json) ;
  close_out oc
