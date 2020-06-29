exception InvalidJSON

exception NotImplemented

exception InvalidArgument

exception InvalidFunctionType

exception InvalidSwitchCase

exception NonConstantInConstExpr

(* System operation *)

module F = Format

let range (i : int) : int list =
  let rec aux n acc = if n < 0 then acc else aux (n - 1) (n :: acc) in
  aux (i - 1) []

let mkdir dirname =
  (* Printf.printf "Creating directory %s\n" dirname ; *)
  if Sys.file_exists dirname && Sys.is_directory dirname then ()
  else if Sys.file_exists dirname && not (Sys.is_directory dirname) then
    let _ = F.fprintf F.err_formatter "Error: %s already exists." dirname in
    exit 1
  else Unix.mkdir dirname 0o755

let contains s1 s2 =
  try
    let len = String.length s2 in
    for i = 0 to String.length s1 - len do
      if String.sub s1 i len = s2 then raise Exit
    done ;
    false
  with Exit -> true

let range n =
  let rec aux acc i =
    if i = 0 then i :: acc else aux ((i - 1) :: acc) (i - 1)
  in
  aux [] n

let name_of_ll_value_kind (vk : Llvm.ValueKind.t) : string =
  match vk with
  | Llvm.ValueKind.NullValue ->
      "NullValue"
  | Argument ->
      "Argument"
  | BasicBlock ->
      "BasicBlock"
  | InlineAsm ->
      "InlineAsm"
  | MDNode ->
      "MDNode"
  | MDString ->
      "MDString"
  | BlockAddress ->
      "BlockAddress"
  | ConstantAggregateZero ->
      "ConstantAggregateZero"
  | ConstantArray ->
      "ConstantArray"
  | ConstantDataArray ->
      "ConstantDataArray"
  | ConstantDataVector ->
      "ConstantDataVector"
  | ConstantExpr ->
      "ConstantExpr"
  | ConstantFP ->
      "ConstantFP"
  | ConstantInt ->
      "ConstantInt"
  | ConstantPointerNull ->
      "ConstantPointerNull"
  | ConstantStruct ->
      "ConstantStruct"
  | ConstantVector ->
      "ConstantVector"
  | Function ->
      "Function"
  | GlobalAlias ->
      "GlobalAlias"
  | GlobalVariable ->
      "GlobalVariable"
  | GlobalIFunc ->
      "GlobalIFunc"
  | UndefValue ->
      "UndefValue"
  | Instruction _ ->
      "Instruction"

let name_of_opcode (opcode : Llvm.Opcode.t) : string =
  match opcode with
  | Invalid ->
      "Invalid" (* Not an instruction *)
  | Ret ->
      "Ret" (* Terminator Instructions *)
  | Br ->
      "Br"
  | Switch ->
      "Switch"
  | IndirectBr ->
      "IndirectBr"
  | Invoke ->
      "Invoke"
  | Invalid2 ->
      "Invalid2"
  | Unreachable ->
      "Unreachable"
  | Add ->
      "Add" (* Standard Binary Operators *)
  | FAdd ->
      "FAdd"
  | Sub ->
      "Sub"
  | FSub ->
      "FSub"
  | Mul ->
      "Mul"
  | FMul ->
      "FMul"
  | UDiv ->
      "UDiv"
  | SDiv ->
      "SDiv"
  | FDiv ->
      "FDiv"
  | URem ->
      "URem"
  | SRem ->
      "SRem"
  | FRem ->
      "FRem"
  | Shl ->
      "Shl" (* Logical Operators *)
  | LShr ->
      "LShr"
  | AShr ->
      "AShr"
  | And ->
      "And"
  | Or ->
      "Or"
  | Xor ->
      "Xor"
  | Alloca ->
      "Alloca" (* Memory Operators *)
  | Load ->
      "Load"
  | Store ->
      "Store"
  | GetElementPtr ->
      "GetElementPtr"
  | Trunc ->
      "Trunc" (* Cast Operators *)
  | ZExt ->
      "ZExt"
  | SExt ->
      "SExt"
  | FPToUI ->
      "FPToUI"
  | FPToSI ->
      "FPToSI"
  | UIToFP ->
      "UIToFP"
  | SIToFP ->
      "SIToFP"
  | FPTrunc ->
      "FPTrunc"
  | FPExt ->
      "FPExt"
  | PtrToInt ->
      "PtrToInt"
  | IntToPtr ->
      "IntToPtr"
  | BitCast ->
      "BitCast"
  | ICmp ->
      "ICmp" (* Other Operators *)
  | FCmp ->
      "FCmp"
  | PHI ->
      "PHI"
  | Call ->
      "Call"
  | Select ->
      "Select"
  | UserOp1 ->
      "UserOp1"
  | UserOp2 ->
      "UserOp2"
  | VAArg ->
      "VAArg"
  | ExtractElement ->
      "ExtractElement"
  | InsertElement ->
      "InsertElement"
  | ShuffleVector ->
      "ShuffleVector"
  | ExtractValue ->
      "ExtractValue"
  | InsertValue ->
      "InsertValue"
  | Fence ->
      "Fence"
  | AtomicCmpXchg ->
      "AtomicCmpXchg"
  | AtomicRMW ->
      "AtomicRMW"
  | Resume ->
      "Resume"
  | LandingPad ->
      "LandingPad"
  | AddrSpaceCast ->
      "AddrSpaceCast"
  | CleanupRet ->
      "CleanupRet"
  | CatchRet ->
      "CatchRet"
  | CatchPad ->
      "CatchPad"
  | CleanupPad ->
      "CleanupPad"
  | CatchSwitch ->
      "CatchSwitch"
  | FNeg ->
      "FNeg"
  | CallBr ->
      "CallBr"

