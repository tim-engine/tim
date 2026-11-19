# A super fast template engine for cool kids
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[tables, httpcore, net, os, strutils, options, locks, times]
import ../meta/cliutils
import pkg/openparser/[yaml, json]
import pkg/watchout
import pkg/vancode/interpreter/[manager, codegen, resolver]

import supranim/network/webserver
from supranim/core/request import getUrl, getAgent

import ../meta/[initializer, config, websocket, cache]

type
  WebApp* = ref object
    server*: WebServer
    engine*: TimEngine
    configInstance*: TimConfig
    baseDir*: string
    watcher*: Watchout
    wsServer*: WebSocketServer

var webapp*: WebApp

var templateLock: Lock # TODO use pkg/threading/rwlocks
initLock(templateLock)

var pendingLock: Lock
var pendingPaths: seq[string] = @[]
initLock(pendingLock)

proc enqueuePending(path: string) =
  ## Watcher-thread entry point. Records a changed path for the server
  ## thread to recompile. Must stay trivial: the watchout FSEvents callback
  ## runs on a foreign pthread, so it must never touch ORC-managed engine
  ## state (manager LRU, codegenCache, TimTemplates) — doing parse/codegen
  ## there corrupts the heap (SIGSEGV in invalidate/precompileTemplate).
  withLock pendingLock:
    if path notin pendingPaths:
      pendingPaths.add(path)

proc drainPending(): seq[string] =
  withLock pendingLock:
    result = move(pendingPaths)
    pendingPaths = @[]

proc waitPathSettled(path: string, settleMs = 75, timeoutMs = 1000): bool =
  ## Server-thread copy of initializer.waitFileSettled (private there).
  ## Editors save via truncate-then-write; wait until mtime+size are stable
  ## so we never compile a torn (often empty) file.
  proc sig(p: string): tuple[mtime: Time, size: int64] =
    let info = getFileInfo(p)
    (info.lastWriteTime, info.size)
  var prev: tuple[mtime: Time, size: int64]
  try:
    prev = sig(path)
  except OSError:
    return false
  if getTime() - prev.mtime > initDuration(milliseconds = 1000):
    return true
  let settleFor = initDuration(milliseconds = settleMs)
  let deadline = getTime() + initDuration(milliseconds = timeoutMs)
  while getTime() < deadline:
    sleep(25)
    var cur: tuple[mtime: Time, size: int64]
    try:
      cur = sig(path)
    except OSError:
      return false
    if cur == prev and getTime() - cur.mtime >= settleFor:
      return true
    prev = cur
  return true

proc recompilePending() =
  ## Drain watcher-enqueued paths and recompile them on the server thread.
  ## All engine mutation (manager.invalidate, codegenCache, precompileTemplate)
  ## happens here under templateLock — never on the FSEvents thread.
  let paths = drainPending()
  if paths.len == 0: return
  let manager = sharedTimManager()
  for fpath in paths:
    if not fileExists(fpath):
      acquire(templateLock)
      let tpl = webapp.engine.getTemplateByPath(fpath)
      if tpl != nil:
        webapp.engine.depResolver.clearFile(normalizedPath(fpath))
        manager.invalidate(normalizedPath(fpath))
        codegenCache.cachedAst.del(tpl.sources.src)
        case tpl.templateType
        of ttView:
          webapp.engine.views.del(tpl.sources.src)
        of ttLayout:
          webapp.engine.layouts.del(tpl.sources.src)
        of ttPartial:
          webapp.engine.partials.del(tpl.sources.src)
      release(templateLock)
      continue
    if not waitPathSettled(fpath): continue
    acquire(templateLock)
    let tpl = webapp.engine.getTemplateByPath(fpath)
    if tpl == nil:
      try:
        let newTpl = webapp.engine.registerTemplate(fpath)
        if newTpl.templateType != ttPartial:
          discard webapp.engine.precompileTemplate(newTpl, manager)
      except CatchableError:
        discard
      release(templateLock)
      continue
    # Drop stale caches before recompile – otherwise precompileTemplate
    # reuses a stale-but-valid on-disk AST and the browser reloads stale
    # content.
    manager.invalidate(normalizedPath(tpl.sources.src))
    codegenCache.cachedAst.del(tpl.sources.src)
    case tpl.templateType
    of ttView, ttLayout:
      discard webapp.engine.precompileTemplate(tpl, manager, force = true)
    of ttPartial:
      # Partial itself doesn't render; recompile its dependants (views/layouts
      # that @include it) with force so their cached ASTs are refreshed.
      discard webapp.engine.precompileTemplate(tpl, manager, force = true)
      for depPath in webapp.engine.depResolver.dependants(normalizedPath(tpl.sources.src)):
        let depTpl = webapp.engine.getTemplateByPath(depPath)
        if depTpl == nil: continue
        manager.invalidate(normalizedPath(depPath))
        codegenCache.cachedAst.del(depPath)
        case depTpl.templateType
        of ttView, ttLayout:
          discard webapp.engine.precompileTemplate(depTpl, manager, force = true)
        of ttPartial:
          discard webapp.engine.precompileTemplate(depTpl, manager, force = true)
    release(templateLock)

