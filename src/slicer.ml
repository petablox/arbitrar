open Printf

module CallEdge = struct
  type t = {caller: Llvm.llvalue; callee: Llvm.llvalue; instr: Llvm.llvalue}

  let create caller callee instr = {caller; callee; instr}

  let to_json llm ce =
    `Assoc
      [ ("caller", `String (Llvm.value_name ce.caller))
      ; ("callee", `String (Llvm.value_name ce.callee))
      ; ("instr", `String (Llvm.string_of_llvalue ce.instr)) ]

  let get_function_of_field llm field_name json : Llvm.llvalue =
    let field = Utils.get_field json field_name in
    match field with
    | `String name ->
        Utils.get_function_in_llm name llm
    | _ ->
        raise Utils.InvalidJSON

  let get_instr_string json : string =
    let field = Utils.get_field json "instr" in
    match field with
    | `String instr_str ->
        instr_str
    | _ ->
        raise Utils.InvalidJSON

  let from_json llm json =
    let caller = get_function_of_field llm "caller" json in
    let callee = get_function_of_field llm "callee" json in
    let instr =
      (* Want to have better algorithm instead of find the instr in linear *)
      raise Utils.NotImplemented
      (* let instr_str = get_instr_string json in
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
      match maybe_instr with
      | Some instr ->
          instr
      | None ->
          raise Utils.InvalidJSON *)
    in
    {caller; callee; instr}
end

module CallGraph = struct
  module Node = struct
    type t = Llvm.llvalue

    let compare = compare

    let equal = ( = )

    let hash = Hashtbl.hash

    let to_string = Llvm.value_name

    let label = Llvm.value_name
  end

  module G = Graph.Persistent.Digraph.ConcreteBidirectional (Node)
  module E = G.E
  module V = G.V

  module CallInstrMap = Map.Make (struct
    type t = Llvm.llvalue * Llvm.llvalue

    let compare = compare

    let hash = Hashtbl.hash
  end)

  module CallInstrSet = Set.Make (struct
    type t = Llvm.llvalue

    let compare = compare
  end)

  type t = {graph: G.t; call_instr_map: CallInstrSet.t CallInstrMap.t}

  let empty = {graph= G.empty; call_instr_map= CallInstrMap.empty}

  let add_edge_e g (caller, instr, callee) =
    let graph = G.add_edge g.graph caller callee in
    let call_instr_map =
      try
        let set = CallInstrMap.find (caller, callee) g.call_instr_map in
        CallInstrMap.add (caller, callee)
          (CallInstrSet.add instr set)
          g.call_instr_map
      with Not_found ->
        CallInstrMap.add (caller, callee)
          (CallInstrSet.singleton instr)
          g.call_instr_map
    in
    {graph; call_instr_map}

  let fold_edges_e f cg acc = G.fold_edges_e f cg.graph acc

  let fold_edges_instr_set f cg acc =
    G.fold_edges_e
      (fun (caller, callee) acc ->
        let instr_set = CallInstrMap.find (caller, callee) cg.call_instr_map in
        CallInstrSet.fold
          (fun instr acc -> f (caller, instr, callee) acc)
          instr_set acc)
      cg.graph acc

  let iter_edges_e f cg = G.iter_edges_e f cg.graph

  let iter_edges_instr_set f cg =
    G.iter_edges
      (fun caller callee ->
        let instr_set = CallInstrMap.find (caller, callee) cg.call_instr_map in
        CallInstrSet.iter (fun instr -> f (caller, instr, callee)) instr_set)
      cg.graph

  let iter_vertex f cg = G.iter_vertex f cg.graph

  let graph_attributes g = []

  let edge_attributes e = []

  let default_edge_attributes g = []

  let get_subgraph v = None

  let vertex_name v = "\"" ^ Node.to_string v ^ "\""

  let vertex_attributes v = []

  let default_vertex_attributes g = []
end

module GraphViz = Graph.Graphviz.Dot (CallGraph)

