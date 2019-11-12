open Printf
open Llvm
open Llvm_bitreader

type call_edge = llvalue * llvalue * llvalue (* Caller, Callee, Instruction *)

type call_graph = call_edge list

type slice = llvalue list * llvalue * llvalue (* (List of functions, Entry function, Point of interest) *)

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

let print_call_graph (llm : llmodule) (cg : call_graph) : unit =
  List.fold_left (fun _ (caller, callee, instr) ->
    let callee_name = value_name callee in
    let caller_name = value_name caller in
    printf "(%s -> %s); " caller_name callee_name;
  ) () cg;
  printf "\n";
  ()

let rec find_callees (depth : int) (env : call_graph) (caller : llvalue) : (llvalue list) =
  match depth with
  | 0 -> []
  | _ -> List.fold_left (fun acc (clr, cle, _) ->
      if caller == clr then
        acc @ (cle :: (find_callees (depth - 1) env cle))
      else
        acc
    ) [] env

let find_slices (depth : int) (env : call_graph) (ce : call_edge) : slice list =
  let (caller, callee, instr) = ce in
  let callees = find_callees depth env caller in
  [(caller :: callees, caller, instr)]

let print_slices (llm : llmodule) (slices : slice list) : unit =
  List.fold_left (fun _ (callees, entry, instr) ->
    let entry_name = value_name entry in
    let callee_names = List.map (fun f -> value_name f) callees in
    let callee_names_str = String.concat ", " callee_names in
    printf "Slice [ Entry: %s, Functions: %s, Instr: %s ]\n" entry_name callee_names_str (string_of_llvalue instr) ;
    ()
  ) () slices

let main input_file =
  let default_slice_depth = 1 in
  let llctx = create_context () in
  let llmem = Llvm.MemoryBuffer.of_file input_file in
  let llm = Llvm_bitreader.parse_bitcode llctx llmem in

  (* Start getting call graph and after that, slices *)
  let call_graph = get_call_graph llm in
  let slices = List.flatten (List.map (find_slices default_slice_depth call_graph) call_graph) in

  (* Print the stuffs *)
  print_call_graph llm call_graph ;
  print_slices llm slices ;

  ()
