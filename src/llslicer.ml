open Printf
open Llvm
open Llvm_bitreader

module CallEdge = struct
  type t = {caller: llvalue; callee: llvalue; instr: llvalue}

  let create caller callee instr = {caller; callee; instr}
end

module CallGraph = struct
  type t = CallEdge.t list

  let empty = []

  let add_edge graph caller callee instr =
    CallEdge.create caller callee instr :: graph
end

module Slice = struct
  type t = {functions: llvalue list; entry: llvalue; call_edge: CallEdge.t}

  let create functions entry call_edge = {functions; entry; call_edge}
end

let get_call_graph (llm : llmodule) : CallGraph.t =
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

let print_call_edge (llm : llmodule) (ce : CallEdge.t) : unit =
  let callee_name = value_name ce.callee in
  let caller_name = value_name ce.caller in
  printf "(%s -> %s); " caller_name callee_name ;
  ()

let print_call_graph (llm : llmodule) (cg : CallGraph.t) : unit =
  List.fold_left (fun _ ce -> print_call_edge llm ce) () cg ;
  printf "\n" ;
  ()

let rec find_entries (depth : int) (env : CallGraph.t) (target : llvalue) :
    (llvalue * int) list =
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

let rec find_callees (depth : int) (env : CallGraph.t) (target : llvalue) :
    llvalue list =
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

let need_find_slices_for_edge (llm : llmodule) (ce : CallEdge.t) : bool =
  match !Options.target_function_name with
  | "" ->
      true
  | n ->
      let callee_name = value_name ce.callee in
      String.equal callee_name n

let find_slices llm depth env (ce : CallEdge.t) : Slice.t list =
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

let print_slices oc (llm : llmodule) (slices : Slice.t list) : unit =
  List.fold_left
    (fun _ (slice : Slice.t) ->
      let entry_name = value_name slice.entry in
      let func_names = List.map (fun f -> value_name f) slice.functions in
      let func_names_str = String.concat ", " func_names in
      let callee_name = value_name slice.call_edge.callee in
      let caller_name = value_name slice.call_edge.caller in
      let instr_str = string_of_llvalue slice.call_edge.instr in
      let call_str = Printf.sprintf "(%s -> %s)" caller_name callee_name in
      fprintf oc "Slice { Entry: %s, Functions: %s, Call: %s, Instr: %s }\n"
        entry_name func_names_str call_str instr_str ;
      ())
    () slices

let slice (llm : llmodule) (slice_depth : int) : Slice.t list =
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
