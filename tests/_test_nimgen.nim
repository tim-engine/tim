import std/[os, osproc, unittest, strutils, json, options, ropes]
include ../src/tim/engine/transformers
import pkg/vancode/interpreter/[ast, chunk, sym]
import pkg/vancode/manager/packager
import ../src/tim/engine/parser
import ../src/tim/engine/stdlib/libsystem
import ../src/tim/engine/transpilers/nimgen

template initPackageManager() {.dirty.} =
  let pkgr = packager.initPackageRemote()
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
  let systemModule = libsystem.loadLibrary(script)
  module.load(systemModule)

proc transpile(code: string): string =
  initPackageManager()
  initParser(code)
  initLibrary()
  var cg = nimgen.initCodeGen(script, module, mainChunk)
  result = $cg.genScript(program, none(string), isMainScript = true, isView = true)

proc runNim(code: string): string =
  let srcFile = getTempDir() / "tim_test.nim"
  let binFile = getTempDir() / "tim_test"
  writeFile(srcFile, code)
  let comp = execCmdEx("nim c --hints:off --warnings:off -o:" & binFile & " " & srcFile)
  if comp.exitCode != 0:
    raise newException(CatchableError, "nim c failed: " & comp.output)
  let sts = execCmdEx(binFile)
  if sts.exitCode != 0:
    raise newException(CatchableError, "binary exited with code " & $sts.exitCode & ": " & sts.output)
  sts.output.strip()

template checkOutput(transpiled, expected: string) =
  let wrapper = "echo getHelloWorldView(newJObject(), newJObject())\n"
  let nimCode = transpiled & "\n" & wrapper
  let output = runNim(nimCode)
  check output == expected

suite "NimGen — Transpiler":
  test "simple variable and element":
    let code = transpile("""
var hello = "Tim Engine is Awesome!"
h1.fw-bold: $hello
""")
    checkOutput code, """<h1 class="fw-bold">Tim Engine is Awesome!</h1>"""

  test "multiple html elements":
    let code = transpile("""
div.container
  h1: "Title"
  p: "Paragraph"
""")
    checkOutput code, """<div class="container"><h1>Title</h1><p>Paragraph</p></div>"""

  test "nested elements":
    let code = transpile("""
div > div > span: "Deep"
""")
    checkOutput code, "<div><div><span>Deep</span></div></div>"

  test "element with id":
    let code = transpile("""
div#myid: "Content"
""")
    checkOutput code, """<div id="myid">Content</div>"""

  test "element with multiple classes":
    let code = transpile("""
a.btn.btn-primary.btn-lg: "Click"
""")
    checkOutput code, """<a class="btn btn-primary btn-lg">Click</a>"""

  test "element with attributes":
    let code = transpile("""
a href="https://example.com" target="_blank": "Link"
""")
    checkOutput code, """<a href="https://example.com" target="_blank">Link</a>"""

  test "boolean attribute":
    let code = transpile("""
input disabled
""")
    checkOutput code, """<input disabled>"""

  test "if condition true branch":
    let code = transpile("""
var flag = true
if $flag == true:
  p: "Yes"
else:
  p: "No"
""")
    checkOutput code, "<p>Yes</p>"

  test "if condition false branch":
    let code = transpile("""
var flag = false
if $flag == true:
  p: "Yes"
else:
  p: "No"
""")
    checkOutput code, "<p>No</p>"

  test "for loop range":
    let code = transpile("""
ul
  for $i in 0..2:
    li: "Item " & $i
""")
    checkOutput code, "<ul><li>Item 0</li><li>Item 1</li><li>Item 2</li></ul>"

  test "for loop array":
    let code = transpile("""
var items = ["a", "b", "c"]
ul
  for $item in $items:
    li: $item
""")
    checkOutput code, "<ul><li>a</li><li>b</li><li>c</li></ul>"

  test "while loop":
    let code = transpile("""
var i = 0
while $i < 3:
  p: $i
  $i = $i + 1
""")
    checkOutput code, "<p>0</p><p>1</p><p>2</p>"

  test "string concatenation":
    let code = transpile("""
var name = "World"
p: "Hello, " & $name & "!"
""")
    checkOutput code, "<p>Hello, World!</p>"

  test "echo statement":
    let code = transpile("""
echo "hello world"
""")
    check code.contains("echo ")

  test "return statement":
    let code = transpile("""
fn test(): string {
  return "hello"
}
""")
    check code.contains("return")

  test "function declaration":
    let code = transpile("""
fn greet(name: string): string {
  return "Hello, " & $name
}
""")
    check code.contains("proc greet(")

  test "macro declaration":
    let code = transpile("""
macro card(title: string) {
  div.card
    h5: $title
}
""")
    check code.contains("proc card(")

  test "void element":
    let code = transpile("""
br
""")
    checkOutput code, "<br>"

  test "img with attributes":
    let code = transpile("""
img src="logo.png" alt="Logo" width="100"
""")
    checkOutput code, """<img src="logo.png" alt="Logo" width="100">"""

  test "inline javascript snippet":
    let code = transpile("""
@javascript
console.log("inline")
@end
""")
    check code.contains("<script>")

  test "inline css snippet":
    let code = transpile("""
@css
body { color: red; }
@end
""")
    check code.contains("<style>")

  test "multiple variables":
    let code = transpile("""
var x = 10
var y = 20
p: $x & " + " & $y & " = " & $x + $y
""")
    checkOutput code, "<p>10 + 20 = 30</p>"

  test "comparison operators":
    let code = transpile("""
var x = 5
if $x > 3:
  p: "greater"
""")
    checkOutput code, "<p>greater</p>"

  test "nested if else":
    let code = transpile("""
var x = 1
if $x == 1:
  p: "one"
elif $x == 2:
  p: "two"
else:
  p: "other"
""")
    checkOutput code, "<p>one</p>"

  test "string escaping":
    let code = transpile("""
p: "Line1\nLine2"
""")
    checkOutput code, "<p>Line1\nLine2</p>"

  test "operator translation":
    let code = transpile("""
var a = true
var b = false
if $a == true and $b == false:
  p: "and works"
""")
    checkOutput code, "<p>and works</p>"

  test "empty template":
    let code = transpile("")
    check code.contains("getHelloWorldView")
    check code.contains("result")