let indices_of_const_gep instr =
  let llvalue_indices =
    List.init
      (Llvm.num_operands instr - 1)
      (fun i -> Llvm.operand instr (i + 1))
  in
  List.map
    (fun llvalue_index ->
      Llvm.int64_of_const llvalue_index |> Option.map Int64.to_int)
    llvalue_indices

let used_global var =
  let kind = Llvm.classify_value var in
  match kind with
  | GlobalVariable | GlobalAlias -> Some var
  | ConstantExpr -> (
    match Llvm.constexpr_opcode var with
    | Llvm.Opcode.GetElementPtr -> Some (Llvm.operand var 0)
    | _ -> None)
  | _ -> None

let used_globals (instr : Llvm.llvalue) : (Llvm.llvalue list) =
  List.init
    (Llvm.num_operands instr)
    (fun i -> Llvm.operand instr i)
  |> List.filter_map used_global

let exp_func_name : string -> string option =
  let asm = " asm " in
  let perc_reg = Str.regexp "%\\d+" in
  let with_at_reg = Str.regexp "@\\([A-Za-z0-9_]+\\)\\.?" in
  let without_at_reg = Str.regexp "\\([A-Za-z0-9_]+\\)\\.?" in
  fun str ->
    if contains str asm then None
    else
      try
        (* Make sure there's no "%\d+" in the function name *)
        let _ = Str.search_forward perc_reg str 0 in
        None
      with _ -> (
        if String.contains str '@' then
          try
            let _ = Str.search_forward with_at_reg str 0 in
            Some (Str.matched_group 1 str)
          with _ -> None
        else
          try
            let _ = Str.string_match without_at_reg str 0 in
            Some (Str.matched_group 1 str)
          with _ -> None )

module GlobalCache = struct
  let ll_func_cache = Hashtbl.create 2048

  let ll_func (f : Llvm.llvalue) : string option =
    if Hashtbl.mem ll_func_cache f then Hashtbl.find ll_func_cache f
    else
      let name = Llvm.value_name f |> exp_func_name in
      Hashtbl.add ll_func_cache f name ;
      name
end

let initialize_output_directories outdir =
  List.iter mkdir
    [ outdir
    ; outdir ^ "/dugraphs"
    ; outdir ^ "/dots"
    ; outdir ^ "/traces"
    ; outdir ^ "/discarded" ]

(* LLVM utility functions *)

let is_control_flow = function
  | Llvm.Opcode.Ret | Llvm.Opcode.Br | Llvm.Opcode.Switch ->
      true
  | _ ->
      false

let is_assignment = function
  | Llvm.Opcode.Invoke
  | Invalid2
  | Add
  | FAdd
  | Sub
  | FSub
  | Mul
  | FMul
  | UDiv
  | SDiv
  | FDiv
  | URem
  | SRem
  | FRem
  | Shl
  | LShr
  | AShr
  | And
  | Or
  | Xor
  | Alloca
  | Load
  | GetElementPtr
  | Trunc
  | ZExt
  | SExt
  | FPToUI
  | FPToSI
  | UIToFP
  | SIToFP
  | FPTrunc
  | FPExt
  | PtrToInt
  | IntToPtr
  | BitCast
  | ICmp
  | FCmp
  | PHI
  | Select
  | UserOp1
  | UserOp2
  | VAArg
  | ExtractElement
  | InsertElement
  | ShuffleVector
  | ExtractValue
  | InsertValue
  | Call (* FIXME: void *)
  | LandingPad ->
      true
  | _ ->
      false

let is_binary_op = function
  | Llvm.Opcode.Add
  | FAdd
  | Sub
  | FSub
  | Mul
  | FMul
  | UDiv
  | SDiv
  | FDiv
  | URem
  | SRem
  | FRem
  | Shl
  | LShr
  | AShr
  | And
  | Or
  | Xor
  | ICmp
  | FCmp ->
      true
  | _ ->
      false

let is_unary_op = function
  | Llvm.Opcode.Trunc
  | ZExt
  | SExt
  | FPToUI
  | FPToSI
  | UIToFP
  | SIToFP
  | FPTrunc
  | FPExt
  | PtrToInt
  | IntToPtr
  | BitCast ->
      true
  | _ ->
      false

let is_phi instr =
  match Llvm.instr_opcode instr with Llvm.Opcode.PHI -> true | _ -> false

let is_argument exp =
  match Llvm.classify_value exp with
  | Llvm.ValueKind.Argument ->
      true
  | _ ->
      false

module EnvCache = struct
  type t =
    { ll_value_string_cache: (Llvm.llvalue, string) Hashtbl.t
    ; string_of_exp_cache: (Llvm.llvalue, string) Hashtbl.t
    ; arg_counter: int ref
    ; arg_id_cache: (Llvm.llvalue, int) Hashtbl.t
    ; const_counter: int ref
    ; const_id_cache: (Llvm.llvalue, int) Hashtbl.t
    ; lhs_counter: int ref
    ; lhs_string_cache: (Llvm.llvalue, string) Hashtbl.t
    ; global_value_counter: int ref
    ; global_value_string_cache: (Llvm.llvalue, string) Hashtbl.t }

  let empty () =
    { ll_value_string_cache= Hashtbl.create 2048
    ; string_of_exp_cache= Hashtbl.create 2048
    ; arg_counter= ref 0
    ; arg_id_cache= Hashtbl.create 2048
    ; const_counter= ref 0
    ; const_id_cache= Hashtbl.create 2048
    ; lhs_counter= ref 0
    ; lhs_string_cache= Hashtbl.create 2048
    ; global_value_counter= ref 0
    ; global_value_string_cache= Hashtbl.create 2048 }

  let ll_value_string cache instr =
    if Hashtbl.mem cache.ll_value_string_cache instr then
      Hashtbl.find cache.ll_value_string_cache instr
    else
      let str = Llvm.string_of_llvalue instr |> String.trim in
      Hashtbl.add cache.ll_value_string_cache instr str ;
      str

  let arg_id cache exp =
    if Hashtbl.mem cache.arg_id_cache exp then
      Hashtbl.find cache.arg_id_cache exp
    else
      let arg_id = !(cache.arg_counter) in
      cache.arg_counter := !(cache.arg_counter) + 1 ;
      Hashtbl.add cache.arg_id_cache exp arg_id ;
      arg_id

  let const_id cache exp =
    if Hashtbl.mem cache.const_id_cache exp then
      Hashtbl.find cache.const_id_cache exp
    else
      let const_id = !(cache.const_counter) in
      cache.const_counter := !(cache.const_counter) + 1 ;
      Hashtbl.add cache.const_id_cache exp const_id ;
      const_id

  let string_of_lhs cache instr =
    if Hashtbl.mem cache.lhs_string_cache instr then
      Hashtbl.find cache.lhs_string_cache instr
    else
      let str = "%" ^ string_of_int !(cache.lhs_counter) in
      cache.lhs_counter := !(cache.lhs_counter) + 1 ;
      Hashtbl.add cache.lhs_string_cache instr str ;
      str

  let string_of_exp cache exp =
    if Hashtbl.mem cache.string_of_exp_cache exp then
      Hashtbl.find cache.string_of_exp_cache exp
    else
      let str =
        match Llvm.classify_value exp with
        | Llvm.ValueKind.NullValue ->
            "0"
        | BasicBlock
        | InlineAsm
        | MDNode
        | MDString
        | BlockAddress
        | ConstantAggregateZero
        | ConstantArray
        | ConstantDataArray
        | ConstantDataVector
        | ConstantExpr ->
            ll_value_string cache exp
        | Argument ->
            let a = arg_id cache exp in
            "%arg" ^ string_of_int a
        | ConstantFP | ConstantInt ->
            let c = const_id cache exp in
            "%const" ^ string_of_int c
        | ConstantPointerNull ->
            "0"
        | ConstantStruct | ConstantVector ->
            ll_value_string cache exp
        | Function ->
            GlobalCache.ll_func exp |> Option.value ~default:"unknown"
        | GlobalIFunc | GlobalAlias ->
            ll_value_string cache exp
        | GlobalVariable ->
            Llvm.value_name exp
        | UndefValue ->
            "undef"
        | Instruction i when is_assignment i -> (
          try string_of_lhs cache exp with _ -> ll_value_string cache exp )
        | Instruction _ ->
            ll_value_string cache exp
      in
      Hashtbl.add cache.string_of_exp_cache exp str ;
      str

  let string_of_global cache g =
    if Hashtbl.mem cache.global_value_string_cache g then
      Hashtbl.find cache.global_value_string_cache g
    else
      let str = "%global" ^ string_of_int !(cache.global_value_counter) in
      cache.global_value_counter := !(cache.global_value_counter) + 1 ;
      Hashtbl.add cache.lhs_string_cache g str ;
      str
end

module SliceCache = struct
  let ll_value_string_cache = Hashtbl.create 2048

  let ll_value_string instr =
    if Hashtbl.mem ll_value_string_cache instr then
      Hashtbl.find ll_value_string_cache instr
    else
      let str = Llvm.string_of_llvalue instr |> String.trim in
      Hashtbl.add ll_value_string_cache instr str ;
      str

  let arg_counter = ref 0

  let arg_id_cache = Hashtbl.create 2048

  let arg_id exp =
    if Hashtbl.mem arg_id_cache exp then Hashtbl.find arg_id_cache exp
    else
      let arg_id = !arg_counter in
      arg_counter := !arg_counter + 1 ;
      Hashtbl.add arg_id_cache exp arg_id ;
      arg_id

  let const_counter = ref 0

  let const_id_cache = Hashtbl.create 2048

  let const_id exp =
    if Hashtbl.mem const_id_cache exp then Hashtbl.find const_id_cache exp
    else
      let const_id = !const_counter in
      const_counter := !const_counter + 1 ;
      Hashtbl.add const_id_cache exp const_id ;
      const_id

  let lhs_string_cache : (Llvm.llvalue, string) Hashtbl.t = Hashtbl.create 2048

  let lhs_counter = ref 0

  let string_of_lhs instr =
    if Hashtbl.mem lhs_string_cache instr then
      Hashtbl.find lhs_string_cache instr
    else
      let str = "%" ^ string_of_int !lhs_counter in
      lhs_counter := !lhs_counter + 1 ;
      Hashtbl.add lhs_string_cache instr str ;
      str

  let string_of_exp_cache = Hashtbl.create 2048

  let string_of_exp exp =
    if Hashtbl.mem string_of_exp_cache exp then
      Hashtbl.find string_of_exp_cache exp
    else
      let str =
        match Llvm.classify_value exp with
        | Llvm.ValueKind.NullValue ->
            "0"
        | BasicBlock
        | InlineAsm
        | MDNode
        | MDString
        | BlockAddress
        | ConstantAggregateZero
        | ConstantArray
        | ConstantDataArray
        | ConstantDataVector
        | ConstantExpr ->
            ll_value_string exp
        | Argument ->
            let a = arg_id exp in
            "%arg" ^ string_of_int a
        | ConstantFP | ConstantInt ->
            let c = const_id exp in
            "%const" ^ string_of_int c
        | ConstantPointerNull ->
            "0"
        | ConstantStruct | ConstantVector ->
            ll_value_string exp
        | Function ->
            GlobalCache.ll_func exp |> Option.value ~default:"unknown"
        | GlobalIFunc | GlobalAlias ->
            ll_value_string exp
        | GlobalVariable ->
            Llvm.value_name exp
        | UndefValue ->
            "undef"
        | Instruction i when is_assignment i -> (
          try string_of_lhs exp with _ -> ll_value_string exp )
        | Instruction _ ->
            ll_value_string exp
      in
      Hashtbl.add string_of_exp_cache exp str ;
      str

  let clear _ =
    lhs_counter := 0 ;
    arg_counter := 0 ;
    const_counter := 0 ;
    Hashtbl.clear ll_value_string_cache ;
    Hashtbl.clear lhs_string_cache ;
    Hashtbl.clear arg_id_cache ;
    Hashtbl.clear const_id_cache ;
    ()
end

let callee_of_call_instr instr = Llvm.operand instr (Llvm.num_operands instr - 1)

let args_of_call_instr instr =
  List.init (Llvm.num_operands instr - 1) (Llvm.operand instr)

let fold_left_all_instr f a m =
  Llvm.fold_left_functions
    (fun a func ->
      if Llvm.is_declaration func then a
      else
        Llvm.fold_left_blocks
          (fun a blk -> Llvm.fold_left_instrs (fun a instr -> f a instr) a blk)
          a func)
    a m

let string_of_location cache llctx instr =
  let dbg = Llvm.metadata instr (Llvm.mdkind_id llctx "dbg") in
  let func = Llvm.instr_parent instr |> Llvm.block_parent |> Llvm.value_name in
  match dbg with
  | Some s -> (
      let str = EnvCache.ll_value_string cache s in
      let blk_mdnode = (Llvm.get_mdnode_operands s).(0) in
      let fun_mdnode = (Llvm.get_mdnode_operands blk_mdnode).(0) in
      let file_mdnode = (Llvm.get_mdnode_operands fun_mdnode).(0) in
      let filename = EnvCache.ll_value_string cache file_mdnode in
      let filename = String.sub filename 2 (String.length filename - 3) in
      let r =
        Str.regexp "!DILocation(line: \\([0-9]+\\), column: \\([0-9]+\\)"
      in
      try
        let _ = Str.search_forward r str 0 in
        let line = Str.matched_group 1 str in
        let column = Str.matched_group 2 str in
        filename ^ ":" ^ func ^ ":" ^ line ^ ":" ^ column
      with Not_found -> func ^ ":0:0" )
  | None ->
      func ^ ":0:0"

let is_void_type t =
  match Llvm.classify_type t with Llvm.TypeKind.Void -> true | _ -> false

let function_of_instr instr = Llvm.instr_parent instr |> Llvm.block_parent

(* Json input/output functions *)

let json_of_opcode name =
  let opcode = ("opcode", `String name) in
  `Assoc [opcode]

let json_of_unop cache instr name =
  let opcode = ("opcode", `String name) in
  let result = `String (EnvCache.string_of_exp cache instr) in
  let op0 = `String (EnvCache.string_of_exp cache (Llvm.operand instr 0)) in
  `Assoc [opcode; ("result", result); ("op0", op0)]

let json_of_binop cache instr name =
  let opcode = ("opcode", `String name) in
  let result = `String (EnvCache.string_of_lhs cache instr) in
  let op0 = `String (EnvCache.string_of_exp cache (Llvm.operand instr 0)) in
  let op1 = `String (EnvCache.string_of_exp cache (Llvm.operand instr 1)) in
  `Assoc [opcode; ("result", result); ("op0", op0); ("op1", op1)]

let json_of_icmp = function
  | Llvm.Icmp.Eq ->
      `String "eq"
  | Ne ->
      `String "ne"
  | Ugt ->
      `String "ugt"
  | Uge ->
      `String "uge"
  | Ult ->
      `String "ult"
  | Ule ->
      `String "ule"
  | Sgt ->
      `String "sgt"
  | Sge ->
      `String "sge"
  | Slt ->
      `String "slt"
  | Sle ->
      `String "sle"

let json_of_fcmp = function
  | Llvm.Fcmp.False ->
      `String "false"
  | Oeq ->
      `String "oeq"
  | Ogt ->
      `String "ogt"
  | Oge ->
      `String "oge"
  | Olt ->
      `String "olt"
  | Ole ->
      `String "ole"
  | One ->
      `String "one"
  | Ord ->
      `String "ord"
  | Uno ->
      `String "uno"
  | Ueq ->
      `String "ueq"
  | Ugt ->
      `String "ugt"
  | Uge ->
      `String "uge"
  | Ult ->
      `String "ult"
  | Ule ->
      `String "ule"
  | Une ->
      `String "une"
  | True ->
      `String "true"

let opcode_of_instr_cache = Hashtbl.create 2048

let opcode_of_instr instr =
  if Hashtbl.mem opcode_of_instr_cache instr then
    Hashtbl.find opcode_of_instr_cache instr
  else
    let opcode = Llvm.instr_opcode instr in
    Hashtbl.add opcode_of_instr_cache instr opcode ;
    opcode

let json_of_instr cache instr =
  let num_of_operands = Llvm.num_operands instr in
  match opcode_of_instr instr with
  | Llvm.Opcode.Invalid ->
      json_of_opcode "invalid"
  | Invalid2 ->
      json_of_opcode "invalid2"
  | Unreachable ->
      json_of_opcode "unreachable"
  | Ret ->
      let opcode = ("opcode", `String "ret") in
      let ret =
        if num_of_operands = 0 then `Null
        else `String (EnvCache.string_of_exp cache (Llvm.operand instr 0))
      in
      `Assoc [opcode; ("op0", ret)]
  | Br ->
      let opcode = ("opcode", `String "br") in
      let cond =
        match Llvm.get_branch instr with
        | Some (`Conditional _) ->
            `String (EnvCache.string_of_exp cache (Llvm.operand instr 0))
        | _ ->
            `Null
      in
      `Assoc [opcode; ("cond", cond)]
  | Switch ->
      let opcode = ("opcode", `String "switch") in
      let op0 = `String (EnvCache.string_of_exp cache (Llvm.operand instr 0)) in
      `Assoc [opcode; ("op0", op0)]
  | IndirectBr ->
      json_of_opcode "indirectbr"
  | Invoke ->
      json_of_opcode "invoke"
  | Add ->
      json_of_binop cache instr "add"
  | FAdd ->
      json_of_binop cache instr "fadd"
  | Sub ->
      json_of_binop cache instr "sub"
  | FSub ->
      json_of_binop cache instr "fsub"
  | Mul ->
      json_of_binop cache instr "mul"
  | FMul ->
      json_of_binop cache instr "fmul"
  | UDiv ->
      json_of_binop cache instr "udiv"
  | SDiv ->
      json_of_binop cache instr "sdiv"
  | FDiv ->
      json_of_binop cache instr "fdiv"
  | URem ->
      json_of_binop cache instr "urem"
  | SRem ->
      json_of_binop cache instr "srem"
  | FRem ->
      json_of_binop cache instr "frem"
  | Shl ->
      json_of_binop cache instr "shl"
  | LShr ->
      json_of_binop cache instr "lshr"
  | AShr ->
      json_of_binop cache instr "ashr"
  | And ->
      json_of_binop cache instr "and"
  | Or ->
      json_of_binop cache instr "or"
  | Xor ->
      json_of_binop cache instr "xor"
  | Alloca ->
      json_of_unop cache instr "alloca"
  | Load ->
      json_of_unop cache instr "load"
  | Store ->
      let opcode = ("opcode", `String "store") in
      let op0 = `String (EnvCache.string_of_exp cache (Llvm.operand instr 0)) in
      let op1 = `String (EnvCache.string_of_exp cache (Llvm.operand instr 1)) in
      `Assoc [opcode; ("op0", op0); ("op1", op1)]
  | GetElementPtr ->
      let opcode = ("opcode", `String "getelementptr") in
      let op0 = `String (EnvCache.string_of_exp cache (Llvm.operand instr 0)) in
      let result = `String (EnvCache.string_of_lhs cache instr) in
      `Assoc [opcode; ("op0", op0); ("result", result)]
  | Trunc ->
      json_of_unop cache instr "trunc"
  | ZExt ->
      json_of_unop cache instr "zext"
  | SExt ->
      json_of_unop cache instr "sext"
  | FPToUI ->
      json_of_unop cache instr "fptoui"
  | FPToSI ->
      json_of_unop cache instr "fptosi"
  | UIToFP ->
      json_of_unop cache instr "uitofp"
  | SIToFP ->
      json_of_unop cache instr "sitofp"
  | FPTrunc ->
      json_of_unop cache instr "fptrunc"
  | FPExt ->
      json_of_unop cache instr "fpext"
  | PtrToInt ->
      json_of_unop cache instr "ptrtoint"
  | IntToPtr ->
      json_of_unop cache instr "inttoptr"
  | BitCast ->
      json_of_unop cache instr "bitcast"
  | ICmp ->
      let opcode = ("opcode", `String "icmp") in
      let op =
        match Llvm.icmp_predicate instr with
        | Some s ->
            s
        | None ->
            failwith "Stmt.json_of_stmt (icmp)"
      in
      let predicate = ("predicate", json_of_icmp op) in
      let result = `String (EnvCache.string_of_lhs cache instr) in
      let op0 = `String (EnvCache.string_of_exp cache (Llvm.operand instr 0)) in
      let op1 = `String (EnvCache.string_of_exp cache (Llvm.operand instr 1)) in
      `Assoc [opcode; ("result", result); predicate; ("op0", op0); ("op1", op1)]
  | FCmp ->
      let opcode = ("opcode", `String "fcmp") in
      let op =
        match Llvm.fcmp_predicate instr with
        | Some s ->
            s
        | None ->
            failwith "Stmt.json_of_stmt (fcmp)"
      in
      let predicate = ("predicate", json_of_fcmp op) in
      let result = `String (EnvCache.string_of_lhs cache instr) in
      let op0 = `String (EnvCache.string_of_exp cache (Llvm.operand instr 0)) in
      let op1 = `String (EnvCache.string_of_exp cache (Llvm.operand instr 1)) in
      `Assoc [opcode; ("result", result); predicate; ("op0", op0); ("op1", op1)]
  | PHI ->
      let opcode = ("opcode", `String "phi") in
      let result = `String (EnvCache.string_of_lhs cache instr) in
      let incoming =
        Llvm.incoming instr
        |> List.map (fun x -> `String (fst x |> EnvCache.string_of_exp cache))
      in
      `Assoc [opcode; ("result", result); ("incoming", `List incoming)]
  | Call -> (
      let opcode = ("opcode", `String "call") in
      let result =
        match Llvm.type_of instr |> Llvm.classify_type with
        | Llvm.TypeKind.Void ->
            `Null
        | _ ->
            `String (EnvCache.string_of_lhs cache instr)
      in
      let callee_exp =
        Llvm.operand instr (num_of_operands - 1) |> EnvCache.string_of_exp cache
      in
      let args =
        List.fold_left
          (fun args a -> args @ [`String (EnvCache.string_of_exp cache a)])
          []
          (List.init (num_of_operands - 1) (fun i -> Llvm.operand instr i))
      in
      match exp_func_name callee_exp with
      | Some callee ->
          `Assoc
            [ opcode
            ; ("result", result)
            ; ("func", `String callee)
            ; ("args", `List args) ]
      | None ->
          `Assoc
            [ opcode
            ; ("result", result)
            ; ("func", `String callee_exp)
            ; ("args", `List args) ] )
  | Select ->
      json_of_opcode "select"
  | UserOp1 ->
      json_of_opcode "userop1"
  | UserOp2 ->
      json_of_opcode "userop2"
  | VAArg ->
      json_of_opcode "vaarg"
  | ExtractElement ->
      json_of_opcode "extractelement"
  | InsertElement ->
      json_of_opcode "insertelement"
  | ShuffleVector ->
      json_of_opcode "shufflevector"
  | ExtractValue ->
      json_of_opcode "extractvalue"
  | InsertValue ->
      json_of_opcode "insertvalue"
  | Fence ->
      json_of_opcode "fence"
  | AtomicCmpXchg ->
      json_of_opcode "atomiccmpxchg"
  | AtomicRMW ->
      json_of_opcode "atomicrmw"
  | Resume ->
      json_of_opcode "resume"
  | LandingPad ->
      json_of_opcode "landingpad"
  | AddrSpaceCast ->
      json_of_opcode "addrspacecast"
  | CleanupRet ->
      json_of_opcode "cleanupret"
  | CatchRet ->
      json_of_opcode "catchret"
  | CatchPad ->
      json_of_opcode "catchpad"
  | CleanupPad ->
      json_of_opcode "cleanuppad"
  | CatchSwitch ->
      json_of_opcode "catchswitch"
  | FNeg ->
      json_of_opcode "fneg"
  | CallBr ->
      json_of_opcode "callbr"

