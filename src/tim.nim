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
  import pkg/clue/kits/phpkit
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
  import pkg/clue/kits/rubykit
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
  import pkg/clue/kits/pykit
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
  import pkg/clue/kits/luakit
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
  # Building Tim Engine as a CLI application
  import pkg/kapsis
  import pkg/kapsis/runtime
  import pkg/kapsis/interactive/prompts
  import ./tim/app/[build, dev, serve]

  initKapsis do:
    defaultCommand: "src"
    commands:
      #
      # Source to Source commands
      # Used to transpile `timl` code to a specific target source
      # Planning to support: HTML, Nim, JS, PHP, Python, Ruby and more
      #
      -- "Source to Source"
      src path(timl),
        ?string("--ext"),      # choose a target (default target `html`)
        ?string("-o"),        # save output to file
        ?json("--data"),      # pass data to global/local scope
        ?bool("--nocache"),   # tells Tim to import modules and rebuild cache
        ?bool("--bench"),     # benchmark operations
        ?bool("--sync"):      # enable sync and reload for development
          ## Transpile `timl` to specific target source

      ast path(timl):
        ## Transpile timl code to AST representation

      #
      # Development commands
      # Used to manage Tim Engine packages locally
      #
      -- "Development"
      init ?string(pkg):
        ## Init a new package
      install string(pkg):
        ## Install a package from remote source
      develop string(pkg):
        ## Create a symlink to a package in local source
      remove string(pkg):
        ## Remove a package from local source

      #
      # Server commands
      #
      -- "Server"
      serve path(config):
        ## Run a built-in server with VM capabilities
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
    result.add("<!DOCTYPE html>")    # Add DOCTYPE declaration at the beginning of the output
    result.add($interpret(viewTpl, layoutTpl, data, engine.globalData))

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
    result.add($interpret(viewTpl, data, engine.globalData))

  proc themeRender*(engine: TimEngine, view: string, layout: string = "base",
              data: JsonNode): string =
    ## Render a Tim Engine template based on the view and layout templates.
    ## This is used for rendering frontend views that are part of the active theme.
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
      viewTpl: TimTemplate = engine.getThemeView(view.replace(".", "/"))
      layoutTpl: TimTemplate = engine.getThemeLayout(layout)
    if viewTpl == nil:
      raise newException(TimEngineError, "View template not found in active theme: " & view)
    if layoutTpl == nil:
      raise newException(TimEngineError, "Layout template not found in active theme: " & layout)
    result.add("<!DOCTYPE html>")    # Add DOCTYPE declaration at the beginning of the output
    result.add($interpret(viewTpl, layoutTpl, data, engine.globalData))

  proc themeRenderView*(engine: TimEngine, view: string, data: JsonNode): string =
    ## Render a Tim Engine template based on the view and layout templates.
    ## This is used for rendering frontend views that are part of the active theme.
    ## 
    ## Optionally, you can pass a `JsonNode` object as data to be used
    ## within the template as local data available under the `$this` variable.
    ## 
    ## If no layout is provided, the default `base` layout will be used.
    ## 
    ## Raises a `TimEngineError` if the view or layout templates are not found.
    ## Ensure to handle these exceptions in your web server to respond
    ## with appropriate HTTP status codes (e.g., 404 or 500).
    let viewTpl: TimTemplate = engine.getThemeView(view.replace(".", "/"))
    if viewTpl == nil:
      raise newException(TimEngineError, "View template not found in active theme: " & view)
    result.add($interpret(viewTpl, data, engine.globalData))
    