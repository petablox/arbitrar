open Processing

module type CHECKER = sig
  type t

  val name : string

  val default : t

  val compare : t -> t -> int

  val to_string : t -> string

  val check : Trace.t -> t list
end

module CheckResult = struct
  type t = Checked of Predicate.t * int64 | NoCheck

  let to_string r : string =
    match r with
    | Checked (pred, value) ->
        Printf.sprintf "Checked(%s,%s)" (Predicate.to_string pred)
          (Int64.to_string value)
    | NoCheck ->
        "NoCheck"
end

module RetValChecker : CHECKER = struct
  open CheckResult

  type t = CheckResult.t

  let name = "retval"

  let default = NoCheck

  let compare = compare

  let to_string = CheckResult.to_string

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
                  [Checked (pred, Value.get_const op0)]
                else if is_op1_const && Value.sem_equal op0 ret then
                  [Checked (pred, Value.get_const op1)]
                else []
            | _ ->
                []
          in
          check_helper cfgraph ret new_explored new_fringe (new_result @ result)
    | None ->
        result

  let check (trace : Trace.t) : t list =
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

  let check (trace : Trace.t) : t list =
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
