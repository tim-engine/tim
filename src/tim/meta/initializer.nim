import std/[os, tables, net, strutils, sequtils, options]

import pkg/openparser/json
import pkg/vancode/interpreter/[ast, codegen, chunk, sym,
                        vm, value, resolver, manager, policy]
import pkg/vancode/manager/configurator # shim for ConfigType/CompilationSettings
import pkg/kapsis/interactive/prompts

import pkg/[watchout, semver, checksums/sha1]
import pkg/openparser/yaml

import ../engine/parser
import ../engine/validator
import ./config

export value
export validator

when defined timHotCode:
  import ./websocket

#
# Standard Libraries
# 
import ../engine/stdlib/[libsystem, libffi, libtimes,
              libstrings, libarrays, libjson, libobjects, inliner]

export TypeKind, StackView, Value, CodeGenError
export configurator, paramDef

# a rudimentary way to add new statement-like node kinds
# planning to replace this with a more robust extensible system in the future
vanCodeStmtNodeKinds.add(@[nkHtmlElement, nkMacro, nkClientBlock, nkViewLoader])

type
  TimTemplateType* = enum
    ## Type of the Tim template
    ttView = "views"
    ttLayout = "layouts"
    ttPartial = "partials"

  TemplateSources* = tuple[src: string, ast: string, html: string, opcache: string]

  TimTemplate* {.acyclic.} = ref object
    ## Object representing a Tim template
    id*: string
      ## unique identifier of the template (based on path hash)
    sources*: TemplateSources
      ## the source paths related to the template, including the
      ## # original source path, the cached AST path,
    templateType*: TimTemplateType
      # the type of the template (view, layout or partial)
    script: Script
      # the compiled script of the template
    mainChunk: Chunk
      # the main chunk of the compiled script
    vmInstance: VM
      # the VM instance for evaluating the template
    dependencies*: seq[string] = @[]
      ## a sequence of source paths that the template depends on (imports/includes)
    embeddedCode*: Option[string]

  UserScript* {.acyclic.} = ref object
    # chunk: Chunk
    # script: Script
    # module: Module
    procs: seq[(string, seq[TempParamDef], TypeKind, ForeignProc, bool)]
      ## A sequence of foreign procedures to be added to the user script
    code: string # A string to inject into the script before execution

  ThemeManifest* {.acyclic.} = object
    ## The manifest for a Tim theme, defined in `theme.yaml` in the theme directory
    name*, author*, url*, license*, description*: string
    version*: semver.Version

  Theme* {.acyclic.} = ref object
    manifest*: ThemeManifest
    path*: string # base path of the theme
    views*, layouts*, partials*: TableRef[string, TimTemplate] = newTable[string, TimTemplate]()
      ## Tables to store templates by their source path
  
  TimSourceType* = enum
    timSourceFilesystem, timSourceEmbedded

  TimEngine* {.acyclic.} = ref object
    ## The main Tim Engine object.
    ## Holds the configuration and the templates.
    ## 
    ## It must be initialized with `newTim()`
    sourceType*: TimSourceType
      ## The source type of the templates, either from the filesystem
      ## or embedded in the binary
    config*: PackageConfig
      ## The configuration for the Tim Engine, including source and output paths, target source, etc.
    userScript*: UserScript
      ## A `UserScript` object that allows users to define custom foreign procedures
    globalData*: JsonNode
      ## Global data available in all templates under the `$app` variable
    depResolver*: FileResolver
      ## A `FileResolver` to manage template dependencies and hot reloading
    enableThemes*: bool
      ## Whether to enable theme support. If true, the engine will look for themes in the
      ## `themes` directory of the installation path and load the active theme's templates.
    themes*: TableRef[string, Theme] = newTable[string, Theme]()
      ## A table to store themes by their name
    activeTheme*: Theme
      ## The currently active theme, if any
    activeThemeName*: string
      ## The name of the currently active theme, used for initialization before loading themes
    fallbackThemeName*: string
      ## The name of the fallback theme, used when a template is missing
      ## from the active theme. When empty, no fallback is applied and
      ## missing templates raise a `TimEngineError`.
    views*, layouts*, partials*: TableRef[string, TimTemplate] = newTable[string, TimTemplate]()
      ## Tables to store templates by their source path
  
  TimEngineError* = object of CatchableError

let stdlibs = newTable[string, proc(script: Script, systemModule: Module): Module]()
stdlibs["system"] = proc(script: Script, systemModule: Module): Module =
  result = libsystem.loadLibrary(script)
stdlibs["strings"] = initStrings
stdlibs["arrays"] = initArrays
stdlibs["json"] = initJSON
stdlibs["objects"] = initObjects

proc parseHook(p: var json.JsonParser, v: var semver.Version) =
  # A JSON parsing hook to parse the `version` field in the
  # theme manifest as a `semver.Version` object
  v = parseVersion(p.curr.value)
  p.advance()

proc parseHook*(p: var YamlParser, v: var semver.Version) =
  # A YAML parsing hook to parse the `version` field in the
  # theme manifest as a `semver.Version` object
  v = parseVersion(p.curr.value)
  p.advance()

iterator getViews*(engine: TimEngine): TimTemplate =
  ## Iterator to get all view templates
  for _, tpl in engine.views:
    yield tpl

iterator getLayouts*(engine: TimEngine): TimTemplate =
  ## Iterator to get all layout templates
  for _, tpl in engine.layouts:
    yield tpl

iterator getPartials*(engine: TimEngine): TimTemplate =
  ## Iterator to get all partial templates
  for _, tpl in engine.partials:
    yield tpl

iterator getViews*(engine: TimEngine, theme: string): TimTemplate =
  ## Iterator to get all view templates of the given theme
  let t = engine.themes.getOrDefault(theme, nil)
  if t == nil:
    raise newException(TimEngineError, "Theme not found: " & theme)
  for _, tpl in t.views:
    yield tpl

iterator getLayouts*(engine: TimEngine, theme: string): TimTemplate =
  ## Iterator to get all layout templates of the given theme
  let t = engine.themes.getOrDefault(theme, nil)
  if t == nil:
    raise newException(TimEngineError, "Theme not found: " & theme)
  for _, tpl in t.layouts:
    yield tpl

iterator getPartials*(engine: TimEngine, theme: string): TimTemplate =
  ## Iterator to get all partial templates of the given theme
  let t = engine.themes.getOrDefault(theme, nil)
  if t == nil:
    raise newException(TimEngineError, "Theme not found: " & theme)
  for _, tpl in t.partials:
    yield tpl

# precompile - forward declarations
proc precompile*(engine: TimEngine) 
proc precompileTemplate*(engine: TimEngine, tpl: TimTemplate,
        manager: ModuleManager, data: JsonNode = nil,
        force: bool = false): bool {.discardable.}