module Slice = struct
  type t =
    {functions: Llvm.llvalue list; entry: Llvm.llvalue; call_edge: CallEdge.t}

  let create functions entry (caller, instr, callee) =
    let call_edge = {CallEdge.caller; instr; callee} in
    {functions; entry; call_edge}

  let to_json llm slice =
    `Assoc
      [ ( "functions"
        , `List
            (List.map (fun f -> `String (Llvm.value_name f)) slice.functions)
        )
      ; ("entry", `String (Llvm.value_name slice.entry))
      ; ("call_edge", CallEdge.to_json llm slice.call_edge) ]

  let get_functions_from_json llm json =
    match Utils.get_field json "functions" with
    | `List func_names ->
        List.map
          (fun func_name ->
            match func_name with
            | `String name ->
                Utils.get_function_in_llm name llm
            | _ ->
                raise Utils.InvalidJSON)
          func_names
    | _ ->
        raise Utils.InvalidJSON

  let get_entry_from_json llm json =
    match Utils.get_field json "entry" with
    | `String name ->
        Utils.get_function_in_llm name llm
    | _ ->
        raise Utils.InvalidJSON

  let get_call_edge_from_json llm json =
    CallEdge.from_json llm (Utils.get_field json "call_edge")

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
        raise Utils.InvalidJSON
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
                  then CallGraph.add_edge_e graph (func, instr, callee)
                  else graph
              | _ ->
                  graph)
            graph block)
        graph func)
    CallGraph.empty llm

let print_call_edge (llm : Llvm.llmodule) (caller, _, callee) : unit =
  let callee_name = Llvm.value_name callee in
  let caller_name = Llvm.value_name caller in
  ignore (printf "(%s -> %s); " caller_name callee_name)

let print_call_graph (llm : Llvm.llmodule) (cg : CallGraph.t) : unit =
  CallGraph.iter_edges_instr_set (fun ce -> print_call_edge llm ce) cg ;
  ignore (printf "\n")

let dump_call_graph cg =
  let oc = open_out (!Options.outdir ^ "/callgraph.dot") in
  GraphViz.output_graph oc cg ;
  close_out oc

let rec find_entries (depth : int) (env : CallGraph.t) (target : Llvm.llvalue)
    : (Llvm.llvalue * int) list =
  match depth with
  | 0 ->
      [(target, 0)]
  | _ ->
      let callers =
        CallGraph.fold_edges_instr_set
          (fun (caller, inst, callee) acc ->
            if target = callee then find_entries (depth - 1) env caller @ acc
            else acc)
          env []
      in
      if List.length callers == 0 then [(target, depth)] else callers

let rec find_callees (depth : int) (env : CallGraph.t) (target : Llvm.llvalue)
    : Llvm.llvalue list =
  match depth with
  | 0 ->
      []
  | _ ->
      CallGraph.fold_edges_instr_set
        (fun (caller, inst, callee) acc ->
          if caller == target then
            acc @ (callee :: find_callees (depth - 1) env callee)
          else acc)
        env []

let need_find_slices_for_edge (llm : Llvm.llmodule) callee : bool =
  match !Options.target_function_name with
  | "" ->
      true
  | n ->
      let callee_name = Llvm.value_name callee in
      String.equal callee_name n

let find_slices llm depth env (caller, inst, callee) : Slices.t =
  if need_find_slices_for_edge llm callee then
    let entries = find_entries depth env caller in
    let uniq_entries = Utils.unique (fun (a, _) (b, _) -> a == b) entries in
    let slices =
      List.map
        (fun (entry, up_count) ->
          let callees = find_callees ((depth * 2) - up_count) env entry in
          let uniq_funcs = Utils.unique ( == ) (entry :: callees) in
          let uniq_funcs_without_callee =
            Utils.without (( == ) callee) uniq_funcs
          in
          Slice.create uniq_funcs_without_callee entry (caller, inst, callee))
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
    CallGraph.fold_edges_instr_set
      (fun edge acc -> acc @ find_slices llm slice_depth call_graph edge)
      call_graph []
  in
  slices

let main input_file =
  let llctx = Llvm.create_context () in
  let llmem = Llvm.MemoryBuffer.of_file input_file in
  let llm = Llvm_bitreader.parse_bitcode llctx llmem in
  let slices = slice llm !Options.slice_depth in
  ignore (print_slices stdout llm slices)
