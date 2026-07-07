# A super fast template engine for cool kids
#
# (c) iLiquid, 2019-2020
#     https://github.com/liquidev/
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim | https://openpeeps.dev/packages/tim

import std/[strutils, options, os, sequtils,
        httpclient, httpcore, random, hashes, math]

import pkg/openparser/json
import pkg/vancode/interpreter/[chunk, ast, sym, value]
import ./inliner

type TimRuntime* = object of CatchableError

proc convertObjectToJson(arg: Value): string =
  case arg.objectVal.isForeign
  of false:
    result = "{"
    let obj = arg.objectVal
    for i in 0..<obj.keys.len:
      result.add("\"" & obj.keys[i] & "\": ")
      let v = obj.fields[i].toValue
      case v.typeId
      of 4: # string
        result.add("\"" & v.stringVal[] & "\"")
      of 15: # object
        result.add("[Object]")
      else: # other types
        result.add($v)
      if i < obj.keys.len - 1:
        result.add(", ")
    result.add("}")
  else:
    result = "{...}"

proc initSystemOps(script: Script, module: Module) =
  ## Add builtin operations into the module.
  ## This should only ever be called when creating the ``system`` module.

  # bool operators
  script.addProc(module, "not", @[paramDef("x", ttyBool)], ttyBool)
  script.addProc(module, "==", @[paramDef("a", ttyBool), paramDef("b", ttyBool)], ttyBool)
  script.addProc(module, "!=", @[paramDef("a", ttyBool), paramDef("b", ttyBool)], ttyBool)

  # number type operators

  for T in [(ttyInt, ttyFloat), (ttyFloat, ttyInt)]:
    script.addProc(module, "+", @[paramDef("a", T[0])], T[0])
    script.addProc(module, "-", @[paramDef("a", T[0])], T[0])
    
    script.addProc(module, "+", @[paramDef("a", T[0]), paramDef("b", T[1])], ttyFloat)
    script.addProc(module, "-", @[paramDef("a", T[0]), paramDef("b", T[1])], ttyFloat)
    script.addProc(module, "*", @[paramDef("X", T[0]), paramDef("b", T[1])], ttyFloat)
    script.addProc(module, "/", @[paramDef("a", T[0]), paramDef("b", T[1])], ttyFloat)
  
    script.addProc(module, "==", @[paramDef("a", T[0]), paramDef("b", T[1])], ttyBool)
    script.addProc(module, "!=", @[paramDef("a", T[0]), paramDef("b", T[1])], ttyBool)
    script.addProc(module, "<", @[paramDef("a", T[0]), paramDef("b", T[1])], ttyBool)
    script.addProc(module, "<=", @[paramDef("a", T[0]), paramDef("b", T[1])], ttyBool)
    script.addProc(module, ">", @[paramDef("a", T[0]), paramDef("b", T[1])], ttyBool)
    script.addProc(module, ">=", @[paramDef("a", T[0]), paramDef("b", T[1])], ttyBool)

  for T in [(ttyInt, ttyInt), (ttyFloat, ttyFloat)]:
    script.addProc(module, "+=", @[paramDef("a", T[0], mut = true), paramDef("b", T[1])], ttyVoid)
    script.addProc(module, "-=", @[paramDef("a", T[0], mut = true), paramDef("b", T[1])], ttyVoid)
    script.addProc(module, "*=", @[paramDef("a", T[0], mut = true), paramDef("b", T[1])], ttyVoid)
    script.addProc(module, "/=", @[paramDef("a", T[0], mut = true), paramDef("b", T[1])], ttyVoid)

    script.addProc(module, ">=", @[paramDef("a", T[0]), paramDef("b", T[1])], ttyBool)
    script.addProc(module, "<=", @[paramDef("a", T[0]), paramDef("b", T[1])], ttyBool)
    script.addProc(module, ">",  @[paramDef("a", T[0]), paramDef("b", T[1])], ttyBool)
    script.addProc(module, "<",  @[paramDef("a", T[0]), paramDef("b", T[1])], ttyBool)
  
  script.addProc(module, "==", @[paramDef("a", ttyBool), paramDef("b", ttyBool)], ttyBool)
  script.addProc(module, "!=", @[paramDef("a", ttyBool), paramDef("b", ttyBool)], ttyBool)

