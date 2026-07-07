# VanCode - A fast, extensible bytecode generator and VM for building
# Domain-Specific Languages (DSLs), or general-purpose programming language
#
# Powered by Nim.
#
# (c) iLiquid, 2019-2020
#     https://github.com/liquidev/
#
# (c) 2025 George Lemon | MIT License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/vancode

import std/options
import pkg/vancode/interpreter/[chunk, codegen, ast, sym, value]
import pkg/vancode/interpreter/stdlib/utils
import ../parser

export utils

proc toStackView(vals: var seq[Value]): StackView {.inline.} =
  ## seq[Value] -> StackView (ptr UncheckedArray[Value])
  if vals.len == 0:
    return cast[StackView](nil)
  cast[StackView](vals[0].addr)

proc applyDefaults(args: StackView, argc: int, params: seq[TempParamDef]): seq[Value] =
  result = newSeqOfCap[Value](params.len)

  for i in 0..<argc:
    result.add(args[i])

  if result.len < params.len:
    for i in result.len..<params.len:
      if params[i].val != nil:
        result.add(params[i].val)
      else:
        raise newException(ValueError, "missing required argument: " & params[i].pName)

proc compileCode*(script: Script, module: Module, filename, code: string) =
  ## Compile some hayago code to the given script and module.
  ## Any generated toplevel code is discarded. This should only be used for
  ## declarations of hayago-side things, eg. iterators.
  var astProgram: Ast
  try:
    parser.parseScript(astProgram, code, "std/system/inline")
  except TimParserError as e:
    echo e.msg
    quit(1)
  try:
    # var codeChunk = newChunk()
    var gen = initCodeGen(script, module, script.mainChunk)
    gen.genScript(astProgram, none(string), emitHalt = false)
  except CodeGenError as e:
    echo e.msg
    quit(1)

const
  InlineCode* = """
iterator `..`*(min: int, max: int): int {
  var i = $min
  if $i >= $max:
    yield($min)
  else:
    while $i <= $max:
      yield($i)
      inc($i)
}

iterator items*(data: json): json {
  var i = 0
  const total = len($data)
  while $i < $total {
    yield($data[$i])
    inc($i)
  }
}

iterator items*(arr: array[object]): object {
  var i = 0
  const total = high($arr)
  while $i <= $total {
    yield($arr[$i])
    inc($i)
  }
}

iterator items*(arr: array[string]): string {
  var i = 0
  const total = high($arr)
  while $i <= $total {
    yield($arr[$i])
    inc($i)
  }
}

iterator items*(arr: array[int]): int {
  var i = 0
  const total = high($arr)
  while $i <= $total {
    yield($arr[$i])
    inc($i)
  }
}
"""