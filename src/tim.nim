# A super fast template engine for cool kids
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim | https://openpeeps.dev/packages/tim

include ./tim/engine/transformers

when defined napi_build:
  # Building Tim Engine as a NAPI module
  # This allows Tim Engine to be used in Node.js/Bun.js applications

  import std/[strutils, json]
  import pkg/[denim, openparser/json, watchout]
  
  import ./tim/meta/initializer
  
  var timjs: TimEngine
  init proc(module: Module) =
    proc init(src: string, output: string, basepath: string) {.export_napi.} =
      ## Initialize Tim Engine
      timjs = newTim(
        args.get("src").getStr,
        args.get("output").getStr,
        args.get("basepath").getStr
      )
      timjs.precompile()

    proc render(view: string, layout: string = "base"): string {.export_napi.} =
      ## Render a Tim Engine template based on the view and layout paths
      let
        layoutPath = args.get("layout").getStr
        layout = timjs.getLayout(layoutPath)
        
        viewPath = args.get("view").getStr
        view = timjs.getView(viewPath)
      let ret = compileCode(view, layout, nil, nil)
      return nodeapi.`%*`(ret.stringVal[])

elif defined php_build:
  import pkg/openparser/json
  import pkg/nimbase/kits/phpkit
  import ./tim/meta/initializer

  var timEngine: TimEngine
  phpModule do:
    name = "tim"
    version = "0.2.3"

    proc init(src: string, output: string, basepath: string) =
      timEngine = newTim($src, $output, $basepath)
      timEngine.precompile()

    proc render(view: string, data: string) =
      let d = parseJson($data)
      toPhpString(retTy, $interpret(timEngine.getView($view), timEngine.getLayout("base"), d, timEngine.globalData))

    proc renderView(view: string, data: string) =
      let d = parseJson($data)
      toPhpString(retTy, $interpret(timEngine.getView($view), d, timEngine.globalData))

elif defined ruby_build:
  import pkg/openparser/json
  import pkg/nimbase/kits/rubykit
  import ./tim/meta/initializer

  var timEngine: TimEngine
  rubyModule do:
    name: "Tim"
    version: "0.2.3"

    proc init(src: string, output: string, basepath: string) =
      timEngine = newTim(src, output, basepath)
      timEngine.precompile()

    proc render(view: string, data: string) =
      let d = parseJson(data)
      result = toRbString($interpret(timEngine.getView(view), timEngine.getLayout("base"), d, timEngine.globalData))

    proc renderView(view: string, data: string) =
      let d = parseJson(data)
      result = toRbString($interpret(timEngine.getView(view), d, timEngine.globalData))

elif defined python_build:
  import pkg/openparser/json
  import pkg/nimbase/kits/pykit
  import ./tim/meta/initializer

  var timEngine: TimEngine
  pythonModule do:
    name: "tim"
    doc: "Tim Engine - a fast template engine for cool kids"

    proc init(src: string, output: string, basepath: string) =
      timEngine = newTim($src, $output, $basepath)
      timEngine.precompile()
      Py_RETURN_NONE

    proc render(view: string, data: string) =
      let d = parseJson($data)
      result = toPyString($interpret(timEngine.getView($view), timEngine.getLayout("base"), d, timEngine.globalData))

    proc renderView(view: string, data: string) =
      let d = parseJson($data)
      result = toPyString($interpret(timEngine.getView($view), d, timEngine.globalData))

elif defined lua_build:
  import pkg/openparser/json
  import pkg/nimbase/kits/luakit
  import ./tim/meta/initializer

  var timEngine: TimEngine
  luaModule do:
    name: "tim"

    proc init(src: string, output: string, basepath: string) =
      timEngine = newTim($src, $output, $basepath)
      timEngine.precompile()

    proc render(view: string, data: string) =
      let d = parseJson($data)
      toLuaString(L, $interpret(timEngine.getView($view), timEngine.getLayout("base"), d, timEngine.globalData))
      return 1

    proc renderView(view: string, data: string) =
      let d = parseJson($data)
      toLuaString(L, $interpret(timEngine.getView($view), d, timEngine.globalData))
      return 1

