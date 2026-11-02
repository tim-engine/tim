import std/[strutils, os]
--mm:orc

when defined(wasm):
  static:
    when (NimMajor, NimMinor) != (2, 2):
      {.error: "The wasm build requires Nim 2.2.x (2.4.x fails with an injectdestructors assertion on this codebase). Use `choosenim 2.2.10`.".}
  # Browser playground: wasm32 via the WASI SDK clang (no Emscripten).
  # `--os:linux` (not standalone) so the full system — notably exception
  # handling — is available; all OS imports resolve against wasi-libc and
  # are satisfied by the JS WASI shim at instantiation. The engine itself
  # never touches the filesystem, network or clocks on this path
  # (see the `when not defined(wasm)` guards).
  # Set $WASI_SDK to override the default SDK location.
  switch("cpu", "wasm32")
  switch("os", "linux")
  switch("cc", "clang")
  const wasiSdk = getEnv("WASI_SDK",
    expandTilde("~/.local/share/wasi-sdk/wasi-sdk-34.0-x86_64-macos"))
  const wasiSysroot = wasiSdk / "share/wasi-sysroot"
  switch("clang.exe", wasiSdk / "bin/clang")
  switch("clang.linkerexe", wasiSdk / "bin/clang")
  switch("passC", "--sysroot=" & wasiSysroot &
    " -D_WASI_EMULATED_MMAN -D_WASI_EMULATED_SIGNAL")
  switch("passL", "--sysroot=" & wasiSysroot &
    " -lwasi-emulated-mman -lwasi-emulated-signal" &
    " -nostartfiles -Wl,--no-entry -Wl,--gc-sections" &
    " -Wl,--export=NimMain -Wl,--export=__wasm_call_ctors" &
    " -Wl,--export=timAlloc -Wl,--export=timFree" &
    " -Wl,--export=timResultPtr -Wl,--export=timResultLen" &
    " -Wl,--export=timRender -Wl,--export=timRenderView" &
    " -Wl,--export=timTranspile -Wl,--export=timVersionInfo" &
    " -Wl,--export=timDebugTag")
  switch("define", "openparserNoMmap")
  --threads:off
  --deepcopy:on
  --define:useMalloc
  --define:release
else:
  --threads:on
  --deepcopy:on
  --define:ssl
  --define:nimPreviewHashRef

  when defined napibuild:
    --define:release

# Search paths for the `cli` feature deps (boogie, bag, supranim, ...).
#
# `denim build` shells out to raw `nim c`, bypassing clue/nimble
# resolution entirely — and denim's `--defines` flag is only forwarded
# to the C build (cmake-js), never to `nim c`, so a define like
# `-d:features.tim.cli` alone can never make `pkg/boogie/...` resolve
# (the NAPI entry pulls `meta/cache` -> boogie via `libsystem`).
# Instead, mirror the feature-resolved paths from `clue.lock` here;
# `clue.lock` itself is produced with the `cli` feature enabled.
const clueLock = currentSourcePath().parentDir() / ".." / "clue.lock"
if fileExists(clueLock):
  # NOTE: do NOT use std/json parseJson here. Nim 2.4.0 crashes in
  # injectdestructors when compiling a parseJson call inside a .nims
  # (NimScript/VM path, both --mm:arc and --mm:orc). Manual scan instead.
  let content = readFile(clueLock)
  var i = 0
  while true:
    let k = content.find("\"path\"", i)
    if k < 0: break
    var c = k + 6
    while c < content.len and (content[c] == ' ' or content[c] == ':' or
        content[c] == '\t' or content[c] == '\r' or content[c] == '\n'):
      inc c
    if c < content.len and content[c] == '"':
      var e = c + 1
      while e < content.len and content[e] != '"': inc e
      let p = content[c + 1 ..< e]
      if p.len > 0 and dirExists(p):
        switch("path", p)
      i = e + 1
    else:
      i = c + 1

