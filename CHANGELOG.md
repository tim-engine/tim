# v0.2.7

### 2026-08-05

- **NEW**: TTL-based response caching for the `fetch` (libsystem) function in `tim serve`.
  Enabled via a `cache:` section in `tim.yml` (`enabled`, `path` defaults to `./cache`,
  `default_ttl` in seconds defaults to 3600). Responses are keyed by a deterministic
  name-based (v3, MD5) UUID derived from method/url/body and stored in a WAL-backed
  Boogie KV store; fresh entries within TTL are served without a network call. Per-call
  overrides in the fetch options: `ttl`, `refresh` (bypass read, still write),
  `noCache` (bypass read and write). Only successful (2xx) responses are cached. The
  cache is a no-op outside of `tim serve` (build, embedded, tests).

# v0.2.6

### 2026-07-27

- **NEW**: Emmet-style `input:TYPE` shorthand — `input:time`, `input:color`, `input:range`,
  etc. are parsed as `<input type="TYPE">` at the lexer/parser level. Distinguishes from
  tim's `:` text-content syntax by checking `wsno == 0` (no whitespace before colon).
  Only triggers on `tagInput`. Subsequent attributes (`.class`, `#id`) still apply.
- **NEW**: `svg` elements now auto-inject `xmlns="http://www.w3.org/2000/svg"` at parse time.
  Skips if the user explicitly provides `xmlns`.
- **FIX**: PHP Linux build — replaced `--passC: staticExec(...)` with `switch("passC", ...)`
  in `tim.nims` (staticExec returns literal text at compile-time, not the const value).
  Uses `php-config --include-dir` as primary header discovery on Linux (with pkg-config
  fallback).
- **FIX**: Clue hardcoded macOS pragmas — wrapped `{.passC:}`/`{.passL:}` in
  `php_api.nim`, `python_api.nim`, `lua_api.nim` inside `when defined(macosx):` to
  prevent MacPorts paths and `-framework CoreFoundation` from leaking into Linux builds.
- **FIX**: Docs workflow — added `permissions: contents: write` to allow
  `peaceiris/actions-gh-pages` to push the `gh-pages` branch (GITHUB_TOKEN defaults to
  read-only on newer repos).
- **NEW**: Ruby extension CI — `tim-ruby/.github/workflows/build.yml` builds the native
  extension via `repository_dispatch` (triggered from tim's release workflow). Builds
  for x86_64-darwin, arm64-darwin, and x86_64-linux sequentially, commits platform
  binaries to the tim-ruby repo.
- **NEW**: `@LitElement, ClassName, "tag-name"` — define Lit-like custom HTML elements
  in Tim. Body supports `@javascript` blocks (concatenated into the class body) and a
  single `@client` block (the render template compiled to JS template literals).
  Generates a JavaScript class extending `LitElement` with `connectedCallback`,
  `render()`, and `customElements.define()`. Client-side only; server-side rendering
  emits the class as a `<script>` block.

### 2026-07-04

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

# 2026-07-04

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