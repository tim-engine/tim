# Tim Engine — wasm32-standalone browser playground bridge.
#
# Stateless string-in/string-out API over the embedded engine: templates
# arrive as strings (never read from disk), are compiled against an
# in-memory VFS and interpreted to HTML. Filesystem, network and
# time-dependent template functions are disabled in `-d:wasm` builds
# for security (see libsystem).
#
# Memory protocol (linear memory is exported by the module):
# - host writes input bytes via `timAlloc`, then calls an API proc,
# - the call returns 0 on success (result bytes in the shared buffer)
#   or 1 on error (message bytes in the shared buffer),
# - host reads `timResultLen` bytes at `timResultPtr` and copies them out.

import std/[tables, options, strutils, os, ropes]
import pkg/openparser/json
import pkg/openparser/html as ohtml

import ./meta/initializer
import ./meta/cliutils
import ./engine/parser
import ./engine/transpilers/[jsgen, pygen, rbgen, phpgen, luagen, nimgen]
import ./engine/stdlib/[libsystem, libstrings, libarrays, libjson]
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value,
                                resolver, manager, policy]

var wasmResult {.global.}: string
var wasmLog {.global.}: string

cliutils.logHook = proc(msg: string) =
  wasmLog.add(msg & "\n")

proc copyFromHost(p: pointer, len: int): string =
  ## Copy `len` bytes from wasm linear memory into a Nim string.
  result = newString(len)
  if len > 0:
    copyMem(addr result[0], p, len)

proc timAlloc*(size: csize_t): pointer {.exportc.} =
  ## Allocate `size` bytes for host-provided input. Host writes input
  ## bytes into the returned pointer before calling an API proc.
  if size == 0:
    return nil
  alloc(size)

proc timFree*(p: pointer) {.exportc.} =
  ## Release a pointer previously returned by `timAlloc`.
  if p != nil:
    dealloc(p)

proc timResultPtr*(): pointer {.exportc.} =
  ## Pointer to the first byte of the last result (or error message).
  if wasmResult.len == 0:
    nil
  else:
    unsafeAddr wasmResult[0]

proc timResultLen*(): cint {.exportc.} =
  ## Length in bytes of the last result (or error message).
  wasmResult.len.cint

proc takeError(msg: string): cint =
  if wasmLog.len > 0:
    wasmResult = wasmLog & msg
  else:
    wasmResult = msg
  wasmLog = ""
  1

proc takeOk(output: string): cint =
  wasmResult = output
  wasmLog = ""
  0

proc splitData(dataJson: string): tuple[localData, globalData: JsonNode] =
  ## Split the data payload: `{"app": ..., "this": ...}` maps to the
  ## `$app` / `$this` scopes; any other object is the `$this` scope.
  var data: JsonNode
  try:
    data = parseJson(dataJson)
  except JsonParsingError, ValueError:
    data = newJObject()
  if data.kind == JObject and (data.hasKey("app") or data.hasKey("this")):
    result.localData =
      if data.hasKey("this"): data["this"]
      else: newJObject()
    result.globalData =
      if data.hasKey("app"): data["app"]
      else: newJObject()
  elif data.kind == JObject:
    result = (data, newJObject())
  else:
    result = (newJObject(), newJObject())

proc parsePartials(partialsJson: string, partials: TableRef[string, string]) =
  ## Register partials (`{"name": "source"}`) under every key shape the
  ## in-memory VFS may look up (`name`, `name.timl`, normalized forms).
  if partialsJson.len == 0:
    return
  var node: JsonNode
  try:
    node = parseJson(partialsJson)
  except CatchableError as e:
    raise newException(TimEngineError, "Invalid partials JSON: " & e.msg)
  if node.kind != JObject:
    raise newException(TimEngineError, "Partials JSON must be an object")
  for name, src in node:
    if src.kind != JString:
      raise newException(TimEngineError,
        "Partial \"" & name & "\" must be a string")
    let content = src.getStr()
    partials[name] = content
    let withExt =
      if name.endsWith(".timl"): name
      else: name & ".timl"
    partials[withExt] = content
    partials[normalizedPath(name)] = content
    partials[normalizedPath(withExt)] = content

proc renderSources(viewSrc, layoutSrc, partialsJson, dataJson: string): string =
  let (localData, globalData) = splitData(dataJson)
  var engine = newTim(globalData)
  var views = newTable[string, string]()
  var layouts = newTable[string, string]()
  var partials = newTable[string, string]()
  views["view"] = viewSrc
  if layoutSrc.len > 0:
    layouts["layout"] = layoutSrc
  parsePartials(partialsJson, partials)
  engine.precompile(views, layouts, partials)
  if "view" notin engine.views:
    raise newException(TimEngineError, "View template failed to compile")
  let viewTpl = engine.views["view"]
  if layoutSrc.len > 0:
    if "layout" notin engine.layouts:
      raise newException(TimEngineError, "Layout template failed to compile")
    result = "<!DOCTYPE html>" &
      $interpret(viewTpl, engine.layouts["layout"], localData, globalData)
  else:
    result = $interpret(viewTpl, localData, globalData)