proc serveTemplate(req: var Request, viewName: string) =
  recompilePending() # serve fresh: apply watcher-enqueued edits first
  acquire(templateLock)
  let viewTpl = webapp.engine.getView(viewName.replace(".", "/"))
  let layoutTpl = webapp.engine.getLayout("base")
  if viewTpl != nil and layoutTpl != nil:
    try:
      let localData = %*{"__req_id": cast[int](addr(req))}
      let html = "<!DOCTYPE html>" & $interpret(viewTpl, layoutTpl, localData, webapp.engine.globalData)
      release(templateLock)
      req.send(200, html)
      return
    except Exception as e:
      release(templateLock)
      req.send(500, "Internal Server Error")
      return
  release(templateLock)
  req.send(404, "Not Found")

proc onRequest(req: var Request) {.gcsafe.} =
  {.gcsafe.}:
    let path = req.path
    var viewName = webapp.configInstance.server.routes.getOrDefault(path)
    if viewName.len == 0 and path != "/":
      viewName = webapp.configInstance.server.routes.getOrDefault(path.strip(chars={'/'}, leading=true))
    if viewName.len > 0:
      serveTemplate(req, viewName)
    else:
      # TODO use powpow stream file
      # https://github.com/openpeeps/powpow/blob/main/examples/stream_server.nim
      let staticPath = webapp.baseDir / "public" / path.relativePath("/")
      if fileExists(staticPath):
        let headers = newHttpHeaders()
        let ext = staticPath.splitFile().ext.toLowerAscii()
        case ext
        of ".html", ".htm": headers.add("Content-Type", "text/html")
        of ".css":          headers.add("Content-Type", "text/css")
        of ".js":           headers.add("Content-Type", "application/javascript")
        of ".png":          headers.add("Content-Type", "image/png")
        of ".jpg", ".jpeg": headers.add("Content-Type", "image/jpeg")
        of ".gif":          headers.add("Content-Type", "image/gif")
        of ".svg":          headers.add("Content-Type", "image/svg+xml")
        of ".ico":          headers.add("Content-Type", "image/x-icon")
        else:               discard
        req.send(200, readFile(staticPath), headers)
      else:
        req.send(404, "Not Found")

