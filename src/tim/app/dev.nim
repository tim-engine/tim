# A super fast template engine for cool kids
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[os, osproc, strutils, strformat, sequtils, uri, httpclient]

import pkg/openparser/yaml
import pkg/kapsis/runtime
import pkg/kapsis/interactive/[prompts, widgets]

import pkg/vancode/interpreter/policy
import std/options

import pkg/semver
import pkg/datpkgr/operations as datpkgrOps
import pkg/datpkgr/config as datpkgrConfig
import ../pkgmanager/configs as timConfigs
import ../pkgmanager/timparser

#
# CLI command `init` a new package
#
proc initCommand*(v: Values) =
  ## Initializes a new Tim Engine package at the current working directory

  let currDirPath = getCurrentDir()
  let currDir = currDirPath.extractFilename()
  var pkgName =
    if v.has"pkg":
      v.get("pkg").getStr
    else:  
      # if no name provided, will prompt user for a package name
      prompt("Package name: ", default = currDir).toLowerAscii()

  if not pkgName.validIdentifier():
    displayError("Invalid package name: `$1`. Package name must be a valid identifier" % [pkgName], quitProcess = true)

  if pkgName == currDir.toLowerAscii():
    # sometimes the pkgName can be a directory created before
    # so we need to check if the current dir is empty before initializing a new package
    let res = toSeq(walkDir(currDirPath, true, true))
    if res.len > 0:
      displayError("Current directory is not empty. Please, choose another one", quitProcess = true)
  else:
    if dirExists(currDirPath / pkgName):
      displayError("Directory `$1` already exists. Please, choose another name" % [pkgName], quitProcess = true)
  
  let pkgDesc = prompt("Package description: ", default = "A new awesome package for Tim Engine")
  let pkgVersion = prompt("Package version: ", default = "0.1.0")
  let pkgLicense = prompt("Package license: ", default = "MIT")

  let pkgTypeOpts = @["project", "package"]
  let pkgType = promptInteractive("Package type: ", answers = pkgTypeOpts, activeIcon = "🍕")
  if pkgType == -1:
    displayError("No package type selected. Please, choose one", quitProcess = true)
  
  createDir(currDirPath / pkgName)
  createDir(currDirPath / pkgName / "src")
  
  let pkgTypeStr = pkgTypeOpts[pkgType]
  if pkgTypeStr == "package":
    const sampleCode = """
var hello = "Tim Engine is Awesome"
echo $hello"""
    writeFile(currDirPath / pkgName / "src" / pkgName & ".timl", sampleCode)
  else:
    createDir(currDirPath / pkgName / "src" / "templates")
    createDir(currDirPath / pkgName / "src" / "templates" / "layouts")
    createDir(currDirPath / pkgName / "src" / "templates" / "views")
    createDir(currDirPath / pkgName / "src" / "templates" / "partials")

  # TODO @ pkg/openparser/yaml advanced dump features to
  # allow for adding extra spaces, exclude fields and more.
  writeFile(currDirPath / pkgName / "tim.config.yml", fmt"""
type: {pkgTypeStr}
description: "{pkgDesc}"
version: "0.1.0"
license: "{pkgLicense}"

compilation:
  source: "./src/templates"
  output: "./build"
  release: false

server:
  port: 8000
  threads: 1
  routes:
    "/": "index"

browser_sync:
  port: 3500
  delay: 200
  """)

proc watchCommand*(v: Values) =
  ## Watches for file changes and rebuilds the project.
  ## 
  ## This command is used for development purposes for
  ## transpiling Tim code to target source on the fly.
  let timConfigPath = getCurrentDir() / "tim.config.yml"
  if not fileExists(timConfigPath):
    displayError("tim.config.yml not found in the current directory", quitProcess = true)
  

