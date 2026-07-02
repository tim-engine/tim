# A super fast template engine for cool kids
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[os, osproc, strutils, strformat, sequtils, uri, httpclient]

import pkg/[semver, openparser/yaml]
import pkg/kapsis/runtime
import pkg/kapsis/interactive/[prompts, widgets]

import pkg/vancode/manager/[configurator, packager, remote]

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
  
  let pkgTypeEnum = parseEnum[ConfigType](pkgTypeOpts[pkgType])
  if pkgTypeEnum == typePackage:
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
type: {pkgTypeEnum}
description: "{pkgDesc}"
version: "0.1.0"
license: "{pkgLicense}"

compilation:
  source: "./templates"
  output: "./app/frontend"
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
# CLI command `install` a package
# 
proc installCommand*(v: Values) =
  ## Install a package from remote GIT sources
  let pkgr = packager.initPackageRemote()
  pkgr.loadPackages() # load database of existing packages
  let pkgUrl = v.get("pkg").getUrl()
  if pkgUrl.scheme.len > 0:
    if pkgUrl.hostname == "github.com":
      let pkgPath = pkgUrl.path[1..^1].split("/")
      # Connect to the remote source and try find a `tim.config.yaml`,
      # Check the `yaml` config file and download the package
      let orgName = pkgPath[0]
      let pkgName = pkgPath[1]
      let res = pkgr.remote.httpGet("repo_contents_path", @[orgName, pkgName, "tim.config.yaml"])
      case res.code
      of Http200:
        let remoteYaml: GithubFileResponse = pkgr.remote.getFileContent(res) # this is base64 encoded
        let pkgConfig: YamlObject = parseYAML(remoteYaml.content.decode())
        # case pkgConfig.`type`:
        #   of typePackage:
        #     if not pkgr.hasPackage(pkgConfig.name):
        #       display(("Installing $1@$2" % [pkgConfig.name, pkgConfig.version]))
        #       if pkgr.createPackage(orgName, pkgName, pkgConfig):
        #         displayInfo("Updating Packager DB")
        #         pkgr.updatePackages()
        #         displaySuccess("Done!")
        #     else:
        #       displayInfo("Package $1@$2 is already installed" % [pkgConfig.name, pkgConfig.version])
        #   else:
        #     displayError("Tim projects cannot be installed via Packager. Use git instead")
      else: discard # todo prompt error

#
# CLI Command `remove` an installed package 
#
proc removeCommand*(v: Values) =
  ## Removes an installed package by name and version (if provided)
  let input = v.get("pkg").getStr.split("@")
  var hasVersion: bool
  let pkgName = input[0]
  let pkgVersion =
    if input.len == 2:
      hasVersion = true; parseVersion(input[1])
    else: newVersion(0,1,0)
  displayInfo("Finding package `" & pkgName & "`")
  let pkgr = packager.initPackageRemote()
  pkgr.loadPackages() # load database of existing packages
  if pkgr.hasPackage(pkgName):
    displaySuccess("Delete package `" & pkgName & "`")
    pkgr.deletePackage(pkgName)
  else:
    displayError("Package `" & pkgName & "` not found")


#
# CLI Command `develop` a package
#
proc developCommand*(v: Values) =
  ## Create a symlink to a package in local source
  let pkgName = v.get("pkg").getStr
  let pkgr = packager.initPackageRemote()
  # pkgr.loadPackages() # load database of existing packages
  # if not pkgr.hasPackage(pkgName):
  #   displayError("Package `$1` not found" % [pkgName], quitProcess = true)
  
  # let pkgPath = pkgr.getPackagePath(pkgName)
  # if pkgPath.len == 0:
  #   displayError("Package `$1` is not installed" % [pkgName], quitProcess = true)

  # let srcPath = getCurrentDir() / "src"
  # if not dirExists(srcPath):
  #   createDir(srcPath)

  # let linkPath = srcPath / pkgName
  # if fileExists(linkPath):
  #   displayError("Symlink `$1` already exists. Please, remove it first" % [linkPath], quitProcess = true)

  # createSymlink(pkgPath, linkPath)
  # displaySuccess("Symlink created: `$1` -> `$2`" % [linkPath, pkgPath])