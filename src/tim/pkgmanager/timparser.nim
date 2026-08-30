# Tim package manifest parser for datpkgr
#
# (c) 2026 George Lemon | MIT License
# Made by Humans from OpenPeeps

import std/[tables, strutils, os, json, sequtils]
import pkg/semver
import pkg/openparser/json as ojson
import datpkgr/types as dt
import datpkgr/config as dc
import ./resolver

# tim relies on yaml manifest (tim.config.yml) — reuse clue-style
# requires parsing but without feature-flag surface.

proc stripQuotes(s: string): string =
  if s.len >= 2 and s[0] == '"' and s[^1] == '"': s[1..^2]
  elif s.len >= 2 and s[0] == '\'' and s[^1] == '\'': s[1..^2]
  else: s

proc normalizeVersion(v: string): string =
  let parts = v.split('.')
  result = v
  for i in parts.len..<3:
    result.add(".0")

proc parseRequiresArg*(arg: string): dt.PkgDependency =
  ## Parse a single requires entry like `foo >= 1.2.3` or `https://...#ref`
  var a = arg.strip()
  if a.len == 0:
    return dt.PkgDependency(constraint: VersionConstraint(kind: vcAny, version: newVersion(0,0,0)))
  # URL deps
  if a.contains("://"):
    let hashPos = a.find('#')
    if hashPos >= 0:
      return dt.PkgDependency(url: a[0..<hashPos], tag: a[hashPos+1..^1],
        constraint: VersionConstraint(kind: vcAny, version: newVersion(0,0,0)))
    else:
      let parts = a.splitWhitespace()
      if parts.len >= 3 and parts[1] in ["==", "=", ">=", ">", "<=", "<", "^", "~>"]:
        let op = if parts[1] == "==": "=" else: parts[1]
        return dt.PkgDependency(url: parts[0],
          constraint: parseConstraint(op & normalizeVersion(parts[2])))
      elif parts.len >= 3 and parts[1].len > 0 and parts[1][0] in {'>','<','=','!','^','~'}:
        raise newException(ResolverError, "Invalid constraint operator '" & parts[1] & "' for " & parts[0])
      else:
        return dt.PkgDependency(url: a,
          constraint: VersionConstraint(kind: vcAny, version: newVersion(0,0,0)))
  # name[#ref] plus optional constraint
  let parts = a.splitWhitespace()
  var namePart = parts[0]
  var refStr = ""
  let hashPos = namePart.find('#')
  if hashPos >= 0:
    refStr = namePart[hashPos+1..^1].strip()
    namePart = namePart[0..<hashPos].strip()
  result = dt.PkgDependency(name: namePart, branch: refStr,
    constraint: VersionConstraint(kind: vcAny, version: newVersion(0,0,0)))
  if parts.len == 2 and parts[1].len > 1:
    for opCand in ["~>", ">=", "<=", "==", "~", "^", ">", "<", "="]:
      if parts[1].startsWith(opCand):
        let verPart = parts[1][opCand.len .. ^1].strip()
        if verPart.len > 0 and verPart[0] in {'0'..'9'}:
          result.constraint = parseConstraint(opCand & normalizeVersion(verPart))
          return
        break
  if parts.len >= 3 and parts[1] in ["==", "=", ">=", ">", "<=", "<", "^", "~>"]:
    let op = if parts[1] == "==": "=" else: parts[1]
    result.constraint = parseConstraint(op & normalizeVersion(parts[2]))
  elif parts.len >= 3 and parts[1].len > 0 and parts[1][0] in {'>','<','=','!','^','~'}:
    raise newException(ResolverError, "Invalid constraint operator '" & parts[1] & "' for " & namePart)

# ----------------------------------------------------------------------
# Raw manifest holder — we parse YAML/JSON leniently
# ----------------------------------------------------------------------

type TimRawManifest = object
  name: string
  version: string
  description: string
  license: string
  requires: seq[string]