#
# CLI command `install` — via datpkgr (https://github.com/tim-engine/pkgs)
#
proc isGitUrl(s: string): bool =
  s.startsWith("https://") or s.startsWith("http://") or
  s.startsWith("git@") or s.startsWith("git+") or s.startsWith("ssh://")

proc installCommand*(v: Values) =
  let cfg = timConfigs.getTimCfg()
  let raw = if v.has("pkg"): v.get("pkg").getStr.strip() else: ""
  if raw.len == 0:
    displayError("Missing package name. Usage: tim install <pkg>[@ref] or <git-url>[#ref]", quitProcess = true)
    return
  if isGitUrl(raw):
    var url = raw
    var urlRef = ""
    let hashPos = url.find('#')
    if hashPos >= 0:
      urlRef = url[hashPos+1..^1]
      url = url[0..<hashPos]
    let name = datpkgrOps.pkgNameFromUrl(url)
    if name.len == 0:
      displayError("Could not derive package name from: " & raw, quitProcess = true)
      return
    let ok = datpkgrOps.installPackage(cfg, name, urlRef, url = url)
    if not ok: quit(1)
    return
  # handle pkg[@ref] or constraint form `pkg >= 1.0` via parser
  # split @ first (explicit ref wins over constraint)
  let atParts = raw.split("@")
  if atParts.len > 1:
    let pkgName = atParts[0].strip()
    let pkgRef = atParts[1].strip()
    if pkgName.len == 0:
      displayError("Invalid package spec: " & raw, quitProcess = true)
      return
    # pkgRef may be version or branch — let datpkgr handle it
    let ok = datpkgrOps.installPackage(cfg, pkgName, pkgRef)
    if not ok: quit(1)
    return
  # Try rich constraint parsing (e.g. `foo >= 1.2.3`, `foo ^0.1.0`)
  try:
    let dep = timparser.parseRequiresArg(raw)
    if dep.url.len > 0:
      let name = if dep.name.len > 0: dep.name else: datpkgrOps.pkgNameFromUrl(dep.url)
      let ok = datpkgrOps.installPackage(cfg, name, dep.tag, url = dep.url, constraint = dep.constraint)
      if not ok: quit(1)
      return
    if dep.name.len > 0:
      let refStr = if dep.branch.len > 0: dep.branch elif dep.tag.len > 0: dep.tag else: ""
      let ok = datpkgrOps.installPackage(cfg, dep.name, refStr, constraint = dep.constraint)
      if not ok: quit(1)
      return
  except CatchableError:
    discard
  # fallback — plain name
  let ok = datpkgrOps.installPackage(cfg, raw)
  if not ok: quit(1)

#
# CLI Command `remove` — via datpkgr
#
proc removeCommand*(v: Values) =
  let cfg = timConfigs.getTimCfg()
  let raw = v.get("pkg").getStr.strip()
  let parts = raw.split("@")
  let pkgName = parts[0].strip()
  let pkgVersion = if parts.len > 1: parts[1].strip() else: ""
  proc confirm(msg: string): bool = promptConfirm(msg)
  let ok = datpkgrOps.uninstallPackage(cfg, pkgName, pkgVersion, confirm)
  if not ok: quit(1)

#
# CLI Command `develop` — via datpkgr
#
proc developCommand*(v: Values) =
  let cfg = timConfigs.getTimCfg()
  # `tim develop <pkg>` historically took pkg arg, but for datpkgr develop
  # we symlink current directory (like `clue develop`). If an explicit path/name
  # is given and it's a directory, use it; otherwise use cwd.
  var dir = getCurrentDir()
  if v.has("pkg"):
    let arg = v.get("pkg").getStr.strip()
    if arg.len > 0 and dirExists(arg):
      dir = absolutePath(arg)
    elif arg.len > 0 and fileExists(arg):
      dir = absolutePath(arg.parentDir())
    elif arg.len > 0:
      # treat arg as informational only — still develop cwd
      discard
  let ok = datpkgrOps.developPackage(cfg, dir)
  if not ok: quit(1)