open Processing
open Checker

module type FEATURE = sig
  type t

  (* The name of the feature, will be the name of the feature JSON *)
  val name : string

  (* Take in a trace folder, do some internal mutation *)
  val init : string -> string -> unit

  (* Take in a function definition (name + type), return whether we
     should include the feature *)
  val filter : Function.t -> bool

  (* Extract a feature from the function definition and a trace *)
  val extract : Function.t -> Trace.t -> t

  (* Turn the feature into a JSON *)
  val to_yojson : t -> Yojson.Safe.t
end

module RetvalFeature = struct
  type t =
    { has_retval_check: bool
    ; check_predicate: Predicate.t option
    ; check_against: Int64.t option
    ; check_branch_taken: bool option
    ; branch_is_zero: bool option
    ; branch_not_zero: bool option }
  [@@deriving to_yojson]

  let name = "retval_check"

  let init _ _ = ()

  let filter func = RetValChecker.filter func

  let extract func trace =
    let results = IcmpBranchChecker.check_retval trace in
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
        { has_retval_check= true
        ; check_predicate= Some pred
        ; check_against= Some i
        ; check_branch_taken= Some (br = Branch.Then)
        ; branch_is_zero= Some is_zero
        ; branch_not_zero= Some not_zero }
    | _ ->
        { has_retval_check= false
        ; check_predicate= None
        ; check_against= None
        ; check_branch_taken= None
        ; branch_is_zero= None
        ; branch_not_zero= None }
end

module ArgvalFeature (A : ARG_INDEX) = struct
  type t =
    { has_argval_check: bool
    ; check_predicate: Predicate.t option
    ; check_against: Int64.t option
    ; check_branch_taken: bool option
    ; branch_is_zero: bool option
    ; branch_not_zero: bool option }
  [@@deriving to_yojson]

  module AVC = ArgValChecker (A)

  let name = Printf.sprintf "argval_%d_check" A.index

  let init _ _ = ()

  let filter = AVC.filter

  let extract _ trace =
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
        { has_argval_check= true
        ; check_predicate= Some pred
        ; check_against= Some i
        ; check_branch_taken= Some (br = Branch.Then)
        ; branch_is_zero= Some is_zero
        ; branch_not_zero= Some not_zero }
    | _ ->
        { has_argval_check= false
        ; check_predicate= None
        ; check_against= None
        ; check_branch_taken= None
        ; branch_is_zero= None
        ; branch_not_zero= None }
end

module StringMap = Map.Make (String)