proc extractTimManifest(content: string, path: string): tuple[name, version, description, license: string, requires: seq[string]] =
  var name = ""
  var version = ""
  var description = ""
  var license = ""
  var reqs: seq[string] = @[]
  # Try JSON first (tim.json)
  var triedJson = false
  if content.strip().startsWith("{"):
    try:
      let j = ojson.fromJson(content)
      if j.kind == JObject:
        if j.hasKey("name"): name = j["name"].getStr
        if j.hasKey("version"): version = j["version"].getStr
        if j.hasKey("description"): description = j["description"].getStr
        if j.hasKey("license"): license = j["license"].getStr
        if j.hasKey("requires") and j["requires"].kind == JArray:
          for item in j["requires"]:
            if item.kind == JString: reqs.add(item.getStr)
            elif item.kind != JNull: reqs.add($item)
      triedJson = true
    except: discard
  if not triedJson:
    # Light line-scan for YAML — sufficient for tim.config.yml simple structure
    var inRequires = false
    for line in content.splitLines():
      let trimmed = line.strip()
      if trimmed.len == 0 or trimmed.startsWith("#"): continue
      if trimmed.startsWith("name:"):
        if name.len == 0:
          name = trimmed[5..^1].strip().stripQuotes()
      elif trimmed.startsWith("version:"):
        if version.len == 0:
          version = trimmed[8..^1].strip().stripQuotes()
      elif trimmed.startsWith("description:"):
        if description.len == 0:
          description = trimmed[12..^1].strip().stripQuotes()
      elif trimmed.startsWith("license:"):
        if license.len == 0:
          license = trimmed[8..^1].strip().stripQuotes()
      elif trimmed.startsWith("requires:"):
        inRequires = true
        let after = trimmed[9..^1].strip()
        if after.len > 0 and after != "|":
          if after.startsWith("["):
            let inner = after[1..^1].strip(chars={'[',']'})
            for part in inner.split(','):
              let p = part.strip().stripQuotes()
              if p.len > 0: reqs.add(p)
            inRequires = false
          elif after.len > 0:
            reqs.add(after.stripQuotes())
            inRequires = false
      elif inRequires:
        if trimmed.startsWith("-"):
          let item = trimmed[1..^1].strip().stripQuotes()
          if item.len > 0: reqs.add(item)
        elif trimmed.contains(":"):
          inRequires = false
        elif trimmed.len == 0:
          discard
  # Infer name from path if still empty
  if name.len == 0 and path.len > 0:
    let base = path.splitFile.name
    if base notin ["tim.config", "tim", "manifest"]:
      name = base
    else:
      # try parent dir name
      let dirName = path.parentDir().extractFilename()
      if dirName.len > 0 and dirName != ".":
        name = dirName
  result = (name, version, description, license, reqs)

proc timManifestParser*(content: string, path: string): dt.Manifest =
  ## Pluggable parser for datpkgr — converts tim.config.yml/json to generic Manifest
  try:
    let (name, version, description, license, reqs) = extractTimManifest(content, path)
    var deps: seq[dt.PkgDependency] = @[]
    for r in reqs:
      if r.strip().len == 0: continue
      try:
        deps.add(parseRequiresArg(r))
      except CatchableError:
        # skip malformed constraint but keep name
        let n = r.splitWhitespace()[0].strip().strip(chars={'"', '\''})
        if n.len > 0:
          deps.add(dt.PkgDependency(name: n,
            constraint: VersionConstraint(kind: vcAny, version: newVersion(0,0,0))))
    result = dt.Manifest(
      path: path,
      name: name,
      version: version,
      description: description,
      license: license,
      dependencies: deps,
      features: initTable[string, seq[dt.PkgDependency]](),
      devDependencies: @[],
      extra: %*{"srcDir": "", "installDirs": newJArray(), "installFiles": newJArray()}
    )
  except CatchableError:
    result = dt.Manifest(path: path, extra: newJObject())

proc timManifestFinder*(dir: string): string =
  var cur = dir
  var depth = 0
  while depth < 15:
    for cand in [cur / "tim.config.yml", cur / "tim.yml", cur / "tim.json", cur / "tim.nimble"]:
      if fileExists(cand):
        return cand
    for f in walkFiles(cur / "*.nimble"):
      if f.extractFilename != "nim.nimble":
        return f
    let parent = cur.parentDir()
    if parent == cur: break
    cur = parent
    inc depth
  ""

proc timManifestFileName*(pkgName: string): string =
  "tim.config.yml"

proc withTimSupport*(cfg: dc.DatpkgrConfig, parser: dt.ManifestParser) =
  cfg.defaultRegistryUrl = "https://raw.githubusercontent.com/tim-engine/pkgs/main/packages.json"
  cfg.defaultSourceName = "tim-engine"
  cfg.toolchainName = "tim"
  cfg.legacyRegistryPath = ""
  cfg.manifestParser = parser
  cfg.manifestFinder = timManifestFinder
  cfg.manifestFileName = timManifestFileName
