<p align="center">
  <img src="https://raw.githubusercontent.com/openpeeps/tim/main/.github/tim_logo.png" alt="Tim - Template Engine" width="120px" height="120px"><br>
  ⚡️ A high-performance templating engine & markup language<br>
  <strong>Fast</strong> • <strong>Compiled</strong> • <strong>Source-to-Source</strong> • <strong>Interpreter</strong><br>
</p>

<p align="center">
  <code>nimble install tim</code> / <code>npm install @openpeeps/tim</code>
</p>

<p align="center">
  <a href="https://openpeeps.github.io/tim/">API reference</a><br>
  <img src="https://github.com/tim-engine/tim/workflows/test/badge.svg" alt="Github Actions">  <img src="https://github.com/tim-engine/tim/workflows/docs/badge.svg" alt="Github Actions">
</p>

## About
This is Tim &bullet; Red Hiney &bullet; The Great Pantzini! &bullet; A powerful front-end engine designed to boost developer productivity. It combines a high-performance templating engine with a versatile micro programming language, enabling developers to create dynamic web applications with ease.

## Key features
- ⚡️ Fast, Compiled, Clean syntax
- Template engine with support for **layouts**, **partials** and **views**
- Source-to-Source transpilation to **Lua**, **Python**, **Ruby**, **JavaScript**, **PHP** and **Nim** lang
- **Standard Library** with many built-in utilities for web development
- 📦 **Built-in Package Manager** for easy installation of third-party packages
- 🔁 Built-in **Browser Sync & Reload**
- Built-in **HTTP Server** and WebSocket support
- Available natively as a **Node.js NAPI module**, **PHP extension**, **Python module**, **Ruby gem**, and **Lua rock**
- SPA Awareness with support for client-side routing and dynamic content updates
- 👑 Written in Nim language

## Syntax Overview
Here is a simple example of Tim Engine's syntax for creating a basic web page template:
```
var title = "Welcome to Tim Engine"
div.container > div.row > div.col-12
  h1.display-4.fw-bold: $title // passing variable to template
  p.lead: "Tim Engine is a powerful templating engine and scripting language for developers."
  a.btn.btn-primary.px-4.rounded-3
    href="https://example.com": "Get Started"
```

Find more about Tim's syntax and features here https://tim.openpeeps.dev/language/syntax

