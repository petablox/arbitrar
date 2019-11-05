open Printf
open Llvm
open Llvm_bitreader

let get_filename (argv : string array) (index : int) : string =
  if Array.length argv > 2 then
    Filename.concat (Sys.getcwd ()) argv.(index)
  else failwith "Please specify file to analyze"

let main (argv : string array) : unit =
  let llctx = create_context () in
  let llmem = Llvm.MemoryBuffer.of_file "./examples/example_1.bc" in
  let llm = Llvm_bitreader.parse_bitcode llctx llmem in
  Llvm.dump_module llm;
  ()
;;

main Sys.argv;;