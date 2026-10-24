## Node.js addon surface for Tim Engine (napibuild only).
##
## Included from `src/tim.nim` after `napi_convert`. Every wrapper
## takes only NAPI-safe params (`string`) and returns plain values via
## denim's `%*`. All Nim failures surface as JS `Error`s by raising
## `ValueError` (a CatchableError — never let an AssertionDefect or
## nil deref escape into Node; denim cannot convert those).

import std/strutils

from ../meta/initializer import TimEngine, TimEngineError, TimTemplate,
  newTim, precompile, getView, getLayout, compileCode
from ../meta/cliutils import timVersion
from pkg/vancode/interpreter/value import `$`

var timEngine {.global.}: TimEngine

proc requireEngine(): TimEngine =
  if timEngine.isNil:
    raise newException(ValueError,
      "tim is not initialized: call init() first")
  timEngine

proc parseDataArg(raw: string): JsonNode =
  try:
    parseJson(raw)
  except JsonParsingError as err:
    raise newException(ValueError, "invalid JSON in `data`: " & err.msg)

init proc(module: Module) =
  proc timInit(src: string, output: string,
               basepath: string) {.export_napi: false.} =
    ## Initialize the engine from a project on disk and precompile it.
    ## `src`/`output` resolve against `basepath`, like `newTim`.
    let engine = newTim(args.get("src").getStr(),
      args.get("output").getStr(), args.get("basepath").getStr())
    try:
      engine.precompile()
    except CatchableError as err:
      raise newException(ValueError, "tim init failed: " & err.msg)
    timEngine = engine
    return %*true

  proc timRender(view: string, layout: string,
                 data: string) {.export_napi: false.} =
    ## Render a view within a layout. `data` is a JSON string exposed
    ## to templates as `$this`. Returns the final HTML string.
    let engine = requireEngine()
    let viewName = args.get("view").getStr().replace(".", "/")
    let viewTpl = engine.getView(viewName)
    if viewTpl.isNil:
      raise newException(ValueError, "view not found: " & viewName)
    let layoutName = args.get("layout").getStr()
    let layoutTpl = engine.getLayout(layoutName)
    if layoutTpl.isNil:
      raise newException(ValueError, "layout not found: " & layoutName)
    let localData = parseDataArg(args.get("data").getStr())
    let ret =
      try:
        compileCode(viewTpl, layoutTpl, localData, engine.globalData)
      except CatchableError as err:
        raise newException(ValueError, "render failed: " & err.msg)
    if ret.isNil:
      return %*""
    return %*($ret)

  proc timRenderView(view: string, data: string) {.export_napi: false.} =
    ## Render a view without a layout. `data` is a JSON string exposed
    ## to the template as `$this`. Returns the final HTML string.
    let engine = requireEngine()
    let viewName = args.get("view").getStr().replace(".", "/")
    let viewTpl = engine.getView(viewName)
    if viewTpl.isNil:
      raise newException(ValueError, "view not found: " & viewName)
    let localData = parseDataArg(args.get("data").getStr())
    let ret =
      try:
        compileCode(viewTpl, localData, engine.globalData)
      except CatchableError as err:
        raise newException(ValueError, "render failed: " & err.msg)
    if ret.isNil:
      return %*""
    return %*($ret)

  proc timVersionFn() {.export_napi: false.} =
    ## Return the engine version (read from `tim.nimble` at compile time).
    return %*timVersion

  module.register("tim", [("init", timInit), ("render", timRender),
    ("renderView", timRenderView), ("version", timVersionFn)])
