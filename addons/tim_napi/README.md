<p align="center">
  <img src="https://raw.githubusercontent.com/openpeeps/tim/main/.github/timengine.png" alt="Tim - Template Engine" width="200px" height="200px"><br>
  ⚡️ A high-performance template engine & markup language<br>
  <strong>Fast</strong> • <strong>Compiled</strong> • Written in Nim 👑
</p>

<p align="center">
  <code>npm install @openpeeps/tim</code>
</p>

## Quick example

```js
const { tim } = require('@openpeeps/tim');

tim.init('templates', 'output', __dirname);
const html = tim.render('index', 'base', { name: 'Node' });
console.log(html);
```

With a layout at `templates/layouts/base.timl` (containing `@view`)
and a view at `templates/views/index.timl`:

```timl
h1: "Hello, " & $this["name"] & "!"
```

`data` (object or JSON string) is exposed to templates as `$this`.
`renderView(view, data)` renders without a layout,
`version()` returns the engine version.

`init` must be called once before rendering; missing views/layouts,
bad JSON data and template errors surface as JS `Error`s.

## API reference

- `tim.init(src, output, basepath): boolean` — init + precompile
- `tim.render(view, layout = 'base', data = {}): string`
- `tim.renderView(view, data = {}): string`
- `tim.version(): string`

## Key features

- Fast, compiled, easy to code
- Caching & Pre-compilation
- Transpiles to JavaScript for Client-Side Rendering
- Supports embeddable code `json`, `js`, `yaml`, `css`
- Built-in Browser Sync & Reload
- Output Minifier
- Written in Nim language 👑

### ❤ Contributions & Support

- 🐛 Found a bug? [Create a new Issue](https://github.com/openpeeps/tim/issues)
- 👋 Wanna help? [Fork it!](https://github.com/openpeeps/tim/fork)

### 🎩 License

Tim Engine | `LGPLv3` license. [Made by Humans from OpenPeeps](https://github.com/openpeeps).<br>
Copyright &copy; 2024 OpenPeeps & Contributors &mdash; All rights reserved.
