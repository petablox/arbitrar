open Printf

let get_filename (argv : string array) (index : int) : string =
  if Array.length argv > 2 then
    Filename.concat (Sys.getcwd ()) argv.(index)
  else failwith "Please specify file to analyze"

let main (argv : string array) : unit =
  printf "Hello world";
;;

main Sys.argv;;