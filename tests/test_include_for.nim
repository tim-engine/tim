import std/[unittest, os, json, options, strutils]
include ../src/tim/engine/transformers
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value, resolver]
import ../src/tim/engine/[parser]
import ../src/tim/engine/stdlib/[libsystem]
from ../src/tim/meta/initializer import declareGlobals

proc parserCallback(astProgram: var Ast, path: string, resolver: FileResolver) =
  parser.parseScript(astProgram, readFile(path), path)

proc toHtmlWithInclude(id, code: string, includePath: string, localData = newJObject(), globalData = newJObject()): string =
  var astTree: Ast
  parser.parseScript(astTree, code, id)
  var mainChunk = newChunk(id)
  var script = newScript(mainChunk)
  var module = newModule(id, some(id))
  let systemModule = libsystem.loadLibrary(script)
  module.load(systemModule)
  script.stdpos = script.procs.high
  var compiler = codegen.initCompiler(script, module, mainChunk, nil, nil, parserCallback)
  compiler.declareGlobals()
  compiler.genScript(program = astTree, includePath = some(includePath))
  let vmm = newVM()
  result = $(vmm.interpret(script, mainChunk, localData = localData, globalData = globalData))

suite "Include inside for loop":
  test "include at top level":
    let dir = getTempDir() / "tim_include_for_test"
    createDir(dir)
    writeFile(dir / "card_static.timl", "div.card: \"hello\"")
    let res = toHtmlWithInclude("test_top", "@include \"card_static\"", dir, newJObject())
    echo "top-level res: ", res
    check "card" in res.toLowerAscii or "div" in res

  test "include inside for loop - current behavior":
    let dir = getTempDir() / "tim_include_for_test2"
    createDir(dir)
    writeFile(dir / "card.timl", "div.card: $item")
    let code = """
ul
  for $item in $this["items"]:
    @include "card"
"""
    var localData = newJObject()
    localData["items"] = newJArray()
    for x in [newJString("A"), newJString("B"), newJString("C")]:
      localData["items"].add(x)
    echo "parsing code with for+include..."
    try:
      let res = toHtmlWithInclude("test_for", code, dir, localData)
      echo "for+include res: ", res
      echo "AST otherPaths check passed"
      check res.contains("A") and res.contains("B") and res.contains("C")
      check res.contains("card")
    except Exception as e:
      echo "FAILED with exception: ", e.msg
      echo e.getStackTrace()
      # capture failure for investigation
      fail()

  test "include inside for with nested HTML":
    let dir = getTempDir() / "tim_include_for_test3"
    createDir(dir)
    writeFile(dir / "item.timl", "li.item: $item & \" - \" & $this[\"suffix\"]")
    let code = """
ul
  for $item in $this["items"]:
    @include "item"
"""
    var localData = newJObject()
    localData["items"] = %* ["A", "B"]
    localData["suffix"] = newJString("!")
    let res = toHtmlWithInclude("test_for2", code, dir, localData)
    echo "nested html res: ", res
    check res.contains("A - !") and res.contains("B - !")

  test "include inside while loop":
    let dir = getTempDir() / "tim_include_for_test4"
    createDir(dir)
    writeFile(dir / "wh.timl", "span: $i")
    let code = """
var i = 0
while $i < 2:
  @include "wh"
  inc($i)
div: "done"
"""
    let res = toHtmlWithInclude("test_while", code, dir, newJObject())
    echo "while res: ", res
    # should have two spans with 0 and 1 plus done
    check res.contains("0")
    check res.contains("1")
    check res.contains("done")

  test "dump AST structure for for+include":
    var astTree: Ast
    parser.parseScript(astTree, """
ul
  for $item in $this["items"]:
    @include "card"
""", "dump")
    echo "otherPaths: ", astTree.otherPaths
    for n in astTree.nodes:
      echo "node ", n.kind, " ", n.render
      if n.kind == nkHtmlElement:
        echo "  tag: ", n.tag, " childElements: ", n.childElements.len
        for ce in n.childElements:
          echo "    ce kind: ", ce.kind, " render: ", ce.render
          if ce.kind == nkFor:
            echo "      for var: ", ce[0].render, " body: ", ce[2].kind
            for b in ce[2].children:
              echo "        body child: ", b.kind, " ", b.render
