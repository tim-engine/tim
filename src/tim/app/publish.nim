# Tim Engine — `tim publish`
#
# (c) 2026 George Lemon | MIT License
# Made by Humans from OpenPeeps
#
# Publish a Tim package by opening a pull request against
# https://github.com/tim-engine/pkgs (fork, edit packages.json, PR).
#
# Auth uses the GitHub token stored encrypted in `~/.tim/secret` (see
# `../pkgmanager/secrets`). The token only ever travels inside temp files
# with owner-only permissions, child-process environments, and TLS request
# bodies — never in argv, logs, or the shell history.

import std/[os, osproc, strutils, strtabs, tempfiles, times, terminal]
import pkg/openparser/json
import ../meta/cliutils

import ../pkgmanager/configs as timConfigs
import ../pkgmanager/secrets

const
  pkgsUpstream* = "tim-engine/pkgs"
  pkgsUpstreamUrl* = "https://github.com/" & pkgsUpstream
  pkgsRegistryRaw* = "https://raw.githubusercontent.com/tim-engine/pkgs/main/packages.json"
  pkgsDefaultBranch* = "main"
  pkgsApiBase* = "https://api.github.com/repos/"
  pkgsApiRoot* = "https://api.github.com"

# ----------------------------------------------------------------------
# Pure helpers (unit-tested, no I/O)
# ----------------------------------------------------------------------

proc splitPublishTags*(s: string): seq[string] =
  ## Split a tag line on commas and any whitespace, dropping empties and
  ## dupes while keeping first-seen order.
  for part in s.split({',', ' ', '\t', '\n', '\r', '\f', '\v'}):
    let tag = part.strip()
    if tag.len > 0 and tag notin result:
      result.add(tag)

proc normalizePublishUrl*(url: string): string =
  ## Normalize a package remote URL to its canonical `https://` form for the
  ## registry index: strips a trailing `.git`, maps scp-like
  ## `git@host:owner/repo` and `ssh://` URLs to https, and rejects URLs
  ## embedding a username or password.
  var u = url.strip()
  if u.endsWith(".git"):
    u = u[0 ..< ^4]
  u = u.strip(chars = {'/'})
  if u.startsWith("git+"):
    u = u[4 .. ^1]
  if "://" notin u and '@' in u and ':' in u:
    let atPos = u.find('@')
    let colonPos = u.find(':', atPos)
    let host = u[atPos + 1 ..< colonPos]
    let path = u[colonPos + 1 .. ^1].strip(chars = {'/'})
    if host.len == 0 or path.len == 0:
      raise newException(ValueError, "Cannot parse repository URL: " & url)
    return "https://" & host & "/" & path
  if u.startsWith("ssh://"):
    var rest = u["ssh://".len .. ^1]
    if '@' in rest:
      rest = rest[rest.find('@') + 1 .. ^1]
    let slashPos = rest.find('/')
    if slashPos < 0:
      raise newException(ValueError, "Cannot parse repository URL: " & url)
    var hostPort = rest[0 ..< slashPos]
    let path = rest[slashPos + 1 .. ^1].strip(chars = {'/'})
    if ':' in hostPort:
      hostPort = hostPort[0 ..< hostPort.find(':')]
    if hostPort.len == 0 or path.len == 0:
      raise newException(ValueError, "Cannot parse repository URL: " & url)
    return "https://" & hostPort & "/" & path
  if u.startsWith("http://") or u.startsWith("https://"):
    let schemeEnd = u.find("://") + 3
    let rest = u[schemeEnd .. ^1]
    let slashPos = rest.find('/')
    let authority = if slashPos < 0: rest else: rest[0 ..< slashPos]
    if '@' in authority:
      raise newException(ValueError,
        "Cannot publish this repository URL because it contains a username " &
        "and/or password. Fix the remote URL. Hint: \"git remote -v\"")
    return u
  raise newException(ValueError, "Cannot parse repository URL: " & url)

