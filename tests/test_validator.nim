include ../src/tim/engine/transformers

import std/[unittest, os, json, options, sequtils]
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value, resolver]
import pkg/openparser/json as ojson
import ../src/tim/engine/[parser, validator]
import ../src/tim/engine/stdlib/[libsystem]

proc parserCallback(astProgram: var Ast, path: string, resolver: FileResolver) =
  parser.parseScript(astProgram, readFile(path), path)

proc declareGlobals(compiler: CodeGen) =
  let appStorage = newIdent("app")
  let thisStorage = newIdent("this")
  compiler.declareVar(appStorage, skConst, compiler.module.sym"json", isMagic = true)
  compiler.declareVar(thisStorage, skConst, compiler.module.sym"json", isMagic = true)

proc toHtml(id, code: string, localData: JsonNode, globalData: JsonNode = newJObject()): string =
  var astTree: Ast
  parser.parseScript(astTree, code, id)
  var mainChunk = newChunk(id)
  var script = newScript(mainChunk)
  var module = newModule(id, some(id))
  let systemModule = libsystem.loadLibrary(script)
  module.load(systemModule)
  script.stdpos = script.procs.high
  var compiler = codegen.initCompiler(script, module, mainChunk, nil, nil, parserCallback)
  declareGlobals(compiler)
  compiler.genScript(program = astTree, includePath = some(getCurrentDir()))
  let vmm = newVM()
  return $(vmm.interpret(script, mainChunk, localData = localData, globalData = globalData))

suite "Validator - valid AST":
  test "valid AST from parser":
    var ast1: Ast
    parser.parseScript(ast1, """
div
  p: "Hello"
  if true:
    span: "yes"
  ul
    for $x in [1, 2, 3]:
      li: $x
""", "test")
    check isValidAst(ast1)
    # also via raising
    validateAst(ast1)

  test "JSON roundtrip valid":
    var ast1: Ast
    parser.parseScript(ast1, "p: \"hi\"", "x")
    let jsonStr = toJson(ast1)
    var ast2 = ojson.fromJson(jsonStr, Ast)
    check isValidAst(ast2)
    validateAst(ast2)
    check ast2.nodes.len == ast1.nodes.len

  test "modern tagMain valid":
    var n = ast.newHtmlElement("main")
    var astM = Ast(nodes: @[n])
    check isValidAst(astM)

suite "Validator - invalid AST":
  test "invalid If missing then":
    var badIf = ast.newTree(nkIf, ast.newIdent("cond"))
    var astBad = Ast(sourcePath: "bad", nodes: @[badIf])
    expect TimAstValidationError:
      validateAst(astBad)
    var errs: seq[ref TimAstValidationError]
    check not validateAst(astBad, errs)
    check errs.len == 1

  test "invalid For missing body":
    var badFor = ast.newTree(nkFor, ast.newIdent("x"), ast.newIdent("items"))
    var astBad = Ast(nodes: @[badFor])
    expect TimAstValidationError:
      validateAst(astBad)

  test "invalid Var with wrong child":
    var badVar = ast.newTree(nkVar, ast.newStringLit("notIdentDefs"))
    var astBad = Ast(nodes: @[badVar])
    expect TimAstValidationError:
      validateAst(astBad)

  test "tampered ident empty":
    var ast1: Ast
    parser.parseScript(ast1, "p: \"hi\"", "x")
    let jsonStr = toJson(ast1)
    var ast2 = ojson.fromJson(jsonStr, Ast)
    # corrupt first ident if found, otherwise add bad node
    var corrupted = false
    for n in ast2.nodes:
      if n.kind == nkHtmlElement:
        # add bad attribute
        let badAttr = ast.newNode(nkHtmlAttribute)
        # leave attrNode nil -> invalid
        n.attributes.add(badAttr)
        corrupted = true
        break
    if not corrupted:
      # add an explicit bad ident node
      ast2.nodes.add(ast.newIdent(""))
    expect TimAstValidationError:
      validateAst(ast2)

  test "HTML invalid tag empty":
    var htmlNode = ast.newHtmlElement("")
    var ast5 = Ast(nodes: @[htmlNode])
    expect TimAstValidationError:
      validateAst(ast5)

  test "otherPaths traversal":
    var ast7 = Ast(sourcePath: "x", otherPaths: @["../evil.timl"], nodes: @[])
    expect TimAstValidationError:
      validateAst(ast7)

  test "duplicate otherPaths":
    var astDup = Ast(sourcePath: "x", otherPaths: @["a.timl", "a.timl"], nodes: @[])
    expect TimAstValidationError:
      validateAst(astDup)

  test "loadValidatedAstFile tampered":
    var ast1: Ast
    parser.parseScript(ast1, "p: \"hi\"", "x")
    writeFile(getTempDir() / "ast_test.json", toJson(ast1))
    let loaded = loadValidatedAstFile(getTempDir() / "ast_test.json")
    check loaded.nodes.len == ast1.nodes.len
    # tampered file with invalid kind
    writeFile(getTempDir() / "ast_bad.json", """{"sourcePath":"bad","otherPaths":[],"nodes":[{"kind":999}]}""")
    expect TimAstValidationError:
      discard loadValidatedAstFile(getTempDir() / "ast_bad.json")

  test "Nil node":
    var astNil = Ast(nodes: @[nil])
    expect TimAstValidationError:
      validateAst(astNil)

  test "cycle detection (self-ref via children)":
    # This is contrived: create node that contains itself indirectly
    # Since Ast is acyclic, we test visited set by manually creating a cycle via seq sharing
    var n1 = ast.newTree(nkBlock)
    var n2 = ast.newTree(nkBlock, n1)
    n1.add(n2) # creates cycle n1 -> n2 -> n1
    var astC = Ast(nodes: @[n1])
    expect TimAstValidationError:
      validateAst(astC)

proc toHtml(a: Ast, local: JsonNode): string =
  # helper that uses already parsed Ast
  var mainChunk = newChunk("test")
  var script = newScript(mainChunk)
  var module = newModule("test", some("test"))
  let systemModule = libsystem.loadLibrary(script)
  module.load(systemModule)
  script.stdpos = script.procs.high
  var compiler = codegen.initCompiler(script, module, mainChunk, nil, nil, parserCallback)
  declareGlobals(compiler)
  compiler.genScript(program = a, includePath = some(getCurrentDir()))
  let vmm = newVM()
  result = $(vmm.interpret(script, mainChunk, localData = local, globalData = newJObject()))

suite "Validator - codegen roundtrip":
  test "validated AST renders via codegen":
    var ast1: Ast
    parser.parseScript(ast1, "p: \"Hello\"", "x")
    let html = toHtml(ast1, newJObject())
    check html == "<p>Hello</p>"
