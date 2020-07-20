open Processing
open Checker

module type FEATURE = sig
  type t

  (* The name of the feature, will be the name of the feature JSON *)
  val name : string

  (* Take in a single trace, do some internal mutation *)
  val init_with_trace : Function.t -> Trace.t -> unit

  (* Take in a function definition (name + type), return whether we
     should include the feature *)
  val filter : Function.t -> bool

  (* Extract a feature from the function definition and a trace *)
  val extract : Function.t -> Trace.t -> t

  (* Turn the feature into a JSON *)
  val to_yojson : t -> Yojson.Safe.t
end

module ContextFeature = struct
  type t = {no_context: bool} [@@deriving to_yojson]

  let name = "context"

  let init_with_trace _ _ = ()

  let filter _ = true

  let rec used_in_location (ret : Value.t) (loc : Location.t) : bool =
    match loc with
    | Location.SymExpr e ->
        ret = Value.SymExpr e
    | Location.Gep (l, _) ->
        used_in_location ret l
    | _ ->
        false

  (* Assuming store/load/ret does not count as "use" *)
  let used_in_stmt (ret : Value.t) (stmt : Statement.t) : bool =
    match stmt with
    | Call {args} ->
        List.find_opt (( = ) ret) args |> Option.is_some
    | Assume {op0; op1} ->
        op0 = ret || op1 = ret
    | Binary {op0; op1} ->
        op0 = ret || op1 = ret
    | Store {loc; value} ->
        let used_in_loc =
          match loc with
          | Location loc ->
              used_in_location ret loc
          | _ ->
              loc = ret
        in
        used_in_loc || value = ret
    | GetElementPtr {op0} ->
        op0 = ret
    | _ ->
        false

  let initialized_in_stmt (arg : Value.t) (stmt : Statement.t) : bool =
    match stmt with
    | Call {result= Some res} ->
        arg = res
    | Assume {result} ->
        arg = result
    | Load {result} ->
        arg = result
    | Alloca {result} ->
        arg = result
    | Binary {result} ->
        arg = result
    | _ ->
        false

  let rec arg_initialized dugraph explored fringe arg =
    match NodeSet.choose_opt fringe with
    | Some hd ->
        let rst = NodeSet.remove hd fringe in
        if NodeSet.mem hd explored then arg_initialized dugraph explored rst arg
        else if initialized_in_stmt arg hd.stmt then true
        else
          let explored = NodeSet.add hd explored in
          let predecessors = NodeSet.of_list (NodeGraph.pred dugraph hd) in
          let fringe = NodeSet.union predecessors rst in
          arg_initialized dugraph explored fringe arg
    | None ->
        false

  let args_initialized (trace : Trace.t) : bool =
    match trace.target_node.stmt with
    | Call {args} ->
        let non_const_args =
          List.filter (fun arg -> Value.is_const arg |> not) args
        in
        if List.length non_const_args = 0 then false
        else
          let fringe = NodeSet.singleton trace.target_node in
          List.map
            (arg_initialized trace.dugraph NodeSet.empty fringe)
            non_const_args
          |> List.fold_left ( && ) true
    | _ ->
        false

  let rec result_used_helper ret dugraph explored fringe =
    match NodeSet.choose_opt fringe with
    | Some hd ->
        if NodeSet.mem hd explored then false
        else if used_in_stmt ret hd.stmt then true
        else
          let rst = NodeSet.remove hd fringe in
          let explored = NodeSet.add hd explored in
          let successors = NodeSet.of_list (NodeGraph.succ dugraph hd) in
          let fringe = NodeSet.union successors rst in
          result_used_helper ret dugraph explored fringe
    | None ->
        false

  let result_used (trace : Trace.t) : bool =
    match trace.target_node.stmt with
    | Call {result} -> (
      match result with
      | Some ret ->
          let sgt_target = NodeSet.singleton trace.target_node in
          result_used_helper ret trace.dugraph NodeSet.empty sgt_target
      | None ->
          false )
    | _ ->
        false

  let extract _ trace =
    let has_context = args_initialized trace || result_used trace in
    {no_context= not has_context}
