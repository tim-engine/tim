'use strict';
// Main entry for the tim native addon.
//
// This package ships prebuilt `.node` binaries per platform/arch under
// `bin/<platform>-<arch>/tim.node` (populated by `npm run build` on
// each host — native addons cannot be cross-compiled). At load time
// the binary matching `process.platform`/`process.arch` is selected.
//
// A repository checkout fallback (`../../bin/tim.node`, produced
// by running `denim build src/tim.nim --cmake -y` at the repo
// root) keeps the developer flow working without packing binaries.
//
// The native module exposes a single `tim` namespace, so this wrapper:
// selects the binary, then exposes ergonomic helpers with defaults
// (`layout = 'base'`, `data = {}` — objects are JSON-encoded for you).

const fs = require('fs');
const path = require('path');

const SUPPORTED = {
  darwin: ['arm64', 'x64'],
  linux: ['arm64', 'x64'],
};

function candidates() {
  const list = [];
  const pair = `${process.platform}-${process.arch}`;
  list.push(path.join(__dirname, 'bin', pair, 'tim.node'));
  // Developer fallback: repo-root build output (not shipped in the
  // published tarball, see package.json `files`).
  list.push(path.join(__dirname, '..', '..', 'bin', 'tim.node'));
  return { list, pair };
}

let loaded = null;
let loadedFrom = null;
const { list, pair } = candidates();
for (const p of list) {
  if (fs.existsSync(p)) {
    loadedFrom = p;
    loaded = require(p);
    break;
  }
}

if (loaded === null) {
  const supported = Object.entries(SUPPORTED)
    .map(([plat, archs]) => archs.map((a) => `${plat}-${a}`).join(', '))
    .join(', ');
  throw new Error(
    `tim-napi: no prebuilt binary for ${pair} and no dev fallback found. Tried:\n` +
      list.join('\n') +
      `\nSupported: ${supported}.\n` +
      'Build it with `npm run build` on the target host ' +
      '(requires Nim, clue, denim and cmake-js).'
  );
}

const native = loaded.tim;
if (native === undefined) {
  throw new Error(
    'tim-napi: loaded binary does not expose the `tim` namespace ' +
      `(${loadedFrom}). Rebuild it with \`npm run build\`.`
  );
}

function encodeData(data) {
  if (data === undefined || data === null) return '{}';
  if (typeof data === 'string') return data.length > 0 ? data : '{}';
  return JSON.stringify(data);
}

/** Filesystem path of the loaded `.node` binary. */
const binaryPath = loadedFrom;
/** The `<platform>-<arch>` pair that was loaded. */
const nativePair = pair;

const tim = {
  /**
   * Initialize the engine from a project on disk and precompile it.
   * `src`/`output` resolve against `basepath`. Must be called once
   * before `render`/`renderView`. Returns `true` on success.
   */
  init: (src, output, basepath) => native.init(src, output, basepath),
  /**
   * Render a view within a layout. `data` (object or JSON string,
   * default `{}`) is exposed to templates as `$this`.
   */
  render: (view, layout = 'base', data = {}) =>
    native.render(view, layout, encodeData(data)),
  /**
   * Render a view without a layout. `data` (object or JSON string,
   * default `{}`) is exposed to the template as `$this`.
   */
  renderView: (view, data = {}) => native.renderView(view, encodeData(data)),
  /** Engine version (read from `tim.nimble` at compile time). */
  version: () => native.version(),
};

module.exports = { tim, binaryPath, nativePair };
