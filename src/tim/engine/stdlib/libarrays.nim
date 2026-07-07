# A super fast template engine for cool kids
#
# (c) iLiquid, 2019-2020
#     https://github.com/liquidev/
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim | https://openpeeps.dev/packages/tim

import std/[options, sequtils, strutils, tables, hashes]
import pkg/vancode/interpreter/[chunk, ast, sym, value]

import ./inliner

proc initArrays*(script: Script, systemModule: Module): Module =
  # foreign stuff
  result = newModule("arrays", some"arrays.timl")
  result.load(systemModule)

  script.addProc(result, "add", @[
      paramDef("s", ttyArray),
      paramDef("item", ttyAny)
    ], ttyVoid,
    proc (args: StackView, argc: int): Value =
      # TODO runtime check for type compatibility
      # inside the standard library 
      args[0].objectVal.fields.add(args[1].toStorage)
    )
    
  script.addProc(result, "delete", @[
    paramDef("s", ttyArray), paramDef("offset", ttyInt)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      args[0].objectVal.fields.delete(args[1].intVal)
  )

  script.addProc(result, "insert", @[
      paramDef("s", ttyArray),
      paramDef("item", ttyAny),
      paramDef("offset", ttyInt)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      insert(args[0].objectVal.fields, args[1].toStorage, args[2].intVal)
  )

  script.addProc(result, "join", @[paramDef("s", ttyArray)], ttyString,
    proc (args: StackView, argc: int): Value =
      # joins an array of strings with ", "
      for vs in args[0].objectVal.fields:
        assert vs.refVal.typeId == tyString, "join() only works on arrays of strings"
      result = initvalue("")
      result.stringVal[] = args[0].objectVal.fields.mapIt(it.refVal.stringVal[]).join(", ")
  )

  script.addProc(result, "contains", @[paramDef("arr", ttyArray), paramDef("x", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      # checks if an array contains a value
      for vs in args[0].objectVal.fields:
        let v = vs.toValue
        case v.typeId
        of tyInt:
          if v.intVal == args[1].intVal:
            return initvalue(true)
        of tyFloat:
          if v.floatVal == args[1].floatVal:
            return initvalue(true)
        of tyBool:
          if v.boolVal == args[1].boolVal:
            return initvalue(true)
        of tyString:
          if v.stringVal[] == args[1].stringVal[]:
            return initvalue(true)
        else:
          assert false, "contains() not supported for this type " & $v.typeId
      result = initvalue(false)
  )
  
  script.addProc(result, "find", @[paramDef("s", ttyArray), paramDef("item", ttyAny)], ttyInt,
    proc (args: StackView, argc: int): Value =
      # returns the index of the first occurrence of item in the array, or -1 if not found
      result = initvalue(-1)
      for i, vs in args[0].objectVal.fields:
        let v = vs.toValue
        case v.typeId
        of tyInt:
          if v.intVal == args[1].intVal:
            result.intVal = i; break
        of tyString:
          if v.stringVal[] == args[1].stringVal[]:
            result.intVal = i; break
        of tyFloat:
          if v.floatVal == args[1].floatVal:
            result.intVal = i; break
        of tyBool:
          if v.boolVal == args[1].boolVal:
            result.intVal = i; break
        else:
          assert false, "find() not supported for this type " & $v.typeId
    )

  # Helper to hash a Value for deduplication
  proc valueHash(v: Value): Hash =
    case v.typeId
    of tyInt: result = hash(v.intVal)
    of tyFloat: result = hash(v.floatVal)
    of tyBool: result = hash(v.boolVal)
    of tyString: result = hash(v.stringVal[])
    else: result = hash(v.typeId) # fallback for unsupported types

  script.addProc(result, "dedup", @[paramDef("s", ttyArray, mut=true)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      # removes duplicates from the array using hash-based comparison
      var seen = newSeq[Hash]()
      var i = 0
      while i < args[0].objectVal.fields.len:
        let v = args[0].objectVal.fields[i].toValue
        let h = valueHash(v)
        if h in seen:
          args[0].objectVal.fields.delete(i)
        else:
          seen.add(h)
          inc(i)
  )

  script.addProc(result, "isEmpty", @[paramDef("arr", ttyArray)], ttyBool,
    proc (args: StackView, argc: int): Value =
      initValue(args[0].objectVal.fields.len == 0))

  script.addProc(result, "first", @[paramDef("arr", ttyArray)], ttyAny,
    proc (args: StackView, argc: int): Value =
      if args[0].objectVal.fields.len > 0:
        result = args[0].objectVal.fields[0].toValue)

  script.addProc(result, "last", @[paramDef("arr", ttyArray)], ttyAny,
    proc (args: StackView, argc: int): Value =
      if args[0].objectVal.fields.len > 0:
        result = args[0].objectVal.fields[^1].toValue)

  script.addProc(result, "reverse", @[paramDef("arr", ttyArray)], ttyArray,
    proc (args: StackView, argc: int): Value =
      let n = args[0].objectVal.fields.len
      result = initArray(n)
      for i in 0..<n:
        result.objectVal.fields[i] = args[0].objectVal.fields[n - 1 - i])