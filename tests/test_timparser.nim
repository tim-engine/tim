import std/[unittest, os, json]
import ../src/tim/pkgmanager/timparser

suite "timparser — manifest discovery":
  test "finder locates tim.config.yaml":
    let dir = getTempDir() / ("tim_parser_yaml_" & $getCurrentProcessId())
    createDir(dir)
    defer: removeDir(dir)
    writeFile(dir / "tim.config.yaml", "name: bootstrap\nversion: 0.1.0\n")
    check timManifestFinder(dir).extractFilename == "tim.config.yaml"

  test "finder prefers tim.config.yml when both exist":
    let dir = getTempDir() / ("tim_parser_both_" & $getCurrentProcessId())
    createDir(dir)
    defer: removeDir(dir)
    writeFile(dir / "tim.config.yaml", "name: bootstrap\nversion: 0.1.0\n")
    writeFile(dir / "tim.config.yml", "name: bootstrap\nversion: 0.2.0\n")
    check timManifestFinder(dir).extractFilename == "tim.config.yml"

  test "canonical manifest file name stays tim.config.yml":
    check timManifestFileName("bootstrap") == "tim.config.yml"

suite "timparser — manifest parsing":
  test "parses name, version and requires from yaml":
    let m = timManifestParser(
      "name: bootstrap\ntype: package\nversion: 0.1.0\ndescription: \"Bootstrap v5.x\"\nlicense: MIT\nrequires:\n  - tim >= 0.1.3\n",
      getTempDir() / "tim.config.yaml")
    check m.name == "bootstrap"
    check m.version == "0.1.0"
    check m.description == "Bootstrap v5.x"
    check m.license == "MIT"
    check m.extra["pkgType"].getStr == "package"
    check m.dependencies.len == 1
    check m.dependencies[0].name == "tim"
