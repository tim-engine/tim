# A super fast template engine for cool kids
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[os, monotimes, times, strutils, json, options, ropes, tables]

import pkg/kapsis/runtime
import pkg/kapsis/interactive/prompts

import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value, resolver, manager, policy]
import pkg/vancode/interpreter/cache/fbe as fbeCache
import pkg/vancode/manager/configurator # shim
import pkg/openparser/yaml

import ../engine/parser
import ../engine/stdlib/[libsystem, libstrings, libarrays, libjson, libobjects]
import ../engine/transpilers/[jsgen, pygen, rbgen, phpgen, luagen, nimgen]
import ../meta/config
from ../meta/initializer import TimEngine, TimEngineError, newTim, precompile,
  precompileTemplate, registerTemplate, getView, getLayout, interpret

proc parserCallback(astProgram: var Ast, path: string, resolver: FileResolver) =
  parser.parseScript(astProgram, readFile(path), path)

proc declareGlobals(compiler: codegen.CodeGen) =
  # Declare global variables for the template scripts, such as `$app` and `$this`.
  let appStorage = newIdent("app")
  let thisStorage = newIdent("this")
  compiler.declareVar(appStorage, skConst, compiler.module.sym"json", isMagic = true)
  compiler.declareVar(thisStorage, skConst, compiler.module.sym"json", isMagic = true)

proc srcCommand*(v: Values) =
  ## Transpiles `timl` code to a target source
  # parse the script
  var srcPath = $(v.get("timl").getPath)
  
  let manager = sharedManager()

  let 
    ext =
      if v.has("--ext"): v.get("--ext").getStr
      else: "html" # default target is HTML
    flagPrettyPrint = v.has("--pretty")
    flagNoCache = v.has("--nocache")
    flagRecache = v.has("--recache")
    hasJsonFlag = v.has("--json-errors")
    outputPath = if v.has("-o"): v.get("-o").getStr else: ""
    flagBencmarks = v.has("--bench")

  if not srcPath.isAbsolute:
    srcPath = getCurrentDir() / srcPath
  var srcFilePath = srcPath
  let
    timlCode = readFile(srcPath)
    t = getMonotime()
    data =
      if v.has("--data"):
        v.get("--data").getJson
      else:
        newJObject()
    globalData =
      if data != nil:
        if data.hasKey"app":
          data["app"]
        else: newJObject()
      else: newJObject()
    localData =
      if data != nil:
        if data.hasKey"this":
          data["this"]
        else: newJObject()
      else: newJObject()

  var program: Ast # the AST representation of the script
  try:
    parser.parseScript(program, timlCode, srcFilePath)
  except TimParserError as e:
    echo e.msg
    quit(1)

  var
    mainChunk = newChunk(srcFilePath)
    script = newScript(mainChunk)
    module = newModule(srcFilePath.extractFilename, some(srcFilePath))

  # load standard library modules
  let systemModule = libsystem.loadLibrary(script)
  module.load(systemModule)

  # let stringsLib = initStrings(script, systemModule)
  # module.load(stringsLib)

  # let arraysLib = initArrays(script, systemModule)
  # module.load(arraysLib)

  script.stdpos = script.procs.high

  let stdlibs = newTable[string, proc(script: Script, systemModule: Module): Module]()
  stdlibs["system"] = proc(script: Script, systemModule: Module): Module =
    result = libsystem.loadLibrary(script)
  stdlibs["strings"] = initStrings
  stdlibs["arrays"] = initArrays
  stdlibs["json"] = initJSON
  stdlibs["objects"] = initObjects

  # let timesModule = script.initTimes(systemModule)
  # module.load(timesModule)
  var output: string
  if ext == "html":
    try:
      var compiler = codegen.initCompiler(script,
              module, mainChunk, manager, stdlibs, parserCallback,
              policy = CompilationPolicy())
      compiler.declareGlobals()
      compiler.genScript(program, none(string))
      let vmInstance = newVm()
      output = $(vmInstance.interpret(script, mainChunk, globalData = globalData, localData = localData))
    except CodeGenError as e:
      displayError("Code generation error in template: " & srcFilePath)
      display(e.msg)
      quit(1)
  elif ext == "js":
    var jst = jsgen.initCodeGen(script, module, mainChunk)
    output = $(jst.genScript(program, none(string), isMainScript = true))
  elif ext == "py":
    var pyt = pygen.initCodeGen(script, module, mainChunk)
    output = $(pyt.genScript(program, none(string), isMainScript = true))
  elif ext == "rb":
    var rbt = rbgen.initCodeGen(script, module, mainChunk)
    output = $(rbt.genScript(program, none(string), isMainScript = true))
  elif ext == "php":
    var phpt = phpgen.initCodeGen(script, module, mainChunk)
    output = $(phpt.genScript(program, none(string), isMainScript = true))
  elif ext == "lua":
    var lut = luagen.initCodeGen(script, module, mainChunk)
    output = $(lut.genScript(program, none(string), isMainScript = true))
  elif ext == "nim":
    var nimt = nimgen.initCodeGen(script, module, mainChunk)
    output = $(nimt.genScript(program, none(string), isMainScript = true))
  else:
    displayError("Unsupported target source extension: " & ext)
    quit(1)

  if outputPath.len > 0:
    writeFile(outputPath, output)
  else:
    echo output

  # display the time taken for compilation
  if flagBencmarks:
    displayInfo("Done in " & $(getMonotime() - t))