proc loadLibrary*(script: Script): Module =
  ## Create and initialize the ``system`` module.

  # foreign stuff
  result = newModule("system", some"system.timl")
  result.initSystemTypes()
  script.initSystemOps(result)

  # string operators
  script.addProc(result, "==", @[paramDef("a", ttyString), paramDef("b", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[] == args[1].stringVal[]))

  script.addProc(result, "!=", @[paramDef("a", ttyString), paramDef("b", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[] != args[1].stringVal[]))

  script.addProc(result, "is", @[paramDef("a", ttyString), paramDef("b", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[] == args[1].stringVal[]))
  
  script.addProc(result, "isnot", @[paramDef("a", ttyString), paramDef("b", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[] != args[1].stringVal[]))

  script.addProc(result, "is", @[paramDef("a", ttyBool), paramDef("b", ttyBool)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[] == args[1].stringVal[]))
  
  script.addProc(result, "isnot", @[paramDef("a", ttyBool), paramDef("b", ttyBool)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[] != args[1].stringVal[]))

  #
  # Object hash and equality
  #
  script.addProc(result, "==", @[paramDef("a", ttyObject), paramDef("b", ttyObject)], ttyBool,
    proc (args: StackView, argc: int): Value =
      when defined(nimPreviewHashRef):
        initvalue(hash(args[0].objectVal) == hash(args[1].objectVal))
      else:
        raise newException(TimRuntime, "Hashing ref is not enabled. Use `-d:nimPreviewHashRef` to enable it.")
    )
      

  #
  # JSON operators between JSON and other types
  #
  script.addProc(result, "==", @[paramDef("a", ttyJson), paramDef("b", ttyBool)], ttyBool,
    proc (args: StackView, argc: int): Value =
      if args[0].jsonVal.kind != JBool:
        result = initValue(false)
      else:
        result = initValue(args[0].jsonVal.getBool == args[1].boolVal))

  script.addProc(result, "==", @[paramDef("a", ttyJson), paramDef("b", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      if args[0].jsonVal.kind != JString:
        result = initValue(false)
      else:
        result = initValue(args[0].jsonVal.getStr() == args[1].stringVal[]))

  script.addProc(result, "==", @[paramDef("a", ttyJson), paramDef("b", ttyInt)], ttyBool,
    proc (args: StackView, argc: int): Value =
      case args[0].jsonVal.kind
      of JInt:
        result = initValue(args[0].jsonVal.getInt() == args[1].intVal)
      of JFloat:
        result = initValue(args[0].jsonVal.getFloat() == toFloat(args[1].intVal))
      else:
        raise newException(TimRuntime, "Type mismatch: expected JSON number, got " & $args[0].jsonVal.kind))

  script.addProc(result, "==", @[paramDef("a", ttyJson), paramDef("b", ttyFloat)], ttyBool,
    proc (args: StackView, argc: int): Value =
      case args[0].jsonVal.kind
      of JFloat:
        result = initValue(args[0].jsonVal.getFloat() == args[1].floatVal)
      of JInt:
        result = initValue(toFloat(args[0].jsonVal.getInt()) == args[1].floatVal)
      else:
        raise newException(TimRuntime, "Type mismatch: expected JSON number, got " & $args[0].jsonVal.kind))

  script.addProc(result, "type", @[paramDef("x", ttyAny)], ttyString,
    proc (args: StackView, argc: int): Value =
      let valueType =
        case args[0].typeId:
        of tyBool: "bool"
        of tyInt: "int"
        of tyFloat: "float"
        of tyString: "string"
        of tyJsonStorage: "json"
        of tyArrayObject: "array"
        # of tyHtmlObject: "html"
        # of ttyPointer: "pointer"
        else: "object"
      result = initValue(valueType))

  script.addProc(result, "jsonType", @[paramDef("x", ttyJson)], ttyString,
    proc (args: StackView, argc: int): Value =
      let valueType =
        case args[0].jsonVal.kind:
        of JBool: "bool"
        of JInt: "int"
        of JFloat: "float"
        of JString: "string"
        of JArray: "array"
        of JObject: "object"
        else: "nil"
      result = initValue(valueType))

  # converters
  script.addProc(result, "toInt", @[paramDef("f", ttyFloat)], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(toInt(args[0].floatVal)))

  script.addProc(result, "parseInt", @[paramDef("i", ttyString)], ttyInt,
    proc (args: StackView, argc: int): Value =
      ## Convert a string to an int.
      result = initValue(parseInt(args[0].stringVal[])))

  script.addProc(result, "toFloat", @[paramDef("i", ttyInt)], ttyFloat,
    proc (args: StackView, argc: int): Value =
      ## Convert an int to a float
      result = initValue(toFloat(args[0].intVal)))

  script.addProc(result, "toFloat", @[paramDef("i", ttyJson)], ttyFloat,
    proc (args: StackView, argc: int): Value =
      if likely(args[0].jsonVal.kind == JInt):
        result = initValue(toFloat(args[0].jsonVal.getInt()))
      elif likely(args[0].jsonVal.kind == JFloat):
        result = initValue(args[0].jsonVal.getFloat())
      else:
        raise newException(TimRuntime, "Cannot convert JSON value to float.")
  )

  script.addProc(result, "assert", @[paramDef("condition", ttyBool)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      ## Assert that the given condition is true.
      if not args[0].boolVal:
        raise newException(TimRuntime, "Assertion failed: " & $args[0].boolVal))

  #
  # String conversion
  #
  script.addProc(result, "toString", @[paramDef("x", ttyInt)], ttyString,
    proc (args: StackView, argc: int): Value =
      ## Convert an int to a string
      result = initValue($(args[0].intVal))
    )

  script.addProc(result, "toString", @[paramDef("x", ttyFloat)], ttyString,
    proc (args: StackView, argc: int): Value =
      ## Convert a float to a string
      result = initValue($(args[0].floatVal))
    )

  script.addProc(result, "toString", @[paramDef("x", ttyBool)], ttyString,
    proc (args: StackView, argc: int): Value =
      ## Convert bool to string
      result = initValue($(args[0].boolVal))
    )

  script.addProc(result, "toString", @[paramDef("x", ttyJson)], ttyString,
    proc (args: StackView, argc: int): Value =
      ## Convert JSON to string
      case args[0].jsonVal.kind
      of JObject, JArray:
        return initValue(toJson(args[0].jsonVal))
      of JInt:
        return initValue($(args[0].jsonVal.getInt()))
      of JFloat:
        return initValue($(args[0].jsonVal.getFloat()))
      of JBool:
        return initValue($(args[0].jsonVal.getBool()))
      of JString:
        return initValue(args[0].jsonVal.getStr())
      else: discard # todo handle nil
  )

  script.addProc(result, "toString", @[paramDef("x", ttyObject)], ttyString,
    proc (args: StackView, argc: int): Value =
      ## Convert Object to JSON string
      result = initValue(convertObjectToJson(args[0]))
    )

  script.addProc(result, "escape", @[paramDef("s", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      ## Escape a string for safe inclusion in HTML.
      result = initValue(args[0].stringVal[].replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\"", "&quot;")
        .replace("'", "&#39;"))
    )

  script.addProc(result, "unescape", @[paramDef("s", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      ## Unescape a string from HTML entities back to normal characters.
      result = initValue(args[0].stringVal[].replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&amp;", "&"))
    )

  script.addProc(result, "toKeys", @[paramDef("obj", ttyJson)], ttyJson,
    proc (args: StackView, argc: int): Value =
      ## Get the keys of a JSON object as an array.
      result = initValue(%*(args[0].jsonVal.keys().toSeq()))
    )

  script.addProc(result, "echo", @[paramDef("x", ttyString)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      if likely(args[0].typeId == tyString):
        echo args[0].stringVal[]
      else:
        echo "<nil>"
    )

  script.addProc(result, "echo", @[paramDef("x", ttyInt)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      echo args[0].intVal)

  script.addProc(result, "echo", @[paramDef("x", ttyFloat)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      echo args[0].floatVal)

  script.addProc(result, "echo", @[paramDef("x", ttyBool)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      echo args[0].boolVal)

  script.addProc(result, "echo", @[paramDef("x", ttyJson)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      case args[0].jsonVal.kind
      of JInt, JFloat, JBool:
        echo $(args[0].jsonVal)
      of JString:
        echo args[0].jsonVal.getStr()
      else:
        echo toJson(args[0].jsonVal)
    )

  script.addProc(result, "echo", @[paramDef("x", ttyNil)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      echo "nil"
  )

  script.addProc(result, "echo", @[paramDef("x", ttyObject)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      echo convertObjectToJson(args[0])
    )

  script.addProc(result, "echo", @[paramDef("x", ttyArray)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      debugEcho args[0]
    )

  script.addProc(result, "echo", @[paramDef("x", ttyPointer)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      if args[0].objectVal == nil or args[0].objectVal.foreign.data == nil:
        echo "pointer(nil)"
      else:
        echo "pointer(", $(cast[int64](args[0].objectVal.foreign.data)), ")"
    )

  let genT = ast.newIdent("T")
  let genArrayType = newSym(skGenericParam, genT, impl = genT)
  genArrayType.constraint = result.sym"any"

  # script.addProc(result, "len", @[paramDef("x", ttyArray, sym = genArrayType)], ttyInt,
  #   proc (args: StackView, argc: int): Value =
  #     result = initValue(len(args[0].objectVal.fields)))

  # script.addProc(result, "high", @[paramDef("x", ttyArray, sym = genArrayType)], ttyInt,
  #   proc (args: StackView, argc: int): Value =
  #     result = initValue(high(args[0].objectVal.fields)))

  script.addProc(result, "high", @[paramDef("x", ttyJson)], ttyInt,
    proc (args: StackView, argc: int): Value =
      let len =
        if args[0].jsonVal.len > 0:
          len(args[0].jsonVal) - 1
        else: 0
      result = initValue(len)
    )

  script.addProc(result, "high", @[paramDef("x", ttyArray)], ttyInt,
    proc (args: StackView, argc: int): Value =
      let len =
        if args[0].objectVal.fields.len > 0:
          len(args[0].objectVal.fields) - 1
        else: 0
      result = initValue(len)
    )

  # script.addProc(result, "len", @[paramDef("x", ttyObject)], ttyInt,
  #   proc (args: StackView, argc: int): Value =
  #     result = initValue(len(args[0].objectVal.fields)))

  #
  # Mutable number operations
  #
  script.addProc(result, "inc", @[paramDef("i", ttyInt, mut = true)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      inc(args[0].intVal))

  script.addProc(result, "dec", @[paramDef("i", ttyInt, mut = true)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      dec(args[0].intVal))

  #
  # String concatenation
  #
  script.addProc(result, "&", @[paramDef("x", ttyString), paramDef("y", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[] & args[1].stringVal[]))

  script.addProc(result, "&", @[paramDef("x", ttyString), paramDef("y", ttyInt)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[] & $(args[1].intVal)))

  script.addProc(result, "&", @[paramDef("x", ttyInt), paramDef("y", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue($(args[0].intVal) & args[1].stringVal[]))

  script.addProc(result, "&", @[paramDef("x", ttyString), paramDef("y", ttyFloat)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[] & $(args[1].floatVal)))

  script.addProc(result, "&", @[paramDef("x", ttyFloat), paramDef("y", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue($(args[1].floatVal) & args[0].stringVal[]))

  script.addProc(result, "&", @[paramDef("x", ttyString), paramDef("y", ttyBool)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[] & $(args[1].boolVal)))

  script.addProc(result, "&", @[paramDef("x", ttyBool), paramDef("y", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue($(args[0].boolVal) & args[1].stringVal[]))

  #
  # String concatenation with JSON
  #
  proc jsonToStr(j: JsonNode): string =
    case j.kind
    of JString: result = j.getStr()
    of JInt: result = $j.getInt()
    of JFloat: result = $j.getFloat()
    of JBool: result = $j.getBool()
    of JNull: result = ""
    else: result = ""

  script.addProc(result, "&", @[paramDef("x", ttyJson), paramDef("y", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(jsonToStr(args[0].jsonVal) & args[1].stringVal[]))

  script.addProc(result, "&", @[paramDef("x", ttyString), paramDef("y", ttyJson)], ttyString,
    proc (args: StackView, argc: int): Value =
      if likely(args[1].jsonVal != nil):
        result = initValue(args[0].stringVal[] & jsonToStr(args[1].jsonVal)))

  script.addProc(result, "hasKey", @[paramDef("obj", ttyJson), paramDef("key", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initvalue(false)
      if args[0].jsonVal.hasKey(args[1].stringVal[]):
        result.boolVal = true
    )

  #
  # Random Utils
  #
  randomize()
  script.addProc(result, "shuffle", @[paramDef("arr", ttyArray)], ttyArray,
    proc (args: StackView, argc: int): Value =
      var arr = initArray(args[0].objectVal.fields.len)
      for i in 0..<args[0].objectVal.fields.len:
        arr.objectVal.fields[i] = args[0].objectVal.fields[i]
      arr.objectVal.fields.shuffle()
      result = arr
    )

  #
  # Echo `$` operator
  #
  # script.addProc(result, "$", @[paramDef("x", ttyBool)], ttyString,
  #   proc (args: StackView, argc: int): Value =
  #     result = initValue($args[0].boolVal))

  # script.addProc(result, "$", @[paramDef("x", ttyInt)], ttyString,
  #   proc (args: StackView, argc: int): Value =
  #     result = initValue($args[0].intVal))

  # script.addProc(result, "$", @[paramDef("x", ttyFloat)], ttyString,
  #   proc (args: StackView, argc: int): Value =
  #     result = initValue($args[0].floatVal))

  # script.addProc(result, "$", @[paramDef("x", ttyString)], ttyString,
  #   proc (args: StackView, argc: int): Value =
  #     result = initValue(args[0].stringVal[]))

  # script.addProc(result, "$", @[paramDef("x", ttyJson)], ttyString,
  #   proc (args: StackView, argc: int): Value =
  #     result = initValue(toJson(args[0].jsonVal)))

  #
  # Content Length
  #
  script.addProc(result, "len", @[paramDef("x", ttyString)], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(len(args[0].stringVal[])))

  script.addProc(result, "len", @[paramDef("x", ttyJson)], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(len(args[0].jsonVal)))

  script.addProc(result, "len", @[paramDef("x", ttyArray)], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(len(args[0].objectVal.fields)))


  #
  # Built-in OS Operations
  # std/os
  #
  script.addProc(result, "readFile", @[paramDef("path", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      initValue(readFile(args[0].stringVal[])))

  script.addProc(result, "writeFile",
    @[paramDef("path", ttyString), paramDef("content", ttyString)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      writeFile(args[0].stringVal[], args[1].stringVal[]))

  script.addProc(result, "sleep", @[paramDef("ms", ttyInt)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      sleep(args[0].intVal))

  #
  # Builtin JSON/YAML support
  #
  script.addProc(result, "parseJSON", @[paramDef("content", ttyString)], ttyJson,
    proc (args: StackView, argc: int): Value =
      result = initValue(fromJson(args[0].stringVal[]))
    )

  script.addProc(result, "loadJSON", @[paramDef("path", ttyString)], ttyJson,
    proc (args: StackView, argc: int): Value =
      let jsonContent = readFile(args[0].stringVal[])
      result = initValue(fromJson(jsonContent))
    )
  
  script.addProc(result, "remoteJSON", @[paramDef("url", ttyString)], ttyJson,
    proc (args: StackView, argc: int): Value =
      ## Fetch a remote JSON file from the given URL.
      var client = newHttpClient()
      try:
        let res = client.get(args[0].stringVal[])
        var resp = %*{
          "status": res.status,
          "headers": toJson(res.headers.table).fromJson(),
          "content": fromJson(res.body)
        }
        result = initValue(resp)
      except:
        let err = getCurrentExceptionMsg()
        var resp = %*{
          "status": 0,
          "headers": %*{},
          "content": %*{"error": err}
        }
        result = initValue(resp)
      finally:
        client.close()
    )

  proc doFetch(url: string, optsJson: JsonNode): Value =
    let
      httpMethod = block:
        if optsJson != nil and optsJson.hasKey("method"):
          try: parseEnum[HttpMethod](optsJson["method"].getStr())
          except: HttpGet
        else: HttpGet
      reqHeaders = block:
        if optsJson != nil and optsJson.hasKey("headers"):
          var h = newHttpHeaders()
          for key, val in optsJson["headers"]:
            h[key] = val.getStr()
          h
        else: newHttpHeaders()
      body = block:
        if optsJson != nil and optsJson.hasKey("body"):
          optsJson["body"].getStr()
        else: ""
      timeout = block:
        if optsJson != nil and optsJson.hasKey("timeout"):
          optsJson["timeout"].getInt()
        else: -1
    var client = newHttpClient(timeout = timeout)
    client.headers = reqHeaders
    try:
      let res = client.request(url, httpMethod, body)
      let httpCode = int(res.code())
      var resp = %*{
        "ok": httpCode >= 200 and httpCode < 300,
        "status": httpCode,
        "statusText": res.status,
        "headers": %*{}
      }
      for k, v in res.headers:
        resp["headers"][k] = %*v
      resp["body"] = %*res.body
      try:
        resp["json"] = fromJson(res.body)
      except:
        resp["json"] = newJNull()
      result = initValue(resp)
    except:
      let err = getCurrentExceptionMsg()
      result = initValue(%*{
        "ok": false,
        "status": 0,
        "statusText": "Error",
        "headers": %*{},
        "body": "",
        "json": newJNull(),
        "error": err
      })
    finally:
      client.close()

  script.addProc(result, "fetch", @[paramDef("url", ttyString), paramDef("options", ttyJson)], ttyJson,
    proc (args: StackView, argc: int): Value =
      doFetch(args[0].stringVal[], args[1].jsonVal))

  script.addProc(result, "fetch", @[paramDef("url", ttyString)], ttyJson,
    proc (args: StackView, argc: int): Value =
      doFetch(args[0].stringVal[], nil))

  for someTy in [ttyBool, ttyInt, ttyFloat, ttyString, ttyJson, ttyNil]:
    script.addProc(result, "==", @[paramDef("a", ttyJson), paramDef("b", someTy)], ttyBool,
      proc (args: StackView, argc: int): Value =
        case args[1].typeId
        of tyBool:
          result = initValue(args[0].jsonVal.getBool() == args[1].boolVal)
        of tyInt:
          case args[0].jsonVal.kind
          of JInt:
            result = initValue(args[0].jsonVal.getInt() == args[1].intVal)
          of JFloat:
            result = initValue(args[0].jsonVal.getFloat() == toFloat(args[1].intVal))
          else:
            raise newException(TimRuntime, "Type mismatch: expected JSON number, got " & $args[0].jsonVal.kind)
        of tyFloat:
          case args[0].jsonVal.kind
          of JFloat:
            result = initValue(args[0].jsonVal.getFloat() == args[1].floatVal)
          of JInt:
            result = initValue(toFloat(args[0].jsonVal.getInt()) == args[1].floatVal)
          else:
            raise newException(TimRuntime, "Type mismatch: expected JSON number, got " & $args[0].jsonVal.kind)
        of tyString:
          result = initValue(args[0].jsonVal.getStr() == args[1].stringVal[])
        of tyJsonStorage:
          result = initValue(args[0].jsonVal == args[1].jsonVal)
        of tyNil:
          result = initValue(args[0].jsonVal.kind == JNull)
        else:
          raise newException(TimRuntime, "Invalid type for comparison with JSON.")
      )

    script.addProc(result, "==", @[paramDef("a", someTy), paramDef("b", ttyJson)], ttyBool,
      proc (args: StackView, argc: int): Value =
        case args[0].typeId
        of tyBool:
          if args[1].jsonVal.kind != JBool:
            result = initValue(false)
          else:
            result = initValue(args[0].boolVal == args[1].jsonVal.getBool())
        of tyInt:
          case args[1].jsonVal.kind
          of JInt:
            result = initValue(args[0].intVal == args[1].jsonVal.getInt())
          of JFloat:
            result = initValue(toFloat(args[0].intVal) == args[1].jsonVal.getFloat())
          else:
            raise newException(TimRuntime, "Type mismatch: expected JSON number, got " & $args[1].jsonVal.kind)
        of tyFloat:
          case args[1].jsonVal.kind
          of JFloat:
            result = initValue(args[0].floatVal == args[1].jsonVal.getFloat())
          of JInt:
            result = initValue(args[0].floatVal == toFloat(args[1].jsonVal.getInt()))
          else:
            raise newException(TimRuntime, "Type mismatch: expected JSON number, got " & $args[1].jsonVal.kind)
        of tyString:
          if args[1].jsonVal.kind != JString:
            raise newException(TimRuntime, "Type mismatch: expected JSON string for comparison")
          else:
            result = initValue(args[0].stringVal[] == args[1].jsonVal.getStr())
        of tyJsonStorage:
          result = initValue(args[0].jsonVal == args[1].jsonVal)
        of tyNil:
          result = initValue(args[1].jsonVal.kind == JNull)
        else:
          raise newException(TimRuntime, "Invalid type for comparison with JSON.")
      )

    script.addProc(result, "!=", @[paramDef("a", ttyJson), paramDef("b", someTy)], ttyBool,
      proc (args: StackView, argc: int): Value =
        case args[1].typeId
        of tyBool:
          if args[0].jsonVal.kind != JBool:
            raise newException(TimRuntime, "Type mismatch: expected JSON bool for comparison")
          result = initValue(args[0].jsonVal.getBool() != args[1].boolVal)
        of tyInt:
          case args[0].jsonVal.kind
          of JInt:
            result = initValue(args[0].jsonVal.getInt() != args[1].intVal)
          of JFloat:
            result = initValue(args[0].jsonVal.getFloat() != toFloat(args[1].intVal))
          else:
            raise newException(TimRuntime, "Type mismatch: expected JSON number, got " & $args[0].jsonVal.kind)
        of tyFloat:
          case args[0].jsonVal.kind
          of JFloat:
            result = initValue(args[0].jsonVal.getFloat() != args[1].floatVal)
          of JInt:
            result = initValue(toFloat(args[0].jsonVal.getInt()) != args[1].floatVal)
          else:
            raise newException(TimRuntime, "Type mismatch: expected JSON number, got " & $args[0].jsonVal.kind)
        of tyString:
          if args[0].jsonVal.kind != JString:
            raise newException(TimRuntime, "Type mismatch: expected JSON string for comparison")
          result = initValue(args[0].jsonVal.getStr() != args[1].stringVal[])
        of tyJsonStorage:
          result = initValue(args[0].jsonVal != args[1].jsonVal)
        of tyNil:
          result = initValue(args[0].jsonVal.kind != JNull)
        else:
          raise newException(TimRuntime, "Invalid type for comparison with JSON.")
    )

    script.addProc(result, "!=", @[paramDef("a", someTy), paramDef("b", ttyJson)], ttyBool,
      proc (args: StackView, argc: int): Value =
        case args[0].typeId
        of tyBool:
          if args[1].jsonVal.kind != JBool:
            raise newException(TimRuntime, "Type mismatch: expected JSON bool for comparison")
          result = initValue(args[0].boolVal != args[1].jsonVal.getBool())
        of tyInt:
          case args[1].jsonVal.kind
          of JInt:
            result = initValue(args[0].intVal != args[1].jsonVal.getInt())
          of JFloat:
            result = initValue(toFloat(args[0].intVal) != args[1].jsonVal.getFloat())
          else:
            raise newException(TimRuntime, "Type mismatch: expected JSON number, got " & $args[1].jsonVal.kind)
        of tyFloat:
          case args[1].jsonVal.kind
          of JFloat:
            result = initValue(args[0].floatVal != args[1].jsonVal.getFloat())
          of JInt:
            result = initValue(args[0].floatVal != toFloat(args[1].jsonVal.getInt()))
          else:
            raise newException(TimRuntime, "Type mismatch: expected JSON number, got " & $args[1].jsonVal.kind)
        of tyString:
          if args[1].jsonVal.kind != JString:
            raise newException(TimRuntime, "Type mismatch: expected JSON string for comparison")
          result = initValue(args[0].stringVal[] != args[1].jsonVal.getStr())
        of tyJsonStorage:
          result = initValue(args[0].jsonVal != args[1].jsonVal)
        of tyNil:
          result = initValue(args[0].jsonVal.kind != JNull)
        else:
          raise newException(TimRuntime, "Invalid type for comparison with JSON.")
    )

  #
  # Math utilities
  #
  script.addProc(result, "abs", @[paramDef("n", ttyInt)], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(abs(args[0].intVal)))

  script.addProc(result, "abs", @[paramDef("n", ttyFloat)], ttyFloat,
    proc (args: StackView, argc: int): Value =
      result = initValue(abs(args[0].floatVal)))

  script.addProc(result, "min", @[paramDef("a", ttyInt), paramDef("b", ttyInt)], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(min(args[0].intVal, args[1].intVal)))

  script.addProc(result, "min", @[paramDef("a", ttyFloat), paramDef("b", ttyFloat)], ttyFloat,
    proc (args: StackView, argc: int): Value =
      result = initValue(min(args[0].floatVal, args[1].floatVal)))

  script.addProc(result, "max", @[paramDef("a", ttyInt), paramDef("b", ttyInt)], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(max(args[0].intVal, args[1].intVal)))

  script.addProc(result, "max", @[paramDef("a", ttyFloat), paramDef("b", ttyFloat)], ttyFloat,
    proc (args: StackView, argc: int): Value =
      result = initValue(max(args[0].floatVal, args[1].floatVal)))

  script.addProc(result, "round", @[paramDef("n", ttyFloat)], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(toInt(round(args[0].floatVal))))

  script.addProc(result, "floor", @[paramDef("n", ttyFloat)], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(toInt(floor(args[0].floatVal))))

  script.addProc(result, "ceil", @[paramDef("n", ttyFloat)], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(toInt(ceil(args[0].floatVal))))

  script.addProc(result, "sqrt", @[paramDef("n", ttyFloat)], ttyFloat,
    proc (args: StackView, argc: int): Value =
      result = initValue(sqrt(args[0].floatVal)))

  #
  # Converter utilities
  #
  script.addProc(result, "toBool", @[paramDef("x", ttyInt)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].intVal != 0))

  script.addProc(result, "toBool", @[paramDef("x", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[] == "true"))

  script.addProc(result, "intVal", @[paramDef("x", ttyJson)], ttyInt,
    proc (args: StackView, argc: int): Value =
      case args[0].jsonVal.kind
      of JInt:
        result = initValue(args[0].jsonVal.getInt())
      of JFloat:
        result = initValue(toInt(args[0].jsonVal.getFloat()))
      else:
        raise newException(TimRuntime, "Cannot convert JSON value to int.")
      )

  script.addProc(result, "strVal", @[paramDef("x", ttyJson)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(jsonToStr(args[0].jsonVal)))

  script.compileCode(result, "system", InlineCode)
