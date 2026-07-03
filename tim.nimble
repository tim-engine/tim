# Package

version       = "0.2.5"
author        = "OpenPeeps"
description   = "A super fast template engine for cool kids!"
license       = "LGPL-3.0-or-later"
srcDir        = "src"
skipDirs      = @["example", "editors", "bindings"]
installExt    = @["nim"]
bin           = @["tim"]
binDir        = "bin"

# Dependencies

requires "nim >= 2.0.0"

requires "kapsis >= 0.3.3"
requires "vancode >= 0.1.2"
requires "flatty >= 0.4.0"
requires "checksums >= 0.2.2"
requires "voodoo >= 0.1.9"
requires "watchout >= 0.2.2"
requires "openparser >= 0.1.2"
requires "semver >= 1.2.3"

requires "supranim >= 0.1.1"
requires "powpow >= 0.1.0"
requires "clue#head"
requires "bag >= 0.1.0"

let arch = staticExec("uname -m").strip()
let plat = arch & "-darwin"

task napi, "build a dev version":
  exec "denim build src/tim.nim --cmake -y"

task devlog, "build a dev version":
  exec "nimble build --mm:arc -d:hayaVmWriteStackOps -d:hayaVmWritePcFlow -d:timLogCodeGen -d:useMalloc"

task php, "build PHP extension":
  exec "nimble build -d:php_build -d:release && cp bin/tim build/tim_php.so && cp build/tim_php.so packages/php/tim_php-" & plat & ".so"

task ruby, "build Ruby extension":
  exec "nimble build -d:ruby_build -d:release && cp bin/tim build/Tim.bundle && cp build/Tim.bundle packages/ruby/lib/tim_engine-" & plat & ".bundle"

task python, "build Python extension":
  exec "nimble build -d:python_build -d:release && cp bin/tim build/tim.so && cp build/tim.so packages/python/tim/_tim-" & plat & ".so"

task lua, "build Lua extension":
  exec "nimble build -d:lua_build -d:release && cp bin/tim build/tim.so && cp build/tim.so packages/lua/src/tim-" & plat & ".so && cp build/tim.so packages/lua/src/tim.so"

import std/os
task build_examples, "build examples":
  for e in walkDir(currentSourcePath().parentDir / "example"):
    let x = e.path.splitFile
    if x.name.startsWith("example_") and x.ext == ".nim" and not x.name.startsWith("!"):
      exec "nim c -d:timHotCode --threads:on --deepcopy:on --mm:arc -o:./example/" & x.name & " example/" & x.name & x.ext
