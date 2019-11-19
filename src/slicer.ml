open Printf

exception InvalidJSON

let get_function_in_llm (func_name : string) (llm : Llvm.llmodule) :
    Llvm.llvalue =
  match Llvm.lookup_function func_name llm with
  | Some entry ->
      entry
  | None ->
      raise InvalidJSON

let get_field json field : Yojson.Safe.t =
  match json with
  | `Assoc fields -> (
    match List.find_opt (fun (key, _) -> key = field) fields with
    | Some (_, field_data) ->
        field_data
    | None ->
        raise InvalidJSON )
  | _ ->
      raise InvalidJSON

module CallEdge = struct
  type t = {caller: Llvm.llvalue; callee: Llvm.llvalue; instr: Llvm.llvalue}

  let create caller callee instr = {caller; callee; instr}

  let to_json llm ce =
    `Assoc
      [ ("caller", `String (Llvm.value_name ce.caller))
      ; ("callee", `String (Llvm.value_name ce.callee))
      ; ("instr", `String (Llvm.string_of_llvalue ce.instr)) ]

  let get_function_of_field llm field_name json : Llvm.llvalue =
    let field = get_field json field_name in
    match field with
    | `String name ->
        get_function_in_llm name llm
    | _ ->
        raise InvalidJSON

  let get_instr_string json : string =
    let field = get_field json "instr" in
    match field with `String instr_str -> instr_str | _ -> raise InvalidJSON

  let from_json llm json =
    let caller = get_function_of_field llm "caller" json in
    let callee = get_function_of_field llm "callee" json in
    let instr =
      let instr_str = get_instr_string json in
      let maybe_instr =
        Llvm.fold_left_blocks
          (fun acc block ->
            Llvm.fold_left_instrs
              (fun acc instr ->
                if Llvm.string_of_llvalue instr = instr_str then Some instr
                else acc)
              acc block)
          None caller
      in
      match maybe_instr with Some instr -> instr | None -> raise InvalidJSON
    in
    {caller; callee; instr}
end

module CallGraph = struct
  type t = CallEdge.t list

  let empty = []

  let add_edge graph caller callee instr =
    CallEdge.create caller callee instr :: graph
end

module Slice = struct
  type t =
    {functions: Llvm.llvalue list; entry: Llvm.llvalue; call_edge: CallEdge.t}

  let create functions entry call_edge = {functions; entry; call_edge}

  let to_json llm slice =
    `Assoc
      [ ( "functions"
        , `List
            (List.map (fun f -> `String (Llvm.value_name f)) slice.functions)
        )
      ; ("entry", `String (Llvm.value_name slice.entry))
      ; ("call_edge", CallEdge.to_json llm slice.call_edge) ]

  let get_functions_from_json llm json =
    match get_field json "functions" with
    | `List func_names ->
        List.map
          (fun func_name ->
            match func_name with
            | `String name ->
                get_function_in_llm name llm
            | _ ->
                raise InvalidJSON)
          func_names
    | _ ->
        raise InvalidJSON

  let get_entry_from_json llm json =
    match get_field json "entry" with
    | `String name ->
        get_function_in_llm name llm
    | _ ->
        raise InvalidJSON

  let get_call_edge_from_json llm json =
    CallEdge.from_json llm (get_field json "call_edge")

  let from_json llm json =
    let entry = get_entry_from_json llm json in
    let functions = get_functions_from_json llm json in
    let call_edge = get_call_edge_from_json llm json in
    {functions; entry; call_edge}
end

module Slices = struct
  type t = Slice.t list

  let to_json llm slices = `List (List.map (Slice.to_json llm) slices)

  let dump_json ?(prefix = "") llm slices =
    let json = to_json llm slices in
    let oc = open_out (prefix ^ "/slices.json") in
    Yojson.Safe.pretty_to_channel oc json

  let from_json llm json =
    match json with
    | `List json_slice_list ->
        List.map (Slice.from_json llm) json_slice_list
    | _ ->
        raise InvalidJSON
end

let get_call_graph (llm : Llvm.llmodule) : CallGraph.t =
  Llvm.fold_left_functions
    (fun graph func ->
      Llvm.fold_left_blocks
        (fun graph block ->
          Llvm.fold_left_instrs
            (fun graph instr ->
              let opcode = Llvm.instr_opcode instr in
              match opcode with
              | Call ->
                  let callee =
                    Llvm.operand instr (Llvm.num_operands instr - 1)
                  in
                  if
                    Llvm.classify_value callee = Llvm.ValueKind.Function
                    && not (Utils.is_llvm_function callee)
                  then CallGraph.add_edge graph func callee instr
                  else graph
              | _ ->
                  graph)
            graph block)
        graph func)
    [] llm

let print_call_edge (llm : Llvm.llmodule) (ce : CallEdge.t) : unit =
  let callee_name = Llvm.value_name ce.callee in
  let caller_name = Llvm.value_name ce.caller in
  ignore (printf "(%s -> %s); " caller_name callee_name)

let print_call_graph (llm : Llvm.llmodule) (cg : CallGraph.t) : unit =
  List.iter (fun ce -> print_call_edge llm ce) cg ;
  ignore (printf "\n")

let rec find_entries (depth : int) (env : CallGraph.t) (target : Llvm.llvalue)
    : (Llvm.llvalue * int) list =
  match depth with
  | 0 ->
      [(target, 0)]
  | _ ->
      let callers =
        List.fold_left
          (fun acc ce ->
            if target == ce.CallEdge.callee then
              find_entries (depth - 1) env ce.caller @ acc
            else acc)
          [] env
      in
      if List.length callers == 0 then [(target, depth)] else callers

let rec find_callees (depth : int) (env : CallGraph.t) (target : Llvm.llvalue)
    : Llvm.llvalue list =
  match depth with
  | 0 ->
      []
  | _ ->
      List.fold_left
        (fun acc ce ->
          if ce.CallEdge.caller == target then
            acc @ (ce.callee :: find_callees (depth - 1) env ce.callee)
          else acc)
        [] env

let need_find_slices_for_edge (llm : Llvm.llmodule) (ce : CallEdge.t) : bool =
  match !Options.target_function_name with
  | "" ->
      true
  | n ->
      let callee_name = Llvm.value_name ce.callee in
      String.equal callee_name n

let find_slices llm depth env (ce : CallEdge.t) : Slices.t =
  if need_find_slices_for_edge llm ce then
    let entries = find_entries depth env ce.caller in
    let uniq_entries = Utils.unique (fun (a, _) (b, _) -> a == b) entries in
    let slices =
      List.map
        (fun (entry, up_count) ->
          let callees = find_callees ((depth * 2) - up_count) env entry in
          let uniq_funcs = Utils.unique ( == ) (entry :: callees) in
          let uniq_funcs_without_callee =
            Utils.without (( == ) ce.callee) uniq_funcs
          in
          Slice.create uniq_funcs_without_callee entry ce)
        uniq_entries
    in
    slices
  else []

let print_slices oc (llm : Llvm.llmodule) (slices : Slices.t) : unit =
  List.iter
    (fun (slice : Slice.t) ->
      let entry_name = Llvm.value_name slice.entry in
      let func_names = List.map (fun f -> Llvm.value_name f) slice.functions in
      let func_names_str = String.concat ", " func_names in
      let callee_name = Llvm.value_name slice.call_edge.callee in
      let caller_name = Llvm.value_name slice.call_edge.caller in
      let instr_str = Llvm.string_of_llvalue slice.call_edge.instr in
      let call_str = Printf.sprintf "(%s -> %s)" caller_name callee_name in
      fprintf oc "Slice { Entry: %s, Functions: %s, Call: %s, Instr: %s }\n"
        entry_name func_names_str call_str instr_str)
    slices

let slice (llm : Llvm.llmodule) (slice_depth : int) : Slices.t =
  let call_graph = get_call_graph llm in
  let slices =
    List.map (find_slices llm slice_depth call_graph) call_graph
    |> List.flatten
  in
  slices

let main input_file =
  let llctx = Llvm.create_context () in
  let llmem = Llvm.MemoryBuffer.of_file input_file in
  let llm = Llvm_bitreader.parse_bitcode llctx llmem in
  let slices = slice llm !Options.slice_depth in
  ignore (print_slices stdout llm slices)
