# A super fast template engine for cool kids
#
# (c) iLiquid, 2019-2020
#     https://github.com/liquidev/
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim | https://openpeeps.dev/packages/tim

import std/[options, sequtils, strutils]
import pkg/vancode/interpreter/[chunk, codegen, ast, sym, value]

import ./inliner
import ../parser

proc initObjects*(script: Script, systemModule: Module): Module =
  # foreign stuff
  result = newModule("objects", some"objects.timl")
  result.load(systemModule)

  script.addProc(result, "add", @[
      paramDef("s", ttyArray), paramDef("item", ttyAny)], ttyVoid,
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
      paramDef("s", ttyArray), paramDef("item", ttyAny),
      paramDef("offset", ttyInt)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      insert(args[0].objectVal.fields, args[1].toStorage, args[2].intVal)
  )

  script.addProc(result, "join", @[paramDef("s", ttyArray)], ttyString,
    proc (args: StackView, argc: int): Value =
      for vs in args[0].objectVal.fields:
        assert vs.refVal.typeId == tyString, "join() only works on arrays of strings"
      result = initvalue("")
      result.stringVal[] = args[0].objectVal.fields.mapIt(it.refVal.stringVal[]).join(", ")
  )

  script.addProc(result, "hasKey", @[
      paramDef("obj", ttyObject), paramDef("key", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initvalue(false)
      for key in args[0].objectVal.keys:
        if key == args[1].stringVal[]:
          result.boolVal = true
          break
    )

  script.addProc(result, "find", @[
      paramDef("s", ttyArray), paramDef("item", ttyAny)], ttyInt,
    proc (args: StackView, argc: int): Value =
      # this should work for strings and numbers
      result = initvalue(-1)
      var i = 1
      for vs in args[0].objectVal.fields:
        let v = vs.toValue
        case v.typeId
        of tyInt:
          if v.intVal == args[1].intVal:
            result.intVal = i - 1; break
        of tyString:
          if v.stringVal[] == args[1].stringVal[]:
            result.intVal = i - 1; break
        of tyFloat:
          if v.floatVal == args[1].floatVal:
            result.intVal = i - 1; break
        of tyBool:
          if v.boolVal == args[1].boolVal:
            result.intVal = i - 1; break
        else:
          assert false, "find() not supported for this type " & $v.typeId
    )

  script.addProc(result, "len", @[paramDef("obj", ttyObject)], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initvalue(args[0].objectVal.fields.len)
    )

  script.addProc(result, "isEmpty", @[paramDef("obj", ttyObject)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initvalue(args[0].objectVal.fields.len == 0)
    )

  script.addProc(result, "clear", @[paramDef("obj", ttyObject, mut=true)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      args[0].objectVal.fields.setLen(0)
    )

  script.addProc(result, "keys", @[paramDef("obj", ttyObject)], ttyArray,
    proc (args: StackView, argc: int): Value =
      let n = args[0].objectVal.keys.len
      result = initArray(n)
      for i, k in args[0].objectVal.keys:
        result.objectVal.fields[i] = initValue(k).toStorage
    )

  script.addProc(result, "values", @[paramDef("obj", ttyObject)], ttyArray,
    proc (args: StackView, argc: int): Value =
      let n = args[0].objectVal.fields.len
      result = initArray(n)
      for i, v in args[0].objectVal.fields:
        result.objectVal.fields[i] = v
    )
