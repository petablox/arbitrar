open Printf
open Llvm
open Llvm_bitreader

type call_edge = llvalue * llvalue * llvalue (* Caller, Callee, Instruction *)

type call_graph = call_edge list

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
                  let callee_name = value_name callee in
                  let caller_name = value_name func in
                  printf "(%s -> %s); " caller_name callee_name ;
                  (func, callee, instr) :: graph
              | _ ->
                  graph)
            graph block)
        graph func)
    [] llm

(* let get_slices (instr : llinstr) : slice list =


let rec loop_call_graph (cg_all cg : call_graph) (sl : slice list) : slice list =
  match cg with
  | (_, _, instr) :: rst -> loop_call_graph rst ((get_slices instr) ++ sl)
  | [] -> [] *)

let main input_file =
  let llctx = create_context () in
  let llmem = Llvm.MemoryBuffer.of_file input_file in
  let llm = Llvm_bitreader.parse_bitcode llctx llmem in
  let _call_graph = get_call_graph llm in
  ()
