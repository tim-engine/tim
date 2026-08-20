# Package

version       = "0.2.8"
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

requires "kapsis >= 0.3.3"
requires "vancode >= 0.2.5"
requires "flatty >= 0.4.0"
requires "checksums >= 0.2.2"
requires "voodoo >= 0.2.0"
requires "watchout >= 0.2.2"
requires "openparser >= 0.2.0"
requires "semver >= 1.2.3"

requires "bag >= 0.1.0"
requires "boogie >= 0.1.2"
requires "supranim >= 0.1.9[powpow]"

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
  exec "nim c -d:php_build -d:release -o:build/tim_php.so src/tim.nim"

task ruby, "build Ruby extension":
  exec "nim c -d:ruby_build -d:release -o:build/Tim.bundle src/tim.nim"

task python, "build Python extension":
  exec "nim c -d:python_build -d:release -o:build/tim.so src/tim.nim"

task lua, "build Lua extension":
  exec "nim c -d:lua_build -d:release -o:build/tim.so src/tim.nim"

import std/os
task build_examples, "build examples":
  for e in walkDir(currentSourcePath().parentDir / "example"):
    let x = e.path.splitFile
    if x.name.startsWith("example_") and x.ext == ".nim" and not x.name.startsWith("!"):
      exec "nim c -d:timHotCode --threads:on --deepcopy:on --mm:arc -o:./example/" & x.name & " example/" & x.name & x.ext
