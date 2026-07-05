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
    --passC: staticExec("pkg-config --cflags --silence-errors php-embed 2>/dev/null || pkg-config --cflags --silence-errors php")
    --passL: staticExec("pkg-config --libs --silence-errors php-embed 2>/dev/null || pkg-config --libs --silence-errors php")

when defined ruby_build:
  --app:lib
  when defined(macosx) or defined(linux):
    --passC: staticExec("pkg-config --cflags --silence-errors ruby-3.2 2>/dev/null || pkg-config --cflags --silence-errors ruby")
    --passL: staticExec("pkg-config --libs --silence-errors ruby-3.2 2>/dev/null || pkg-config --libs --silence-errors ruby")
  when defined(macosx):
    --passL:"-Wl,-undefined,dynamic_lookup"

when defined python_build:
  --app:lib
  when defined(macosx):
    --passC:"-I/opt/local/Library/Frameworks/Python.framework/Versions/3.11/include/python3.11"
    --passL:"-L/opt/local/Library/Frameworks/Python.framework/Versions/3.11/lib/python3.11/config-3.11-darwin -lpython3.11 -ldl -framework CoreFoundation -Wl,-undefined,dynamic_lookup"
  when defined(linux):
    --passC: staticExec("pkg-config --cflags --silence-errors python3-embed 2>/dev/null || pkg-config --cflags --silence-errors python3")
    --passL: staticExec("pkg-config --libs --silence-errors python3-embed 2>/dev/null || pkg-config --libs --silence-errors python3")

when defined lua_build:
  --app:lib
  when defined(macosx):
    --passC:"-I/opt/local/include/luajit-2.1"
    --passL:"-L/opt/local/lib -lluajit-5.1 -Wl,-undefined,dynamic_lookup"
  when defined(linux):
    --passC: staticExec("pkg-config --cflags --silence-errors luajit 2>/dev/null || pkg-config --cflags --silence-errors lua5.1")
    --passL: staticExec("pkg-config --libs --silence-errors luajit 2>/dev/null || pkg-config --libs --silence-errors lua5.1")