let is_llvm_function f : bool =
  let r1 = Str.regexp "llvm\\.dbg\\..+" in
  let r2 = Str.regexp "llvm\\.lifetime\\..+" in
  Str.string_match r1 (Llvm.value_name f) 0
  || Str.string_match r2 (Llvm.value_name f) 0

let get_abs_path (name : string) =
  let is_starting_from_root = name.[0] = '/' in
  if is_starting_from_root then name else Filename.concat (Sys.getcwd ()) name

let rec unique (f : 'a -> 'a -> bool) (ls : 'a list) : 'a list =
  match ls with
  | hd :: tl ->
      let tl_no_hd = List.filter (fun x -> not (f hd x)) tl in
      let uniq_rest = unique f tl_no_hd in
      hd :: uniq_rest
  | [] ->
      []

let rec without (f : 'a -> bool) (ls : 'a list) : 'a list =
  match ls with
  | [] ->
      []
  | hd :: tl ->
      if f hd then without f tl else hd :: without f tl

let get_function_in_llm (func_name : string) (llm : Llvm.llmodule) :
    Llvm.llvalue =
  match Llvm.lookup_function func_name llm with
  | Some entry ->
      entry
  | None ->
      raise InvalidJSON

let get_field json field : Yojson.Safe.t =
  match json with
  | `Assoc fields -> (
    match List.find_opt (fun (key, _) -> key = field) fields with
    | Some (_, field_data) ->
        field_data
    | None ->
        raise InvalidJSON )
  | _ ->
      raise InvalidJSON

let get_field_opt json field : Yojson.Safe.t option =
  match json with
  | `Assoc fields -> (
    match List.find_opt (fun (key, _) -> key = field) fields with
    | Some (_, field_data) ->
        Some field_data
    | None ->
        None )
  | _ ->
      raise InvalidJSON

let get_field_not_null json field : Yojson.Safe.t option =
  match json with
  | `Assoc fields -> (
    match List.find_opt (fun (key, _) -> key = field) fields with
    | Some (_, field_data) -> (
      match field_data with `Null -> None | _ -> Some field_data )
    | None ->
        None )
  | _ ->
      raise InvalidJSON

let string_from_json json : string =
  match json with `String str -> str | _ -> raise InvalidJSON

let string_opt_from_json json : string option =
  match json with `String str -> Some str | _ -> None

let int_from_json json : int =
  match json with `Int i -> i | _ -> raise InvalidJSON

let int_from_json_field json field : int = int_from_json (get_field json field)

let list_from_json json : Yojson.Safe.t list =
  match json with `List ls -> ls | _ -> raise InvalidJSON

let bool_from_json json : bool =
  match json with `Bool b -> b | _ -> raise InvalidJSON

let string_from_json_field json field : string =
  string_from_json (get_field json field)

let string_opt_from_json_field json field : string option =
  Option.bind (get_field_opt json field) string_opt_from_json

let string_list_from_json json : string list =
  match json with
  | `List ls ->
      List.map string_from_json ls
  | _ ->
      raise InvalidJSON

let option_map_default f d m = match m with Some a -> f a | None -> d

let string_of_bool b = if b then "true" else "false"