proc getHashedPath(path: string): string =
  # Get a SHA1 hash of the given path.
  toLowerAscii($(sha1.secureHash(path)))

proc newTemplate*(id: string, templateType: TimTemplateType, sources: TemplateSources): TimTemplate =
  ## Create a half-initialized `TimTemplate` object with
  ## the given id, type and source path
  result = TimTemplate(id: id, templateType: templateType, sources: sources)

proc addProc*(userScript: UserScript, name: string, params: seq[TempParamDef] = @[],
        returnTy: TypeKind, impl: ForeignProc = nil, exportSym = true) =
  ## Add a foregin function to the `UserScript`.
  userScript.procs.add((name, params, returnTy, impl, exportSym))

proc injectScript*(userScript: UserScript, code: string) =
  ## Inject a code string into the `UserScript`.
  # userScript.script.compileCode(userScript.module, "user_script", code)

proc newTim*(src, output, basepath: string,
          target = TargetSource.tsHtml,
          globalData: JsonNode = newJObject(),
          enableThemes: bool = false,
          activeThemeName: string = "",
          fallbackThemeName: string = ""): TimEngine =
  ## Initialize a new Tim Engine instance.
  ## 
  ## - `src`: the source directory containing the templates
  ## - `output`: the output directory where the rendered files will be saved
  ## - `basepath`: the base path to resolve the `src` and `output` paths
  ## - `target`: the target source for transpilation (default: HTML)
  let sourcePath = normalizedPath(basepath / src)
  result = TimEngine(
    userScript: UserScript(),
    globalData: globalData,
    depResolver: initResolver(),
    enableThemes: enableThemes,
    activeThemeName: activeThemeName,
    fallbackThemeName: fallbackThemeName,
    config: PackageConfig(
      `type`: ConfigType.typeProject,
      compilation: CompilationSettings(
        source: sourcePath,
        output: normalizedPath(basepath / output),
        basePath: basepath,
        layoutsPath: sourcePath / "layouts",
        viewsPath: sourcePath / "views",
        partialsPath: sourcePath / "partials",
      )
    )
  )
  # stdlibs["times"] = loadTimes this should not be here

proc newTim*(globalData: JsonNode = nil,
            enableThemes: bool = false,
            activeThemeName: string = "",
            fallbackThemeName: string = ""): TimEngine =
  ## Initialize a new Tim Engine instance from a preloaded table of templates.
  ## 
  ## Usually used in embedded mode, where the templates are embedded into the binary
  ## as a table of source paths to template content strings.
  result = TimEngine(
    sourceType: TimSourceType.timSourceEmbedded,
    userScript: UserScript(),
    globalData: globalData,
    depResolver: initResolver(),
    enableThemes: enableThemes,
    activeThemeName: activeThemeName,
    fallbackThemeName: fallbackThemeName,
    config: PackageConfig(
      `type`: ConfigType.typeProject,
      compilation: CompilationSettings(
        # sourceType: SourceType.sourceEmbedded,
      )
    )
  )

proc getFallbackTheme*(engine: TimEngine): Theme =
  ## Get the fallback theme, if one is configured and loaded.
  ## Returns nil when no fallback is configured or found.
  if engine.fallbackThemeName.len > 0 and engine.fallbackThemeName in engine.themes:
    if engine.activeTheme == nil or engine.fallbackThemeName != engine.activeThemeName:
      return engine.themes[engine.fallbackThemeName]

proc getTheme*(engine: TimEngine, name: string): Theme =
  ## Get a loaded theme by its manifest name. Returns nil if not found.
  engine.themes.getOrDefault(name, nil)

proc listThemes*(engine: TimEngine): seq[string] =
  ## List the names of all discovered themes.
  for name in engine.themes.keys:
    result.add(name)

proc setActiveTheme*(engine: TimEngine, name: string) =
  ## Switch the active theme at runtime. Raises `TimEngineError`
  ## if no theme with the given name has been discovered.
  if name notin engine.themes:
    var available: seq[string] = @[]
    for themeName in engine.themes.keys:
      available.add(themeName)
    raise newException(TimEngineError,
      "Theme not found: " & name & ". Available themes: " & available.join(", "))
  engine.activeTheme = engine.themes[name]
  engine.activeThemeName = name

proc getTemplateByPath*(engine: TimEngine, path: string): TimTemplate =
  ## Get a Tim template by its source path.
  ## Returns a TimTemplate object with the template type set to `ttView`.
  if engine.enableThemes:
    # when themes are enabled, we need to look for the template in the active theme's tables,
    # falling back to the fallback theme when configured
    if engine.activeTheme == nil:
      raise newException(TimEngineError, "Active theme is not set")
    let active = engine.activeTheme
    if path in active.views:
      return active.views[path]
    if path in active.layouts:
      return active.layouts[path]
    if path in active.partials:
      return active.partials[path]
    let fallback = engine.getFallbackTheme()
    if fallback != nil:
      if path in fallback.views:
        return fallback.views[path]
      if path in fallback.layouts:
        return fallback.layouts[path]
      if path in fallback.partials:
        return fallback.partials[path]
    return nil
  else:
    if path in engine.views:
      return engine.views[path]

    if path in engine.layouts:
      return engine.layouts[path]

    if path in engine.partials:
      return engine.partials[path]

#
# Tim Engine getters
#
# forward declarations (theme getters are defined below,
# but the unified getters use them for fallback lookup)
proc getThemePartial*(engine: TimEngine, key: string): TimTemplate
proc getThemeLayout*(engine: TimEngine, key: string): TimTemplate
proc getThemeView*(engine: TimEngine, key: string): TimTemplate

proc getLayout*(engine: TimEngine, key: string): TimTemplate =
  ## Get a layout template by its name (with/without extension).
  ## When themes are enabled, looks in the active theme first,
  ## then in the fallback theme (if configured).
  if engine.enableThemes:
    result = engine.getThemeLayout(key)
    if result == nil:
      let fallback = engine.getFallbackTheme()
      if fallback != nil:
        var fkey = key
        if not fkey.endsWith(".timl"):
          fkey = fkey & ".timl"
        result = fallback.layouts.getOrDefault(fallback.path / "layouts" / fkey, nil)
    return result
  let path = engine.config.compilation.layoutsPath / key
  if not key.endsWith(".timl"):
    return engine.layouts.getOrDefault(path & ".timl", nil)
  return engine.layouts.getOrDefault(path, nil)

