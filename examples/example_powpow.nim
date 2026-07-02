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

import pkg/powpow

let server = newHttpServer()

proc resp(req: HttpRequest, res: HttpResponse, view: string,
          layout = "base", code = Http200, data = newJObject()) =
  data["path"] = %*(req.getPath())
  let htmlOutput = timEngine.render(view, layout, data = data)
  res.status(code)
     .header("Content-Type", "text/html; charset=utf-8")
     .send(htmlOutput)

proc onRequest(req: HttpRequest, res: HttpResponse) =
  {.gcsafe.}:
    let meth = req.getMethod()
    let path = req.getPath()

    case meth:
      of HttpGet:
        if path == "/":
          res.status(Http200)
             .header("Content-Type", "text/html; charset=utf-8")
             .send(timEngine.render("index", "base", data = %*{
               "meta": {
                 "title": "Tim Engine is Awesome!"
               }
             }))
        else:
          res.status(Http404)
             .header("Content-Type", "text/html; charset=utf-8")
             .send(timEngine.render("error", "base", data = %*{
               "meta": {
                 "title": "Oh, you're a genius!",
                 "msg": "Oh yes, yes. It's got action, it's got drama, it's got dance! Oh, it's going to be a hit hit hit!"
               }
             }))
      else:
        res.status(Http501)


server.start(onRequest, Port(8080))