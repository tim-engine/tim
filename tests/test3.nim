import std/[os, monotimes, times, osproc,
        unittest, strutils, json, options, ropes]

import ../src/tim/engine/transformers

import pkg/vancode/interpreter/[ast, chunk, sym]
import pkg/vancode/manager/packager

import ../src/tim/engine/parser
import ../src/tim/engine/stdlib/libsystem
import ../src/tim/engine/transpilers/[jsgen, pygen, rbgen, phpgen, luagen, nimgen]

proc parserCallback(astProgram: var Ast, path: string) =
  parser.parseScript(astProgram, readFile(path), path)

template initPackageManager() {.dirty.} =
  let pkgr = packager.initPackageRemote[PackageConfig]()
  pkgr.loadPackages()

template initParser(code: string, srcPath = "HelloWorld") {.dirty.} =
  var program: Ast
  try:
    parser.parseScript(program, code, srcPath)
  except TimParserError as e:
    doAssert false, "Parsing failed with error: " & e.msg

  var
    mainChunk = newChunk(srcPath)
    script = newScript(mainChunk)
    module = newModule(srcPath.extractFilename, some(srcPath))

template initLibrary() {.dirty.} =
  let
    data = newJObject()
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
  let systemModule = libsystem.loadLibrary(script)
  module.load(systemModule)

proc rubyWrapper(x: Rope, className: string): string =
  result = $x
  result.add("\n")
  result.add("puts " & className & ".render()")

proc pythonWrapper(x: Rope, className: string): string =
  result = $x
  result.add("\n")
  result.add("print(" & className & ".render())")

proc jsWrapper(x: Rope, className: string): string =
  result = $x
  result.add("\n")
  result.add("console.log(" & className & ".render())")

proc luaWrapper(x: Rope, className: string): string =
  result = $x
  result.add("\n")
  result.add("do\n  local mod = " & className & "\n  print(mod:render())\nend\n")

const
  sample1 = """
var hello = "Tim Engine is Awesome!"
h1.fw-bold: $hello
"""
  sample1Html = """<h1 class="fw-bold">Tim Engine is Awesome!</h1>"""

test "s2s ruby":
  initPackageManager()
  initParser(sample1)
  initLibrary()

  var rbt = rbgen.initCodeGen(script, module, mainChunk)
  let output = rbt.genScript(program, none(string), isMainScript = true)
  echo "Generated Ruby code:\n" & output
  let s2sPath = getCurrentDir() / "tests" / "s2s"
  
  discard existsOrCreateDir(s2sPath)
  writeFile(s2sPath / "sample1.rb", rubyWrapper(output, "HelloWorld"))
  let stsOutput = execCmdEx("ruby " & s2sPath / "sample1.rb")
  assert stsOutput.exitCode == 0
  assert stsOutput.output.strip() == sample1Html

  echo "Generated Ruby code:"
  echo stsOutput.output

test "s2s python":
  initPackageManager()
  initParser(sample1)
  initLibrary()

  var pyt = pygen.initCodeGen(script, module, mainChunk)
  let output = pyt.genScript(program, none(string), isMainScript = true)
  echo "Generated Python code:\n" & output
  let s2sPath = getCurrentDir() / "tests" / "s2s"
  
  discard existsOrCreateDir(s2sPath)
  writeFile(s2sPath / "sample1.py", pythonWrapper(output, "HelloWorld"))
  
  let stsOutput = execCmdEx("python " & s2sPath / "sample1.py")
  assert stsOutput.exitCode == 0
  assert stsOutput.output.strip() == sample1Html

  echo "Generated Python code:"
  echo stsOutput.output

test "s2s javascript":
  initPackageManager()
  initParser(sample1)
  initLibrary()

  var jst = jsgen.initCodeGen(script, module, mainChunk)
  let output = jst.genScript(program, none(string), isMainScript = true)
  echo "Generated JavaScript code:\n" & output
  let s2sPath = getCurrentDir() / "tests" / "s2s"
  
  discard existsOrCreateDir(s2sPath)
  writeFile(s2sPath / "sample1.js", jsWrapper(output, "HelloWorld"))
  
  let stsOutput = execCmdEx("node " & s2sPath / "sample1.js")
  assert stsOutput.exitCode == 0
  assert stsOutput.output.strip() == sample1Html

  echo "Generated JavaScript code:"
  echo stsOutput.output

test "s2s lua":
  initPackageManager()
  initParser(sample1)
  initLibrary()

  var lgt = luagen.initCodeGen(script, module, mainChunk)
  let output = lgt.genScript(program, none(string), isMainScript = true, withReturnStmt = false)
  echo "Generated Lua code:\n" & output
  let s2sPath = getCurrentDir() / "tests" / "s2s"
  
  discard existsOrCreateDir(s2sPath)
  writeFile(s2sPath / "sample1.lua", luaWrapper(output, "HelloWorld"))
  
  let stsOutput = execCmdEx("luajit " & s2sPath / "sample1.lua")
  assert stsOutput.exitCode == 0
  assert stsOutput.output.strip() == sample1Html

  echo "Generated Lua code:"
  echo stsOutput.output