proc getView*(engine: TimEngine, key: string): TimTemplate =
  ## Get a view template by its name (with/without extension).
  ## When themes are enabled, looks in the active theme first,
  ## then in the fallback theme (if configured).
  if engine.enableThemes:
    result = engine.getThemeView(key.replace(".", "/"))
    if result == nil:
      let fallback = engine.getFallbackTheme()
      if fallback != nil:
        var fkey = key.replace(".", "/")
        if not fkey.endsWith(".timl"):
          fkey = fkey & ".timl"
        result = fallback.views.getOrDefault(fallback.path / "views" / fkey, nil)
    return result
  let path = engine.config.compilation.viewsPath / key
  if not key.endsWith(".timl"):
    return engine.views.getOrDefault(path & ".timl", nil)
  return engine.views.getOrDefault(path, nil)

proc getPartial*(engine: TimEngine, key: string): TimTemplate =
  ## Get a partial template by its name (with/without extension).
  ## When themes are enabled, looks in the active theme first,
  ## then in the fallback theme (if configured).
  if engine.enableThemes:
    result = engine.getThemePartial(key)
    if result == nil:
      let fallback = engine.getFallbackTheme()
      if fallback != nil:
        var fkey = key
        if not fkey.endsWith(".timl"):
          fkey = fkey & ".timl"
        result = fallback.partials.getOrDefault(fallback.path / "partials" / fkey, nil)
    return result
  let path = engine.config.compilation.partialsPath / key
  if not key.endsWith(".timl"):
    return engine.partials.getOrDefault(path & ".timl", nil)
  return engine.partials.getOrDefault(path, nil)

proc simplifyTemplatePath(engine: TimEngine, tpl: TimTemplate): string =
  replace(tpl.sources.src, engine.config.compilation.source)

#
# Theme template getters
#
proc getThemePartial*(engine: TimEngine, key: string): TimTemplate =
  ## Get a partial template from the active theme by its name (with/without extension).
  {.gcsafe.}:
    if engine.activeTheme == nil:
      raise newException(TimEngineError, "Active theme is not set")
    let path = engine.activeTheme.path / "partials" / key
    if not key.endsWith(".timl"):
      return engine.activeTheme.partials.getOrDefault(path & ".timl", nil)
    return engine.activeTheme.partials.getOrDefault(path, nil)

proc getThemeLayout*(engine: TimEngine, key: string): TimTemplate =
  ## Get a layout template from the active theme by its name (with/without extension).
  {.gcsafe.}:
    if engine.activeTheme == nil:
      raise newException(TimEngineError, "Active theme is not set")
    let path = engine.activeTheme.path / "layouts" / key
    if not key.endsWith(".timl"):
      return engine.activeTheme.layouts.getOrDefault(path & ".timl", nil)
    result = engine.activeTheme.layouts.getOrDefault(path, nil)

proc getThemeView*(engine: TimEngine, key: string): TimTemplate =
  ## Get a view template from the active theme by its name (with/without extension).
  {.gcsafe.}:
    if engine.activeTheme == nil:
      raise newException(TimEngineError, "Active theme is not set")
    let path = engine.activeTheme.path / "views" / key
    if not key.endsWith(".timl"):
      return engine.activeTheme.views.getOrDefault(path & ".timl", nil)
    return engine.activeTheme.views.getOrDefault(path, nil)

proc themeCacheSources(engine: TimEngine, themeName, srcPath: string): TemplateSources =
  ## Build cache paths for a theme template, namespaced under
  ## `output/<themeName>/`. Uses `.json` for AST/opcache to match
  ## `registerTemplate` and `tryLoadValidatedAst`.
  let cachedOutputPath = engine.config.compilation.output / themeName
  (src: srcPath,
   ast: cachedOutputPath / "ast" / getHashedPath(srcPath) & ".json",
   html: cachedOutputPath / "html" / getHashedPath(srcPath) & ".html",
   opcache: cachedOutputPath / "opcache" / getHashedPath(srcPath) & ".json")

proc registerTemplate*(engine: TimEngine, src: string): TimTemplate =
  ## Register a new Tim template by its source path.
  ## 
  ## This is used during the precompilation process to create a new Tim template
  ## and register it in the engine's tables based on its type (view, layout or partial).
  ## When themes are enabled and `src` lives inside a discovered theme directory,
  ## the template is registered in that theme's tables with per-theme cache paths.
  if engine.enableThemes:
    for themeName, theme in engine.themes:
      if src.startsWith(theme.path):
        var templateType: TimTemplateType
        if src.startsWith(theme.path / $ttView):
          templateType = ttView
        elif src.startsWith(theme.path / $ttLayout):
          templateType = ttLayout
        elif src.startsWith(theme.path / $ttPartial):
          templateType = ttPartial
        else: continue
        let tpl = newTemplate(getHashedPath(src), templateType,
                              engine.themeCacheSources(themeName, src))
        case templateType
        of ttView:
          theme.views[src] = tpl
        of ttLayout:
          theme.layouts[src] = tpl
        of ttPartial:
          theme.partials[src] = tpl
        return tpl
  var templateType: TimTemplateType
  if src.startsWith(engine.config.compilation.viewsPath):
    templateType = ttView
  elif src.startsWith(engine.config.compilation.layoutsPath):
    templateType = ttLayout
  elif src.startsWith(engine.config.compilation.partialsPath):
    templateType = ttPartial
  else:
    raise newException(TimEngineError,
      "Cannot determine template type for path (outside views/layouts/partials): " & src)
  let sources = (
    src: src,
    ast: engine.config.compilation.output / "ast" / getHashedPath(src) & ".json",
    html: engine.config.compilation.output / "html" / getHashedPath(src) & ".html",
    opcache: engine.config.compilation.output / "opcache" / getHashedPath(src) & ".json"
  )
  let tpl = newTemplate(getHashedPath(src), templateType, sources)
  case templateType
  of ttView:
    engine.views[src] = tpl
  of ttLayout:
    engine.layouts[src] = tpl
  of ttPartial:
    engine.partials[src] = tpl
  return tpl

proc parserCallback(astProgram: var Ast, path: string, resolver: FileResolver) =
  var content: string
  try:
    content = resolver.readFile(path)
  except ResolverError:
    # fallback to disk read as before
    content = readFile(path)
  parser.parseScript(astProgram, content, path)

proc partialsPathFor(engine: TimEngine, tpl: TimTemplate): string =
  ## Resolve the partials directory for a template, preferring the owning
  ## theme's `partials` dir when themes are enabled. Falls back to the
  ## engine-wide partials path (used in non-theme mode).
  if engine.enableThemes:
    for theme in engine.themes.values:
      if tpl.sources.src.startsWith(theme.path):
        return theme.path / "partials"
  engine.config.compilation.partialsPath