end

module Usage = struct
  type t = UsedInCall | UsedInLoad | UsedInStore | UsedInGEP
end

module RetvalFeature = struct
  type t =
    { related_to_check: bool
    ; has_retval_check: bool
    ; has_other_retval_check: bool
    ; used_in_logical_formula: bool
    ; check_branch_taken: bool option
    ; branch_is_zero: bool option
    ; branch_not_zero: bool option
    ; used_after: bool }
  [@@deriving to_yojson]

  type temp_result = IcmpResult of t | LogicalResult of t | None

  let base_result =
    { related_to_check= false
    ; has_retval_check= false
    ; has_other_retval_check= false
    ; used_in_logical_formula= false
    ; check_branch_taken= None
    ; branch_is_zero= None
    ; branch_not_zero= None
    ; used_after= false }

  let name = "retval"

  let init_with_trace _ _ = ()

  let filter (_, (ret_ty, _), _) = not (TypeKind.Void = ret_ty)

  let target_result (trace : Trace.t) =
    let target = trace.target_node in
    match target.stmt with
    | Statement.Call {result= Some result} ->
        result
    | _ ->
        raise Utils.InvalidArgument

  let extract_uses (trace : Trace.t) =
    let target = trace.target_node in
    let ret = target_result trace in
    let results =
      NodeGraph.traversal trace.cfgraph target true
        (fun results node ->
          match node.stmt with
          | Statement.Load {loc} ->
              if ret = loc then Usage.UsedInLoad :: results else results
          | Statement.Store {loc} ->
              if ret = loc then Usage.UsedInStore :: results else results
          | Statement.GetElementPtr {op0} ->
              if ret = op0 then Usage.UsedInGEP :: results else results
          | _ ->
              results)
        []
    in
    let used_after = List.length results > 0 in
    used_after

  let extract func trace =
    let results = IcmpBranchChecker.check_retval trace in
    let rec recurse_results results =
      match results with
      | IcmpBranchChecker.Checked (pred, i, br, immediate) :: _ ->
          let is_zero, not_zero =
            match (pred, i, br, immediate) with
            | Predicate.Eq, 0L, Branch.Then, true
            | Predicate.Ne, 0L, Branch.Else, true ->
                (true, false)
            | Predicate.Eq, 0L, Branch.Else, true
            | Predicate.Ne, 0L, Branch.Then, true ->
                (false, true)
            | _ ->
                (false, false)
          in
          IcmpResult
            { base_result with
              related_to_check= true
            ; has_retval_check= true
            ; check_branch_taken= Some (br = Branch.Then)
            ; branch_is_zero= Some is_zero
            ; branch_not_zero= Some not_zero }
      | IcmpBranchChecker.CheckedAgainstVar (_, br) :: _ ->
          IcmpResult
            { base_result with
              related_to_check= true
            ; has_retval_check= true
            ; check_branch_taken= Some (br = Branch.Then) }
      | IcmpBranchChecker.CheckedOtherVar (_, br) :: _ ->
          IcmpResult
            { base_result with
              related_to_check= true
            ; has_other_retval_check= true
            ; check_branch_taken= Some (br = Branch.Then) }
      | IcmpBranchChecker.UsedInLogicalFormula _ :: rs -> (
          let rest_result = recurse_results rs in
          match rest_result with
          | None ->
              LogicalResult
                { base_result with
                  related_to_check= true
                ; used_in_logical_formula= true }
          | _ ->
              rest_result )
      | _ ->
          None
    in
    let check_result =
      match recurse_results results with
      | IcmpResult r ->
          r
      | LogicalResult r ->
          r
      | None ->
          base_result
    in
    let used_after = extract_uses trace in
    {check_result with used_after}
