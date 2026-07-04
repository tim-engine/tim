# Tim Template Language — Syntax Reference

Tim is an indentation-based DSL front-end engine. HTML tags are written **without angle brackets** (`<`/`>`). The syntax blends Emmet-style shorthands, Pug-like nesting, and a Nim-inspired scripting language.

---

## 1. HTML Tags

### Basic element
```timl
div
h1
br
```

### Classes via `.`
```timl
div.container
a.btn.btn-primary.btn-lg
h1.display-4.fw-bold
```

### ID via `#`
```timl
div#main
a#my-link.btn
```

### Void (self-closing) elements
Automatically rendered without closing tag: `area`, `base`, `br`, `col`, `embed`, `hr`, `img`, `input`, `link`, `meta`, `param`, `source`, `track`, `wbr`, `command`, `keygen`, `frame`.

### Custom tags
Any unrecognized tag name is rendered as-is.

---

## 2. Nesting

### Inline nesting with `>`
Children on the same line:
```timl
div.container > div.row > div.col-12
```
```html
<div class="container"><div class="row"><div class="col-12"></div></div></div>
```

Also works with macros:
```timl
@container() > @row() > @col()
```

### Multi-line indentation nesting
Children are indented deeper than their parent:
```timl
div.container
  h1: "Title"
  p: "Paragraph"
```
```html
<div class="container"><h1>Title</h1><p>Paragraph</p></div>
```

---

## 3. Attributes

### Key=value
```timl
a href="https://example.com" target="_blank": "Link"
img src="logo.png" alt="Logo"
```

### Boolean (no value)
```timl
input disabled
hr noshade
```

### Dynamic via `$var`
```timl
a href=$url: "Link"
div class=$myClass
```

### Multi-line continuation
```timl
a.btn.btn-primary.px-4.rounded-3
  href="https://example.com": "Get Started"
```

### Class merging
Dot-shorthand classes merge with `class="..."` attribute.

---

## 4. Content / Text

### Colon syntax
```timl
h1: "Hello World!"
p.lead: "This is a lead paragraph."
```

### Bare string on its own line
```timl
div.container
  "Tim Engine is Awesome!"
```

### Expression embedding
```timl
p: "Hello, " & $this["name"] & "!"
p: $x + $y
```

### Script minification
When `script:` is followed by content, JS is automatically minified:
```timl
script: """
function hello() { return "world"; }
"""
```

---

## 5. Variable References (`$`)

Variables must be prefixed with `$` to distinguish them from HTML tags:
```timl
p: $name           <!-- render variable `name` -->
p: $title
```

### Built-in context variables
- `$this` — local view data (JSON object passed at render time)
- `$app` — global application data
- `$this["key"]` — bracket access into local data
- `$app["key"]` — bracket access into global data

---

## 6. Variable Definitions

### `var` (mutable)
```timl
var name: string
var title = "Welcome"
var x: int = 42
var a, b: string
```

### `const` (immutable)
```timl
const version = "1.0.0"
const pi = 3.14159
```

### Exported with `*`
```timl
var name* = "Public"
```

---

## 7. Control Flow

### `if` / `elif` / `else`
```timl
if $this["isLoggedIn"] == true:
  p: "Welcome back!"
elif $this["isAdmin"] == true:
  p: "Welcome admin!"
else:
  p: "Please log in."
```

### `for` loops
Iterating over an array:
```timl
for $item in $items:
  li: $item
```

Range:
```timl
for $i in 0..2:
  li: "Item " & $i
```

Object key-value:
```timl
for $key, $value in $person:
  echo $key & ": " & $value
```

### `while` loop
```timl
var count = 0
while $count < 5:
  p: "Count is " & $count
  inc($count)
```

### `break` / `continue`
```timl
for $i in 0..10:
  if $i == 5:
    break
  if $i % 2 == 0:
    continue
  p: $i
```

---

## 8. Functions

### Declaration
```timl
fn greet(name: string): string =
  return "Hello, " & $name & "!"
```

### Curly brace body
```timl
func greet(name: string): string {
  return "Hello, " & $name & "!"
}
```

### Named arguments
```timl
echo greet(name="Tim", age=30)
```

### `return` / `yield`
```timl
return "value"
yield($value)
```

### Iterator
```timl
iterator myRange(min: int, max: int): int {
  var i = $min
  while $i <= $max:
    yield($i)
    inc($i)
}
```

---

## 9. Macros

### Definition
```timl
macro PrimaryButton(label: string, url: string) =
  a.btn.btn-primary title=$label href=$url: $label
```

### Call with `@`
```timl
@PrimaryButton("Click Me", "https://example.com")
```

### Curly brace body
```timl
macro Card(title: string, content: string) {
  div.card
    div.card-header: $title
    div.card-body: $content
}
```

### Trailing block via `@statement`
```timl
macro col(width: int) =
  div.col-lg-$($width):
    @statement

@col(6):
  p: "Content inside the column."
```

### Exported (public) with `*`
```timl
macro myComponent*() =
  div: "Public!"
```

---

## 10. Element Multiplication