#
# AST 
#
proc astCommand*(v: Values) =
  ## Generate the AST representation of a `timl` script
  let
    srcPath = getCurrentDir() / $(v.get("timl").getPath)
    timlCode = readFile(srcPath)
  
  var program: Ast # the AST representation of the script
  parser.parseScript(program, timlCode, srcPath)
  writeFile(srcPath.changeFileExt("ast"), fbeCache.toFbe(program, TimFbeVersion))

#
# Static HTML builder
#
proc normalizeViewKey(key: string): string =
  ## Normalize a user-provided view reference to a `getView` lookup key.
  ## Accepts dotted (`blog.post`), slash (`blog/post`), with or without
  ## the `.timl` extension, and tolerates a leading `/` or `views/` prefix.
  var k = key.strip()
  if k.startsWith("/"):
    k = k[1..^1]
  if k.startsWith("views/"):
    k = k["views/".len..^1]
  if k.endsWith(".timl"):
    k = k[0..^6]
  if "/" notin k and "." in k:
    k = k.replace(".", "/")
  k

proc buildSingleView(timEngine: TimEngine, viewKey, layoutName, outArg: string) =
  ## Render one view + layout pair and save it to a single `.html` file
  let viewTpl = timEngine.getView(viewKey)
  if viewTpl == nil:
    displayError("View template not found: " & viewKey, quitProcess = true)
  let layoutTpl = timEngine.getLayout(layoutName)
  if layoutTpl == nil:
    displayError("Layout template not found: " & layoutName, quitProcess = true)
  let html = "<!DOCTYPE html>" &
    $interpret(viewTpl, layoutTpl, newJObject(), timEngine.globalData)
  let tsName = $toUnix(getTime()) & ".html"
  var outFile: string
  if outArg.len == 0:
    outFile = getCurrentDir() / tsName
  elif dirExists(outArg) or outArg.endsWith("/") or outArg.splitFile().ext.len == 0:
    # A directory (existing, trailing slash, or extensionless path):
    # save the timestamped file inside it
    discard existsOrCreateDir(outArg)
    outFile = outArg / tsName
  else:
    let parent = outArg.parentDir()
    if parent.len > 0:
      discard existsOrCreateDir(parent)
    outFile = outArg
  writeFile(outFile, html)
  displaySuccess("Statically built " & outFile.extractFilename())

