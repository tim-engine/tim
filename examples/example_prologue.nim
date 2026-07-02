# This is an example of using Tim Engine with Prologue

import std/[strutils, times, os]
import ../src/tim

#
# Setup Tim Engine
#
var
  timEngine = newTim(
    src = "templates",            # where to find the .timl files
    output = "storage",           # where to cache precompiled templates
    basepath = getCurrentDir()    # base path for resolving absolute paths in templates
  )

timEngine.precompile()

#
# Setup Prologue
#
import prologue

let settings = newSettings(port = Port(8082))
var app = newApp(settings = settings)

#define your route handling callbacks
proc indexPageHandler(ctx: Context) {.async, gcsafe.} =
  {.gcsafe.}:
    let localObjects = %*{
      "meta": {
          "title": "Tim Engine is Awesome!"
      },
      "path": "/"
    }
    let indexPage = timEngine.render(view = "index", data = localObjects)
    resp indexPage

proc e404(ctx: Context) {.async, gcsafe.} =
  {.gcsafe.}:
    let localObjects = %*{
      "meta": {
          "title": "Oh, you're a genius!",
          "msg": "Oh yes, yes. It's got action, it's got drama, it's got dance! Oh, it's going to be a hit hit hit!"
      },
      "path": %*(ctx.request.path)
    }
    let e404Page = timEngine.render(view = "error", data = localObjects)
    resp e404Page

#tell prologue how to handle routes
app.addRoute("/", indexPageHandler)
app.registerErrorHandler(Http404, e404)

app.run()