Repeat an element N times using `*N` after the tag:
```timl
li*5: "Item"
div.col*3: "Cell"
```
Produces 5 `<li>` / 3 `<div>` elements. An implicit `$i` variable (0-based) is injected inside the loop.

---

## 11. Imports & Includes

```timl
@import "utils"
@import "../some/other/utils"
@import "std/math"
@import "pkg/bootstrap/grid"
@include "partials/header"
```

Multi-import:
```timl
@import { "module1", "module2" }
```

The stdlib path (`std/...`) imports built-in modules (system, strings, arrays, json, objects).

---

## 12. Directives

### `@javascript` / `@css` — with minification
```timl
@javascript
  console.log("Hello, World!")
@end

@css
  body { color: red; }
@end
```

### `@html` — raw HTML (no escaping)
```timl
@html
  <custom>raw html here</custom>
@end
```

### `@view` — layout placeholder
```timl
body
  div.container
    @view
```

### `@client` — SPA-aware block
```timl
@client
  // client-side only content
@end
```

### `static` block
```timl
static
  p: "This is static content"
```

---

## 13. Comments

### Single-line `//`
```timl
// This is a comment
div.container  // inline comment
```

### Block `/* */`
```timl
/*
  Documentation comment
  Transpiled to HTML <!-- comment -->
*/
```

### HTML `<!-- -->`
```timl
<!-- This appears in output -->
```

### `@doc`
```timl
@doc This is a doc comment
```

---

## 14. Data Types & Literals

| Type | Example |
|---|---|
| `string` | `"hello"`, `'hello'`, `` `hello` ``, `"""raw"""` |
| `int` | `42`, `-5` |
| `float` | `3.14`, `-0.5` |
| `bool` | `true`, `false` |
| `nil` | `nil` |
| `array` | `[1, 2, 3]` |
| `object` | `{name: "Alice", age: 30}` |

### String variants
- **Double-quoted** `"..."` — escape sequences (`\n`, `\r`, `\t`, `\"`, `\\`, `\0`), multi-line allowed
- **Single-quoted** `'...'` — single-line only
- **Backtick** `` `...` `` — template interpolation with `${expr}`
- **Triple-quoted** `"""..."""` — raw text, no escaping needed, multi-line

### Type definition
```timl
type MyObject = object
  name: string
  age: int
```

Generic annotation:
```timl
var list: array[int]
var dict: array[object] = {key: "value"}
```

---

## 15. Operators & Precedence (highest first)

| Prec | Operators | Assoc |
|---|---|---|
| 45 | `.` (dot access) | Left |
| 40 | `[` (bracket access) | Left |
| 20 | `*`, `/` | Left |
| 10 | `+`, `-` | Left |
| 6 | `&` (concat) | Left |
| 5 | `==`, `!=`, `>`, `<`, `>=`, `<=` | Left |
| 3 | `and`, `&&` | Left |
| 2 | `or`, `||` | Left |
| 1 | `=` (assignment) | Right |

Range `..` is parsed as an iterator call.

---

## 16. Standard Library

### `std/system` (auto-imported)
`type`, `abs`, `min`, `max`, `round`, `floor`, `ceil`, `sqrt`, `toBool`, `toInt`, `toFloat`, `toString`, `parseInt`, `parseFloat`, `intVal`, `strVal`, `escape`, `unescape`, `len`, `high`, `hasKey`, `parseJSON`, `loadJSON`, `remoteJSON`, `writeFile`, `readFile`, `sleep`.

### `std/strings`
`contains`, `startsWith`, `endsWith`, `toUpper`, `toLower`, `strip`, `split`, `replace`, `repeat`, `capitalize`, `count`, `isAlphaNumeric`, `isDigit`, `encode`, `decode`.

### `std/arrays`
`add`, `insert`, `delete`, `contains`, `find`, `isEmpty`, `first`, `last`, `reverse`, `dedup`, `join`.

### `std/objects`
Dot property access, iteration via `for $key, $value in $obj`.

### `std/json`
`keys`, `values`, `pretty`, `get`, `jsonType`.

---

## 17. Complete Example

```timl
div.row.align-items-center.vh-100 > div.col-lg-10.mx-auto
  h3.h6.text-uppercase href="/" class="text-decoration-none": "&mdash; The Lord of All Space-mud!"
  h1.display-4.fw-bold: "A super fast front-end engine for cool kids!"
  p.mb-3.fw-light.lead: "Tim is a high-performance DSL front-end engine..."
  div.d-grid.gap-4.d-md-flex.justify-content-md-start
    a href="https://tim.openpeeps.dev" class="btn btn-lg rounded-4 btn-outline-light border-2 rounded-3 px-4"
      "Check documentation"
    a href="https://github.com/openpeeps/tim" class="btn btn-lg rounded-4 btn-danger border-2 rounded-3 px-4"
      "Check Tim on GitHub"
```

## 18. Reserved Keywords

```
if, elif, else, for, while, in, and, or, var, const,
fn, func, macro, iterator, return, yield, break, continue,
echo, type, object, nil, true, false, case, of, discard,
static, import, include, component
```

`@`-prefixed: `@import`, `@include`, `@javascript`, `@css`, `@html`, `@yaml`, `@json`, `@md`, `@view`, `@client`, `@end`, `@doc`.