elif isMainModule:
  # Building Tim Engine as a CLI application (stdlib `parseopt`, no deps)
  import std/[os, parseopt, strutils]
  import ./tim/app/[build, dev, serve, publish]
  import ./tim/meta/cliutils

  proc printTimHelp() =
    echo grey("tim " & timVersion & " - a super fast template engine") & "\n"
    echo grey("LGPL-3.0-or-later | Made by Humans from OpenPeeps\n  https://github.com/openpeeps/tim")
    echo ""
    echo "usage: tim <command> [args] [options]"
    echo ""
    echo label("Source to Source:")
    echo "  src <timl>            " & grey("transpile timl to a target source (default html)")
    echo "    --ext:<fmt>         " & grey("target source: html, js, py, rb, php, lua, nim (default: html)")
    echo "    -o:<file>           " & grey("save output to file (default: stdout)")
    echo "    --data:<json>       " & grey("pass data to global/local scope")
    echo "    --nocache           " & grey("tell Tim to import modules and rebuild cache")
    echo "    --bench             " & grey("benchmark operations")
    echo "    --sync              " & grey("enable sync and reload for development")
    echo "  ast <timl>            " & grey("transpile timl code to AST representation")
    echo "  h2t <input>           " & grey("convert HTML to TIML")
    echo "    --out:<file>, -o    " & grey("save TIML output to file (default: stdout)")
    echo ""
    echo label("Development:")
    echo "  init <pkg>            " & grey("init a new package")
    echo "  install <pkg>         " & grey("install a package from remote source")
    echo "  develop <pkg>         " & grey("create a symlink to a package in local source")
    echo "  remove <pkg>          " & grey("remove a package from local source")
    echo "  publish               " & grey("publish the current package to the tim-engine/pkgs registry")
    echo "    --path:<dir>        " & grey("package directory (default: cwd)")
    echo "    --tags:<list>       " & grey("comma or space separated tags")
    echo "    --web:<url>         " & grey("package website URL")
    echo "    --message:<msg>     " & grey("extra message for the pull request body")
    echo "    --dry-run           " & grey("no network, git, or secret changes")
    echo "    --direct            " & grey("push a branch to tim-engine/pkgs directly")
    echo "    --reset-token       " & grey("delete the stored token and run first-time setup")
    echo "    --yes               " & grey("skip confirmation prompts")
    echo ""
    echo label("Server:")
    echo "  serve <config>        " & grey("run a built-in server with VM capabilities")
    echo "    --sync              " & grey("enable browser live-reload")
    echo "  build <view>          " & grey("build the project to static HTML")
    echo "    --layout:<name>     " & grey("layout to wrap the view (default: base)")
    echo "    --out:<file|dir>    " & grey("output file or directory")
    echo ""
    echo label("options:")
    echo "  -h, --help            " & grey("show this help")
    echo "  -v, --version         " & grey("show version")

  proc toFlag(val: string): bool =
    ## Presence means true; an explicit false-ish value opts out.
    case val.toLowerAscii()
    of "", "true", "1", "yes", "y", "on": true
    of "false", "0", "no", "n", "off": false
    else: true

  proc main(): int =
    var positionals: seq[string] = @[]
    var showHelp = false
    var showVersion = false
    var extArg = "html"
    var outArg = ""
    var dataArg = ""
    var layoutArg = "base"
    var pathArg = ""
    var tagsArg = ""
    var webArg = ""
    var messageArg = ""
    var bench, syncFlag: bool
    var dryRun, direct, resetToken, yes: bool
    var p = initOptParser(commandLineParams(),
      shortNoVal = {'h', 'v'},
      longNoVal = @["help", "version", "nocache", "bench", "sync",
        "dry-run", "direct", "reset-token", "yes"],
      mode = LaxMode)
    for kind, key, val in p.getopt():
      case kind
      of cmdArgument:
        positionals.add(key)
      of cmdLongOption, cmdShortOption:
        case key
        of "help", "h":
          showHelp = true
        of "version", "v":
          showVersion = true
        of "ext":
          extArg = val
        of "o", "out":
          outArg = val
        of "data":
          dataArg = val
        of "layout":
          layoutArg = val
        of "path":
          pathArg = val
        of "tags":
          tagsArg = val
        of "web":
          webArg = val
        of "message":
          messageArg = val
        of "nocache":
          discard # accepted for compat; cache handling is automatic
        of "bench":
          bench = toFlag(val)
        of "sync":
          syncFlag = toFlag(val)
        of "dry-run":
          dryRun = toFlag(val)
        of "direct":
          direct = toFlag(val)
        of "reset-token":
          resetToken = toFlag(val)
        of "yes":
          yes = toFlag(val)
        else:
          echo errPrefix() & " unknown option --" & key
          printTimHelp()
          return 1
      of cmdEnd:
        discard
    if showVersion:
      echo timVersion
      return 0
    if showHelp:
      printTimHelp()
      return 0
    if positionals.len == 0:
      printTimHelp()
      echo "\n" & errPrefix() & " a command is required"
      return 1
    var cmd = positionals[0].toLowerAscii
    var args: seq[string]
    if cmd in ["help", "--help", "-h"]:
      printTimHelp()
      return 0
    if cmd in ["version", "--version", "-v"]:
      echo timVersion
      return 0
    if cmd notin ["src", "ast", "h2t", "init", "install", "develop",
        "remove", "publish", "serve", "build"]:
      # `defaultCommand "src"`: a bare `tim file.timl` transpiles it
      cmd = "src"
      args = positionals
    else:
      args = positionals[1 .. ^1]

    proc need(n: int, what: string): bool =
      if args.len < n:
        echo errPrefix() & " " & cmd & " needs " & what
        printTimHelp()
        return false
      true
    proc rejectExtra(maxn: int): bool =
      if args.len > maxn:
        echo errPrefix() & " unexpected positional argument: " & args[^1]
        return false
      true

    case cmd
    of "src":
      if not need(1, "a timl file"): return 1
      if not rejectExtra(1): return 1
      if extArg.len == 0:
        echo errPrefix() & " --ext requires a value"
        return 1
      srcCommand(args[0], extArg, outArg, dataArg, bench)
    of "ast":
      if not need(1, "a timl file"): return 1
      if not rejectExtra(1): return 1
      astCommand(args[0])
    of "h2t":
      if not need(1, "an input file"): return 1
      if not rejectExtra(1): return 1
      htCommand(args[0], outArg)
    of "init":
      if not rejectExtra(1): return 1
      initCommand(if args.len > 0: args[0] else: "")
    of "install":
      if not need(1, "a package name"): return 1
      if not rejectExtra(1): return 1
      installCommand(args[0])
    of "develop":
      if not rejectExtra(1): return 1
      developCommand(if args.len > 0: args[0] else: "")
    of "remove":
      if not need(1, "a package name"): return 1
      if not rejectExtra(1): return 1
      removeCommand(args[0])
    of "publish":
      if not rejectExtra(0): return 1
      publishCommand(pathArg, tagsArg, webArg, messageArg,
        dryRun, yes, direct, resetToken)
    of "serve":
      if not need(1, "a config file"): return 1
      if not rejectExtra(1): return 1
      serveCommand(args[0], syncFlag)
    of "build":
      if not rejectExtra(1): return 1
      buildCommand(if args.len > 0: args[0] else: "",
        layoutArg, outArg)
    else:
      echo errPrefix() & " unknown command: " & cmd
      printTimHelp()
      return 1
    0

  quit(main())
