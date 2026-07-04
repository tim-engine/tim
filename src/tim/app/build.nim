# A super fast template engine for cool kids
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[os, monotimes, times, strutils, json, options, ropes, tables]

import pkg/flatty
import pkg/kapsis/runtime
import pkg/kapsis/interactive/prompts

import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value, resolver]
import pkg/vancode/manager/[packager, configurator]

import ../engine/parser
import ../engine/stdlib/[libsystem, libstrings, libarrays, libjson, libobjects]
import ../engine/transpilers/[jsgen, pygen, rbgen, phpgen, luagen, nimgen]

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
  
  # init the package manager and load the local packages
  let pkgr = packager.initPackageRemote()
  pkgr.loadPackages()

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
              module, mainChunk, pkgr, stdlibs, parserCallback,
              policy = CompilationPolicy()) # empty polcy for now - TODO - tim.config.yaml
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
  writeFile(srcPath.changeFileExt("ast"), toFlatty(program))