# Package

version       = "0.2.10"
author        = "OpenPeeps"
description   = "A super fast template engine for cool kids!"
license       = "LGPL-3.0-or-later"
srcDir        = "src"
skipDirs      = @["example", "editors", "bindings"]
installExt    = @["nim"]
installDirs   = @["tim"]
bin           = @["tim"]
binDir        = "bin"

# Dependencies

requires "nim >= 2.2.10"

requires "datpkgr >= 0.1.12"
requires "vancode >= 0.3.2"
requires "checksums >= 0.2.2"
requires "voodoo >= 0.2.1"
requires "watchout >= 0.3.2"
requires "openparser >= 0.4.2"
requires "semver >= 1.2.3"
requires "nimcypher >= 0.2.5"

feature "cli":
  requires "bag >= 0.1.0"
  requires "boogie >= 0.2.1"
  requires "supranim >= 0.1.11"

let arch = staticExec("uname -m").strip()
when defined(linux):
  let plat = arch & "-linux"
elif defined(macosx):
  let plat = arch & "-darwin"
else:
  let plat = arch

task napi, "build a dev version":
  exec "denim build src/tim.nim --cmake -y"

task php, "build PHP extension":
  exec "clue build -d:php_build -d:release -o:build/tim_php.so src/tim.nim"

task ruby, "build Ruby extension":
  exec "clue build -d:ruby_build -d:release -o:build/Tim.bundle src/tim.nim"

task python, "build Python extension":
  exec "clue build -d:python_build -d:release -o:build/tim.so src/tim.nim"

task lua, "build Lua extension":
  exec "clue build -d:lua_build -d:release -o:build/tim.so src/tim.nim"

task wasm, "build Tim for browsers (wasm32-standalone, no backend needed)":
  exec "clue build -d:wasm -o:build/tim.wasm src/tim.nim && cp build/tim.wasm examples/wasm/tim.wasm && cp bindings/wasm/tim.js examples/wasm/tim.js"

import std/os
task build_examples, "build examples":
  for e in walkDir(currentSourcePath().parentDir / "example"):
    let x = e.path.splitFile
    if x.name.startsWith("example_") and x.ext == ".nim" and not x.name.startsWith("!"):
      exec "clue build -d:timHotCode --threads:on --deepcopy:on --mm:arc -o:./example/" & x.name & " example/" & x.name & x.ext