end

module ArgvalFeature (A : ARG_INDEX) = struct
  type check_result = Check of bool * bool * bool | NoCheck

  type t =
    { has_argval_check: bool (* Argval Check Features *)
    ; check_branch_taken: bool option
    ; branch_is_zero: bool option
    ; branch_not_zero: bool option
    ; used_after: bool (* Usage Features *)
    ; used_in_call: bool
    ; used_in_store: bool
    ; used_in_load: bool
    ; used_in_gep: bool }
  [@@deriving to_yojson]

  module AVC = ArgValChecker (A)

  let name = Printf.sprintf "argval_%d" A.index

  let init_with_trace _ _ = ()

  let filter = AVC.filter

  let target_arg (trace : Trace.t) =
    let target = trace.target_node in
    match target.stmt with
    | Statement.Call {args} ->
        List.nth args A.index
    | _ ->
        raise Utils.InvalidArgument

  let extract_check_result trace =
    let results = IcmpBranchChecker.check_argval trace A.index in
    match results with
    | IcmpBranchChecker.Checked (pred, i, br, immediate) :: _ ->
        let is_zero, not_zero =
          match (pred, i, br, immediate) with
          | Predicate.Eq, 0L, Branch.Then, true
          | Predicate.Ne, 0L, Branch.Else, true ->
              (true, false)
          | Predicate.Eq, 0L, Branch.Else, true
          | Predicate.Ne, 0L, Branch.Then, true ->
              (false, true)
          | _ ->
              (false, false)
        in
        (true, Some (br = Branch.Then), Some is_zero, Some not_zero)
    | _ ->
        (false, None, None, None)

  let extract_uses (trace : Trace.t) =
    let target = trace.target_node in
    let arg = target_arg trace in
    let results =
      NodeGraph.traversal trace.cfgraph target true
        (fun results node ->
          match node.stmt with
          | Statement.Call {args} ->
              if List.mem arg args then Usage.UsedInCall :: results else results
          | Statement.Load {loc} ->
              if arg = loc then Usage.UsedInLoad :: results else results
          | Statement.Store {loc} ->
              if arg = loc then Usage.UsedInStore :: results else results
          | Statement.GetElementPtr {op0} ->
              if arg = op0 then Usage.UsedInGEP :: results else results
          | _ ->
              results)
        []
    in
    let used = List.length results > 0 in
    let used_in_call = List.mem Usage.UsedInCall results in
    let used_in_load = List.mem Usage.UsedInLoad results in
    let used_in_store = List.mem Usage.UsedInStore results in
    let used_in_gep = List.mem Usage.UsedInGEP results in
    (used, used_in_call, used_in_load, used_in_store, used_in_gep)

  let extract _ trace =
    let has_argval_check, check_branch_taken, branch_is_zero, branch_not_zero =
      extract_check_result trace
    in
    let used_after, used_in_call, used_in_load, used_in_store, used_in_gep =
      extract_uses trace
    in
    { has_argval_check
    ; check_branch_taken
    ; branch_is_zero
    ; branch_not_zero
    ; used_after
    ; used_in_call
    ; used_in_load
    ; used_in_store
    ; used_in_gep }
end

module StringMap = Map.Make (String)

module CausalityDictionary = struct
  type t = float StringMap.t

  let empty : t = StringMap.empty

  let singleton (caused : string) (score : float) =
    StringMap.singleton caused score

  let add (dict : t) (caused : string) (score : float) =
    StringMap.update caused
      (fun maybe_agg ->
        match maybe_agg with
        | Some agg ->
            Some (agg +. score)
        | None ->
            Some score)
      dict

  let find dict f =
    match StringMap.find_opt f dict with Some i -> i | None -> 0

  let rec sublist b e l =
    match l with
    | [] ->
        []
    | h :: t ->
        let tail = if e = 0 then [] else sublist (b - 1) (e - 1) t in
        if b > 0 then tail else h :: tail

  let sign_of_float (f : float) : int =
    if f > 0.0 then 1 else if f = 0.0 then 0 else -1

  let top (dict : t) (amount : int) =
    let ls =
      StringMap.fold
        (fun func count ls ->
          if func = "unknown" then ls
            (* No unknown function in the dictionary *)
          else (func, count) :: ls)
        dict []
    in
    let sorted =
      List.sort (fun (_, c1) (_, c2) -> sign_of_float (c2 -. c1)) ls
    in
    let top_sorted = sublist 0 amount sorted in
    List.map fst top_sorted
