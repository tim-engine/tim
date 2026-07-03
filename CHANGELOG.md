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
