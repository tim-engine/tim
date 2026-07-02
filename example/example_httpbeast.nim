# This is an example of using Tim Engine with HttpBeast
import std/[options, asyncdispatch, macros,
            os, strutils, times, json, httpcore, net]

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

import pkg/[httpbeast]

proc resp(req: Request, view: string, layout = "base", code = Http200,
    headers = "Content-Type: text/html", data = newJObject()) =
  data["path"] = %*(req.path.get())
  let htmlOutput = timEngine.render(view, layout, data = data)
  req.send(code, htmlOutput, headers)

proc onRequest(req: Request): Future[void] =
  {.gcsafe.}:
    let path = req.path.get()
    case req.httpMethod.get()
    of HttpGet:
      case path
      of "/":
        req.resp("index",
          data = %*{
            "meta": {
              "title": "Tim Engine is Awesome!"
            }
          })
      else:
        req.resp("error", code = Http404, data = %*{
          "meta": {
            "title": "Oh, you're a genius!",
            "msg": "Oh yes, yes. It's got action, it's got drama, it's got dance! Oh, it's going to be a hit hit hit!"
          }
        })
    else: req.send(Http501)

echo "Serving on http://localhost:8080"
let serverSettings = initSettings(Port(8080), numThreads = 1)
run(onRequest, serverSettings)
