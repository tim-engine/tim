# v0.2.5 - 2026-07-03

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

# v0.2.6 - 2026-07-04

- **FIX**: fixed `source` and `output` fields in `tim.config.yml`
- **FIX**: `parseVarIdent` now handles generic type annotations (`var abc: array[string]`)
  by calling `parseGenericType` instead of leaving `[string]` unconsumed
- **NEW**: `CompilationPolicy` is now threaded from `engine.config.compilation.policy`
  into the codegen via `initCompiler`, enabling per-project feature restrictions
  (imports, stdlib, packages, loops, conditionals, assignments, dynamic libs)