proc compilerFSFor(engine: TimEngine, tpl: TimTemplate): VirtualFileSystem =
  ## Build the virtual filesystem used when compiling `tpl`.
  ##
  ## When themes are enabled and `tpl` belongs to the active theme, partial
  ## includes first resolve against the active theme's `partials` dir and
  ## then fall back to the fallback theme's `partials` dir. This lets minimal
  ## themes override only a few templates while inheriting the rest.
  ## In all other cases a plain disk filesystem is returned.
  if engine.enableThemes and engine.activeTheme != nil:
    let active = engine.activeTheme
    if tpl.sources.src.startsWith(active.path):
      let fallback = engine.getFallbackTheme()
      if fallback != nil:
        let primaryDir = active.path / "partials"
        let fallbackDir = fallback.path / "partials"
        if primaryDir != fallbackDir:
          let disk = newDiskFS()
          result = VirtualFileSystem()
          result.existsProc = proc(path: string): bool =
            if disk.existsProc(path):
              return true
            let p = normalizedPath(path)
            if p.startsWith(normalizedPath(primaryDir)):
              return disk.existsProc(fallbackDir / relativePath(p, primaryDir))
            false
          result.readProc = proc(path: string): string =
            if disk.existsProc(path):
              return disk.readProc(path)
            let p = normalizedPath(path)
            if p.startsWith(normalizedPath(primaryDir)):
              let alt = fallbackDir / relativePath(p, primaryDir)
              if disk.existsProc(alt):
                return disk.readProc(alt)
            raise newException(ResolverError, "File does not exist: " & path)
          return result
  newDiskFS()

proc resolveDepPath(engine: TimEngine, ownerSrc, dep: string): string =
  # Resolve the path of a dependency based on the owner template's
  # source path and the engine's configuration.
  if dep.isAbsolute: return normalizedPath(dep)

  let fromOwner = normalizedPath(ownerSrc.parentDir / dep)
  if fileExists(fromOwner): return fromOwner

  if engine.enableThemes:
    # probe the active theme's partials, then the fallback theme's partials
    if engine.activeTheme != nil:
      let fromActiveTheme = normalizedPath(engine.activeTheme.path / "partials" / dep)
      if fileExists(fromActiveTheme): return fromActiveTheme
    let fallback = engine.getFallbackTheme()
    if fallback != nil:
      let fromFallbackTheme = normalizedPath(fallback.path / "partials" / dep)
      if fileExists(fromFallbackTheme): return fromFallbackTheme

  let fromPartials = normalizedPath(engine.config.compilation.partialsPath / dep)
  if fileExists(fromPartials): return fromPartials
  return fromOwner

proc updateDeps(engine: TimEngine, tpl: TimTemplate, rawDeps: sink seq[string]) =
  # Update the dependencies of a template based on the raw dependency
  # paths extracted from the AST.
  var deps: seq[string] = @[]
  let owner = normalizedPath(tpl.sources.src)
  for raw in rawDeps:
    let d = engine.resolveDepPath(owner, raw.addFileExt("timl"))
    if d != owner and d notin deps:
      deps.add(d)
  tpl.dependencies =move deps
  engine.depResolver.setDependencies(owner, tpl.dependencies)

proc parsePartial(engine: TimEngine, tpl: TimTemplate) =
  # Parse a partial template to extract its dependencies
  # and update the engine's resolver.
  var astProgram: Ast
  try:
    parser.parseScript(astProgram, readFile(tpl.sources.src), tpl.sources.src)
  except TimParserError as e:
    echo "Error parsing template: ", e.msg
    echo tpl.sources.src
    return
  engine.updateDeps(tpl, astProgram.otherPaths)

proc declareGlobals*(compiler: CodeGen) =
  # Declare global variables for the template scripts, such as `$app` and `$this`.
  let appStorage = newIdent("app")
  let thisStorage = newIdent("this")
  compiler.declareVar(appStorage, skConst, compiler.module.sym"json", isMagic = true)
  compiler.declareVar(thisStorage, skConst, compiler.module.sym"json", isMagic = true)

proc tryLoadValidatedAst*(path, sourcePath: string): tuple[ast: Ast, ok: bool] =
  ## Try to load a cached AST from `path` and validate it. Returns (ast, true) on success,
  ## (nil, false) if file missing or validation failed. Used for packed theme distribution
  ## where `.timl` sources may be omitted.
  if not fileExists(path):
    return (nil, false)
  try:
    let data = readFile(path)
    var a = fromJson(data, Ast)
    if sourcePath.len > 0:
      a.sourcePath = sourcePath
    a.validateAst()
    return (a, true)
  except Exception as e:
    when defined timDebugCache:
      displayInfo("Cached AST invalid at " & path & ": " & e.msg)
    return (nil, false)

