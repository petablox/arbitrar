let string_of_instr instr = Llvm.string_of_llvalue instr |> String.trim

let string_of_lhs instr =
  let s = string_of_instr instr in
  let r = Str.regexp " = " in
  let idx = Str.search_forward r s 0 in
  String.sub s 0 idx
