open Processing

module type CHECKER = sig
  type t

  val name : string

  val default : t

  val compare : t -> t -> int

  val to_string : t -> string

  val filter : Function.t -> bool

  val check : Function.t -> Trace.t -> t list
end

module IcmpResult = struct
  type t = Checked of Predicate.t * int64 | NoCheck

  let normalize_predicate (pred : Predicate.t) =
    match pred with Predicate.Ne -> Predicate.Eq | _ -> pred

  let checked pred i = Checked (normalize_predicate pred, i)

  let to_string r : string =
    match r with
    | Checked (pred, value) ->
        Printf.sprintf "Checked(%s,%s)" (Predicate.to_string pred)
          (Int64.to_string value)
    | NoCheck ->
        "NoCheck"
end

module RetValChecker : CHECKER = struct
  open IcmpResult

  type t = IcmpResult.t

  let name = "retval"

  let default = NoCheck

  let compare = compare

  let to_string = IcmpResult.to_string

  let filter (_, (ret_ty, _)) =
    match ret_ty with TypeKind.Pointer _ -> true | _ -> false

  let rec check_helper cfgraph ret explored fringe result =
    match NodeSet.choose_opt fringe with
    | Some hd ->
        let rst = NodeSet.remove hd fringe in
        if NodeSet.mem hd explored then
          check_helper cfgraph ret explored rst result
        else
          let new_explored = NodeSet.add hd explored in
          let new_fringe =
            NodeSet.union (NodeSet.of_list (NodeGraph.succ cfgraph hd)) rst
          in
          let new_result =
            match hd.stmt with
            | Assume {pred; op0; op1} ->
                let is_op0_const = Value.is_const op0 in
                let is_op1_const = Value.is_const op1 in
                if is_op0_const && is_op0_const then []
                else if is_op0_const && Value.sem_equal op1 ret then
                  [checked pred (Value.get_const op0)]
                else if is_op1_const && Value.sem_equal op0 ret then
                  [checked pred (Value.get_const op1)]
                else []
            | _ ->
                []
          in
          check_helper cfgraph ret new_explored new_fringe (new_result @ result)
    | None ->
        result

  let check _ (trace : Trace.t) : t list =
    match trace.target_node.stmt with
    | Call {result} -> (
      match result with
      | Some ret -> (
          let targets = NodeSet.singleton trace.target_node in
          let results =
            check_helper trace.cfgraph ret NodeSet.empty targets []
          in
          match results with [] -> [NoCheck] | _ -> results )
      | None ->
          [] )
    | _ ->
        []
end

