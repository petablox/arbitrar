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
    | (IcmpBranchChecker.Checked (pred, i, br)) :: _ ->
        let (is_zero, not_zero) = match (pred, i, br) with
        | Predicate.Eq, 0L, Branch.Then
        | Predicate.Ne, 0L, Branch.Else -> true, false
        | Predicate.Eq, 0L, Branch.Else
        | Predicate.Ne, 0L, Branch.Then -> false, true
        | _ -> false, false
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
        ; branch_not_zero = None }
end

(* module ArgvalFeature (A : ARG_INDEX) = struct
  type t =
    { has_arg_check: bool
    ; check_predicate: Predicate.t option
    ; check_against: Int64.t option
    ; check_branch_taken: bool option
    ; branch_is_zero: bool option
    ; branch_not_zero: bool option }
end *)

module StringMap = Map.Make (String)

module CausalityDictionary = struct
  type t = int StringMap.t

  let empty : t = StringMap.empty

  let singleton caused = StringMap.singleton caused 1

  let add dict caused =
    StringMap.update caused
      (fun maybe_count ->
        match maybe_count with
        | Some count -> Some (count + 1)
        | None -> Some 1)
      dict

  let rec sublist b e l =
    match l with
    | [] -> []
    | h :: t ->
        let tail = if e = 0 then [] else sublist (b - 1) (e - 1) t in
        if b > 0 then tail else h :: tail

  let top dict amount =
    let ls = StringMap.fold
      (fun func count ls -> (func, count) :: ls)
      dict []
    in
    let sorted = List.sort (fun (_, c1) (_, c2) -> c1 - c2) ls in
    let top_sorted = sublist 0 amount sorted in
    List.map fst top_sorted
end

module FunctionCausalityDictionary = struct
  type t = CausalityDictionary.t StringMap.t

  let empty : t = StringMap.empty

  let add dict func caused_func =
    StringMap.update func
      (fun maybe_caused_dict ->
        match maybe_caused_dict with
        | Some caused_dict -> Some (CausalityDictionary.add caused_dict caused_func)
        | None -> Some (CausalityDictionary.singleton caused_func))
      dict

  let find dict func = StringMap.find func dict
end

module InvokedBeforeFeature = struct
  type dict = FunctionCausalityDictionary.t

  type t = Yojson.Safe.t

  let name = "invoked_before"

  let dictionary = ref FunctionCausalityDictionary.empty

  let amount = 10

  let caused_funcs trace : string list =
    let results = CausalityChecker.check_trace trace in
    List.filter_map
      (fun result ->
        match result with
        | CausalityChecker.Causing f -> Some f
        | _ -> None)
      results

  let init slices_json_dir dugraphs_dir =
    let dict = fold_traces slices_json_dir dugraphs_dir
      (fun dict ((func_name, _), trace) ->
        Printf.printf "Initializing #%d-#%d \r" trace.slice_id trace.trace_id ;
        let results = caused_funcs trace in
        List.fold_left
          (fun dict caused_func_name ->
            FunctionCausalityDictionary.add dict func_name caused_func_name)
          dict results)
      FunctionCausalityDictionary.empty
    in
    dictionary := dict ;
    ()

  let filter _ = true

  let extract (func_name, _) trace =
    let results = caused_funcs trace in
    let caused_dict = FunctionCausalityDictionary.find !dictionary func_name in
    let top_caused = CausalityDictionary.top caused_dict amount in
    let assocs = List.fold_left
      (fun assocs func_name ->
        let has_func = List.mem func_name results in
        (func_name, `Bool has_func) :: assocs)
      [] top_caused
    in
    `Assoc assocs

  let to_yojson j = j
end

module InvokedAfterFeature = struct
  type dict = FunctionCausalityDictionary.t

  type t = Yojson.Safe.t

  let name = "invoked_after"

  let dictionary = ref FunctionCausalityDictionary.empty

  let amount = 10

  let caused_funcs trace : string list =
    let results = CausalityChecker.check_trace_backward trace in
    List.filter_map
      (fun result ->
        match result with
        | CausalityChecker.Causing f -> Some f
        | _ -> None)
      results

  let init slices_json_dir dugraphs_dir =
    let dict = fold_traces slices_json_dir dugraphs_dir
      (fun dict ((func_name, _), trace) ->
        Printf.printf "Initializing #%d-#%d \r" trace.slice_id trace.trace_id ;
        let results = caused_funcs trace in
        List.fold_left
          (fun dict caused_func_name ->
            FunctionCausalityDictionary.add dict func_name caused_func_name)
          dict results)
      FunctionCausalityDictionary.empty
    in
    dictionary := dict ;
    ()

  let filter _ = true

  let extract (func_name, _) trace =
    let results = caused_funcs trace in
    let caused_dict = FunctionCausalityDictionary.find !dictionary func_name in
    let top_caused = CausalityDictionary.top caused_dict amount in
    let assocs = List.fold_left
      (fun assocs func_name ->
        let has_func = List.mem func_name results in
        (func_name, `Bool has_func) :: assocs)
      [] top_caused
    in
    `Assoc assocs

  let to_yojson j = j
end

let feature_extractors : (module FEATURE) list =
  [ (module RetvalFeature)
  ; (module InvokedAfterFeature)
  ; (module InvokedBeforeFeature) ]

let process_trace features_dir func trace =
  let (func_name, func_type) = func in
  (* Iterate through all feature extractors to generate features *)
  let features = List.fold_left
    (fun assoc extractor ->
      let module M = (val extractor : FEATURE) in
      if M.filter func then
        let result = M.extract func trace in
        let json_result = M.to_yojson result in
        (M.name, json_result) :: assoc
      else (
        Printf.printf "Have not pass the filter; \n" ;
        assoc)
    ) [] feature_extractors
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
  let _ = List.iter
    (fun extractor ->
      let module M = (val extractor : FEATURE) in
      Printf.printf "Initializing Feature Extractor %s\n" M.name ;
      M.init dugraphs_dir slices_json_dir)
    feature_extractors
  in
  (* Run extractors on every trace *)
  let _ = fold_traces dugraphs_dir slices_json_dir
    (fun _ (func, trace) ->
      Printf.printf "Extracting trace #%d/#%d\r" trace.slice_id trace.trace_id ;
      flush stdout ;
      process_trace features_dir func trace
    ) ()
  in
  Printf.printf "Done Feature Extraction\n" ;
  ()
