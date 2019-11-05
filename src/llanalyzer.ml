open Printf
open Llvm
open Llvm_bitreader

type call_edge =
  | Call of llvalue * llvalue
  | Ret of llvalue * llvalue

type call_graph = call_edge list

let get_call_graph (llm : llmodule) : call_graph =
  fold_left_functions (fun graph func ->
    fold_left_blocks (fun graph block ->
      fold_left_instrs (fun graph instr ->
        let opcode = instr_opcode instr in
        match opcode with
        | Call -> let () = dump_value instr in graph
        | _ -> graph
      ) graph block
    ) graph func
  ) [] llm

let get_filename (argv : string array) (index : int) : string =
  if Array.length argv >= 2 then
    Filename.concat (Sys.getcwd ()) argv.(index)
  else failwith "Please specify file to analyze"

let main (argv : string array) : unit =
  let llctx = create_context () in
  let llmem = Llvm.MemoryBuffer.of_file (get_filename argv 1) in
  let llm = Llvm_bitreader.parse_bitcode llctx llmem in
  let _ = get_call_graph llm in
  ()
;;

main Sys.argv;;