## Getting Started
To get started with Tim Engine, you can install it using Nimble, or download the latest release from GitHub. For detailed installation instructions and usage examples, please refer to the [Official Documentation](https://tim.openpeeps.dev/).

## Documentation
- [API Reference](https://openpeeps.github.io/tim/)
- [Official Documentation](https://tim.openpeeps.dev/)
- [Examples](https://github.com/openpeeps/tim/tree/main/examples)
- [Unit Tests](https://github.com/openpeeps/tim/tree/main/tests)

## CLI Application
Tim comes with a command-line interface application that wraps the core engine and provides a way to compile and run templates directly from the terminal. Additionally, the CLI app can be used to generate AST representation of templates, manage Tim packages using the built-in package manager and also use Tim Engine at runtime to serve templates via the built-in HTTP server. Crazy!

### Tim Runtime 
Use the built-in HTTP server to compile and serve templates at runtime. Basically, you can use Tim Engine as a web server to serve dynamic content. The HTTP server supports routing, middleware, and WebSocket connections.

### Source to Source transpilation

The CLI app supports source-to-source transpilation to multiple target languages: **Lua**, **Python**, **Ruby**, **JavaScript**, **PHP** and **Nim**. Note that all transpilation targets are currently in very early stages of development and may not yet be fully functional or stable.

> [!NOTE]
> The primary focus of the project is currently on the core templating engine and its features, with transpilation capabilities being developed incrementally over time.

## Tim as a native extension
Tim is written in Nim lang, this allows it to be compiled to a native extension for other programming languages. Currently, Tim Engine is available as a **Node.js NAPI module**, **PHP extension**, **Python module**, **Ruby gem**, and **Lua rock**. Check the [example directory](https://github.com/openpeeps/tim/tree/main/examples) for usage examples

> [!NOTE]
> The native extension support is still in early stages of development and may not yet be fully functional or stable. Publishing Tim via Package Registries for the supported languages is also a work in progress and may not yet be available for all target languages.

## Benchmarks

Showcasing Tim's virtual machine (VM) when executing pre-compiled templates. The benchmarks include various scenarios such as rendering HTML, dynamic data, conditionals, loops, and more.
```
Benchmark                           Iterations    Total (ms)    Mean (µs)       Ops/sec
─────────────────────────────────────────────────────────────────────────────────────
VM — static HTML                     10000        30.094         3.009       332289.
VM — dynamic data                    10000        39.361         3.936       254060.
VM — conditionals (true)             10000        22.154         2.215       451380.
VM — conditionals (false)            10000        22.737         2.274       439810.
VM — loops (10 items)                10000        68.805         6.880       145339.
VM — loops (1000 items)               1000       418.102       418.102         2392.
VM — string stdlib                   10000        23.358         2.336       428125.
VM — deep nesting                    10000        58.691         5.869       170384.
VM — mixed template                   5000       177.691        35.538        28139.
─────────────────────────────────────────────────────────────────────────────────────
```

While these benchmarks shows the full pipeline (lexing, parsing > ast > codegen > vm execution) for the same templates, which includes the overhead of parsing and code generation, it gives a more realistic picture of the overall performance of the engine when rendering templates without a prepared VM bytecode.
```
Benchmark                           Iterations    Total (ms)    Mean (µs)       Ops/sec
─────────────────────────────────────────────────────────────────────────────────────
Parsing — small                        10000        21.169         2.117       472396.
Parsing — complex                       5000       100.764        20.153        49621.
Full pipeline — static                  2000       607.031       303.515         3295.
Full pipeline — dynamic                 2000       627.298       313.649         3188.
Conditionals — true                     2000       609.800       304.900         3280.
Conditionals — false                    2000       610.486       305.243         3276.
Loops — 10 items                        1000       321.576       321.576         3110.
Loops — 1000 items                        50        37.672       753.439         1327.
String stdlib                           1000       303.507       303.507         3295.
Deep nesting                             500       161.140       322.281         3103.
Mixed template                           500       205.136       410.272         2437.
```

Now, let's run some HTTP server benchmarks to see how Tim performs when serving templates over HTTP. We'll use the `wrk` and `bombardier` tools to simulate concurrent requests and measure the throughput and latency of the server. We are going to use `tim.config.yml` available in the [/examples](https://github.com/tim-engine/tim/tree/main/examples) directory, which will load the `index.timl` + `base.timl` layout available at `/examples/templates/`.

1. wrk benchmark
```
Running 10s test @ http://localhost:8000
  2 threads and 125 connections
  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency     3.45ms  448.71us  23.88ms   99.22%
    Req/Sec    18.08k   375.10    18.62k    96.00%
  359749 requests in 10.00s, 2.27GB read
Requests/sec:  35969.58
Transfer/sec:    232.30MB
```

2. bombardier benchmark
```
Bombarding http://localhost:8000 for 10s using 125 connection(s)
Statistics        Avg      Stdev        Max
  Reqs/sec     36487.04    1624.69   38432.07
  Latency        3.42ms   352.59us    28.41ms
  HTTP codes:
    1xx - 0, 2xx - 364958, 3xx - 0, 4xx - 0, 5xx - 0
    others - 0
  Throughput:   237.78MB/s
```

Amazing! The built-in webserver is powered by [Supranim](https://github.com/supranim/supranim) using the [PowPow](https://github.com/openpeeps/powpow) backend.

## Changelog
This project uses [changer](https://github.com/iffy/changer) to manage its changelog. See the [CHANGELOG.md](./CHANGELOG.md) file for the release history.

## Roadmap 
- [ ] Update Tim Engine for Node.js runtime
- [ ] Build and publish Tim extension package for PHP, Lua, Python and Ruby

## Awesome Projects using Tim Engine
- [Sunday Publishing Platform](https://github.com/getsunday) - A modern, open-source publishing platform built with Tim Engine

### ❤ Contributions & Support
- 🐛 Found a bug? [Create a new Issue](https://github.com/openpeeps/tim/issues)
- 👋 Wanna help? [Fork it!](https://github.com/openpeeps/tim/fork)
- 🎉 Spread the word! **Tell your friends about Tim Engine**
- ⚽️ Play with Tim Engine in your next web-project

|  |  |
|---|---|
| <a href="https://opencode.ai/go?ref=BHMEEK48QX"><img src="https://github.com/openpeeps/pistachio/blob/main/.github/opencode.png" alt="OpenCode"></a> | Switch to **Open-Source LLMs** via OpenCode GO, choosing from a variety of powerful models such as DeepSeek, Qwen, Kimi, GLM-5, MiniMax, MiMo. 🍕 [Use our referral link to get started!](https://opencode.ai/go?ref=BHMEEK48QX)|

### 🎩 License
Tim Engine | `LGPLv3` license. [Made by Humans from OpenPeeps](https://github.com/openpeeps).<br>
Copyright &copy; 2026 OpenPeeps & Contributors &mdash; All rights reserved.