end

module FunctionCausalityDictionary = struct
  type t = CausalityDictionary.t StringMap.t

  let empty : t = StringMap.empty

  let add dict func caused_func score =
    StringMap.update func
      (fun maybe_caused_dict ->
        match maybe_caused_dict with
        | Some caused_dict ->
            Some (CausalityDictionary.add caused_dict caused_func score)
        | None ->
            Some (CausalityDictionary.singleton caused_func score))
      dict

  let find dict func = StringMap.find func dict

  let find_opt dict func = StringMap.find_opt func dict

  let print dict =
    StringMap.iter
      (fun func caused_func ->
        Printf.printf "=======\n" ;
        Printf.printf "%s" func ;
        Printf.printf "=======\n" ;
        StringMap.iter
          (fun caused count -> Printf.printf "%s: %f\n" caused count)
          caused_func)
      dict
end

module type DICTIONARY_HOLDER = sig
  val dictionary : FunctionCausalityDictionary.t ref
end

module CausalityFeatureHelper (D : DICTIONARY_HOLDER) = struct
  type feature =
    { invoked: bool
    ; invoked_more_than_once: bool
    ; share_argument: bool
    ; share_argument_type: bool
    ; share_return_value: bool
    ; same_context: bool }

  let feature_to_yojson
      { invoked
      ; invoked_more_than_once
      ; share_argument
      ; share_argument_type
      ; share_return_value
      ; same_context } =
    `Assoc
      [ ("invoked", `Bool invoked)
      ; ("invoked_more_than_once", `Bool invoked_more_than_once)
      ; ("share_argument", `Bool share_argument)
      ; ("share_argument_type", `Bool share_argument_type)
      ; ("share_return_value", `Bool share_return_value)
      ; ("same_context", `Bool same_context) ]

  type t = Yojson.Safe.t

  let dictionary = ref FunctionCausalityDictionary.empty

  let filter _ = true

  let new_feature =
    { invoked= false
    ; invoked_more_than_once= false
    ; share_argument= false
    ; share_argument_type= false
    ; share_return_value= false
    ; same_context= false }

  let gen_exc_filter exc : string -> bool =
    if String.equal exc "" then fun _ -> false
    else
      let exc_reg = Str.regexp exc in
      fun str -> Str.string_match exc_reg str 0

  let function_filter : string -> bool =
    let is_excluding = gen_exc_filter !Options.exclude_func in
    let invalid_starting_char f =
      match f.[0] with '(' | '%' -> true | _ -> false
    in
    let asm_reg = Str.regexp " asm " in
    fun f ->
      if (not (invalid_starting_char f)) && not (is_excluding f) then
        try
          let _ = Str.search_forward asm_reg f 0 in
          false
        with _ -> true
      else false

  let share_value (v1s : Value.t list) (v2s : Value.t list) : bool =
    List.fold_left (fun acc v1 -> acc || List.mem v1 v2s) false v1s

  let share_value_opt (ret : Value.t option) (vs : Value.t list) : bool =
    match ret with Some ret -> List.mem ret vs | None -> false

  let share_type (ts1 : TypeKind.t list) (ts2 : TypeKind.t list) : bool =
    List.fold_left
      (fun acc t1 ->
        let temp_share_type =
          List.fold_left
            (fun acc t2 ->
              acc || Slicer.TypeKindHelpers.have_common_struct t1 t2)
            false ts2
        in
        acc || temp_share_type)
      false ts1

  type call =
    { func: string
    ; func_type: FunctionType.t
    ; args: Value.t list
    ; arg_types: TypeKind.t list
    ; result: Value.t option }

  let call_of_node (node : Node.t) =
    match node.stmt with
    | Call {func; func_type; args; arg_types; result} ->
        {func; func_type; args; arg_types; result}
    | _ ->
        raise Utils.InvalidArgument

  let traverse_call (trace : Trace.t) forward fold base =
    NodeGraph.traversal trace.cfgraph trace.target_node forward
      (fun agg node ->
        match node.stmt with
        | Call {func} ->
            if function_filter func then
              let call = call_of_node node in
              fold agg (node, call)
            else agg
        | _ ->
            agg)
      base

  let causal_score call_1 call_2 =
    let share_arg_score =
      if share_value call_1.args call_2.args then 2.0 else 0.0
    in
    let share_ret_score =
      if
        share_value_opt call_1.result call_2.args
        || share_value_opt call_2.result call_1.args
      then 2.0
      else 0.0
    in
    let share_ty_score =
      if share_type call_1.arg_types call_2.arg_types then 1.0 else 0.0
    in
    1.0 +. share_arg_score +. share_ret_score +. share_ty_score

  let init_with_trace_helper (forward : bool) (func_name, _, num_traces)
      (trace : Trace.t) =
    let normalize = 1.0 /. float_of_int num_traces in
    let target = trace.target_node in
    let target_call = call_of_node target in
    let results =
      traverse_call trace forward
        (fun results (_, caused_call) ->
          let {func} = caused_call in
          let score = causal_score target_call caused_call in
          let normalized_score = score *. normalize in
          (func, normalized_score) :: results)
        []
    in
    let dict =
      List.fold_left
        (fun dict (caused_func_name, score) ->
          FunctionCausalityDictionary.add dict func_name caused_func_name score)
        !dictionary results
    in
    dictionary := dict

  let extract_helper forward (func_name, _, _) (trace : Trace.t) =
    let target_call = call_of_node trace.target_node in
    let target_context = Node.context trace.target_node in
    let maybe_caused_dict =
      FunctionCausalityDictionary.find_opt !dictionary func_name
    in
    match maybe_caused_dict with
    | Some caused_dict ->
        let top_caused =
          CausalityDictionary.top caused_dict !Options.causality_dict_size
        in
        let assocs =
          List.fold_left
            (fun assocs func_name ->
              let feature =
                traverse_call trace forward
                  (fun acc (node, call) ->
                    let {func} = call in
                    if func = func_name then
                      let invoked = true in
                      let invoked_more_than_once = acc.invoked in
                      let share_argument =
                        share_value target_call.args call.args
                      in
                      let share_argument_type =
                        share_type target_call.arg_types call.arg_types
                      in
                      let share_return_value =
                        share_value_opt call.result target_call.args
                        || share_value_opt target_call.result call.args
                      in
                      let same_context =
                        let node_context = Node.context node in
                        node_context = target_context
                      in
                      { invoked
                      ; invoked_more_than_once
                      ; share_argument= acc.share_argument || share_argument
                      ; share_argument_type=
                          acc.share_argument_type || share_argument_type
                      ; share_return_value=
                          acc.share_return_value || share_return_value
                      ; same_context= acc.same_context || same_context }
                    else acc)
                  new_feature
              in
              (func_name, feature_to_yojson feature) :: assocs)
            [] top_caused
        in
        `Assoc assocs
    | None ->
        `Assoc []

  let to_yojson j = j
end

module InvokedBeforeFeature = struct
  include CausalityFeatureHelper (struct
    let dictionary = ref FunctionCausalityDictionary.empty
  end)

  let name = "invoked_before"

  let init_with_trace = init_with_trace_helper true

  let extract = extract_helper true
end

module InvokedAfterFeature = struct
  include CausalityFeatureHelper (struct
    let dictionary = ref FunctionCausalityDictionary.empty
  end)

  let name = "invoked_after"

  let init_with_trace = init_with_trace_helper false

  let extract = extract_helper false
end

module LoopFeature = struct
  type t = {contains_loop: bool} [@@deriving to_yojson]

  let name = "loop"

  let filter _ = true

  let init_with_trace _ _ = ()

  let extract _ (trace : Trace.t) =
    let contains_loop =
      NodeGraph.fold_vertex
        (fun (node : Node.t) (contains_loop : bool) ->
          match node.stmt with
          | Statement.UnconditionalBranch {is_loop} ->
              contains_loop || is_loop
          | _ ->
              contains_loop)
        trace.cfgraph false
    in
    {contains_loop}
end

let feature_extractors : (module FEATURE) list =
  [ (module LoopFeature)
  ; (module ContextFeature)
  ; (module RetvalFeature)
  ; (module InvokedAfterFeature)
  ; (module InvokedBeforeFeature)
  ; ( module ArgvalFeature (struct
      let index = 0
    end) )
  ; ( module ArgvalFeature (struct
      let index = 1
    end) )
  ; ( module ArgvalFeature (struct
      let index = 2
    end) )
  ; ( module ArgvalFeature (struct
      let index = 3
    end) ) ]

let process_trace features_dir func (trace : Trace.t) =
  let func_name, func_type, num_traces = func in
  (* Iterate through all feature extractors to generate features *)
  let features =
    List.fold_left
      (fun assoc extractor ->
        let module M = (val extractor : FEATURE) in
        if M.filter func then (
          Printf.printf "Extracting trace %d/%d with %s    \r" trace.slice_id
            trace.trace_id M.name ;
          let result = M.extract func trace in
          let json_result = M.to_yojson result in
          (M.name, json_result) :: assoc )
        else assoc)
      [] feature_extractors
  in
  let json = `Assoc features in
  let func_dir = Printf.sprintf "%s/%s" features_dir func_name in
  Utils.mkdir func_dir ;
  let outfile =
    Printf.sprintf "%s/%d-%d.json" func_dir trace.slice_id trace.trace_id
  in
  Yojson.Safe.to_file outfile json

let init_features_dirs input_directory =
  if !Options.use_batch then
    List.map
      (fun batch_folder ->
        let batch_feature_dir = batch_folder ^ "/features" in
        Utils.mkdir batch_feature_dir ;
        (batch_folder, batch_feature_dir))
      (batch_folders input_directory)
  else
    let features_dir = input_directory ^ "/features" in
    Utils.mkdir features_dir ;
    [(input_directory, features_dir)]

let main input_directory =
  Printf.printf "Extracting Features for %s...\n" input_directory ;
  flush stdout ;
  let out_dirs = init_features_dirs input_directory in
  (* Initialize the extractors with traces *)
  let _ =
    fold_traces input_directory
      (fun _ (func, trace) ->
        Printf.printf "Initializing with trace %d/%d   \r" trace.slice_id
          trace.trace_id ;
        flush stdout ;
        List.iter
          (fun extractor ->
            let module M = (val extractor : FEATURE) in
            M.init_with_trace func trace)
          feature_extractors)
      ()
  in
  (* Run extractors on every trace *)
  let _ =
    List.iteri
      (fun i (batch_dir, batch_feature_dir) ->
        if !Options.use_batch then
          Printf.printf "Doing feature extraction on batch %d...\n" i ;
        fold_traces_normal batch_dir
          (fun _ (func, trace) ->
            flush stdout ;
            process_trace batch_feature_dir func trace)
          ())
      out_dirs
  in
  Printf.printf "Done Feature Extraction\n" ;
  ()