proc precompileTemplate*(engine: TimEngine, tpl: TimTemplate,
                 manager: ModuleManager, data: JsonNode = nil,
                 force: bool = false): bool {.discardable.} =
  ## Precompile a Tim template. This involves parsing the template to extract its dependencies,
  ## compiling the template into a script, and updating the engine's dependency resolver.
  ##
  ## Pass `force = true` to skip the on-disk AST cache and re-parse from source.
  ## The file watcher uses this when a template (or one of its dependencies)
  ## changes: cache validation is structural only, so a stale-but-valid AST
  ## would otherwise shadow the edit.
  var astProgram: Ast
  var loadedFromCache = false
  # Try to reuse validated cached AST (enables packed themes without .timl)
  block tryCache:
    if force: break tryCache
    if fileExists(tpl.sources.ast):
      let (cached, ok) = tryLoadValidatedAst(tpl.sources.ast, tpl.sources.src)
      if ok and cached != nil:
        # If the original .timl is missing (packed distribution), accept cache directly.
        # If .timl exists, still prefer cache if newer? For now prefer cache when valid.
        astProgram = cached
        loadedFromCache = true
        break tryCache
      elif not fileExists(tpl.sources.src):
        # Packed mode: we have no source, cache is corrupt -> cannot proceed
        displayError("Tim Engine –– Cached AST invalid and no source at " & tpl.sources.src)
        return
  if not loadedFromCache:
    # Fallback: parse from .timl source (normal development path)
    try:
      parser.parseScript(astProgram, readFile(tpl.sources.src), tpl.sources.src)
    except TimParserError as e:
      displayError("Tim Engine –– Parsing error –– " & e.msg)
      displayInfo(cyan(engine.simplifyTemplatePath(tpl)))
      return
    except IOError as e:
      # Packed distribution without .timl but no valid cache
      displayError("Tim Engine –– Missing source and no valid cache for " & tpl.sources.src & ": " & e.msg)
      return

  var
    mainChunk = newChunk(tpl.sources.src)
    script = newScript(mainChunk)
    module = newModule(tpl.sources.src.extractFilename, some(tpl.sources.src))
    localData = newJObject()

  engine.updateDeps(tpl, astProgram.otherPaths)

  # load standard library modules
  let systemModule = libsystem.loadLibrary(script)
  module.load(systemModule)

  # load the user defined script
  if engine.userScript != nil:
    for procDef in engine.userScript.procs:
      script.addProc(
        module,
        procDef[0], # name
        procDef[1], # params
        procDef[2], # return type
        procDef[3], # implementation
        procDef[4]  # export symbol
      )
    # module.load(engine.userScript.module)

  script.addProc(module, "evaluate", @[paramDef("code", ttyString)], ttyAny,
    proc (args: StackView, argc: int): Value =
      ## Evaluate a string of Tim code and return the result.
      var inlineAst: Ast
      try:
        parser.parseScript(inlineAst, args[0].stringVal[], "inline")
        var inlineChunk = newChunk("inline")
        var inlineScript = newScript(inlineChunk)
        var inlineModule = newModule("inline", some("inline"))

        let systemModule = libsystem.loadLibrary(inlineScript)
        inlineModule.load(systemModule)

        var inlineCompiler = codegen.initCompiler(inlineScript, inlineModule,
                                inlineChunk, manager, stdlibs, parserCallback,
                                policy = engine.config.compilation.policy)

        inlineCompiler.declareGlobals()
        inlineCompiler.genScript(
          program = inlineAst,
          includePath = some(engine.config.compilation.partialsPath)
        )

        let prefs = VMPreferences(enableHotCodeDetection: true, hotProcThreshold: 5)
        var vmInstance = newVirtualMachine(prefs)
        result = vm.interpret(vmInstance, inlineScript, inlineChunk, localData = newJObject())

      except TimParserError as e:
        raise newException(TimRuntime, e.msg)
    )

  let stringsLib = initStrings(script, systemModule)
  module.load(stringsLib)

  let arraysLib = initArrays(script, systemModule)
  module.load(arraysLib)

  let jsonlib = initJSON(script, systemModule)
  module.load(jsonlib)

  # module.load(stdlibs["ffi"](script, systemModule))
  # module.load(stdlibs["times"](script, systemModule))

  script.stdpos = script.procs.high
  
  var compiler =
    codegen.initCompiler(script, module, mainChunk, manager,
                          stdlibs, parserCallback,
                          policy = engine.config.compilation.policy)
  compiler.declareGlobals()
  compiler.resolver.fs = engine.compilerFSFor(tpl)
  try:
    compiler.genScript(
      program = astProgram,
      includePath = some(engine.partialsPathFor(tpl))
    )
    
    tpl.script = script
    tpl.mainChunk = mainChunk
    
    let prefs = VMPreferences(enableHotCodeDetection: true, hotProcThreshold: 5)
    tpl.vmInstance = newVirtualMachine(prefs)
    
    writeFile(tpl.sources.ast, toJson(astProgram))
    writeFile(tpl.sources.opcache, tpl.mainChunk.code)
    return true # marks the template as successfully precompiled
  except CodeGenError as e:
    displayError("Code generation error in template: " & tpl.sources.src)
    display(e.msg)

proc precompileEmbeddedTemplate*(engine: TimEngine, tpl: TimTemplate,
        manager: ModuleManager, data: JsonNode = nil,
        vfsMap: TableRef[string, string] = nil): bool {.discardable.} =
  ## Precompile a Tim template from embedded code. This is used when the
  ## templates are embedded into the binary as strings, and we need to compile them into scripts.
  ## Optionally pass a `vfsMap` containing all available embedded templates for include/import resolution.
  var astProgram: Ast
  try:
    parser.parseScript(astProgram, tpl.embeddedCode.get(), tpl.id)
  except TimParserError as e:
    displayError("Tim Engine –– Parsing error –– " & e.msg)
    displayInfo(cyan(engine.simplifyTemplatePath(tpl)))
    return
  
  var
    mainChunk = newChunk(tpl.id)
    script = newScript(mainChunk)
    module = newModule(tpl.id, some(tpl.id))
    localData = newJObject()
  
  # load standard library modules
  let systemModule = libsystem.loadLibrary(script)
  module.load(systemModule)

  # load the user defined script
  if engine.userScript != nil:
    for procDef in engine.userScript.procs:
      script.addProc(
        module,
        procDef[0], # name
        procDef[1], # params
        procDef[2], # return type
        procDef[3], # implementation
        procDef[4]  # export symbol
      )

  let stringsLib = initStrings(script, systemModule)
  module.load(stringsLib)

  let arraysLib = initArrays(script, systemModule)
  module.load(arraysLib)

  let jsonlib = initJSON(script, systemModule)
  module.load(jsonlib)

  script.stdpos = script.procs.high
  
  var compiler =
    codegen.initCompiler(script, module, mainChunk, manager,
                      stdlibs, parserCallback,
                      policy = engine.config.compilation.policy)
  # and parserCallback read from embedded contents.
  # Use the provided vfsMap (all templates) or fall back to a single-entry map
  var localVfsMap = vfsMap
  if localVfsMap == nil:
    localVfsMap = newTable[string, string]()
    localVfsMap[normalizedPath(tpl.id)] = tpl.embeddedCode.get()
  compiler.resolver.fs = newInMemoryFS(localVfsMap)
  compiler.declareGlobals()
  # In embedded mode, the VFS already contains all templates keyed by simple
  # filenames. Don't use an includePath so that @include "leftsidebar" resolves
  # to "leftsidebar.timl" directly via the VFS rather than an absolute path.
  compiler.genScript(
    program = astProgram,
    includePath = none(string)
  )
  
  tpl.script = script
  tpl.mainChunk = mainChunk
  tpl.vmInstance = newVM()

  result = true # marks the template as successfully precompiled

var
  browserSyncWatcher: Watchout
  browserSyncThemeWatcher: Watchout

proc interpret*(view, layout: TimTemplate, localData,
        globalData: JsonNode): Value =
  ## Evaluate a view within a layout and return the final HTML output.
  ## 
  ## Templates are evaluated in the context of the provided `localData` and `globalData`, which are
  ## available in the templates under the `$this` and `$app` variables, respectively.
  ## 
  ## The view template is evaluated first, and its output is passed to the layout
  ## template as the content to be rendered within the layout.
  assert view.script != nil and
    layout.script != nil, "View or Layout script is not initialized"
  
  let vm = VM()
  let viewOutput = view.vmInstance.interpret(view.script, view.mainChunk,
                                      globalData = globalData, localData = localData)
  result = vm.interpret(layout.script, layout.mainChunk,
                  staticString = some($viewOutput),
                  globalData = globalData,
                  localData = localData)
  if result == nil:
    result = initValue("")

proc interpret*(view: TimTemplate, localData,
      globalData: JsonNode): Value =
  ## Evaluate a view without a layout and return the final HTML output. 
  ## This can be used for rendering partials or standalone views.
  assert view.script != nil, "View script is not initialized"
  # let vm = newVM()
  view.vmInstance.interpret(view.script, view.mainChunk,
                  globalData = globalData,
                  localData = localData)