proc buildAllViews(timEngine: TimEngine, layoutName, outArg: string) =
  ## Render every view with the given layout, mirroring the
  ## `views/` tree as `.html` files inside the output directory
  let layoutTpl = timEngine.getLayout(layoutName)
  if layoutTpl == nil:
    displayError("Layout template not found: " & layoutName, quitProcess = true)
  let outDir =
    if outArg.len == 0: getCurrentDir() / "dist"
    else: outArg
  discard existsOrCreateDir(outDir)
  let viewsPath = timEngine.config.compilation.viewsPath
  var count = 0
  for srcPath, viewTpl in timEngine.views:
    let rel = relativePath(srcPath, viewsPath).changeFileExt("html")
    let dest = outDir / rel
    discard existsOrCreateDir(dest.parentDir())
    try:
      let html = "<!DOCTYPE html>" &
        $interpret(viewTpl, layoutTpl, newJObject(), timEngine.globalData)
      writeFile(dest, html)
      inc count
    except CatchableError as e:
      displayWarning("Skipping " & rel & ": " & e.msg)
  displaySuccess("Statically built " & $count & " views to " & outDir)

proc precompileLazy(timEngine: TimEngine, viewKey, layoutName: string) =
  ## Precompile only the requested view, its layout and their transitive
  ## dependencies (partials). A single page needs a handful of templates,
  ## not the whole project — full `precompile()` dominates `build <view>`
  ## wall time (bench: 1.28s single vs 1.31s all-views on zaiku preview).
  let manager = sharedManager()
  let
    viewsPath = timEngine.config.compilation.viewsPath
    layoutsPath = timEngine.config.compilation.layoutsPath
    viewSrc = viewsPath / viewKey & ".timl"
    layoutSrc =
      if layoutName.endsWith(".timl"): layoutsPath / layoutName
      else: layoutsPath / layoutName & ".timl"
  if not fileExists(viewSrc):
    displayError("View template not found: " & viewKey, quitProcess = true)
  if not fileExists(layoutSrc):
    displayError("Layout template not found: " & layoutName, quitProcess = true)
  # BFS over template sources: each compiled template reports its
  # dependencies, which are registered and compiled in turn.
  var
    queue = @[viewSrc, layoutSrc]
    seen: seq[string] = @[]
  while queue.len > 0:
    let src = queue.pop()
    if src in seen:
      continue
    seen.add(src)
    if not fileExists(src):
      displayWarning("Skipping missing template: " & src)
      continue
    try:
      let tpl = timEngine.registerTemplate(src)
      if timEngine.precompileTemplate(tpl, manager):
        for dep in tpl.dependencies:
          if dep notin seen:
            queue.add(dep)
    except TimEngineError as e:
      displayWarning("Skipping template " & src & ": " & e.msg)

proc buildCommand*(v: Values) =
  ## Build the Tim project in the current directory to static HTML.
  ## With a `view` renders a single page (`--layout`, default `base`;
  ## `--out` file or directory, default `CWD/<unixtime>.html`).
  ## Without a `view` renders every view into `--out` (default `CWD/dist`).
  let timConfigPath = getCurrentDir() / "tim.config.yml"
  if not fileExists(timConfigPath):
    displayError("tim.config.yml not found in the current directory", quitProcess = true)

  let config: TimConfig = parseYaml(readFile(timConfigPath), TimConfig)
  let baseDir = getCurrentDir()
  let timEngine = newTim(
    src = config.compilation.source,
    output = config.compilation.output,
    basepath = baseDir
  )
  timEngine.config.compilation.policy = config.compilation.policy
  # Static builds never carry the live-reload snippet: `enableBrowserSync`
  # stays unset so `interpret` renders plain HTML (see `serve --sync`).

  let layoutName =
    if v.has("--layout"): v.get("--layout").getStr
    else: "base"
  let outArg =
    if v.has("--out"): v.get("--out").getStr
    else: ""

  if v.has("view"):
    let viewKey = normalizeViewKey(v.get("view").getStr)
    timEngine.precompileLazy(viewKey, layoutName)
    buildSingleView(timEngine, viewKey, layoutName, outArg)
  else:
    timEngine.precompile()
    buildAllViews(timEngine, layoutName, outArg)