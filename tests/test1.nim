import std/[unittest, os, xmltree, strtabs,
        sequtils, json, options, strutils]
import pkg/openparser/html

include ../src/tim/engine/transformers
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value, resolver]

import ../src/tim/engine/[errors, parser]
import ../src/tim/engine/stdlib/[libsystem]

from ../src/tim/meta/initializer import declareGlobals

proc parserCallback(astProgram: var Ast, path: string, resolver: FileResolver) =
  parser.parseScript(astProgram, readFile(path), path)

proc toHtml(id, code: string, localData, globalData = newJObject()): string =

  var astTree: Ast
  parser.parseScript(astTree, code, id)

  var mainChunk = newChunk(id)
  var script = newScript(mainChunk)
  var module = newModule(id, some(id))

  # load standard library modules
  let systemModule = libsystem.loadLibrary(script)
  module.load(systemModule)

  script.stdpos = script.procs.high # start after stdlib procs
  
  var compiler = codegen.initCompiler(script, module, mainChunk, nil, nil, parserCallback)
  compiler.declareGlobals()
  compiler.genScript(program = astTree, includePath = some(getCurrentDir()))

  let vmm = newVM()
  return $(vmm.interpret(script, mainChunk, localData = localData, globalData = globalData))

suite "Basics":
  test "simple template":
    let samplecode= """
div.container > div.row > div.col-12
  "Tim Engine is Awesome!"
"""
    assert toHtml("test1", samplecode) ==
      """<div class="container"><div class="row"><div class="col-12">Tim Engine is Awesome!</div></div></div>"""
  
  test "text elements":
    let samplecode = """
h1: "Hello World!"
  span: "This span is inside the h1 element"
"""
    assert toHtml("test2", samplecode) ==
      """<h1>Hello World!<span>This span is inside the h1 element</span></h1>"""
  
  test "attributes and nesting":
    let samplecode = """
a#my-link.btn.btn-primary href="https://example.com"
  target="_blank" title="Example Link": "Click me!"
"""
    assert toHtml("test3", samplecode) ==
      """<a id="my-link" href="https://example.com" target="_blank" title="Example Link" class="btn btn-primary">Click me!</a>"""
  
  test "dynamic data":
    let samplecode = """
p: "Hello, " & $this["name"] & "!"
"""
    let localData = newJObject()
    localData["name"] = newJString("Tim")
    assert toHtml("test4", samplecode, localData) ==
      """<p>Hello, Tim!</p>"""
  test "conditionals":
    let samplecode = """
if $this["isLoggedIn"] == true:
  p: "Welcome back, " & $this["username"] & "!"
else:
  p: "Please log in to continue."
"""
    let localData = newJObject()
    localData["isLoggedIn"] = newJBool(true)
    localData["username"] = newJString("Tim")
    
    assert toHtml("test5", samplecode, localData) ==
      """<p>Welcome back, Tim!</p>"""
    
    # Test the else branch
    localData["isLoggedIn"] = newJBool(false)
    assert toHtml("test5", samplecode, localData) ==
      """<p>Please log in to continue.</p>"""

    test "loops":
      let samplecode = """
ul
  for $item in $this["items"]:
    li: $item
"""
      var localData = newJObject()
      localData["items"] = newJArray()
      for x in [newJString("Item 1"), newJString("Item 2"), newJString("Item 3")]:
        localData["items"].add(x)
      assert toHtml("test6", samplecode, localData) ==
        """<ul><li>Item 1</li><li>Item 2</li><li>Item 3</li></ul>"""

    test "error handling":
      let samplecode = """
p: "This will cause an error: " & $this["undefinedKey"]
"""
      try:
        discard toHtml("test7", samplecode)
        doAssert false, "Expected an error due to undefined key, but no error was raised."
      except KeyError as e:
        # this is not a code generation error, but a runtime error due  to
        # accessing an undefined key in the JSON storage, so a KeyError is expected
        assert e.msg == "key not found: undefinedKey"

    test "html comments":
      let samplecode = """
div.container
  <!-- This is an HTML comment -->
  p: "Hello"
"""
      let html = toHtml("test8", samplecode)
      doAssert "<!-- This is an HTML comment -->" in html