# when defined php_build:
#   --app:lib
#   when defined(macosx):
#     --passC:"-I/opt/local/include/php83/php -I/opt/local/include/php83/php/main -I/opt/local/include/php83/php/TSRM -I/opt/local/include/php83/php/Zend -I/opt/local/include/php83/php/ext -I/opt/local/include/php83/php/ext/date/lib -I/opt/local/include"
#     --passL:"-Wl,-undefined,dynamic_lookup"
#   when defined(linux):
#     const phpCFlags = staticExec("php-config --include-dir 2>/dev/null | xargs -I{} echo -I{} -I{}/main -I{}/Zend -I{}/TSRM -I{}/ext -I{}/ext/date/lib || pkg-config --cflags --silence-errors php-embed 2>/dev/null || pkg-config --cflags --silence-errors php 2>/dev/null").strip()
#     const phpLFlags = staticExec("pkg-config --libs --silence-errors php-embed 2>/dev/null || pkg-config --libs --silence-errors php 2>/dev/null").strip()
#     if phpCFlags.len > 0:
#       switch("passC", phpCFlags)
#     if phpLFlags.len > 0:
#       switch("passL", phpLFlags)

# when defined ruby_build:
#   --app:lib
#   when defined(macosx) or defined(linux):
#     const rubyCFlags = staticExec("ruby -rrbconfig -e 'puts \"-I#{RbConfig::CONFIG[\"rubyhdrdir\"]} -I#{RbConfig::CONFIG[\"rubyarchhdrdir\"]}\"' 2>/dev/null || pkg-config --cflags --silence-errors ruby-3.2 2>/dev/null || pkg-config --cflags --silence-errors ruby 2>/dev/null").strip()
#     const rubyLFlags = staticExec("ruby -rrbconfig -e 'puts \"-L#{RbConfig::CONFIG[\"libdir\"]} -l#{RbConfig::CONFIG[\"RUBY_SO_NAME\"]}\"' 2>/dev/null || pkg-config --libs --silence-errors ruby-3.2 2>/dev/null || pkg-config --libs --silence-errors ruby 2>/dev/null").strip()
#     if rubyCFlags.len > 0:
#       switch("passC", rubyCFlags)
#     if rubyLFlags.len > 0:
#       switch("passL", rubyLFlags)
#   when defined(macosx):
#     --passL:"-Wl,-undefined,dynamic_lookup"

# when defined python_build:
#   --app:lib
#   when defined(macosx):
#     --passC:"-I/opt/local/Library/Frameworks/Python.framework/Versions/3.11/include/python3.11"
#     --passL:"-L/opt/local/Library/Frameworks/Python.framework/Versions/3.11/lib/python3.11/config-3.11-darwin -lpython3.11 -ldl -framework CoreFoundation -Wl,-undefined,dynamic_lookup"
#   when defined(linux):
#     const pythonCFlags = staticExec("python3-config --includes 2>/dev/null || pkg-config --cflags --silence-errors python3-embed 2>/dev/null || pkg-config --cflags --silence-errors python3 2>/dev/null").strip()
#     const pythonLFlags = staticExec("python3-config --ldflags 2>/dev/null || pkg-config --libs --silence-errors python3-embed 2>/dev/null || pkg-config --libs --silence-errors python3 2>/dev/null").strip()
#     if pythonCFlags.len > 0:
#       switch("passC", pythonCFlags)
#     if pythonLFlags.len > 0:
#       switch("passL", pythonLFlags)

# when defined lua_build:
#   --app:lib
#   when defined(macosx):
#     --passC:"-I/opt/local/include/luajit-2.1"
#     --passL:"-L/opt/local/lib -lluajit-5.1 -Wl,-undefined,dynamic_lookup"
#   when defined(linux):
#     const luajitCFlags = staticExec("pkg-config --cflags --silence-errors luajit 2>/dev/null || pkg-config --cflags --silence-errors lua5.1 2>/dev/null").strip()
#     const luajitLFlags = staticExec("pkg-config --libs --silence-errors luajit 2>/dev/null || pkg-config --libs --silence-errors lua5.1 2>/dev/null").strip()
#     if luajitCFlags.len > 0:
#       switch("passC", luajitCFlags)
#     if luajitLFlags.len > 0:
#       switch("passL", luajitLFlags)
