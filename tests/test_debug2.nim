import std/[os, osproc, strutils, json, options, ropes]
include ../src/tim/engine/transformers
import pkg/vancode/interpreter/[ast, chunk, sym]
import pkg/vancode/manager/packager
import ../src/tim/engine/parser
import ../src/tim/engine/stdlib/libsystem
import ../src/tim/engine/transpilers/jsgen

let code = """img src="logo.png" alt="Logo""""

var program: Ast
parser.parseScript(program, code, "TestMod")
var mainChunk = newChunk("TestMod")
var script = newScript(mainChunk)
var module = newModule("TestMod".extractFilename, some("TestMod"))
let systemModule = libsystem.loadLibrary(script)
module.load(systemModule)
let pkgr = packager.initPackageRemote[PackageConfig]()
pkgr.loadPackages()
var cg = jsgen.initCodeGen(script, module, mainChunk)
let output = $cg.genScript(program, none(string), isMainScript = true)
echo "JS CODE:"
echo output
writeFile("/tmp/tim_test_img.js", output & "\nconsole.log(TestMod.render());")
echo "---"
echo "NODE OUTPUT:"
echo execCmdEx("node /tmp/tim_test_img.js").output
