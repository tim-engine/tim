include ../src/tim/engine/transformers

import std/[unittest, os, json, options]
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value, resolver]
import ../src/tim/engine/[parser, validator, html2timl]
import ../src/tim/engine/stdlib/[libsystem]

proc parserCallback(astProgram: var Ast, path: string, resolver: FileResolver) =
  parser.parseScript(astProgram, readFile(path), path)

proc declareGlobals(compiler: CodeGen) =
  let appStorage = newIdent("app")
  let thisStorage = newIdent("this")
  compiler.declareVar(appStorage, skConst, compiler.module.sym"json", isMagic = true)
  compiler.declareVar(thisStorage, skConst, compiler.module.sym"json", isMagic = true)

proc renderTiml(code: string): string =
  var astTree: Ast
  parser.parseScript(astTree, code, "h2t")
  validateAst(astTree)
  var mainChunk = newChunk("h2t")
  var script = newScript(mainChunk)
  var module = newModule("h2t", some("h2t"))
  let systemModule = libsystem.loadLibrary(script)
  module.load(systemModule)
  script.stdpos = script.procs.high
  var compiler = codegen.initCompiler(script, module, mainChunk, nil, nil, parserCallback)
  declareGlobals(compiler)
  compiler.genScript(program = astTree, includePath = some(getCurrentDir()))
  let vmm = newVM()
  result = $(vmm.interpret(script, mainChunk,
    localData = newJObject(), globalData = newJObject()))

suite "HTML to TIML":
  test "basic nesting with class and id":
    let timl = parseHtmlToTiml(
      """<article class="post featured" id="intro"><h1>Hello</h1><p>Welcome</p></article>""",
      "basic.html")
    check timl == "article.post.featured#intro\n  h1: \"Hello\"\n  p: \"Welcome\""
    check renderTiml(timl) ==
      """<article id="intro" class="post featured"><h1>Hello</h1><p>Welcome</p></article>"""

  test "attributes are sorted deterministically":
    let timl = parseHtmlToTiml(
      """<a title="Example" href="/" target="_blank" data-track="nav">Link</a>""",
      "attrs.html")
    check timl ==
      "a data-track=\"nav\" href=\"/\" target=\"_blank\" title=\"Example\": \"Link\""
    check renderTiml(timl) ==
      """<a data-track="nav" href="/" target="_blank" title="Example">Link</a>"""

  test "void and boolean attributes":
    let timl = parseHtmlToTiml(
      """<div><img src="logo.png" alt="Logo"><input disabled type="text"></div>""",
      "void.html")
    check timl ==
      "div\n  img alt=\"Logo\" src=\"logo.png\"\n  input disabled type=\"text\""
    check renderTiml(timl) ==
      """<div><img alt="Logo" src="logo.png"><input disabled type="text"></div>"""

  test "form labels and inputs":
    let timl = parseHtmlToTiml(
      """<form><label>Email</label><input id="email" type="email"></form>""",
      "form.html")
    check timl ==
      "form\n  label: \"Email\"\n  input#email type=\"email\""
    check renderTiml(timl) ==
      """<form><label>Email</label><input id="email" type="email"></form>"""

  test "mixed text and elements":
    # Note: OpenParser strips whitespace adjacent to tags, so the space
    # before `<a>` is normalized away (documented converter limitation).
    let timl = parseHtmlToTiml(
      """<p>Welcome to <a href="/">Tim</a>.</p>""",
      "mixed.html")
    check timl ==
      "p\n  \"Welcome to\"\n  a href=\"/\": \"Tim\"\n  \".\""
    check renderTiml(timl) ==
      """<p>Welcome to<a href="/">Tim</a>.</p>"""

  test "comments and entities are preserved":
    let timl = parseHtmlToTiml(
      """<!-- Hello &amp; goodbye --><p>Fish &amp; Chips</p>""",
      "comments.html")
    check timl ==
      "<!-- Hello &amp; goodbye -->\n" & "p: \"Fish &amp; Chips\""
    check renderTiml(timl) ==
      """<!-- Hello &amp; goodbye --><p>Fish &amp; Chips</p>"""

  test "entities preserve otherwise lossy characters":
    let timl = parseHtmlToTiml(
      """<p>and&#47;or, a&#61;b, a &gt; b</p>""",
      "entities.html")
    check timl == "p: \"and&#47;or, a&#61;b, a &gt; b\""
    check renderTiml(timl) ==
      """<p>and&#47;or, a&#61;b, a &gt; b</p>"""

  test "quotes and backslashes are escaped":
    let timl = parseHtmlToTiml(
      "<p title='She said \"hi\"'>Back\\slash</p>",
      "escaping.html")
    check timl ==
      "p title=\"She said \\\"hi\\\"\": \"Back\\\\slash\""
    var generated: Ast
    parser.parseScript(generated, timl, "escaping.html")
    validateAst(generated)
    check renderTiml(timl) ==
      "<p title=\"She said \"hi\"\">Back\\slash</p>"

  test "HTML files are converted by path":
    let path = getTempDir() / "h2t-basic.html"
    writeFile(path, """<main><p>From file</p></main>""")
    check parseHtmlFileToTiml(path) == "main\n  p: \"From file\""

  test "unsupported constructs are rejected":
    expect Html2TimlError:
      discard parseHtmlToTiml("<my-card>Hi</my-card>", "custom.html")
    expect Html2TimlError:
      discard parseHtmlToTiml("<script>alert(1);</script>", "script.html")
    expect Html2TimlError:
      discard parseHtmlToTiml("<style>p { color: red; }</style>", "style.html")
    expect Html2TimlError:
      discard parseHtmlToTiml("<pre>  spaced</pre>", "pre.html")
    expect Html2TimlError:
      discard parseHtmlToTiml("<!DOCTYPE html><p>Hi</p>", "doctype.html")
    expect Html2TimlError:
      discard parseHtmlToTiml("<p>Hello {{name}}</p>", "template.html")
    expect Html2TimlError:
      discard parseHtmlToTiml("<button @click=\"go\">Go</button>", "framework.html")
    expect Html2TimlError:
      discard parseHtmlToTiml("<label for=\"email\">Email</label>", "keyword-attr.html")
    expect Html2TimlError:
      discard parseHtmlToTiml("<div><p>Hi", "unclosed.html")
    expect Html2TimlError:
      discard parseHtmlToTiml("<div><p>Hi</div></p>", "mismatch.html")
    expect Html2TimlError:
      discard parseHtmlToTiml("<div class=\"x\" <p>Hi</p></div>", "missing-bracket.html")
    expect Html2TimlError:
      discard parseHtmlToTiml("<p>and/or</p>", "slash-text.html")
    expect Html2TimlError:
      discard parseHtmlToTiml("<p>a=b</p>", "equals-text.html")
    expect Html2TimlError:
      discard parseHtmlToTiml("<p>a > b</p>", "bracket-text.html")
    expect Html2TimlError:
      discard parseHtmlToTiml("<a href=/go>Go</a>", "unquoted-slash.html")
    expect Html2TimlError:
      discard parseHtmlToTiml("<p title=\"a<b\">Hi</p>", "bracket-attr.html")
    expect Html2TimlError:
      discard parseHtmlToTiml("<div/><p>Hi</p>", "self-close.html")
    expect Html2TimlError:
      discard parseHtmlToTiml("Hello", "text.html")
    expect Html2TimlError:
      discard parseHtmlFileToTiml(getTempDir() / "h2t-missing.html")
