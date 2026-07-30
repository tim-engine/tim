# A super fast template engine for cool kids
#
# (c) 2025 George Lemon | LGPL License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[tables, strutils, os, osproc, options, sequtils]
import pkg/[flatty, openparser/yaml, semver, checksums/md5]
import pkg/vancode/interpreter/ast

import ./remote, ./configurator

type
  VersionedPackage = OrderedTableRef[string, TimConfig]
  PackagesTable* = OrderedTableRef[string, VersionedPackage]
  Packager* = ref object
    remote*: RemoteSource
    packages: PackagesTable
      # An ordered table containing a versioned
      # table of `Package`
    flagNoCache*: bool
    flagRecache*: bool

const
  pkgrHomeDir* = getHomeDir() / ".tim"
  pkgrHomeDirTemp* = pkgrHomeDir / "tmp"
  pkgrPackagesDir* = pkgrHomeDir / "packages"
  pkgrTokenPath* = pkgrHomeDir / ".env"
  pkgrPackageCachedDir* = pkgrPackagesDir / "$1" / "$2" / ".cache"
  pkgrPackageSourceDir* = pkgrPackagesDir / "$1" / "$2" / "src"
  pkgrIndexPath* = pkgrPackagesDir / "index.json"

proc initPackager*: Packager =
  discard existsOrCreateDir(pkgrHomeDir)
  discard existsOrCreateDir(pkgrHomeDirTemp)
  result = Packager()

proc initPackageRemote*: Packager =
  ## Initialize Tim Engine Packager with Remote Source
  result = initPackager()
  result.remote = initRemoteSource(pkgrHomeDir)

proc hasPackage*(pkgr: Packager, pkgName: string): bool =
  ## Determine if a `pkgName` is installed
  result = pkgr.packages.hasKey(pkgName)
  if result:
    result = dirExists(pkgrPackagesDir / pkgName)
    result = dirExists(pkgrPackageSourceDir % [pkgName, "0.1.0"])

proc updatePackages*(pkgr: Packager) =
  ## Update packages index
  writeFile(pkgrIndexPath, toJson(pkgr.packages))

proc createPackage*(pkgr: Packager, orgName, pkgName: string, pkgConfig: TimConfig): bool =
  ## Create package directory for `pkgConfig`
  ## Returns `true` if succeed.
  let v = pkgConfig.version
  discard existsOrCreateDir(pkgrPackagesDir / pkgConfig.name)
  let tempPath = pkgrHomeDirTemp / pkgConfig.name & "@" & v & ".tar"
  let pkgPath = pkgrPackagesDir / pkgConfig.name / v
  if not existsOrCreateDir(pkgPath):
    if not fileExists(tempPath):
      if pkgr.remote.download("repo_tarball_ref", tempPath, @[orgName, pkgName, "main"]):
        discard execProcess("tar", args = ["-xzf", tempPath, "-C", pkgPath, "--strip-components=1"],
          options = {poStdErrToStdOut, poUsePath})
        result = true
    else:
      discard execProcess("tar", args = ["-xzf", tempPath, "-C", pkgPath, "--strip-components=1"],
        options = {poStdErrToStdOut, poUsePath})
      result = true
  if result:
    if not pkgr.packages.hasKey(pkgConfig.name):
      pkgr.packages[pkgConfig.name] = VersionedPackage()
    pkgr.packages[pkgConfig.name][v] = pkgConfig

proc deletePackage*(pkgr: Packager, pkgName: string, pkgVersion: Option[Version] = none(Version)) =
  ## Delete a package by name and semantic version (when provided).
  ## Running the `remove` command over an aliased package
  ## will delete de alias and keep the original package folder in place
  let pkgConfig = pkgr.packages[pkgName]
  let version =
    if pkgVersion.isSome:
      # use the specified version
      $(pkgVersion.get())
    else:
      # always choose the latest version
      let versions = pkgConfig.keys.toSeq
      pkgConfig[versions[versions.high]].version
  echo pkgrPackagesDir / pkgConfig[version].name / version

proc loadModule*(pkgr: Packager, pkgName: string): string =
  ## Load a Tim Engine module from a specific package
  let pkgName = pkgName[4..^1].split("/")
  let pkgPath = pkgrPackageSourceDir % [pkgName[0], "0.1.0"]
  result = readFile(normalizedPath(pkgPath / pkgName[1..^1].join("/") & ".timl"))

proc getModulePath*(pkgr: Packager, pkgName, path: string): string =
  ## Get the file path of a Tim Engine module from a specific package
  let pkgPath = pkgrPackageSourceDir % [pkgName, "0.1.0"]
  result = normalizedPath(pkgPath / path & ".timl")

proc cacheModule*(pkgr: Packager, pkgName: string, ast: Ast) =
  ## Cache a Tim Engine module to binary AST
  let pkgName = pkgName[4..^1].split("/")
  let cachePath = pkgrPackageCachedDir % [pkgName[0], "0.1.0"]
  let cacheAstPath = cachePath / getMD5(pkgName[1..^1].join("/")) & ".ast"
  discard existsOrCreateDir(cachePath)
  writeFile(cacheAstPath, toFlatty(ast))

proc getCachedModule*(pkgr: Packager, pkgName: string): Ast =
  ## Retrieve a cached binary AST
  let pkgName = pkgName[4..^1].split("/")
  let cachePath = pkgrPackageCachedDir % [pkgName[0], "0.1.0"]
  let cacheAstPath = cachePath / getMD5(pkgName[1..^1].join("/")) & ".ast"
  # if fileExists(cacheAstPath):
    # result = fromFlatty(readFile(cacheAstPath), Ast)

proc hasLoadedPackages*(pkgr: Packager): bool =
  ## Determine if packager has loaded the local database in memory
  pkgr.packages != nil

proc loadPackages*(pkgr: Packager) =
  ## Load the local database of packages in memory
  if pkgrIndexPath.fileExists:
    let db = readFile(pkgrIndexPath)
    if db.len > 0:
      pkgr.packages = fromJson(readFile(pkgrIndexPath), PackagesTable)
      return
  new(pkgr.packages)
