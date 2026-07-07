# A super fast template engine for cool kids
#
# (c) iLiquid, 2019-2020
#     https://github.com/liquidev/
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim | https://openpeeps.dev/packages/tim

import std/[strutils, options, base64]
import pkg/vancode/interpreter/[chunk, ast, sym, value]

import ./inliner

proc initStrings*(script: Script, systemModule: Module): Module =
  # foreign stuff
  result = newModule("strings", some"strings.timl")
  result.load(systemModule)

  script.addProc(result, "contains", @[paramDef("s", ttyString), paramDef("sub", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      initValue(strutils.contains(args[0].stringVal[], args[1].stringVal[])))

  script.addProc(result, "startsWith", @[paramDef("s", ttyString), paramDef("prefix", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      initValue(strutils.startsWith(args[0].stringVal[], args[1].stringVal[])))

  script.addProc(result, "endsWith", @[paramDef("s", ttyString), paramDef("suffix", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      initValue(strutils.endsWith(args[0].stringVal[], args[1].stringVal[])))

  script.addProc(result, "toUpper", @[paramDef("s", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      initValue(strutils.toUpperAscii(args[0].stringVal[])))

  # script.addProc(result, "isUpper", @[paramDef("s", ttyString)], ttyBool,
  #   proc (args: StackView, argc: int): Value =
  #     # todo handle utf8
  #     initValue(strutils.isUpperAscii(args[0].stringVal[])))

  script.addProc(result, "toLower", @[paramDef("s", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      initValue(strutils.toLowerAscii(args[0].stringVal[])))

  # script.addProc(result, "isLower", @[paramDef("s", ttyString)], ttyBool,
  #   proc (args: StackView, argc: int): Value =
  #     # todo handle utf8
  #     initValue(strutils.isLowerAscii(args[0].stringVal[])))

  #
  # Base64 encoding/decoding
  #
  script.addProc(result, "encode", @[paramDef("s", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      initValue(base64.encode(args[0].stringVal[])))

  script.addProc(result, "decode", @[paramDef("s", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      initValue(base64.decode(args[0].stringVal[])))

  script.addProc(result, "strip", @[paramDef("s", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      initValue(strutils.strip(args[0].stringVal[])))

  script.addProc(result, "split", @[paramDef("s", ttyString), paramDef("sep", ttyString)], ttyArray,
    proc (args: StackView, argc: int): Value =
      let parts = strutils.split(args[0].stringVal[], args[1].stringVal[])
      result = initArray(parts.len)
      for i, p in parts:
        result.objectVal.fields[i] = initValue(p).toStorage)

  script.addProc(result, "replace", @[paramDef("s", ttyString), paramDef("from", ttyString), paramDef("to", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      initValue(strutils.replace(args[0].stringVal[], args[1].stringVal[], args[2].stringVal[])))

  script.addProc(result, "repeat", @[paramDef("s", ttyString), paramDef("n", ttyInt)], ttyString,
    proc (args: StackView, argc: int): Value =
      initValue(strutils.repeat(args[0].stringVal[], args[1].intVal)))

  script.addProc(result, "capitalize", @[paramDef("s", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      initValue(strutils.capitalizeAscii(args[0].stringVal[])))

  script.addProc(result, "count", @[paramDef("s", ttyString), paramDef("sub", ttyString)], ttyInt,
    proc (args: StackView, argc: int): Value =
      initValue(strutils.count(args[0].stringVal[], args[1].stringVal[])))

  script.addProc(result, "isAlphaNumeric", @[paramDef("s", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      var res = args[0].stringVal[].len > 0
      for c in args[0].stringVal[]:
        if not strutils.isAlphaNumeric(c):
          res = false
          break
      initValue(res))

  script.addProc(result, "isDigit", @[paramDef("s", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      var res = args[0].stringVal[].len > 0
      for c in args[0].stringVal[]:
        if not strutils.isDigit(c):
          res = false
          break
      initValue(res))
