# A super fast template engine for cool kids
#
# (c) 2024 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim
import std/tables
import pkg/[openparser/yaml, semver]
import pkg/vancode/manager/configurator

from std/net import Port, `$`

when not defined napibuild:
  import pkg/openparser/json

export `$`

type
  TargetSource* = enum
    ## The target source for template compilation,
    ## determining how templates are loaded and rendered
    tsNim    = "nim"
    tsJS     = "js"
    tsHtml   = "html"
    tsRuby   = "rb"
    tsPython = "py"

  BrowserSync* = ref object
    ## Configuration for browser synchronization during development,
    ## allowing for live-reloading of templates in the browser when changes are detected
    port*: Port
    delay*: uint # ms todo use jsony hooks + std/times

  # ConfigType* = enum
  #   ## The type of configuration being defined, which determines
  #   ## the structure of the TimConfig
  #   typeProject = "project"
  #   typePackage = "package"

  SourceType* = enum
    sourceFilesystem, sourceEmbedded

  EmbeddedTemplates* = TableRef[string, string]
    ## An alias for a simple in-memory template store, used when loading templates
    ## from embedded resources instead of the filesystem.

  WebServerConfig* = object
    port*: Port
    threads*: uint
    routes*: Table[string, string]

  CacheConfig* = ref object
    ## Configuration for the `fetch` response caching layer used
    ## by the `tim serve` development server
    enabled*: bool
      ## Whether response caching is enabled
    path*: string
      ## Directory (relative to the project base dir) where the cache
      ## store files live. Defaults to `cache`
    defaultTTL*: int
      ## Default time-to-live in seconds for cached responses.
      ## Can be overridden per-call via the `ttl` fetch option.
      ## Defaults to 3600 when zero

  TimConfig* = ref object
    ## The main configuration object for the Tim template engine
    name*: string
      ## Name of the package or project
      ## This must be a valid identifier
    version*: string
      ## The version of the package
    description*: string
      ## A short description of the package
    license*: string
      ## The license of the package
      ## See https://spdx.org/licenses/ for more information
    requires*: seq[string]
      ## A list of requirements for the package
      ## Each requirement must be a valid identifier
      ## and can be a version range, e.g. "tim >= 0.1.0"
    case `type`*: ConfigType
    of ConfigType.typeProject:
      compilation*: CompilationSettings
      browser_sync*: BrowserSync
      server*: WebServerConfig
      cache*: CacheConfig
    else: discard

when not defined napibuild:
  proc generateYaml*(c: TimConfig): string =
    ## Generate a YAML representation of the TimConfig
    ## This is used to generate the `tim.yml` file
    let str =
      if c.`type` == ConfigType.typePackage:
        json.toJson(c, JsonOptions(
          skipFields: @["type", "compilation", "browser_sync"]
        ))
      else:
        json.toJson(c)
    yaml.dump(json.fromJson(str))

  proc `$`*(c: TimConfig): string = 
    json.toJson(c)

proc getBasePath*(config: TimConfig): string =
  ## Get the base path for template loading based on the configuration
  return config.compilation.basePath

# FBE versioning — Tim supplies version to vancode/manager/fbe_ast via pkginfo
func semverToFbeVersion*(v: Version): uint32 =
  result = uint32(((v.major and 0xFF) shl 16) or ((v.minor and 0xFF) shl 8) or (v.patch and 0xFF))

# TimFbeVersion is computed in tim's main package file via pkginfo to avoid
# pkg().getVersion() issues in submodules; provide default for now
const TimFbeVersion* = 1'u32