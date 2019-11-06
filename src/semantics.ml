module Trace = struct
  type t = Llvm.llvalue list

  let empty = []

  let append x t = t @ [x]
end

module Stack = struct
  type t = Llvm.llvalue Stack.t

  let empty = Stack.create ()

  let push x s = Stack.push x s ; s

  let pop s = (Stack.top s, Stack.pop s)

  let is_empty = Stack.is_empty
end

module Value = struct
  type t = Function of Llvm.llvalue

  let func v = Function v
end

module Memory = struct
  include Map.Make (struct
    type t = Llvm.llvalue

    let compare = compare
  end)
end

module State = struct
  type t = {stack: Stack.t; memory: Value.t Memory.t; trace: Trace.t}

  let empty = {stack= Stack.empty; memory= Memory.empty; trace= Trace.empty}

  let push_stack x s = {s with stack= Stack.push x s.stack}

  let add_trace x s = {s with trace= Trace.append x s.trace}

  let add_memory x v s = {s with memory= Memory.add x v s.memory}
end