proc compileCode*(view, layout: TimTemplate,
                localData, globalData: JsonNode): Value =
  ## Compile a view and layout into HTML without evaluating them.
  ## This can be used for debugging or for generating the HTML output
  ## without executing any code in the templates.
  interpret(view, layout, localData, globalData)

proc compileCode*(view: TimTemplate, localData, globalData: JsonNode): Value =
  ## Compile a view into HTML without evaluating it.
  interpret(view, localData, globalData)

proc precompile*(engine: TimEngine,
        views, layouts, partials: EmbeddedTemplates,
        globalData: JsonNode = nil) =
  ## Precompile a set of embedded templates and return a Tim Engine instance.
  if engine.sourceType != TimSourceType.timSourceEmbedded:
    # when the source type is embedded, we need to precompile the templates
    raise newException(TimEngineError, "Source type is not set to embedded. Cannot precompile embedded templates.")
  
  # init the package manager and load the local packages
  let manager = sharedManager()

  # Build a complete VFS with all templates so @include/@import directives
  # can resolve across views, layouts, and partials
  var allTemplates = newTable[string, string]()
  for k, v in views:    allTemplates[k] = v
  for k, v in layouts:  allTemplates[k] = v
  for k, v in partials: allTemplates[k] = v

  for k, view in views:
    let id = getHashedPath(k)
    let tpl = TimTemplate(id: id, templateType: ttView, embeddedCode: some(view))
    if engine.precompileEmbeddedTemplate(tpl, manager, vfsMap = allTemplates):
      engine.views[k] = tpl
  
  for k, layout in layouts:
    let id = getHashedPath(k)
    let tpl = TimTemplate(id: id, templateType: ttLayout, embeddedCode: some(layout))
    if engine.precompileEmbeddedTemplate(tpl, manager, vfsMap = allTemplates):
      engine.layouts[k] = tpl
  
  for k, partial in partials:
    let id = getHashedPath(k)
    let tpl = TimTemplate(id: id, templateType: ttPartial, embeddedCode: some(partial))
    if engine.precompileEmbeddedTemplate(tpl, manager, vfsMap = allTemplates):
      engine.partials[k] = tpl

type
  EmbeddedTheme* = tuple
    ## An embedded theme bundle: template contents keyed by template name,
    ## as produced by `supra bundle.assets` per theme directory.
    views, layouts, partials: EmbeddedTemplates

proc precompileEmbeddedTheme(engine: TimEngine, name: string,
        bundle: EmbeddedTheme, manager: ModuleManager) =
  ## Precompile a single embedded theme bundle into `engine.themes[name]`.
  var theme = Theme(path: "embedded" / name,
    manifest: ThemeManifest(name: name))
  engine.themes[name] = theme
  var allTemplates = newTable[string, string]()
  for k, v in bundle.views:    allTemplates[k] = v
  for k, v in bundle.layouts:  allTemplates[k] = v
  for k, v in bundle.partials: allTemplates[k] = v
  for k, view in bundle.views:
    let tpl = TimTemplate(id: getHashedPath(name / k),
      templateType: ttView, embeddedCode: some(view))
    if engine.precompileEmbeddedTemplate(tpl, manager, vfsMap = allTemplates):
      theme.views[theme.path / "views" / k] = tpl
  for k, layout in bundle.layouts:
    let tpl = TimTemplate(id: getHashedPath(name / k),
      templateType: ttLayout, embeddedCode: some(layout))
    if engine.precompileEmbeddedTemplate(tpl, manager, vfsMap = allTemplates):
      theme.layouts[theme.path / "layouts" / k] = tpl
  for k, partial in bundle.partials:
    let tpl = TimTemplate(id: getHashedPath(name / k),
      templateType: ttPartial, embeddedCode: some(partial))
    if engine.precompileEmbeddedTemplate(tpl, manager, vfsMap = allTemplates):
      theme.partials[theme.path / "partials" / k] = tpl

proc precompile*(engine: TimEngine,
        themes: Table[string, EmbeddedTheme],
        globalData: JsonNode = nil) =
  ## Precompile embedded theme bundles and activate one of them.
  ##
  ## The engine must have been created with `enableThemes = true` and an
  ## `activeThemeName` matching one of the keys in `themes`. When a
  ## `fallbackThemeName` is set, that bundle is compiled as well and used
  ## for templates missing from the active theme.
  if engine.sourceType != TimSourceType.timSourceEmbedded:
    raise newException(TimEngineError, "Source type is not set to embedded. Cannot precompile embedded templates.")
  if not engine.enableThemes:
    raise newException(TimEngineError, "Engine themes are not enabled. Create the engine with `enableThemes = true`.")
  if engine.activeThemeName.len == 0 or engine.activeThemeName notin themes:
    var available: seq[string] = @[]
    for name in themes.keys:
      available.add(name)
    raise newException(TimEngineError,
      "Active theme not found: " & engine.activeThemeName &
      ". Available themes: " & available.join(", "))
  if engine.fallbackThemeName.len > 0 and engine.fallbackThemeName notin themes:
    raise newException(TimEngineError,
      "Fallback theme not found: " & engine.fallbackThemeName)
  let manager = sharedManager()
  for name, bundle in themes:
    # compile the active theme and the fallback theme only;
    # other bundles stay undiscovered to keep the binary lean
    if name == engine.activeThemeName or name == engine.fallbackThemeName:
      engine.precompileEmbeddedTheme(name, bundle, manager)
  engine.activeTheme = engine.themes[engine.activeThemeName]


