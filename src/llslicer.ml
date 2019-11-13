open Printf
open Llvm
open Llvm_bitreader

(* Caller, Callee, Instruction *)
type call_edge = llvalue * llvalue * llvalue

type call_graph = call_edge list

(* (List of functions, Entry function, Point of interest) *)
type slice = llvalue list * llvalue * call_edge

let get_call_graph (llm : llmodule) : call_graph =
  fold_left_functions
    (fun graph func ->
      fold_left_blocks
        (fun graph block ->
          fold_left_instrs
            (fun graph instr ->
              let opcode = instr_opcode instr in
              match opcode with
              | Call ->
                  let callee = operand instr (num_operands instr - 1) in
                  (func, callee, instr) :: graph
              | _ ->
                  graph)
            graph block)
        graph func)
    [] llm

let print_call_edge (llm : llmodule) (ce : call_edge) : unit =
  let caller, callee, instr = ce in
  let callee_name = value_name callee in
  let caller_name = value_name caller in
  printf "(%s -> %s); " caller_name callee_name ;
  ()

let print_call_graph (llm : llmodule) (cg : call_graph) : unit =
  List.fold_left (fun _ ce -> print_call_edge llm ce) () cg ;
  printf "\n" ;
  ()

let rec find_entries (depth : int) (env : call_graph) (callee : llvalue) :
    (llvalue * int) list =
  match depth with
  | 0 ->
      [(callee, 0)]
  | _ ->
      let callers =
        List.fold_left
          (fun acc (clr, cle, _) ->
            if cle == callee then find_entries (depth - 1) env clr @ acc
            else acc)
          [] env
      in
      if List.length callers == 0 then [(callee, depth)] else callers

let rec find_callees (depth : int) (env : call_graph) (caller : llvalue) :
    llvalue list =
  match depth with
  | 0 ->
      []
  | _ ->
      List.fold_left
        (fun acc (clr, cle, _) ->
          if caller == clr then acc @ (cle :: find_callees (depth - 1) env cle)
          else acc)
        [] env

let rec unique (f : 'a -> 'a -> bool) (funcs : 'a list) : 'a list =
  match funcs with
  | hd :: tl ->
      let tl_no_hd = List.filter (fun x -> not (f hd x)) tl in
      let uniq_rest = unique f tl_no_hd in
      hd :: uniq_rest
  | [] ->
      []

let rec without (f : 'a -> bool) (funcs : 'a list) : 'a list =
  match funcs with
  | [] ->
      []
  | hd :: tl ->
      if f hd then without f tl else hd :: without f tl

let need_find_slices_for_edge (llm : llmodule) (ce : call_edge) : bool =
  match !Options.target_function_name with
  | "" ->
      true
  | n ->
      let _, callee, _ = ce in
      let callee_name = value_name callee in
      String.equal callee_name n

let find_slices llm depth env ce : slice list =
  if need_find_slices_for_edge llm ce then
    let caller, callee, _ = ce in
    let entries = find_entries depth env caller in
    let uniq_entries = unique (fun (a, _) (b, _) -> a == b) entries in
    let slices =
      List.map
        (fun (entry, up_count) ->
          let callees = find_callees ((depth * 2) - up_count) env entry in
          let uniq_funcs = unique ( == ) (entry :: callees) in
          let uniq_funcs_without_callee = without (( == ) callee) uniq_funcs in
          (uniq_funcs_without_callee, entry, ce))
        uniq_entries
    in
    slices
  else []

let print_slices oc (llm : llmodule) (slices : slice list) : unit =
  List.fold_left
    (fun _ (callees, entry, call_edge) ->
      let entry_name = value_name entry in
      let callee_names = List.map (fun f -> value_name f) callees in
      let callee_names_str = String.concat ", " callee_names in
      let caller, callee, instr = call_edge in
      let callee_name = value_name callee in
      let caller_name = value_name caller in
      let call_str = Printf.sprintf "(%s -> %s)" caller_name callee_name in
      fprintf oc "Slice { Entry: %s, Functions: %s, Call: %s, Instr: %s }\n"
        entry_name callee_names_str call_str (string_of_llvalue instr) ;
      ())
    () slices

let slice (llm : llmodule) (slice_depth : int) : slice list =
  let call_graph = get_call_graph llm in
  let slices =
    List.map (find_slices llm slice_depth call_graph) call_graph
    |> List.flatten
  in
  slices

let main input_file =
  let llctx = create_context () in
  let llmem = Llvm.MemoryBuffer.of_file input_file in
  let llm = Llvm_bitreader.parse_bitcode llctx llmem in
  let slices = slice llm !Options.slice_depth in
  print_slices stdout llm slices ;
  ()