else:
  # Importing Tim Engine as a Nimble library
  # so it can be used in other Nim projects
  import std/[macros, strutils, macrocache, json]

  import ./tim/meta/initializer
  export initializer

  const
    localStorage* = CacheSeq"LocalStorage"

  macro initCommonStorage*(x: untyped) =
    ## Initializes a common localStorage that can be
    ## shared between controllers
    if x.kind == nnkStmtList:
      add localStorage, x[0]
    elif x.kind == nnkTableConstr:
      add localStorage, x
    else: error("Invalid common storage initializer. Use `{}`, or `do` block")

  proc toLocalStorage*(x: NimNode): NimNode =
    if x.kind in {nnkTableConstr, nnkCurly}:
      var shareLocalNode: NimNode
      if localStorage.len > 0:
        shareLocalNode = localStorage[0]
      if x.len > 0:
        shareLocalNode.copyChildrenTo(x)
        return newCall(ident("%*"), x)
      if shareLocalNode != nil:
        return newCall(ident("%*"), shareLocalNode)
    result = newCall(ident"newJObject")
    # error("Local storage requires either `nnkTableConstr` or `nnkCurly`")

  macro `&*`*(n: untyped): untyped =
    ## Compile-time localStorage initializer
    ## that helps reusing shareable data.
    ## 
    ## Once merged it calls `%*` macro from `std/json`
    ## for converting NimNode to JsonNode
    result = toLocalStorage(n)

  proc flush*(engine: TimEngine) =
    ## Flush the Tim Engine cache
    discard # to be implemented

  proc render*(engine: TimEngine, view: string, layout: string = "base",
              data: JsonNode): string =
    ## Render a Tim Engine template based on the view and layout templates.
    ## 
    ## Optionally, you can pass a `JsonNode` object as data to be used
    ## within the template as local data available under the `$this` variable.
    ## 
    ## If no layout is provided, the default `base` layout will be used.
    ## 
    ## Raises a `TimEngineError` if the view or layout templates are not found.
    ## Ensure to handle these exceptions in your web server to respond
    ## with appropriate HTTP status codes (e.g., 404 or 500).
    let
      viewTpl: TimTemplate = engine.getView(view.replace(".", "/"))
      layoutTpl: TimTemplate = engine.getLayout(layout)
    
    if viewTpl == nil:
      raise newException(TimEngineError, "View template not found: " & view)

    if layoutTpl == nil:
      raise newException(TimEngineError, "Layout template not found: " & layout)
    result.add("<!DOCTYPE html>")
    let rendered = interpret(viewTpl, layoutTpl, data, engine.globalData)
    if rendered != nil:
      result.add($rendered)

  proc renderView*(engine: TimEngine, view: string, data: JsonNode): string =
    ## Render a Tim Engine template based on the view and layout templates.
    ## 
    ## Optionally, you can pass a `JsonNode` object as data to be used
    ## within the template as local data available under the `$this` variable.
    ## 
    ## If no layout is provided, the default `base` layout will be used.
    ## 
    ## Raises a `TimEngineError` if the view or layout templates are not found.
    ## Ensure to handle these exceptions in your web server to respond
    ## with appropriate HTTP status codes (e.g., 404 or 500).
    let viewTpl: TimTemplate = engine.getView(view.replace(".", "/"))
    if viewTpl == nil:
      raise newException(TimEngineError, "View template not found: " & view)
    let rendered = interpret(viewTpl, data, engine.globalData)
    if rendered != nil:
      result.add($rendered)

  proc themeRender*(engine: TimEngine, view: string, layout: string = "base",
              data: JsonNode): string =
    ## Render a Tim Engine template from the active theme.
    ##
    ## Requires an engine created with `enableThemes = true`.
    ## Falls back to the fallback theme (when configured) for templates
    ## missing from the active theme.
    if not engine.enableThemes:
      raise newException(TimEngineError,
        "Theme rendering requires an engine created with `enableThemes = true`")
    render(engine, view, layout, data)

  proc themeRenderView*(engine: TimEngine, view: string, data: JsonNode): string =
    ## Render a Tim Engine view from the active theme, without a layout.
    ## Requires an engine created with `enableThemes = true`.
    if not engine.enableThemes:
      raise newException(TimEngineError,
        "Theme rendering requires an engine created with `enableThemes = true`")
    renderView(engine, view, data)
    