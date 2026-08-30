# Tim - facade over datpkgr (app-agnostic library)
#
# (c) 2026 George Lemon | MIT License
# Made by Humans from OpenPeeps

import std/[os, options]
import pkg/boogie/stores/rdbms
import pkg/openparser/json
import datpkgr/config as datpkgrConfig
import datpkgr/types as datpkgrTypes
import datpkgr/store as datpkgrStore
import ./timparser as timParser

export rdbms
export datpkgrTypes
export datpkgrConfig

var timCfgImpl: DatpkgrConfig

proc getTimCfg*(): DatpkgrConfig =
  if timCfgImpl.isNil:
    timCfgImpl = newDatpkgrConfig("tim")
    timCfgImpl.withTimSupport(timParser.timManifestParser)
  timCfgImpl

template timCfg*(): DatpkgrConfig = getTimCfg()

template timPath*: string = getTimCfg().rootPath
template timDBPath*: string = getTimCfg().dbPath()
template versionsDBPath*: string = getTimCfg().versionsDBPath()
template timPkgsPath*: string = getTimCfg().pkgsPath()
template timPkgsCachePath*: string = getTimCfg().pkgsCachePath()
template timBinPath*: string = getTimCfg().binPath()
template timBuildTempPath*: string = getTimCfg().buildTempPath()
template timDevelopPath*: string = getTimCfg().developPath()
template timSourcesPath*: string = getTimCfg().rootPath / "sources.json"
template timRegistriesDir*: string = getTimCfg().rootPath / "registries"
template timPackagesUrl*: string = getTimCfg().defaultRegistryUrl
template defaultSourceName*: string = getTimCfg().defaultSourceName

template timDB*: Store = getTimCfg().stores.db
template versionsDB*: Store = getTimCfg().stores.versionsDB

template debugEnabled*: untyped = getTimCfg().debugEnabled

proc debugLog*(msg: string) =
  if getTimCfg().debugEnabled:
    getTimCfg().logDebug(msg)

proc isInsidePkgs*(dir: string): bool = timCfg.isInsidePkgs(dir)
proc safeRemoveDir*(dir: string) = timCfg.safeRemoveDir(dir)
proc safeRemoveSymlink*(p: string) = timCfg.safeRemoveSymlink(p)

proc isValidSourceName*(s: string): bool = datpkgrStore.isValidSourceName(s)
proc sourceCachePath*(name: string): string = timCfg.sourceCachePath(name)
proc ensureSourcesFile*() = timCfg.ensureSourcesFile()
proc loadSources*(): seq[Source] = timCfg.loadSources()
proc saveSources*(sources: seq[Source]) = timCfg.saveSources(sources)

proc resetTimForTests*() = timCfg.resetDatpkgrForTests()
proc seedPackagesTable*(packages: JsonNode, source: string = defaultSourceName): int =
  timCfg.seedPackagesTable(packages, source)

proc initTim*() = timCfg.initDatpkgr()

proc refreshSource*(sourceName: string): bool = timCfg.refreshSource(sourceName)
proc refreshAllSources*(): bool = timCfg.refreshAllSources()
proc refreshRegistry*(): bool = timCfg.refreshRegistry()

template withTimDB*(body: untyped) =
  timCfg.withDatpkgrDB:
    body

proc fetchPkgMeta*(pkgName: string, sourceFilter: string = ""): Option[PkgRef] =
  timCfg.fetchPkgMeta(pkgName, sourceFilter)

proc fetchAllPkgMetas*(pkgName: string): seq[PkgRef] =
  timCfg.fetchAllPkgMetas(pkgName)
