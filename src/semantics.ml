module Stmt = struct
  type t = Llvm.llvalue

  let compare = compare

  let hash = Hashtbl.hash

  let equal = ( = )

  let string_of_opcode = function
    | Llvm.Opcode.Invalid ->
        "Invalid"
    | Ret ->
        "Ret"
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
        "Add"
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
        "Shl"
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
        "Alloca"
    | Load ->
        "Load"
    | Store ->
        "Store"
    | GetElementPtr ->
        "GetElementPtr"
    | Trunc ->
        "Trunc"
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
        "ICmp"
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

  let string_of_location debug s =
    let func = Llvm.instr_parent s |> Llvm.block_parent |> Llvm.value_name in
    match debug with
    | Some s ->
        let str = Llvm.string_of_llvalue s in
        let r =
          Str.regexp "!DILocation(line: \\([0-9]+\\), column: \\([0-9]+\\)"
        in
        let _ = Str.search_forward r str 0 in
        let line = Str.matched_group 1 str in
        let column = Str.matched_group 2 str in
        func ^ ":" ^ line ^ ":" ^ column
    | None ->
        func ^ ":0:0"

  let to_json llctx s =
    let opcode = Llvm.instr_opcode s in
    let dbg = Llvm.metadata s (Llvm.mdkind_id llctx "dbg") in
    let op = ("Opcode", `String (string_of_opcode opcode)) in
    let loc = ("Location", `String (string_of_location dbg s)) in
    match opcode with
    | x ->
        let assoc = [op; loc; ("Instr", `String (Llvm.string_of_llvalue s))] in
        `Assoc assoc
end

module Trace = struct
  type t = Stmt.t list

  let empty = []

  let append x t = t @ [x]

  let to_json llctx t =
    let l = List.map (Stmt.to_json llctx) t in
    `List l
end

module Stack = struct
  type t = Llvm.llvalue list

  let empty = []

  let push x s = x :: s

  let pop = function x :: s -> Some (x, s) | [] -> None

  let is_empty s = s = []

  let length = List.length
end

module Symbol = struct
  type t = string

  let count = ref 0

  let new_symbol () =
    let sym = "$" ^ string_of_int !count in
    count := !count + 1 ;
    sym

  let to_string x = x
end

module Value = struct
  type t =
    | Function of Llvm.llvalue
    | Symbol of Symbol.t
    | Int of int
    | Address of Llvm.llvalue
    | Unknown

  let func v = Function v
end

module Memory = struct
  include Map.Make (struct
    type t = Llvm.llvalue

    let compare = compare
  end)
end

module InstrSet = Set.Make (struct
  type t = Llvm.llvalue

  let compare = compare
end)

module State = struct
  type t =
    { stack: Stack.t
    ; memory: Value.t Memory.t
    ; trace: Trace.t
    ; visited: InstrSet.t }

  let empty =
    { stack= Stack.empty
    ; memory= Memory.empty
    ; trace= Trace.empty
    ; visited= InstrSet.empty }

  let push_stack x s = {s with stack= Stack.push x s.stack}

  let pop_stack s =
    match Stack.pop s.stack with
    | Some (x, stk) ->
        Some (x, {s with stack= stk})
    | None ->
        None

  let add_trace x s = {s with trace= Trace.append x s.trace}

  let add_memory x v s = {s with memory= Memory.add x v s.memory}

  let visit instr s = {s with visited= InstrSet.add instr s.visited}
end