module ArgRelChecker : CHECKER = struct
  (**
   * When there's a relation, the `int` means the index of the argument.
   * e.g.
   *
   *   [sum(a, b, c)]
   *
   * When there's a relation between `a` and `c`, we have a relation
   *
   *   Relation (0, 2)
   *
   * Otherwise there's no relation. When a function only takes in a single
   * argument, it's trivial that the arguments has no relation.
   *
   * There is a relation between two arguments when the two arguments
   * has some symbols or function call results in common.
   *)
  type t = Relation of int * int | NoRelation

  let name = "argrel"

  let default = NoRelation

  let compare = compare

  let to_string r : string =
    match r with
    | Relation (i, j) ->
        Printf.sprintf "Relation(%d,%d)" i j
    | NoRelation ->
        "NoRelation"

  let filter _ = true

  let has_intersect_symbols e1 e2 =
    let s1 = SymExpr.get_used_symbols e1 in
    let s2 = SymExpr.get_used_symbols e2 in
    let itsct = SymbolSet.inter s1 s2 in
    SymbolSet.cardinal itsct > 0

  let has_intersect_rets e1 e2 =
    let s1 = SymExpr.get_used_ret_ids e1 in
    let s2 = SymExpr.get_used_ret_ids e2 in
    let itsct = RetIdSet.inter s1 s2 in
    RetIdSet.cardinal itsct > 0

  let intersect v1 v2 =
    match (v1, v2) with
    | Value.SymExpr e1, Value.SymExpr e2 ->
        has_intersect_rets e1 e2 || has_intersect_symbols e1 e2
    | _ ->
        false

  let combinations (ls : 'a list) : (int * 'a * int * 'a) list =
    List.mapi
      (fun i1 e1 ->
        List.mapi
          (fun i2 e2 -> if i1 <> i2 then Some (i1, e1, i2, e2) else None)
          ls)
      ls
    |> List.flatten
    |> List.filter_map (fun x -> x)

  let check _ (trace : Trace.t) : t list =
    let target_stmt = trace.target_node.stmt in
    match target_stmt with
    | Call {args} -> (
        let cart = combinations args in
        let results =
          List.filter_map
            (fun (i1, e1, i2, e2) ->
              if intersect e1 e2 then Some (Relation (i1, i2)) else None)
            cart
        in
        match results with [] -> [NoRelation] | _ -> results )
    | _ ->
        []
end

module type ARG_INDEX = sig
  val index : int
end

module ArgValChecker (A : ARG_INDEX) : CHECKER = struct
  open IcmpResult

  type t = IcmpResult.t

  let name = Printf.sprintf "argval-%d" A.index

  let default = NoCheck

  let compare = compare

  let to_string = IcmpResult.to_string

  let filter (_, (_, arg_types)) =
    if List.length arg_types > A.index then
      match List.nth arg_types A.index with
      | TypeKind.Pointer _ ->
          true
      | _ ->
          false
    else false

  let rec check_helper cfgraph ret explored fringe result =
    match NodeSet.choose_opt fringe with
    | Some hd ->
        let rst = NodeSet.remove hd fringe in
        if NodeSet.mem hd explored then
          check_helper cfgraph ret explored rst result
        else
          let new_explored = NodeSet.add hd explored in
          let new_fringe =
            NodeSet.union (NodeSet.of_list (NodeGraph.pred cfgraph hd)) rst
          in
          let new_result =
            match hd.stmt with
            | Assume {pred; op0; op1} ->
                let is_op0_const = Value.is_const op0 in
                let is_op1_const = Value.is_const op1 in
                if is_op0_const && is_op0_const then []
                else if is_op0_const && Value.sem_equal op1 ret then
                  [checked pred (Value.get_const op0)]
                else if is_op1_const && Value.sem_equal op0 ret then
                  [checked pred (Value.get_const op1)]
                else []
            | _ ->
                []
          in
          check_helper cfgraph ret new_explored new_fringe (new_result @ result)
    | None ->
        result

  let check _ (trace : Trace.t) : t list =
    match trace.target_node.stmt with
    | Call {args} -> (
        let arg = List.nth args A.index in
        let targets = NodeSet.singleton trace.target_node in
        let results =
          check_helper trace.cfgraph arg NodeSet.empty targets []
        in
        match results with [] -> [NoCheck] | _ -> results )
    | _ ->
        []
end

module Arg0ValChecker = ArgValChecker ((
  struct
    let index = 0
  end :
    ARG_INDEX ))

module Arg1ValChecker = ArgValChecker ((
  struct
    let index = 1
  end :
    ARG_INDEX ))

module Arg2ValChecker = ArgValChecker ((
  struct
    let index = 2
  end :
    ARG_INDEX ))

module Arg3ValChecker = ArgValChecker ((
  struct
    let index = 3
  end :
    ARG_INDEX ))

module Causality = struct
  type t = Causing of string | None

  let to_string r =
    match r with
    | Causing func_name ->
        Printf.sprintf "Causing(%s)" func_name
    | None ->
        "None"

  let rec check_helper dugraph explored fringe result =
    match NodeSet.choose_opt fringe with
    | Some hd ->
        let rst = NodeSet.remove hd fringe in
        if NodeSet.mem hd explored then
          check_helper dugraph explored rst result
        else
          let new_explored = NodeSet.add hd explored in
          let new_fringe =
            NodeSet.union (NodeSet.of_list (NodeGraph.succ dugraph hd)) rst
          in
          let new_result =
            match hd.stmt with
            | Call {func} -> Causing func :: result
            | _ -> result
          in
          check_helper dugraph new_explored new_fringe new_result
    | None ->
        result

  let dedup xs =
    let uniq_cons x xs = if List.mem x xs then xs else x :: xs in
    List.fold_right uniq_cons xs []

  let check (trace : Trace.t) : t list =
    let explored = NodeSet.singleton trace.target_node in
    let fringe = NodeSet.of_list (NodeGraph.succ trace.dugraph trace.target_node) in
    let results = check_helper trace.dugraph explored fringe [] in
    match results with [] -> [None] | _ -> results
end

module CausalityChecker : CHECKER = struct
  open Causality

  type t = Causality.t

  let name = "causality"

  let default = Causality.None

  let compare = compare

  let to_string = Causality.to_string

  let filter _ = true

  let check _ = Causality.check
end

module IcmpBranchChecker = struct
  type t = Checked of Predicate.t * int64 * Branch.t | NoCheck

  let rec check_helper cfgraph succ var explored fringe result =
    match NodeSet.choose_opt fringe with
    | Some hd ->
        let rst = NodeSet.remove hd fringe in
        if NodeSet.mem hd explored then
          check_helper cfgraph succ var explored rst result
        else
          let new_explored = NodeSet.add hd explored in
          let new_fringe =
            NodeSet.union (NodeSet.of_list (succ cfgraph hd)) rst
          in
          let new_result =
            match hd.stmt with
            | Assume {pred; op0; op1} ->
                let branch_instrs = NodeGraph.succ cfgraph hd in
                let maybe_branch_instr =
                  List.find_opt
                    (fun (node : Node.t) ->
                      match node.stmt with
                      | Statement.ConditionalBranch _ -> true
                      | _ -> false)
                    branch_instrs
                in
                (match maybe_branch_instr with
                | Some ({stmt= Statement.ConditionalBranch {br}}) ->
                    let is_op0_const = Value.is_const op0 in
                    let is_op1_const = Value.is_const op1 in
                    if is_op0_const && is_op0_const then result
                    else if is_op0_const && Value.sem_equal op1 var then
                      Checked (pred, (Value.get_const op0), br) :: result
                    else if is_op1_const && Value.sem_equal op0 var then
                      Checked (pred, (Value.get_const op1), br) :: result
                    else result
                | _ -> result)
            | _ ->
                result
          in
          check_helper cfgraph succ var new_explored new_fringe new_result
    | None ->
        result

  let check (trace : Trace.t) (var : Value.t) (start : Node.t) (succ : bool) : t list =
    let succ_func = if succ then NodeGraph.succ else NodeGraph.pred in
    let fringe = NodeSet.of_list (succ_func trace.cfgraph start) in
    let explored = NodeSet.empty in
    check_helper trace.cfgraph succ_func var explored fringe []

  let check_retval (trace : Trace.t) : t list =
    match trace.target_node.stmt with
    | Call {result} -> (
      match result with
      | Some ret -> check trace ret trace.target_node true
      | None -> [] )
    | _ -> []
end

module FOpenChecker : CHECKER = struct
  type t = Ok | Alarm

  let name = "fopen"

  let default = Alarm

  let compare = compare

  let to_string r = match r with Ok -> "Ok" | _ -> "Alarm"

  let regex = Str.regexp ".*fopen.*"

  let filter (func_name, _) = Str.string_match regex func_name 0

  let check _ (trace : Trace.t) : t list =
    let retval_checks = IcmpBranchChecker.check_retval trace in
    let retval_checked = List.length retval_checks > 0 in
    if retval_checked then
      let causings = Causality.check trace in
      let is_causing_fputs = List.mem (Causality.Causing "fputs") causings in
      let is_causing_fclose = List.mem (Causality.Causing "fclose") causings in
      match List.nth retval_checks 0 with
      | IcmpBranchChecker.Checked (Predicate.Eq, 0L, Branch.Then)
      | IcmpBranchChecker.Checked (Predicate.Ne, 0L, Branch.Else) ->
          if is_causing_fclose || is_causing_fputs then [Alarm]
          else [Ok]
      | IcmpBranchChecker.Checked (Predicate.Eq, 0L, Branch.Else)
      | IcmpBranchChecker.Checked (Predicate.Ne, 0L, Branch.Then) ->
          if is_causing_fclose then [Ok]
          else [Alarm]
      | _ -> [Alarm]
    else [Alarm]
end