proc publishEntry*(name, url, description, license, web: string,
    tags: seq[string]): JsonNode =
  ## Build the packages.json entry for a package, matching the index schema.
  var tagsArr = newJArray()
  for t in tags:
    tagsArr.add(%t)
  result = %*{
    "name": name,
    "url": url,
    "method": "git",
    "tags": tagsArr,
    "description": description,
    "license": license,
    "web": web
  }

proc entryExists*(packagesJson: JsonNode, name: string): bool =
  ## True when `packages.json` (a top-level array) already holds `name`.
  if packagesJson.kind != JArray:
    return false
  for entry in packagesJson:
    if entry.kind == JObject and entry.hasKey("name") and
        entry["name"].getStr == name:
      return true
  false

proc insertEntrySorted*(packagesJson: JsonNode, entry: JsonNode): JsonNode =
  ## Return a copy of `packages.json` with `entry` inserted so entries stay
  ## sorted ascending by `name`. The registry keeps alphabetical order.
  let newName = entry["name"].getStr
  result = newJArray()
  var placed = false
  for existing in packagesJson:
    if not placed and existing.kind == JObject and existing.hasKey("name") and
        existing["name"].getStr > newName:
      result.add(entry)
      placed = true
    result.add(existing)
  if not placed:
    result.add(entry)

proc publishBranchName*(pkgName: string): string =
  "add-" & pkgName & "-" & getTime().utc.format("HHmm")

proc prTitle*(pkgName, version: string): string =
  "Add " & pkgName & " " & version

proc prBody*(pkgName, version, url, description, extra: string,
    hasTag: bool): string =
  result = description & "\n\n" & url
  result.add("\n\nVerification:")
  result.add("\n- [x] `tim.config` manifest with name, version, description, license")
  result.add("\n- [x] remote reachable anonymously (`git ls-remote`)")
  if hasTag:
    result.add("\n- [x] semver tag for " & version & " exists")
  else:
    result.add("\n- [ ] no semver tag for " & version & " — installs use the default branch")
  if extra.len > 0:
    result.add("\n\n" & extra)

proc extraStr*(m: Manifest, key: string): string =
  if m.extra != nil and m.extra.kind == JObject and m.extra.hasKey(key) and
      m.extra[key].kind == JString:
    return m.extra[key].getStr
  ""

# ----------------------------------------------------------------------
# Command I/O helpers
# ----------------------------------------------------------------------

proc runCmd(workdir, cmd: string,
    extraEnv: openArray[(string, string)] = []): tuple[output: string, code: int] =
  ## Run `cmd` in `workdir` with the parent environment plus `extraEnv`.
  var env = newStringTable()
  for k, v in envPairs():
    env[k] = v
  for (k, v) in extraEnv:
    env[k] = v
  let (output, exitCode) = execCmdEx(cmd, workingDir = workdir, env = env)
  (output: output, code: exitCode)

proc runGit(workdir, args: string,
    extraEnv: openArray[(string, string)] = []): bool =
  ## Run a git command in `workdir`, echoing its output on failure.
  ## Callers must never pass secrets in `args` (argv is observable);
  ## use `extraEnv` for credentials instead.
  let (output, code) = runCmd(workdir, "git " & args, extraEnv)
  if code != 0:
    displayError("git " & args & " failed: " & output.strip())
    return false
  true

proc fetchUrl*(url: string): tuple[output: string, code: int] =
  ## Plain unauthenticated GET over curl (same transport as registry
  ## downloads). Used for public reads that need no token.
  let (output, exitCode) =
    execCmdEx("curl -fsSL --connect-timeout 15 " & quoteShell(url))
  (output: output, code: exitCode)