module CausalityDictionary = struct
  type t = float StringMap.t

  let empty : t = StringMap.empty

  let singleton (normalization : int) caused =
    StringMap.singleton caused (1.0 /. float_of_int normalization)

  let add dict (normalization : int) caused =
    let normalized = 1.0 /. float_of_int normalization in
    StringMap.update caused
      (fun maybe_count ->
        match maybe_count with
        | Some count ->
            Some (count +. normalized)
        | None ->
            Some normalized)
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

  let add dict (num_traces : int) func caused_func =
    StringMap.update func
      (fun maybe_caused_dict ->
        match maybe_caused_dict with
        | Some caused_dict ->
            Some (CausalityDictionary.add caused_dict num_traces caused_func)
        | None ->
            Some (CausalityDictionary.singleton num_traces caused_func))
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
    ; share_return_value: bool
    ; same_context: bool }

  let feature_to_yojson
      {invoked; invoked_more_than_once; share_argument; share_return_value; same_context} =
    `Assoc
      [ ("invoked", `Bool invoked)
      ; ("invoked_more_than_once", `Bool invoked_more_than_once)
      ; ("share_argument", `Bool share_argument)
      ; ("share_return_value", `Bool share_return_value)
      ; ("same_context", `Bool same_context)]

  type t = Yojson.Safe.t

  let dictionary = ref FunctionCausalityDictionary.empty

  let new_feature =
    { invoked= false
    ; invoked_more_than_once= false
    ; share_argument= false
    ; share_return_value= false
    ; same_context= false }

  let gen_exc_filter exc : string -> bool =
    if String.equal exc "" then fun _ -> false
    else
      let exc_reg = Str.regexp exc in
      fun str -> Str.string_match exc_reg str 0

  let function_filter =
    let is_excluding = gen_exc_filter !Options.exclude_func in
    let invalid_starting_char f =
      match f.[0] with '(' | '%' -> true | _ -> false
    in
    fun f -> (not (invalid_starting_char f)) && not (is_excluding f)

  let caused_funcs_helper trace checker : (string * int) list =
    let results = checker trace in
    List.filter_map
      (fun (f, id) -> if function_filter f then Some (f, id) else None)
      results

  let init_helper checker slices_json_dir dugraphs_dir =
    let dict =
      fold_traces slices_json_dir dugraphs_dir
        (fun dict ((func_name, _, num_traces), trace) ->
          Printf.printf "Initializing #%d-#%d \r" trace.slice_id trace.trace_id ;
          let results = caused_funcs_helper trace checker in
          List.fold_left
            (fun dict caused_func_name ->
              FunctionCausalityDictionary.add dict num_traces func_name
                caused_func_name)
            dict (List.map fst results))
        FunctionCausalityDictionary.empty
    in
    dictionary := dict ;
    ()

  let filter _ = true

  let share_value (v1s : Value.t list) (v2s : Value.t list) : bool =
    List.fold_left (fun acc v1 -> acc || List.mem v1 v2s) false v1s

  let share_value_opt (ret : Value.t option) (vs : Value.t list) : bool =
    match ret with Some ret -> List.mem ret vs | None -> false

  let res_and_args (node : Node.t) : Value.t option * Value.t list =
    match node.stmt with
    | Statement.Call {result; args} ->
        (result, args)
    | _ ->
        failwith "[res_and_args] Node should be a call statement"

  let extract_helper checker (func_name, _, _) (trace : Trace.t) =
    let target_result, target_args = res_and_args trace.target_node in
    let target_context = Node.context trace.target_node in
    let results = caused_funcs_helper trace checker in
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
                List.fold_left
                  (fun acc (func, id) ->
                    if func = func_name then
                      let invoked = true in
                      let invoked_more_than_once = acc.invoked in
                      let node = Trace.node trace id in
                      let node_result, node_args = res_and_args node in
                      let share_argument = share_value target_args node_args in
                      let share_return_value =
                        share_value_opt node_result target_args
                        || share_value_opt target_result node_args
                      in
                      let same_context =
                        let node_context = Node.context node in
                        node_context = target_context
                      in
                      { invoked
                      ; invoked_more_than_once
                      ; share_argument= acc.share_argument || share_argument
                      ; share_return_value=
                          acc.share_return_value || share_return_value
                      ; same_context= acc.same_context || same_context }
                    else acc)
                  new_feature results
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

  let init = init_helper CausalityChecker.check_trace

  let extract = extract_helper CausalityChecker.check_trace
end

module InvokedAfterFeature = struct
  include CausalityFeatureHelper (struct
    let dictionary = ref FunctionCausalityDictionary.empty
  end)

  let name = "invoked_after"

  let init = init_helper CausalityChecker.check_trace_backward

  let extract = extract_helper CausalityChecker.check_trace_backward
end

let feature_extractors : (module FEATURE) list =
  [ (module RetvalFeature)
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

let process_trace features_dir func trace =
  let func_name, func_type, num_traces = func in
  (* Iterate through all feature extractors to generate features *)
  let features =
    List.fold_left
      (fun assoc extractor ->
        let module M = (val extractor : FEATURE) in
        if M.filter func then
          let result = M.extract func trace in
          let json_result = M.to_yojson result in
          (M.name, json_result) :: assoc
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

let init_features_dir input_directory =
  let features_dir = input_directory ^ "/features" in
  Utils.mkdir features_dir ; features_dir

let main input_directory =
  Printf.printf "Extracting Features for %s...\n" input_directory ;
  flush stdout ;
  let features_dir = init_features_dir input_directory in
  let dugraphs_dir = input_directory ^ "/dugraphs" in
  let slices_json_dir = input_directory ^ "/slices.json" in
  (* Initialize the extractors with traces *)
  let _ =
    List.iter
      (fun extractor ->
        let module M = (val extractor : FEATURE) in
        Printf.printf "Initializing Feature Extractor %s\n" M.name ;
        M.init dugraphs_dir slices_json_dir)
      feature_extractors
  in
  (* Run extractors on every trace *)
  let _ =
    fold_traces dugraphs_dir slices_json_dir
      (fun _ (func, trace) ->
        Printf.printf "Extracting trace #%d/#%d\r" trace.slice_id trace.trace_id ;
        flush stdout ;
        process_trace features_dir func trace)
      ()
  in
  Printf.printf "Done Feature Extraction\n" ;
  ()
