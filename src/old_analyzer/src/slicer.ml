module CallEdge = struct
  type t =
    { caller: Llvm.llvalue
    ; callee: Llvm.llvalue
    ; instr: Llvm.llvalue
    ; location: string }

  let create caller callee instr location = {caller; callee; instr; location}

  let to_json llm ce : Yojson.Safe.t =
    let caller_name = Utils.GlobalCache.ll_func ce.caller |> Option.get in
    let callee_name = Utils.GlobalCache.ll_func ce.callee |> Option.get in
    let instr = "" in
    (* Utils.string_of_instr ce.instr in *)
    `Assoc
      [ ("caller", `String caller_name)
      ; ("callee", `String callee_name)
      ; ("instr", `String instr)
      ; ("location", `String ce.location) ]

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

  let from_json llm json : t =
    (*
    let caller = get_function_of_field llm "caller" json in
    let callee = get_function_of_field llm "callee" json in
    let instr =
      (* Want to have better algorithm instead of find the instr in linear *)
      raise Utils.NotImplemented
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
      match maybe_instr with
      | Some instr ->
          instr
      | None ->
          raise Utils.InvalidJSON
    in*)
    raise Utils.NotImplemented
end

module LlvalueSet = Set.Make (struct
  type t = Llvm.llvalue

  let compare = compare
end)

module CallGraph = struct
  module Node = struct
    type t = Llvm.llvalue

    let compare = compare

    let equal = ( == )

    let hash = Hashtbl.hash

    let to_string = Llvm.value_name

    let label = Llvm.value_name
  end

  module Edge = struct
    (* Caller, Instr, Callee *)
    type t = Llvm.llvalue * Llvm.llvalue * Llvm.llvalue

    let compare = compare
  end

  module G = Graph.Persistent.Digraph.ConcreteBidirectional (Node)
  module E = G.E
  module V = G.V

  module CallInstrMap = Map.Make (struct
    type t = Llvm.llvalue * Llvm.llvalue

    let compare = compare

    let hash = Hashtbl.hash
  end)

  type t = {graph: G.t; call_instr_map: LlvalueSet.t CallInstrMap.t}

  let empty = {graph= G.empty; call_instr_map= CallInstrMap.empty}

  let succ cg n = G.succ cg.graph n

  let pred cg n = G.pred cg.graph n

  let add_edge_e g (caller, instr, callee) =
    let graph = G.add_edge g.graph caller callee in
    let call_instr_map =
      try
        let set = CallInstrMap.find (caller, callee) g.call_instr_map in
        CallInstrMap.add (caller, callee) (LlvalueSet.add instr set)
          g.call_instr_map
      with Not_found ->
        CallInstrMap.add (caller, callee)
          (LlvalueSet.singleton instr)
          g.call_instr_map
    in
    {graph; call_instr_map}

  let fold_edges_e f cg acc = G.fold_edges_e f cg.graph acc

  let fold_edges_instr_set f cg acc =
    G.fold_edges_e
      (fun (caller, callee) acc ->
        let instr_set = CallInstrMap.find (caller, callee) cg.call_instr_map in
        LlvalueSet.fold
          (fun instr acc -> f (caller, instr, callee) acc)
          instr_set acc)
      cg.graph acc

  let fold_pred f cg n = G.fold_pred f cg.graph n

  let iter_edges_e f cg = G.iter_edges_e f cg.graph

  let iter_edges_instr_set f cg =
    G.iter_edges
      (fun caller callee ->
        let instr_set = CallInstrMap.find (caller, callee) cg.call_instr_map in
        LlvalueSet.iter (fun instr -> f (caller, instr, callee)) instr_set)
      cg.graph

  let iter_vertex f cg = G.iter_vertex f cg.graph

  let graph_attributes g = []

  let edge_attributes e = []

  let default_edge_attributes g = []

  let get_subgraph v = None

  let vertex_name v = "\"" ^ Node.to_string v ^ "\""

  let vertex_attributes v = []

  let default_vertex_attributes g = []

  let num_edges cg = G.nb_edges cg.graph

  let from_llm llm =
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
                      && not (Utils.is_dummy_function callee)
                    then add_edge_e graph (func, instr, callee)
                    else graph
                | _ ->
                    graph)
              graph block)
          graph func)
      empty llm
end

module GraphViz = Graph.Graphviz.Dot (CallGraph)

module TypeKind = struct
  type t =
    | Void
    | Half
    | Float
    | Double
    | Integer
    | Function of t * t list
    | NamedStruct of string
    | Struct of t list
    | Array of t * int
    | Pointer of t
    | Vector of t * int
    | Other
  [@@deriving yojson {exn= true}]

  let compare = compare

  let list_from_array arr = Array.fold_right (fun a ls -> a :: ls) arr []

  let from_lltype ty =
    let rec from_lltype_helper depth ty =
      if depth > 3 then Other
      else
        let recur = from_lltype_helper (depth + 1) in
        match Llvm.classify_type ty with
        | Llvm.TypeKind.Void ->
            Void
        | Llvm.TypeKind.Half ->
            Half
        | Llvm.TypeKind.Float ->
            Float
        | Llvm.TypeKind.Double ->
            Double
        | Llvm.TypeKind.Integer ->
            Integer
        | Llvm.TypeKind.Function ->
            let ll_ret = Llvm.return_type ty in
            let ll_args = list_from_array (Llvm.param_types ty) in
            Function (recur ll_ret, List.map recur ll_args)
        | Llvm.TypeKind.Struct -> (
          match Llvm.struct_name ty with
          | Some name ->
              NamedStruct name
          | None ->
              let ll_elems = list_from_array (Llvm.struct_element_types ty) in
              Struct (List.map recur ll_elems) )
        | Llvm.TypeKind.Array ->
            let elem = Llvm.element_type ty in
            let length = Llvm.array_length ty in
            Array (recur elem, length)
        | Llvm.TypeKind.Pointer ->
            let elem = Llvm.element_type ty in
            Pointer (recur elem)
        | Llvm.TypeKind.Vector ->
            let elem = Llvm.element_type ty in
            let size = Llvm.vector_size ty in
            Vector (recur elem, size)
        | _ ->
            Other
    in
    from_lltype_helper 0 ty

  let to_json = to_yojson

  let from_json = of_yojson_exn
end

module TypeKindHelpers = struct
  module StringSet = Set.Make (String)

  module TypeKindSet = Set.Make (struct
    type t = TypeKind.t

    let compare = compare
  end)

  let used_structs ty =
    let rec used_structs_helper used fringe =
      match TypeKindSet.choose_opt fringe with
      | Some ty -> (
          let new_fringe = TypeKindSet.remove ty fringe in
          match ty with
          | TypeKind.NamedStruct name ->
              let new_used = StringSet.add name used in
              used_structs_helper new_used new_fringe
          | Function (ret_ty, arg_tys) ->
              used_structs_helper used
                (TypeKindSet.union
                   (TypeKindSet.of_list (ret_ty :: arg_tys))
                   new_fringe)
          | Array (ty, _) ->
              used_structs_helper used (TypeKindSet.add ty new_fringe)
          | Pointer ty ->
              used_structs_helper used (TypeKindSet.add ty new_fringe)
          | Vector (ty, _) ->
              used_structs_helper used (TypeKindSet.add ty new_fringe)
          | _ ->
              used_structs_helper used new_fringe )
      | None ->
          used
    in
    used_structs_helper StringSet.empty (TypeKindSet.singleton ty)

  let have_common_struct t1 t2 =
    let structs1 = used_structs t1 in
    let structs2 = used_structs t2 in
    not (StringSet.disjoint structs1 structs2)
end

module FunctionType = struct
  type t = TypeKind.t * TypeKind.t list [@@deriving yojson {exn= true}]

  let from_llvalue f : t =
    (* `Llvm.type_of f` is a pointer to the function type *)
    (* `element_type` can get the function type out of pointer *)
    let f_lltype = Llvm.element_type (Llvm.type_of f) in
    let f_type = TypeKind.from_lltype f_lltype in
    match f_type with
    | TypeKind.Function (ret, args) ->
        (ret, args)
    | _ ->
        raise Utils.InvalidFunctionType

  let to_json = to_yojson

  let from_json = of_yojson_exn
end

module Slice = struct
  type t =
    { functions: Llvm.llvalue list
    ; entry: Llvm.llvalue
    ; call_edge: CallEdge.t
    ; target_type: FunctionType.t }

  let create function_set entry caller instr callee location =
    let call_edge = {CallEdge.caller; instr; callee; location} in
    let functions = LlvalueSet.elements function_set in
    let target_type = FunctionType.from_llvalue callee in
    {functions; entry; call_edge; target_type}

  let have_common_prefix f1 f2 =
    let n1 = Llvm.value_name f1 in
    let n2 = Llvm.value_name f2 in
    let common_length = min (String.length n1) (String.length n2) in
    let chars = List.init common_length (fun i -> (n1.[i], n2.[i])) in
    let common_prefix_length, _ =
      List.fold_left
        (fun (len, is_prefix) (c1, c2) ->
          if is_prefix && c1 == c2 then (len + 1, true) else (len, false))
        (0, true) chars
    in
    common_prefix_length > 0

  let have_common_struct_type f1 f2 =
    let r1, a1 = FunctionType.from_llvalue f1 in
    let r2, a2 = FunctionType.from_llvalue f2 in
    TypeKindHelpers.have_common_struct
      (TypeKind.Function (r1, a1))
      (TypeKind.Function (r2, a2))

  let within_function_group f1 f2 =
    if f1 == f2 then true
    else if have_common_prefix f1 f2 then true
    else have_common_struct_type f1 f2

  module LlvalueMap = Map.Make (struct
    type t = Llvm.llvalue

    let compare = compare
  end)

  let merge_map (m1 : 'a LlvalueMap.t) (m2 : 'a LlvalueMap.t)
      (f : 'a -> 'a -> 'a) : 'a LlvalueMap.t =
    LlvalueMap.fold
      (fun key v2 map ->
        match LlvalueMap.find_opt key map with
        | Some v1 ->
            LlvalueMap.update key (fun _ -> Some (f v1 v2)) map
        | None ->
            LlvalueMap.add key v2 map)
      m2 m1

  let reduce call_graph slice =
    let target = slice.call_edge.callee in
    let slice_fn_set = LlvalueSet.of_list slice.functions in
    let rec is_related visited is_related_map queue =
      match queue with
      | fn :: tl ->
          if LlvalueSet.mem fn visited then
            if LlvalueMap.mem fn is_related_map then
              is_related visited is_related_map tl
            else
              let callees = CallGraph.succ call_graph fn in
              let fn_is_related =
                List.fold_left
                  (fun fn_is_related callee ->
                    match LlvalueMap.find_opt callee is_related_map with
                    | Some callee_is_related ->
                        fn_is_related || callee_is_related
                    | None ->
                        fn_is_related)
                  false callees
              in
              is_related visited
                (LlvalueMap.add fn fn_is_related is_related_map)
                tl
          else
            let visited = LlvalueSet.add fn visited in
            let directly_related = within_function_group target fn in
            if directly_related then
              is_related visited (LlvalueMap.add fn true is_related_map) tl
            else if LlvalueSet.mem fn slice_fn_set then
              let callees = CallGraph.succ call_graph fn in
              let fn_is_related, callee_need_work =
                List.fold_left
                  (fun (fn_is_related, callee_need_work) callee ->
                    if LlvalueSet.mem callee visited then
                      let callee_is_related =
                        match LlvalueMap.find_opt callee is_related_map with
                        | Some callee_is_related ->
                            callee_is_related
                        | None ->
                            false
                      in
                      (fn_is_related || callee_is_related, callee_need_work)
                    else (fn_is_related, callee :: callee_need_work))
                  (false, []) callees
              in
              if List.length callee_need_work > 0 then
                is_related visited is_related_map (callee_need_work @ queue)
              else
                is_related visited
                  (LlvalueMap.add fn fn_is_related is_related_map)
                  tl
            else is_related visited (LlvalueMap.add fn false is_related_map) tl
      | [] ->
          (visited, is_related_map)
    in
    let _, is_related_map =
      List.fold_left
        (fun (visited, is_related_map) fn ->
          is_related visited is_related_map [fn])
        (LlvalueSet.empty, LlvalueMap.empty)
        slice.functions
    in
    let functions =
      List.filter
        (fun fn ->
          LlvalueMap.find_opt fn is_related_map |> Option.value ~default:false)
        slice.functions
    in
    {slice with functions}

  let to_json llm slice : Yojson.Safe.t =
    let functions =
      `List
        (List.filter_map
           (fun f ->
             Utils.GlobalCache.ll_func f |> Option.map (fun s -> `String s))
           slice.functions)
    in
    let fn_type = FunctionType.to_json slice.target_type in
    let call_edge = CallEdge.to_json llm slice.call_edge in
    let entry = `String (Utils.GlobalCache.ll_func slice.entry |> Option.get) in
    `Assoc
      [ ("functions", functions)
      ; ("entry", entry)
      ; ("target_type", fn_type)
      ; ("call_edge", call_edge) ]

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
    let target_type = FunctionType.from_llvalue call_edge.callee in
    {functions; entry; call_edge; target_type}
end

module Slices = struct
  type t = Slice.t list

  let to_json llm slices =
    `List
      (List.mapi
         (fun i slice ->
           Printf.printf "Converting slice #%d to json...\r" i ;
           flush stdout ;
           Slice.to_json llm slice)
         slices)

  let dump_json ?(prefix = "") llm slices =
    Printf.printf "Dumping slices into json...\n" ;
    flush stdout ;
    let json = to_json llm slices in
    flush stdout ;
    let oc = open_out (prefix ^ "/slices.json") in
    Options.json_to_channel oc json ;
    close_out oc

  let from_json llm json =
    match json with
    | `List json_slice_list ->
        List.map (Slice.from_json llm) json_slice_list
    | _ ->
        raise Utils.InvalidJSON

  let dump oc llm slices : unit =
    List.iter
      (fun (slice : Slice.t) ->
        let entry_name = Llvm.value_name slice.entry in
        let func_names =
          List.map (fun f -> Llvm.value_name f) slice.functions
        in
        let func_names_str = String.concat ", " func_names in
        let callee_name = Llvm.value_name slice.call_edge.callee in
        let caller_name = Llvm.value_name slice.call_edge.caller in
        let instr_str = Llvm.string_of_llvalue slice.call_edge.instr in
        let call_str = Printf.sprintf "(%s -> %s)" caller_name callee_name in
        Printf.fprintf oc
          "Slice { Entry: %s, Functions: %s, Call: %s, Instr: %s }\n" entry_name
          func_names_str call_str instr_str)
      slices
end

module Llvalue = struct
  type t = Llvm.llvalue

  let compare = compare
end

module FunctionCounter = struct
  module FunctionMap = Map.Make (Llvalue)

  type t = int FunctionMap.t

  let empty = FunctionMap.empty

  let add ctr func count =
    FunctionMap.update func
      (fun maybe_count ->
        match maybe_count with
        | Some old_count ->
            Some (old_count + count)
        | None ->
            Some count)
      ctr

  let get ctr func = FunctionMap.find func ctr

  let fold = FunctionMap.fold
end

module EdgeEntriesMap = struct
  module EdgeMap = Map.Make (CallGraph.Edge)

  type t = LlvalueSet.t EdgeMap.t

  let add map edge entries =
    EdgeMap.update edge
      (fun maybe_entries ->
        match maybe_entries with
        | Some old_entries ->
            Some (LlvalueSet.union old_entries entries)
        | None ->
            Some entries)
      map

  let size map = EdgeMap.cardinal map

  let empty = EdgeMap.empty

  let fold = EdgeMap.fold
end

let print_call_edge (llm : Llvm.llmodule) (caller, _, callee) : unit =
  let callee_name = Llvm.value_name callee in
  let caller_name = Llvm.value_name caller in
  Printf.printf "(%s -> %s); " caller_name callee_name

let print_call_graph (llm : Llvm.llmodule) (cg : CallGraph.t) : unit =
  CallGraph.iter_edges_instr_set (print_call_edge llm) cg ;
  Printf.printf "\n"

let dump_call_graph cg =
  let oc = open_out (Options.outdir () ^ "/callgraph.dot") in
  GraphViz.output_graph oc cg ;
  close_out oc

let rec find_entries depth cg fringe entries =
  match depth with
  | 0 ->
      LlvalueSet.union fringe entries
  | _ ->
      let direct_callers, terminating_callers =
        LlvalueSet.fold
          (fun target (direct, terminating) ->
            let preds = CallGraph.pred cg target in
            match preds with
            | [] ->
                let new_terminating = LlvalueSet.add target terminating in
                (direct, new_terminating)
            | _ ->
                let preds_set = LlvalueSet.of_list preds in
                let new_direct = LlvalueSet.union direct preds_set in
                (new_direct, terminating))
          fringe
          (LlvalueSet.empty, LlvalueSet.empty)
      in
      let new_entries = LlvalueSet.union entries terminating_callers in
      find_entries (depth - 1) cg direct_callers new_entries

let rec find_callees depth cg poi_callee fringe callees =
  match depth with
  | 0 ->
      LlvalueSet.union fringe callees |> LlvalueSet.remove poi_callee
  | _ ->
      let direct_callees =
        LlvalueSet.fold
          (fun target direct_callees ->
            if target = poi_callee then direct_callees
            else
              LlvalueSet.of_list (CallGraph.succ cg target)
              |> LlvalueSet.union direct_callees)
          fringe LlvalueSet.empty
      in
      LlvalueSet.union callees direct_callees
      |> find_callees (depth - 1) cg poi_callee direct_callees

let gen_inc_filter inc : string -> bool =
  if String.equal inc "" then fun _ -> true
  else
    let inc_reg = Str.regexp inc in
    fun str -> Str.string_match inc_reg str 0

let gen_exc_filter exc : string -> bool =
  if String.equal exc "" then fun _ -> false
  else
    let exc_reg = Str.regexp exc in
    fun str -> Str.string_match exc_reg str 0

let gen_filter inc exc : string -> bool =
  let is_including = gen_inc_filter inc in
  let is_excluding = gen_exc_filter exc in
  fun str -> is_including str && not (is_excluding str)

module SlicingContext = struct
  type t =
    { llctx: Llvm.llcontext
    ; llm: Llvm.llmodule
    ; is_excluding: string -> bool
    ; filter: string -> bool
    ; entry_filter: string -> bool
    ; call_graph: CallGraph.t
    ; depth: int }

  let create llctx llm depth : t =
    let _ = Random.init !Options.seed in
    let is_excluding = gen_exc_filter !Options.exclude_func in
    let filter = gen_filter !Options.include_func !Options.exclude_func in
    let entry_filter = gen_inc_filter !Options.entry_location in
    let call_graph = CallGraph.from_llm llm in
    {llctx; llm; is_excluding; filter; entry_filter; call_graph; depth}
end

let sample_include () =
  if !Options.sample_slice then
    let rnd = Random.float 1.0 in
    rnd < !Options.sample_slice_percentage
  else false

let call_edges (slicing_ctx : SlicingContext.t) :
    FunctionCounter.t * EdgeEntriesMap.t =
  let _, func_counter, edge_entries =
    CallGraph.fold_edges_instr_set
      (fun edge (i, func_counter, edge_entries) ->
        Printf.printf "Slicing edge #%d...\r" i ;
        flush stdout ;
        let caller, _, callee = edge in
        if slicing_ctx.filter (Utils.GlobalCache.ll_func callee |> Option.get)
        then
          let singleton_caller = LlvalueSet.singleton caller in
          let entries =
            find_entries slicing_ctx.depth slicing_ctx.call_graph
              singleton_caller LlvalueSet.empty
          in
          let entries =
            LlvalueSet.filter
              (fun func ->
                let fn_loc =
                  Utils.GlobalCache.ll_func_location slicing_ctx.llctx func
                in
                if slicing_ctx.entry_filter fn_loc then true
                else sample_include ())
              entries
          in
          let num_entries = LlvalueSet.cardinal entries in
          if num_entries > 0 then
            let func_counter =
              FunctionCounter.add func_counter callee num_entries
            in
            let edge_entries = EdgeEntriesMap.add edge_entries edge entries in
            (i + 1, func_counter, edge_entries)
          else (i + 1, func_counter, edge_entries)
        else (i + 1, func_counter, edge_entries))
      slicing_ctx.call_graph
      (0, FunctionCounter.empty, EdgeEntriesMap.empty)
  in
  (func_counter, edge_entries)

let slices_from_edges (func_counter : FunctionCounter.t)
    (edge_entries : EdgeEntriesMap.t) (slicing_ctx : SlicingContext.t) :
    int * Slices.t =
  let cache = Utils.EnvCache.empty () in
  EdgeEntriesMap.fold
    (fun edge entries (num_slices, slices) ->
      let caller, instr, callee = edge in
      let count = FunctionCounter.get func_counter callee in
      if count >= !Options.min_freq then
        LlvalueSet.fold
          (fun entry (num_slices, acc) ->
            Printf.printf "Processing slice #%d...\r" num_slices ;
            flush stdout ;
            let entry_set = LlvalueSet.singleton entry in
            let callees =
              let all_callees =
                find_callees (slicing_ctx.depth + 1) slicing_ctx.call_graph
                  callee entry_set entry_set
              in
              LlvalueSet.filter
                (fun callee ->
                  not
                    (slicing_ctx.is_excluding
                       (Utils.GlobalCache.ll_func callee |> Option.get)))
                all_callees
            in
            let location =
              Utils.string_of_instr_location cache slicing_ctx.llctx instr
            in
            let slice =
              Slice.create callees entry caller instr callee location
            in
            let slice =
              if !Options.reduce_slice then
                Slice.reduce slicing_ctx.call_graph slice
              else slice
            in
            (num_slices + 1, slice :: acc))
          entries (num_slices, slices)
      else (num_slices, slices))
    edge_entries (0, [])

let slice llctx llm depth : Slices.t =
  let slicing_ctx = SlicingContext.create llctx llm depth in
  if !Options.output_callgraph then dump_call_graph slicing_ctx.call_graph ;
  let func_counter, edge_entries = call_edges slicing_ctx in
  Printf.printf "\nDone creating edge entries map containing %d call edges\n"
    (EdgeEntriesMap.size edge_entries) ;
  flush stdout ;
  let num_slices, slices =
    slices_from_edges func_counter edge_entries slicing_ctx
  in
  Printf.printf "\nSlicer done creating %d slices\n" num_slices ;
  flush stdout ;
  slices

let occurrence input_file =
  let llctx = Llvm.create_context () in
  let llmem = Llvm.MemoryBuffer.of_file input_file in
  let llm = Llvm_irreader.parse_ir llctx llmem in
  let call_graph = CallGraph.from_llm llm in
  let filter = gen_filter !Options.include_func !Options.exclude_func in
  let func_counter =
    CallGraph.fold_edges_instr_set
      (fun edge func_counter ->
        let caller, _, callee = edge in
        if filter (Llvm.value_name callee) then
          let singleton_caller = LlvalueSet.singleton caller in
          let entries =
            find_entries 1 call_graph singleton_caller LlvalueSet.empty
          in
          let num_entries = LlvalueSet.cardinal entries in
          FunctionCounter.add func_counter callee num_entries
        else func_counter)
      call_graph FunctionCounter.empty
  in
  let func_count_list =
    FunctionCounter.fold
      (fun func count ls ->
        match Utils.GlobalCache.ll_func func with
        | Some fname ->
            (fname, count) :: ls
        | None ->
            ls)
      func_counter []
  in
  let sorted_func_count_list =
    List.sort (fun (_, c1) (_, c2) -> c2 - c1) func_count_list
  in
  let outdir = Options.outdir () in
  Utils.initialize_output_directories outdir ;
  if not !Options.occ_output_json then (
    let file = outdir ^ "/occurrence.csv" in
    let oc = open_out file in
    Printf.fprintf oc "Function,Occurrence\n" ;
    List.iter
      (fun (func_name, count) -> Printf.fprintf oc "%s,%d\n" func_name count)
      sorted_func_count_list )
  else
    let file = outdir ^ "/occurrence.json" in
    let assoc =
      List.map
        (fun (func_name, count) -> (func_name, `Int count))
        sorted_func_count_list
    in
    let json = `Assoc assoc in
    Yojson.Safe.to_file file json

let main input_file =
  let llctx = Llvm.create_context () in
  let llmem = Llvm.MemoryBuffer.of_file input_file in
  let llm = Llvm_irreader.parse_ir llctx llmem in
  let slices = slice llctx llm !Options.slice_depth in
  Slices.dump stdout llm slices