proc ghApi*(url, token: string, payload = ""): tuple[output: string, code: int] =
  ## Minimal authenticated GitHub API client over curl. The token travels
  ## inside a temp curl-config file (owner-only, removed afterwards) —
  ## never in argv.
  let dir = createTempDir("tim-gh-", "")
  try:
    let cfgFile = dir / "curl.cfg"
    var cfgText = "silent = true\nshow-error = true\nfail = true\n" &
      "location = true\nconnect-timeout = 15\n"
    cfgText.add("header = \"Authorization: Bearer " & token & "\"\n")
    cfgText.add("header = \"Accept: application/vnd.github+json\"\n")
    if payload.len > 0:
      let bodyFile = dir / "body.json"
      writeFile(bodyFile, payload)
      setFilePermissions(bodyFile, {fpUserRead, fpUserWrite})
      cfgText.add("request = \"POST\"\n")
      cfgText.add("header = \"Content-Type: application/json\"\n")
      cfgText.add("data = \"@" & bodyFile & "\"\n")
    writeFile(cfgFile, cfgText)
    setFilePermissions(cfgFile, {fpUserRead, fpUserWrite})
    let (output, exitCode) =
      execCmdEx("curl -sS -K " & quoteShell(cfgFile) & " " & quoteShell(url))
    result = (output: output, code: exitCode)
  finally:
    try: removeDir(dir)
    except OSError, IOError: discard

proc githubUser*(token: string): string =
  ## Resolve the token owner (`login`) — also verifies the token works.
  let (output, code) = ghApi(pkgsApiRoot & "/user", token)
  if code != 0:
    return ""
  try:
    let j = parseJson(output)
    if j.kind == JObject and j.hasKey("login"):
      return j["login"].getStr
  except CatchableError:
    discard
  ""

proc isCorrectFork(output: string): bool =
  ## True when a `GET /repos/{user}/pkgs` body is a fork of tim-engine/pkgs.
  try:
    let j = parseJson(output)
    if j.kind == JObject and j.hasKey("fork") and j["fork"].getBool:
      let parent = j["parent"]
      if parent.kind == JObject and parent.hasKey("full_name"):
        return parent["full_name"].getStr == pkgsUpstream
  except CatchableError:
    discard
  false

proc ensureFork*(user, token: string): bool =
  ## Make sure `{user}/pkgs` is a fork of tim-engine/pkgs, forking first
  ## when needed. Returns false with the caller logging the reason.
  let (output, code) = ghApi(pkgsApiBase & user & "/pkgs", token)
  if code == 0 and isCorrectFork(output):
    return true
  displayInfo("Forking " & pkgsUpstream & " ...")
  let (_, forkCode) = ghApi(pkgsApiBase & pkgsUpstream & "/forks", token, "{}")
  if forkCode != 0:
    displayError("Unable to create fork. The token might not have enough " &
      "permissions (needs `public_repo`).", quitProcess = true)
    return false
  displayInfo("Waiting 10s to let GitHub create the fork ...")
  sleep(10_000)
  true

proc createPullRequest*(token, headOwner, branch, title,
    body: string): string =
  ## Open the PR against tim-engine/pkgs; returns its `html_url` or "".
  ## `headOwner` is the fork owner, or "tim-engine" for direct (same-repo) PRs.
  let headRef =
    if headOwner == "tim-engine": branch
    else: headOwner & ":" & branch
  let payload = %*{
    "title": title,
    "head": headRef,
    "base": pkgsDefaultBranch,
    "body": body
  }
  let (output, code) = ghApi(pkgsApiBase & pkgsUpstream & "/pulls",
    token, $payload)
  if code != 0:
    return ""
  try:
    let j = parseJson(output)
    if j.kind == JObject and j.hasKey("html_url"):
      return j["html_url"].getStr
  except CatchableError:
    discard
  ""

proc detectRepoUrl*(dir: string): string =
  ## The checkout's `origin` remote URL ("" when not a git checkout).
  if not dirExists(dir / ".git"):
    return ""
  let (output, code) = runCmd(dir, "git ls-remote --get-url")
  if code != 0:
    return ""
  output.strip()

proc isCleanTree*(dir: string): bool =
  let (output, code) = runCmd(dir, "git status --porcelain")
  code == 0 and output.strip().len == 0

proc remoteReachable*(url: string): bool =
  ## True when the repo clones anonymously (what installers will hit).
  let (_, code) = execCmdEx("git ls-remote " & quoteShell(url) & " HEAD")
  code == 0

proc hasVersionTag*(dir, version: string): bool =
  let (output, code) = runCmd(dir, "git tag --list")
  if code != 0:
    return false
  version in output.splitLines() or ("v" & version) in output.splitLines()

