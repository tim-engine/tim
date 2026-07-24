--mm:atomicArc
--threads:on
--deepcopy:on
--define:ssl
--define:vancodeJit
--define:supraNative
--define:nimPreviewHashRef

when defined napibuild:
  --define:release

when defined php_build:
  --app:lib
  when defined(macosx):
    --passC:"-I/opt/local/include/php83/php -I/opt/local/include/php83/php/main -I/opt/local/include/php83/php/TSRM -I/opt/local/include/php83/php/Zend -I/opt/local/include/php83/php/ext -I/opt/local/include/php83/php/ext/date/lib -I/opt/local/include"
    --passL:"-Wl,-undefined,dynamic_lookup"
  when defined(linux):
    const phpCFlags = staticExec("php-config --include-dir 2>/dev/null | xargs -I{} echo -I{} -I{}/main -I{}/Zend -I{}/TSRM -I{}/ext -I{}/ext/date/lib || pkg-config --cflags --silence-errors php-embed 2>/dev/null || pkg-config --cflags --silence-errors php 2>/dev/null").strip()
    const phpLFlags = staticExec("pkg-config --libs --silence-errors php-embed 2>/dev/null || pkg-config --libs --silence-errors php 2>/dev/null").strip()
    if phpCFlags.len > 0:
      switch("passC", phpCFlags)
    if phpLFlags.len > 0:
      switch("passL", phpLFlags)

when defined ruby_build:
  --app:lib
  when defined(macosx) or defined(linux):
    const rubyCFlags = staticExec("ruby -rrbconfig -e 'puts \"-I#{RbConfig::CONFIG[\"rubyhdrdir\"]} -I#{RbConfig::CONFIG[\"rubyarchhdrdir\"]}\"' 2>/dev/null || pkg-config --cflags --silence-errors ruby-3.2 2>/dev/null || pkg-config --cflags --silence-errors ruby 2>/dev/null").strip()
    const rubyLFlags = staticExec("ruby -rrbconfig -e 'puts \"-L#{RbConfig::CONFIG[\"libdir\"]} -l#{RbConfig::CONFIG[\"RUBY_SO_NAME\"]}\"' 2>/dev/null || pkg-config --libs --silence-errors ruby-3.2 2>/dev/null || pkg-config --libs --silence-errors ruby 2>/dev/null").strip()
    if rubyCFlags.len > 0:
      switch("passC", rubyCFlags)
    if rubyLFlags.len > 0:
      switch("passL", rubyLFlags)
  when defined(macosx):
    --passL:"-Wl,-undefined,dynamic_lookup"

when defined python_build:
  --app:lib
  when defined(macosx):
    --passC:"-I/opt/local/Library/Frameworks/Python.framework/Versions/3.11/include/python3.11"
    --passL:"-L/opt/local/Library/Frameworks/Python.framework/Versions/3.11/lib/python3.11/config-3.11-darwin -lpython3.11 -ldl -framework CoreFoundation -Wl,-undefined,dynamic_lookup"
  when defined(linux):
    const pythonCFlags = staticExec("python3-config --includes 2>/dev/null || pkg-config --cflags --silence-errors python3-embed 2>/dev/null || pkg-config --cflags --silence-errors python3 2>/dev/null").strip()
    const pythonLFlags = staticExec("python3-config --ldflags 2>/dev/null || pkg-config --libs --silence-errors python3-embed 2>/dev/null || pkg-config --libs --silence-errors python3 2>/dev/null").strip()
    if pythonCFlags.len > 0:
      switch("passC", pythonCFlags)
    if pythonLFlags.len > 0:
      switch("passL", pythonLFlags)

when defined lua_build:
  --app:lib
  when defined(macosx):
    --passC:"-I/opt/local/include/luajit-2.1"
    --passL:"-L/opt/local/lib -lluajit-5.1 -Wl,-undefined,dynamic_lookup"
  when defined(linux):
    const luajitCFlags = staticExec("pkg-config --cflags --silence-errors luajit 2>/dev/null || pkg-config --cflags --silence-errors lua5.1 2>/dev/null").strip()
    const luajitLFlags = staticExec("pkg-config --libs --silence-errors luajit 2>/dev/null || pkg-config --libs --silence-errors lua5.1 2>/dev/null").strip()
    if luajitCFlags.len > 0:
      switch("passC", luajitCFlags)
    if luajitLFlags.len > 0:
      switch("passL", luajitLFlags)
