let string_of_instr instr = Llvm.string_of_llvalue instr |> String.trim

let string_of_lhs instr =
  let s = string_of_instr instr in
  let r = Str.regexp " = " in
  let idx = Str.search_forward r s 0 in
  String.sub s 0 idx

let fold_left_all_instr f a m =
  Llvm.fold_left_functions
    (fun a func ->
      if Llvm.is_declaration func then a
      else
        Llvm.fold_left_blocks
          (fun a blk -> Llvm.fold_left_instrs (fun a instr -> f a instr) a blk)
          a func)
    a m
