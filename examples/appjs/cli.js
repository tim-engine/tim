const path = require('path')
const http = require('http')

const tim = require('@openpeeps/tim/uni')

let now = new Date()
let watchoutOpts = {
  enable: true,
  port: 6502,
  delay: 300,
}
tim.initGlobals({
  data: {
    watchout: watchoutOpts,
    year: now.getFullYear(),
    stylesheets: [
      {
        type: "stylesheet",
        src: "https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css"
      },
      {
        type: "preconnect",
        src: "https://fonts.googleapis.com"
      },
      {
        type: "preconnect",
        src: "https://fonts.gstatic.com"
      },
      {
        type: "stylesheet",
        src: "https://fonts.googleapis.com/css2?family=Inter:wght@100..900&display=swap"
      }
    ]
  },
  watchout: watchoutOpts
})

// tim.render("index", "base", {
//   meta: {
//     title: "Tim Engine is Awesome!"
//   },
//   path: "/"
// }).then((res) => console.log(res))

// Let's create a simple server using `std/http` module
const
  host = 'localhost'
  port = '3000'

http.createServer(
  async function(req, res) {
    res.setHeader('Content-Type', 'text/html')
    res.setHeader('charset', 'utf-8')
    if(req.url == '/') {
      res.writeHead(200)
      res.end(
        await tim.render("index", "base", {
          meta: {
            title: "Tim Engine is Awesome!"
          },
          path: req.url
        })
      )
    } else if(req.url == '/about') {
      res.writeHead(200)
      res.end(
        await tim.render("about", "secondary", {
          meta: {
            title: "Tim Engine is Awesome!"
          },
          path: req.url
        })
      )
    } else {
      res.writeHead(404)
      res.end(
        await tim.render("error", "base", {
          meta: {
            title: "Oh, you're a genius!",
            msg: "Oh yes, yes. It's got action, it's got drama, it's got dance! Oh, it's going to be a hit hit hit!"
          },
          path: req.url
        })
      )
    }
}).listen(port, host, () => {
  console.log(`Server is running on http://${host}:${port}`)
})