proc gitIdentity*(): tuple[name, email: string] =
  ## Commit identity for the temp registry clone: the user's global git
  ## config when set, otherwise a neutral fallback (the PR itself still
  ## carries the GitHub user as author via the fork).
  result = ("tim publish", "tim@localhost")
  let (n, c1) = execCmdEx("git config --global user.name")
  if c1 == 0 and n.strip().len > 0:
    result.name = n.strip()
  let (e, c2) = execCmdEx("git config --global user.email")
  if c2 == 0 and e.strip().len > 0:
    result.email = e.strip()

proc pushBranch*(workdir, remoteUrl, branch, token: string): bool =
  ## Push `branch` to `remoteUrl` (https with the non-secret
  ## `x-access-token` user). The token reaches git only through a temp
  ## askpass helper fed from the environment — never in argv.
  let askFile = workdir / "tim-askpass.sh"
  writeFile(askFile, "#!/bin/sh\nexec echo \"$TIM_PUBLISH_TOKEN\"\n")
  setFilePermissions(askFile, {fpUserRead, fpUserWrite, fpUserExec})
  runGit(workdir, "push -q " & quoteShell(remoteUrl) & " " & branch,
    {"GIT_ASKPASS": askFile, "GIT_TERMINAL_PROMPT": "0",
     "TIM_PUBLISH_TOKEN": token})

proc promptHidden*(label: string): string =
  ## Print `label` and read one masked line via `std/terminal`. Prints
  ## nothing extra — so a token prompt never reads as a password prompt
  ## and vice versa. There is no GitHub password anywhere here: the token
  ## is pasted manually, and the password only encrypts the local file.
  stdout.write(label & ": ")
  stdout.flushFile()
  result = readPasswordFromStdin("")

proc unlockToken*(homeRoot: string, reset: bool): string =
  ## Return the stored GitHub token: interactive first-time setup when no
  ## secret exists (or `reset` is set), otherwise a masked password prompt
  ## with three attempts. Fatal when setup is declined or fails.
  if not isatty(stdin):
    displayError("`tim publish` needs an interactive terminal to read the " &
      "GitHub token and secret password.", quitProcess = true)
    return ""
  if reset:
    deleteSecretFile(homeRoot)
  if not hasSecretFile(homeRoot):
    displayInfo("First publish setup: the GitHub token is stored encrypted in " &
      secretFilePath(homeRoot) & ".")
    let token = promptHidden("GitHub token (needs the `public_repo` scope)").strip()
    if token.len == 0:
      displayError("Empty token — cancelled.", quitProcess = true)
      return ""
    if githubUser(token).len == 0:
      displayError("Could not verify the token (GET /user failed). " &
        "Check the token and network.", quitProcess = true)
      return ""
    let pw1 = promptHidden("Choose a secret password (encrypts the token)")
    let pw2 = promptHidden("Repeat the secret password")
    if pw1 != pw2:
      displayError("Passwords do not match.", quitProcess = true)
      return ""
    if pw1.len < 8:
      displayError("Password must be at least 8 characters.", quitProcess = true)
      return ""
    storeGithubToken(homeRoot, token, pw1)
    displaySuccess("Token stored encrypted in " & secretFilePath(homeRoot))
    return token
  for attempt in 1 .. 3:
    let pw = promptHidden("Secret password (attempt " & $attempt & "/3)")
    try:
      return loadGithubToken(homeRoot, pw)
    except SecretError as e:
      displayWarning(e.msg)
  displayError("Too many wrong attempts.", quitProcess = true)
  ""

# ----------------------------------------------------------------------
# CLI command `publish`
# ----------------------------------------------------------------------

