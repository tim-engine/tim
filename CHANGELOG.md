# v0.2.6 - 2026-07-04

- **NEW**: Lexer gains `tkIs`/`tkIsNot` token kinds; parser recognizes them as infix operators (precedence 5, equal to `==`). Registered as stdlib foreign procs with Nim implementations that compare values at runtime by `TypeId`. Related to VanCode v0.2.0 - 2026-07-08
- **CHANGE:** Updated stdlib for VanCode v0.1.9 ValueStorage API — `Object.fields`
  changed from `seq[Value]` to `seq[ValueStorage]` (inline primitive storage).
  All field reads now use `.toValue`, all field writes use `.toStorage`:
  - `libarrays.nim` — `add`, `insert`, `join`, `contains`, `find`, `dedup`,
    `first`, `last` updated for `ValueStorage`
  - `libobjects.nim` — `add`, `insert`, `join`, `find`, `keys` updated
  - `libstrings.nim` — `split` result assignment updated
  - `libsystem.nim` — object `$` dump helper updated
  No functional changes — the engine continues to work unchanged.

- **NEW:** Element multiplication syntax: `tag*N` repeats an HTML element N times
  with an injected `$i` index variable (0-based).
  Example: `li*3: $items[$i]` produces 3 `<li>` elements
- **NEW:** `@import "std/..."` system: populated stdlibs table, fixed `libobjects.nim`
  syntax errors, switched `build.nim` to `initCompiler` for stdlibs pass-through
- **FIX:** Fixed `addCallable` KeyError in vancode when `exportFunctions` key
  is missing on overloaded function names
- **FIX:** Exported macros (`macro foo*`) now properly cross module boundaries
  via `exported = true` in `genMacro`
- **FIX:** `serve` command no longer hardcodes template paths — reads
  `compilation.source`, `compilation.output`, and subdirectory paths
  from `tim.config.yml`
- **NEW:** Exposed supranim Request API as foreign functions callable
  via `$this.getPath()`, `$this.getMethod()`, `$this.getQuery("key")`,
  `$this.getHeader("key")`, `$this.getBody()`, `$this.getIp()`,
  `$this.getUrl()`, `$this.getAgent()`, `$this.getParam("key")`

- **NEW:** `@static` compile-time evaluator for `for` loops and `if`/`elif`/`else`
  conditionals. The body is captured as raw text, `{$varName}` patterns are
  substituted with literal iteration values, then re-parsed by an inner parser.
  For loops unroll into the parent AST; conditionals select the matching branch
  at compile time. Both the lexer and parser were extended (`tkStatic`, `nkStatic`,
  `parseStaticStmt` rewrite, `parseScript` flattening of expanded nodes).
  Supports both literal arrays and `start..end` integer ranges
  (e.g., `@static for $x in 1..12:`).

# v0.2.6 - 2026-07-04

- **FIX**: fixed `source` and `output` fields in `tim.config.yml`
- **FIX**: `parseVarIdent` now handles generic type annotations (`var abc: array[string]`)
  by calling `parseGenericType` instead of leaving `[string]` unconsumed
- **NEW**: `CompilationPolicy` is now threaded from `engine.config.compilation.policy`
  into the codegen via `initCompiler`, enabling per-project feature restrictions
  (imports, stdlib, packages, loops, conditionals, assignments, dynamic libs)
- **NEW**: Ruby gem automation — `release.yml` now pushes platform-specific binaries
  (x86_64-darwin, arm64-darwin, x86_64-linux) to `openpeeps/tim-ruby` on tag releases
- **FIX**: `tim.nims` Ruby build now uses `pkg-config` on both macOS and Linux (was
  hardcoded to MacPorts paths)
- **FIX**: `tim.nimble` `plat` variable now detects Linux (`x86_64-linux`) in addition
  to macOS (`x86_64-darwin` / `arm64-darwin`)
- **FIX**: Removed hardcoded MacPorts paths from Clue's `ruby_api.nim` — uses
  project-level `pkg-config` instead