proc transpileSource(src, target, dataJson: string): string =
  var program: Ast
  try:
    parser.parseScript(program, src, "playground")
  except TimParserError as e:
    raise newException(TimEngineError, "Parsing error – " & e.msg)
  var
    mainChunk = newChunk("playground")
    script = newScript(mainChunk)
    module = newModule("playground", some("playground"))
  let systemModule = libsystem.loadLibrary(script)
  module.load(systemModule)
  module.load(initStrings(script, systemModule))
  module.load(initArrays(script, systemModule))
  module.load(initJSON(script, systemModule))
  script.stdpos = script.procs.high
  case target
  of "html":
    let (localData, globalData) = splitData(dataJson)
    let manager = sharedTimManager()
    var compiler = codegen.initCompiler(script, module, mainChunk, manager,
      initializer.stdlibs, nil, policy = CompilationPolicy())
    compiler.resolver.fs = newInMemoryFS(newTable[string, string]())
    compiler.declareGlobals()
    compiler.genScript(program, none(string))
    let vmInstance = newVm()
    result = $(vmInstance.interpret(script, mainChunk,
      globalData = globalData, localData = localData))
  of "js":
    var jst = jsgen.initCodeGen(script, module, mainChunk)
    result = $(jst.genScript(program, none(string), isMainScript = true))
  of "py":
    var pyt = pygen.initCodeGen(script, module, mainChunk)
    result = $(pyt.genScript(program, none(string), isMainScript = true))
  of "rb":
    var rbt = rbgen.initCodeGen(script, module, mainChunk)
    result = $(rbt.genScript(program, none(string), isMainScript = true))
  of "php":
    var phpt = phpgen.initCodeGen(script, module, mainChunk)
    result = $(phpt.genScript(program, none(string), isMainScript = true))
  of "lua":
    var lut = luagen.initCodeGen(script, module, mainChunk)
    result = $(lut.genScript(program, none(string), isMainScript = true))
  of "nim":
    var nimt = nimgen.initCodeGen(script, module, mainChunk)
    result = $(nimt.genScript(program, none(string), isMainScript = true))
  else:
    raise newException(TimEngineError,
      "Unsupported transpile target: " & target)

proc timRender*(viewPtr: pointer, viewLen: cint,
                layoutPtr: pointer, layoutLen: cint,
                partialsPtr: pointer, partialsLen: cint,
                dataPtr: pointer, dataLen: cint): cint {.exportc.} =
  ## Render a view inside a layout. Empty layout renders the view alone.
  wasmLog = ""
  try:
    let html = renderSources(
      copyFromHost(viewPtr, viewLen.int),
      copyFromHost(layoutPtr, layoutLen.int),
      copyFromHost(partialsPtr, partialsLen.int),
      copyFromHost(dataPtr, dataLen.int))
    takeOk(html)
  except CatchableError as e:
    takeError("Render error: " & e.msg)
  except Exception as e:
    takeError("Render error: " & e.msg)

proc timRenderView*(viewPtr: pointer, viewLen: cint,
                    partialsPtr: pointer, partialsLen: cint,
                    dataPtr: pointer, dataLen: cint): cint {.exportc.} =
  ## Render a view without a layout.
  timRender(viewPtr, viewLen, nil, 0, partialsPtr, partialsLen,
    dataPtr, dataLen)

proc timTranspile*(srcPtr: pointer, srcLen: cint,
                   targetPtr: pointer, targetLen: cint,
                   dataPtr: pointer, dataLen: cint): cint {.exportc.} =
  ## Transpile timl source to `html`, `js`, `py`, `rb`, `php`, `lua` or `nim`.
  ## `data` (JSON) feeds `$app` / `$this` for the `html` target.
  wasmLog = ""
  try:
    let output = transpileSource(
      copyFromHost(srcPtr, srcLen.int),
      copyFromHost(targetPtr, targetLen.int),
      copyFromHost(dataPtr, dataLen.int))
    takeOk(output)
  except CatchableError as e:
    takeError("Transpile error: " & e.msg)
  except Exception as e:
    takeError("Transpile error: " & e.msg)

proc timVersionInfo*(): cint {.exportc.} =
  ## Report the engine version through the shared result buffer.
  wasmLog = ""
  takeOk(timVersion)

proc timDebugTag*(namePtr: pointer, nameLen: cint): cint {.exportc.} =
  ## Debug: normalize + resolve a tag name; result buffer gets
  ## `normalized|ord`. Useful for host-side diagnostics.
  wasmLog = ""
  try:
    let name = copyFromHost(namePtr, nameLen.int)
    let norm = nimIdentNormalize(name)
    let tag = ohtml.getHtmlTag(name)
    takeOk(norm & "|" & $ord(tag) & "|" & $tag)
  except CatchableError as e:
    takeError("debug error: " & e.msg)
  except Exception as e:
    takeError("debug error: " & e.msg)