proc publishCommand*(pathArg, tagsArg, webArg, messageArg: string,
    dryRun, yesMode, directMode, resetToken: bool) =
  let cfg = timConfigs.getTimCfg()

  var dir = getCurrentDir()
  if pathArg.len > 0:
    dir = absolutePath(pathArg.strip())
  if not dirExists(dir):
    displayError("Package directory not found: " & dir, quitProcess = true)
    return

  let manifestPath = cfg.findManifestForDir(dir)
  if manifestPath.len == 0:
    displayError("No tim.config.yml (or .yaml) found in " & dir &
      ". `tim publish` must run inside a package directory.", quitProcess = true)
    return
  var manifest: Manifest
  try:
    manifest = cfg.parseManifest(readFile(manifestPath), manifestPath)
  except CatchableError as e:
    displayError("Could not parse " & manifestPath & ": " & e.msg,
      quitProcess = true)
    return
  let pkgName = manifest.name.strip()
  if pkgName.len == 0:
    displayError("The manifest has no `name` — set one before publishing " &
      "(it becomes the registry name).", quitProcess = true)
    return
  let pkgType = extraStr(manifest, "pkgType")
  if pkgType.len > 0 and pkgType != "package":
    displayError("Only `type: package` can be published (this one is `type: " &
      pkgType & "`).", quitProcess = true)
    return
  let pkgVersion = manifest.version.strip()
  if pkgVersion.len == 0:
    displayError("The manifest has no `version` — set one before publishing.",
      quitProcess = true)
    return
  let pkgDesc = manifest.description.strip()
  if pkgDesc.len == 0:
    displayError("The manifest has no `description` — refusing to publish " &
      "an undescribed package.", quitProcess = true)
    return
  let pkgLicense = manifest.license.strip()
  if pkgLicense.len == 0:
    displayError("The manifest has no `license` — refusing to publish " &
      "an unlicensed package.", quitProcess = true)
    return

  var url = ""
  let detected = detectRepoUrl(dir)
  if detected.len > 0:
    try:
      url = normalizePublishUrl(detected)
    except ValueError as e:
      displayError(e.msg, quitProcess = true)
      return
  if url.len == 0:
    if not yesMode and not isatty(stdout):
      displayError("Could not detect a git remote. Re-run inside the " &
        "package checkout or from a terminal.", quitProcess = true)
      return
    let typed = prompt("Repository URL of " & pkgName).strip()
    if typed.len == 0:
      displayInfo("Cancelled.")
      quit(0)
    try:
      url = normalizePublishUrl(typed)
    except ValueError as e:
      displayError(e.msg, quitProcess = true)
      return

  var tags: seq[string]
  if tagsArg.len > 0:
    tags = splitPublishTags(tagsArg)
  else:
    if not isatty(stdout):
      displayError("No `--tags` given and no interactive terminal. " &
        "Re-run with `--tags:\"tim, bootstrap, ui\"`.", quitProcess = true)
      return
    tags = splitPublishTags(prompt(
      "Comma or space separated list of tags? (For example: tim bootstrap ui)"))
  if tags.len == 0:
    displayError("At least one tag is required to publish.", quitProcess = true)
    return

  var web = url
  if webArg.len > 0:
    web = webArg.strip()
  if web.len == 0:
    displayError("Empty `--web` URL.", quitProcess = true)
    return

  if not isCleanTree(dir):
    displayError("Working tree has uncommitted changes — commit and push " &
      "first so the registry points at published code.", quitProcess = true)
    return
  if not remoteReachable(url):
    displayError("Cannot reach " & url & " anonymously (`git ls-remote` " &
      "failed). Push the repo first.", quitProcess = true)
    return
  let tagged = hasVersionTag(dir, pkgVersion)
  if not tagged:
    displayWarning("No git tag for version " & pkgVersion &
      " — installs will use the default branch until you push one.")

  let entry = publishEntry(pkgName, url, pkgDesc, pkgLicense, web, tags)
  let branchName = publishBranchName(pkgName)
  var extraMsg = ""
  if messageArg.len > 0:
    extraMsg = messageArg.strip()

  if dryRun:
    displayInfo("Dry run — no network, git, or secret changes made.")
    displayInfo("Package entry:")
    echo pretty(entry)
    displayInfo("Would " & (if directMode: "push a branch to " & pkgsUpstream
      else: "fork " & pkgsUpstreamUrl) & ", add the entry to packages.json " &
      "on branch " & branchName & ", push, and open a PR against " &
      pkgsDefaultBranch & ".")
    displaySuccess("Dry run complete")
    return

  # Auth only past this point: dry runs stay fully offline and secret-free.
  let token = unlockToken(cfg.rootPath, resetToken)
  if token.len == 0:
    return
  let user = githubUser(token)
  if user.len == 0:
    displayError("Could not verify the GitHub API token (GET /user failed). " &
      "Check the token and network.", quitProcess = true)
    return
  displaySuccess("Verified as " & user)

  let (regBody, regCode) = fetchUrl(pkgsRegistryRaw)
  if regCode != 0:
    displayError("Could not download the registry from " & pkgsRegistryRaw,
      quitProcess = true)
    return
  var registry: JsonNode
  try:
    registry = parseJson(regBody)
  except CatchableError as e:
    displayError("Could not parse the registry: " & e.msg, quitProcess = true)
    return
  if registry.kind != JArray:
    displayError("The registry is not a top-level array.", quitProcess = true)
    return
  if entryExists(registry, pkgName):
    displayError("Package '" & pkgName & "' is already listed in the " &
      "registry.", quitProcess = true)
    return

  if not yesMode:
    if not isatty(stdout):
      displayError("`tim publish` needs confirmation; re-run with --yes in " &
        "non-interactive environments.", quitProcess = true)
      return
    if not promptConfirm("Open a pull request adding " & pkgName & " " &
        pkgVersion & " to " & pkgsUpstream & "?"):
      displayInfo("Cancelled.")
      quit(0)

  var forkOwner = user
  if directMode:
    forkOwner = "tim-engine"
  elif not ensureFork(user, token):
    return

  let workdir = createTempDir("tim-publish-", "")
  try:
    if not runGit(workdir, "init -q"): return
    if not runGit(workdir, "checkout -q -B " & pkgsDefaultBranch): return
    displayInfo("Fetching " & forkOwner & "/pkgs ...")
    if not runGit(workdir, "pull -q https://github.com/" & forkOwner &
        "/pkgs.git " & pkgsDefaultBranch): return
    if forkOwner != "tim-engine":
      displayInfo("Syncing with upstream ...")
      if not runGit(workdir, "pull -q " & pkgsUpstreamUrl & ".git " &
          pkgsDefaultBranch): return
    let (idName, idEmail) = gitIdentity()
    if not runGit(workdir, "config user.name " & quoteShell(idName)): return
    if not runGit(workdir, "config user.email " & quoteShell(idEmail)): return
    let pkgsFile = workdir / "packages.json"
    if not fileExists(pkgsFile):
      displayError("No packages.json found in " & forkOwner & "/pkgs.",
        quitProcess = true)
      return
    var packagesJson: JsonNode
    try:
      packagesJson = parseJson(readFile(pkgsFile))
    except CatchableError as e:
      displayError("Could not parse packages.json: " & e.msg,
        quitProcess = true)
      return
    if packagesJson.kind != JArray:
      displayError("packages.json is not a top-level array.", quitProcess = true)
      return
    if entryExists(packagesJson, pkgName):
      displayError("Package '" & pkgName & "' appeared in packages.json " &
        "while working (already listed).", quitProcess = true)
      return
    writeFile(pkgsFile, pretty(insertEntrySorted(packagesJson, entry)))
    if not runGit(workdir, "checkout -q -B " & branchName): return
    if not runGit(workdir, "add packages.json"): return
    if not runGit(workdir, "commit -q -m " &
        quoteShell("Add " & pkgName & " " & pkgVersion)): return
    displayInfo("Pushing branch " & branchName & " ...")
    if not pushBranch(workdir,
        "https://x-access-token@github.com/" & forkOwner & "/pkgs.git",
        branchName, token): return
    displayInfo("Creating pull request ...")
    let prUrl = createPullRequest(token, forkOwner, branchName,
      prTitle(pkgName, pkgVersion),
      prBody(pkgName, pkgVersion, url, pkgDesc, extraMsg, tagged))
    if prUrl.len == 0:
      displayError("Pull request creation failed.", quitProcess = true)
      return
    displaySuccess("Pull request opened: " & prUrl)
  finally:
    try: removeDir(workdir)
    except OSError, IOError: discard