proc serveCommand*(configPathArg: string, sync: bool) =
  let configPath = configPathArg
  if not fileExists(configPath):
    displayError("File not found: " & configPathArg, quitProcess = true)
  let yamlFile = readFile(configPath)
  let config: TimConfig = parseYaml(yamlFile, TimConfig)
  let baseDir = absolutePath(configPath.parentDir())
  discard existsOrCreateDir(baseDir / config.compilation.output)

  if config.cache != nil and config.cache.enabled:
    let cachePath =
      if config.cache.path.len == 0: "cache"
      else: config.cache.path
    let defaultTTL =
      if config.cache.defaultTTL > 0: config.cache.defaultTTL
      else: 3600
    initFetchCache(baseDir / cachePath, defaultTTL)

  let timEngine = newTim(
    src = config.compilation.source,
    output = config.compilation.output,
    basepath = baseDir
  )
  timEngine.config.compilation.policy = config.compilation.policy

  # `--sync` exposes `$app["enableBrowserSync"]` to templates and
  # triggers automatic live-reload script injection at render time
  timEngine.globalData["enableBrowserSync"] = %sync

  timEngine.userScript.addProc("getPath", @[paramDef("obj", ttyJson)], ttyString,
    proc (args: StackView; argc: int): value.Value =
      let req = cast[ptr Request](args[0].jsonVal["__req_id"].getInt())
      return initValue(req.path)
    )
  timEngine.userScript.addProc("getMethod", @[paramDef("obj", ttyJson)], ttyString,
    proc (args: StackView; argc: int): value.Value =
      let req = cast[ptr Request](args[0].jsonVal["__req_id"].getInt())
      return initValue($req[].getMethod())
    )
  timEngine.userScript.addProc("getQuery", @[paramDef("obj", ttyJson), paramDef("key", ttyString)], ttyString,
    proc (args: StackView; argc: int): value.Value =
      let req = cast[ptr Request](args[0].jsonVal["__req_id"].getInt())
      let key = args[1].stringVal[]
      let q = req[].getQuery()
      return initValue(q.getOrDefault(key, ""))
    )
  timEngine.userScript.addProc("getHeader", @[paramDef("obj", ttyJson), paramDef("key", ttyString)], ttyString,
    proc (args: StackView; argc: int): value.Value =
      let req = cast[ptr Request](args[0].jsonVal["__req_id"].getInt())
      let key = args[1].stringVal[]
      return initValue(req[].getHeader(key).get(""))
    )
  timEngine.userScript.addProc("getBody", @[paramDef("obj", ttyJson)], ttyString,
    proc (args: StackView; argc: int): value.Value =
      let req = cast[ptr Request](args[0].jsonVal["__req_id"].getInt())
      return initValue(req[].getBody().get(""))
    )
  timEngine.userScript.addProc("getIp", @[paramDef("obj", ttyJson)], ttyString,
    proc (args: StackView; argc: int): value.Value =
      let req = cast[ptr Request](args[0].jsonVal["__req_id"].getInt())
      return initValue(req[].getIp())
    )
  timEngine.userScript.addProc("getUrl", @[paramDef("obj", ttyJson)], ttyString,
    proc (args: StackView; argc: int): value.Value =
      let req = cast[ptr Request](args[0].jsonVal["__req_id"].getInt())
      return initValue(req[].getUrl())
    )
  timEngine.userScript.addProc("getAgent", @[paramDef("obj", ttyJson)], ttyString,
    proc (args: StackView; argc: int): value.Value =
      let req = cast[ptr Request](args[0].jsonVal["__req_id"].getInt())
      return initValue(req[].getAgent().get(""))
    )
  timEngine.userScript.addProc("getParam", @[paramDef("obj", ttyJson), paramDef("key", ttyString)], ttyString,
    proc (args: StackView; argc: int): value.Value =
      let req = cast[ptr Request](args[0].jsonVal["__req_id"].getInt())
      let key = args[1].stringVal[]
      return initValue(req.routeParams.getOrDefault(key, ""))
    )
  timEngine.userScript.addProc("isDevel", @[], ttyBool,
    proc (args: StackView; argc: int): value.Value =
      return initValue(config.compilation.release == false)
    )
  timEngine.userScript.addProc("getConfig", @[], ttyJson,
    proc (args: StackView; argc: int): value.Value =
      return initValue(%*{
        "isDevel": config.compilation.release == false,
        "browserSync": %*{
          "port": uint16(config.browser_sync.port),
          "delay": config.browser_sync.delay
        }
      })
    )

  timEngine.precompile()

  # Start WebSocket first so watcher callbacks can safely notify.
  # Previously watcher.start() ran before wsServer was assigned,
  # causing handleEvent's initial scan (onChange -> notifyAllClients(nil))
  # to SIGSEGV at websocket.nim:80.
  let wsPort =
    if config.browser_sync != nil:
      config.browser_sync.port
    else:
      config.browser_sync = BrowserSync(port: Port(9000), delay: 300)
      config.browser_sync.port

  let wsServer = startWebSocket(wsPort)
  # tiny delay to let WS thread bind before FSEvents fire
  sleep(100)

  webapp = WebApp(
    server: newWebServer(
      port = config.server.port,
      enableMultiThreading = config.server.threads > 1
    ),
    engine: timEngine,
    configInstance: config,
    baseDir: baseDir,
    wsServer: wsServer
  )

  webapp.watcher = newWatchout(@[
    timEngine.config.compilation.layoutsPath,
    timEngine.config.compilation.viewsPath,
    timEngine.config.compilation.partialsPath
  ], some("*.timl"))

  # NOTE: these callbacks run on watchout's foreign FSEvents pthread.
  # They must only enqueue the path and notify browsers. All engine work
  # (invalidate, precompileTemplate, table updates) runs on the server
  # thread via recompilePending() in serveTemplate — running it here
  # corrupts the ORC heap (SIGSEGV in manager.invalidate / precompile).
  # Notify is optimistic: the browser reloads, and that request drains
  # the queue and serves fresh content (settle wait is server-side).
  webapp.watcher.onFound = proc(file: watchout.File) =
    enqueuePending(file.getPath())
    if webapp.wsServer != nil:
      notifyAllClients(webapp.wsServer)

  webapp.watcher.onChange = proc(file: watchout.File) =
    enqueuePending(file.getPath())
    if webapp.wsServer != nil:
      notifyAllClients(webapp.wsServer)

  webapp.watcher.onDelete = proc(file: watchout.File) =
    enqueuePending(file.getPath())
    if webapp.wsServer != nil:
      notifyAllClients(webapp.wsServer)

  webapp.watcher.start()
  webapp.server.start(onRequest)
