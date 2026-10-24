/**
 * Type definitions for @openpeeps/tim — Node.js native bindings for
 * Tim Engine (built with denim: `denim build src/tim.nim --cmake -y`).
 *
 * The package ships prebuilt binaries per platform/arch under
 * `bin/<platform>-<arch>/tim.node`; `index.js` selects the one
 * matching `process.platform`/`process.arch` at load time.
 *
 * Data passed to `render`/`renderView` may be a plain object (encoded
 * as JSON for you) or a JSON string. Inside templates it is available
 * as `$this`; engine-wide data is available as `$app`.
 */

/** Tim Engine template API (single engine instance per process). */
export namespace tim {
  /**
   * Initialize the engine from a project on disk and precompile all
   * templates. `src`/`output` resolve against `basepath`.
   * Must be called once before `render`/`renderView`.
   * Throws a JS `Error` when the project or a template fails to compile.
   */
  function init(src: string, output: string, basepath: string): boolean;
  /**
   * Render a view within a layout. `layout` defaults to `'base'`,
   * `data` defaults to `{}`. Returns the final HTML string.
   * Throws when the view/layout is missing or rendering fails.
   */
  function render(view: string, layout?: string, data?: unknown): string;
  /**
   * Render a view without a layout. `data` defaults to `{}`.
   * Returns the final HTML string.
   */
  function renderView(view: string, data?: unknown): string;
  /**
   * Engine version (read from `tim.nimble` at compile time).
   */
  function version(): string;
}

/** Filesystem path of the loaded `.node` binary. */
export const binaryPath: string;

/** The `<platform>-<arch>` pair that was loaded. */
export const nativePair: string;