proc precompile*(engine: TimEngine) =
  ## Precompile Tim Engine templates.
  ## 
  ## This proc is usually called before starting the development server.
  ## It compiles all the templates and sets up the file watcher
  ## for hot reloading.

  # init the package manager and load the local packages
  let manager = sharedManager()
  
  if engine.enableThemes:
    # when themes are enabled, will discover themes available in the `themes` directory
    # of the installation path. Each theme should have a `theme.yaml` manifest file and its own
    # `views`, `layouts` and `partials` directories.
    #
    # The active theme is determined by the `activeTheme` field in the engine config, which should
    # match the name of one of the discovered themes. Once found, we will load and compile
    # the templates of the active theme and set up the file watcher for hot reloading
    let srcDir = engine.config.compilation.source
    for themeDir in walkDirs(srcDir / "*"):
      let yamlConfigPath = themeDir / "theme.yaml"
      let jsonConfigPath = themeDir / "theme.json"
      var themeManifest: ThemeManifest
      var manifestOk = false
      if fileExists(yamlConfigPath):
        try:
          themeManifest = parseYaml(readFile(yamlConfigPath), ThemeManifest)
          manifestOk = true
        except OpenParserYamlError as e:
          displayError("Failed to parse theme manifest: " & yamlConfigPath & "\nError: " & e.msg)
      elif fileExists(jsonConfigPath):
        try:
          themeManifest = fromJson(readFile(jsonConfigPath), ThemeManifest)
          manifestOk = true
        except JsonParsingError:
          displayError("Failed to parse theme manifest: " & jsonConfigPath)
      else:
        displayError("No theme manifest found for theme: " & themeDir)
      if not manifestOk or themeManifest.name.len == 0:
        # skip broken themes so they can't be activated; they remain
        # visible via `listThemes` absence plus the error above
        displayError("Skipping theme with missing or invalid manifest: " & themeDir)
        continue
      var theme = Theme(path: themeDir, manifest: themeManifest)
      engine.themes[themeManifest.name] = theme

    if engine.activeThemeName.len == 0:
      raise newException(TimEngineError,
        "Theme support is enabled but no active theme is set. " &
        "Pass `activeThemeName` to `newTim` or call `setActiveTheme`. " &
        "Available themes: " & engine.listThemes().join(", "))
    if engine.activeThemeName notin engine.themes:
      raise newException(TimEngineError,
        "Active theme not found: " & engine.activeThemeName &
        ". Available themes: " & engine.listThemes().join(", "))
    if engine.fallbackThemeName.len > 0 and engine.fallbackThemeName notin engine.themes:
      raise newException(TimEngineError,
        "Fallback theme not found: " & engine.fallbackThemeName &
        ". Available themes: " & engine.listThemes().join(", "))

    proc compileTheme(engine: TimEngine, theme: Theme, manager: ModuleManager) =
      # load and compile a single theme's templates. A theme may ship only
      # a subset of templates (e.g. just `views/index.timl`); anything missing
      # resolves via the fallback theme at render time (see `getView`,
      # `getLayout`, `getPartial`).
      let cachedOutputPath = engine.config.compilation.output / theme.manifest.name
      try:
        createDir(cachedOutputPath)
        createDir(cachedOutputPath / "ast")
        createDir(cachedOutputPath / "html")
        createDir(cachedOutputPath / "opcache")
      except OSError as e:
        raise newException(TimEngineError,
          "Cannot create theme cache directory " & cachedOutputPath & ": " & e.msg)
      for sourceDir in [ttLayout, ttView, ttPartial]:
        let themeSourcePath = theme.path / $sourceDir
        if not dirExists(themeSourcePath):
          displayError("Missing directory $1 for theme $2: \n$3" % [$sourceDir, theme.manifest.name, themeSourcePath])
          continue
        # follow symlinks so symlinked theme trees (theme dev via `ln -s`)
        # compile exactly like regular directories
        for srcPath in walkDirRec(themeSourcePath,
                                  yieldFilter = {pcFile, pcLinkToFile},
                                  followFilter = {pcDir, pcLinkToDir}):
          if not srcPath.endsWith(".timl"):
            continue
          let
            id = getHashedPath(srcPath) # unique id based on path
            sources = engine.themeCacheSources(theme.manifest.name, srcPath)
          case sourceDir:
          of ttLayout:
            let tpl = newTemplate(id, ttLayout, sources)
            if engine.precompileTemplate(tpl, manager):
              theme.layouts[srcPath] =  tpl
          of ttView:
            let tpl = newTemplate(id, ttView, sources)
            if engine.precompileTemplate(tpl, manager):
              theme.views[srcPath] = tpl
          of ttPartial:
            let tpl = newTemplate(id, ttPartial, sources)
            if engine.precompileTemplate(tpl, manager):
              theme.partials[srcPath] = tpl

    # compile the active theme, plus the fallback theme when configured
    # (fallback templates only render when the active theme lacks them)
    engine.activeTheme = engine.themes[engine.activeThemeName]
    engine.compileTheme(engine.activeTheme, manager)
    let fallbackTheme = engine.getFallbackTheme()
    if fallbackTheme != nil:
      engine.compileTheme(fallbackTheme, manager)
          
    # set up file watcher for the active theme (and fallback, when configured)
    when defined timHotCode:
      var themeWatchPaths = @[
        engine.activeTheme.path / "layouts",
        engine.activeTheme.path / "views",
        engine.activeTheme.path / "partials"
      ]
      if fallbackTheme != nil:
        themeWatchPaths.add(fallbackTheme.path / "layouts")
        themeWatchPaths.add(fallbackTheme.path / "views")
        themeWatchPaths.add(fallbackTheme.path / "partials")
      browserSyncThemeWatcher = newWatchout(themeWatchPaths, some("*.timl"))

      # Note: the theme watcher owns the browser-sync port (9000) because in
      # theme mode the non-theme watcher never starts, and layouts listen on
      # port 9000 for reload notifications.
      let ws2 = startWebSocket(port = Port(9000))
      sleep(100) # wait for the websocket server

      # Callback `onFound`
      proc onFound(file: watchout.File) =
        # Runs when detecting a new template.
        let tpl: TimTemplate = engine.getTemplateByPath(file.getPath())
        if tpl != nil:
          case tpl.templateType
          of ttView, ttLayout:
            engine.precompileTemplate(tpl, manager)
          else: discard
        else:
          # if the template is not registered,
          # we need to register it and compile it
          let newTpl = engine.registerTemplate(file.getPath())
          if newTpl.templateType != ttPartial:
            # partials don't need to be compiled as they
            # are included in other templates (layouts or views)
            engine.precompileTemplate(newTpl, manager)
          else:
            # for partials, we only need to parse them to get their dependencies
            parsePartial(engine, newTpl)

      # Callback `onChange`
      proc onChange(file: watchout.File) =
        # Runs when detecting changes
        let tpl: TimTemplate = engine.getTemplateByPath(file.getPath())
        if tpl == nil: return # template not found, ignore
        # Drop stale caches for the changed file first. `@include` resolution
        # inside dependants is path-keyed with no content validation, so without
        # this the recompile below reuses the pre-edit AST while the browser
        # still reloads (stale content).
        manager.invalidate(normalizedPath(tpl.sources.src))
        codegenCache.cachedAst.del(tpl.sources.src)
        case tpl.templateType
        of ttView, ttLayout:
          # if the template is a view or layout, compile it
          engine.precompileTemplate(tpl, manager, force = true)
          ws2.notifyAllClients()
        of ttPartial:
          # refresh changed partial dependencies first
          parsePartial(engine, tpl)
          # re-compile all recursive dependants
          for depPath in engine.depResolver.dependants(normalizedPath(tpl.sources.src)):
            let depTpl = engine.getTemplateByPath(depPath)
            if depTpl == nil: continue
            manager.invalidate(normalizedPath(depPath))
            case depTpl.templateType
            of ttView, ttLayout:
              engine.precompileTemplate(depTpl, manager, force = true)
            of ttPartial:
              parsePartial(engine, depTpl)
            # clear the cached AST of the dependant to force
            # re-parsing and updating their dependencies
            codegenCache.cachedAst.del(depPath)
          ws2.notifyAllClients()

      # Callback `onDelete`
      proc onDelete(file: watchout.File) =
        # Runs when detecting a deleted template
        let tpl: TimTemplate = engine.getTemplateByPath(file.getPath())
        if tpl != nil:
          # if the template is found, remove it from the theme tables
          # and clear its dependencies from the resolver. We also need
          # to re-compile all the dependants of the deleted template to update
          # their dependencies and remove the deleted template from their dependency list
          engine.depResolver.clearFile(normalizedPath(tpl.sources.src))
          manager.invalidate(normalizedPath(tpl.sources.src))
          codegenCache.cachedAst.del(tpl.sources.src)
          for theme in engine.themes.values:
            case tpl.templateType
            of ttView:
              theme.views.del(tpl.sources.src)
            of ttLayout:
              theme.layouts.del(tpl.sources.src)
            of ttPartial:
              theme.partials.del(tpl.sources.src)

      browserSyncThemeWatcher.onFound = onFound
      browserSyncThemeWatcher.onChange = onChange
      browserSyncThemeWatcher.onDelete = onDelete
      browserSyncThemeWatcher.start()
  else:
    # for non-theme mode, we load all templates from the source directory and compile them
    discard existsOrCreateDir(engine.config.compilation.output)
    discard existsOrCreateDir(engine.config.compilation.output / "ast")
    discard existsOrCreateDir(engine.config.compilation.output / "html")
    discard existsOrCreateDir(engine.config.compilation.output / "opcache")
    let srcDir = engine.config.compilation.source
    for sourceDir in [ttLayout, ttView, ttPartial]:
      if not dirExists(srcDir / $sourceDir):
        raise newException(TimEngineError, "Missing directory $1: \n$2" % [$sourceDir, srcDir / $sourceDir])
      for srcPath in walkDirRec(srcDir / $sourceDir,
                                yieldFilter = {pcFile, pcLinkToFile},
                                followFilter = {pcDir, pcLinkToDir}):
        if not srcPath.endsWith(".timl"):
          continue
        let
          id = getHashedPath(srcPath) # unique id based on path
          astPath = engine.config.compilation.output / "ast" / id & ".json"
          htmlPath = engine.config.compilation.output / "html" / id & ".html"
          opcachePath = engine.config.compilation.output / "opcache" / id & ".json"
          sources = (src: srcPath, ast: astPath, html: htmlPath, opcache: opcachePath)
        case sourceDir:
          of ttLayout:
            let tpl = newTemplate(id, ttLayout, sources)
            if engine.precompileTemplate(tpl, manager):
              engine.layouts[srcPath] =  tpl
          of ttView:
            let tpl = newTemplate(id, ttView, sources)
            if engine.precompileTemplate(tpl, manager):
              engine.views[srcPath] = tpl 
          of ttPartial:
            let tpl = newTemplate(id, ttPartial, sources)
            if engine.precompileTemplate(tpl, manager):
              engine.partials[srcPath] = tpl
          else: discard

    when defined timHotCode:
      browserSyncWatcher = 
        newWatchout(@[
          engine.config.compilation.layoutsPath,
          engine.config.compilation.viewsPath,
          engine.config.compilation.partialsPath
        ], some("*.timl"))
      
      let ws1 = startWebSocket(port = Port(9000))
      sleep(100) # wait for the websocket server

      # Callback `onFound`
      proc onFound(file: watchout.File) =
        # Runs when detecting a new template.
        let tpl: TimTemplate = engine.getTemplateByPath(file.getPath())
        if tpl != nil:
          case tpl.templateType
          of ttView, ttLayout:
            engine.precompileTemplate(tpl, manager)
          else: discard
        else:
          # if the template is not registered,
          # we need to register it and compile it
          let newTpl = engine.registerTemplate(file.getPath())
          if newTpl.templateType != ttPartial:
            # partials don't need to be compiled as they
            # are included in other templates (layouts or views)
            engine.precompileTemplate(newTpl, manager)
          else:
            # for partials, we only need to parse them to get their dependencies
            parsePartial(engine, newTpl)

      # Callback `onChange`
      proc onChange(file: watchout.File) =
        # Runs when detecting changes
        let tpl: TimTemplate = engine.getTemplateByPath(file.getPath())
        if tpl == nil: return # template not found, ignore
        # Drop stale caches for the changed file first. `@include` resolution
        # inside dependants is path-keyed with no content validation, so without
        # this the recompile below reuses the pre-edit AST while the browser
        # still reloads (stale content).
        manager.invalidate(normalizedPath(tpl.sources.src))
        codegenCache.cachedAst.del(tpl.sources.src)
        case tpl.templateType
        of ttView, ttLayout:
          # if the template is a view or layout, compile it
          engine.precompileTemplate(tpl, manager, force = true)
          ws1.notifyAllClients()
        of ttPartial:
          # refresh changed partial dependencies first
          parsePartial(engine, tpl)
          # re-compile all recursive dependants
          for depPath in engine.depResolver.dependants(normalizedPath(tpl.sources.src)):
            let depTpl = engine.getTemplateByPath(depPath)
            if depTpl == nil: continue
            manager.invalidate(normalizedPath(depPath))
            case depTpl.templateType
            of ttView, ttLayout:
              engine.precompileTemplate(depTpl, manager, force = true)
            of ttPartial:
              parsePartial(engine, depTpl)
            # clear the cached AST of the dependant to force
            # re-parsing and updating their dependencies
            codegenCache.cachedAst.del(depPath)
          ws1.notifyAllClients()

      # Callback `onDelete`
      proc onDelete(file: watchout.File) =
        # Runs when detecting a deleted template
        let tpl: TimTemplate = engine.getTemplateByPath(file.getPath())
        if tpl != nil:
          # if the template is found, remove it from the engine tables
          # and clear its dependencies from the resolver. We also need
          # to re-compile all the dependants of the deleted template to update
          # their dependencies and remove the deleted template from their dependency list
          engine.depResolver.clearFile(normalizedPath(tpl.sources.src))
          manager.invalidate(normalizedPath(tpl.sources.src))
          codegenCache.cachedAst.del(tpl.sources.src)
          case tpl.templateType
          of ttView:
            engine.views.del(tpl.sources.src)
          of ttLayout:
            engine.layouts.del(tpl.sources.src)
          of ttPartial:
            engine.partials.del(tpl.sources.src)

      # Set up file watcher callbacks and start watching for changes
      browserSyncWatcher.onFound = onFound
      browserSyncWatcher.onChange = onChange
      browserSyncWatcher.onDelete = onDelete
      browserSyncWatcher.start()