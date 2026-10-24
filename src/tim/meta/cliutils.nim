# Tim Engine — minimal stdlib CLI helpers
#
# (c) 2025 George Lemon | LGPL-3.0-or-later
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim
#
# Replaces the `kapsis` display/prompt layer with stdlib-only
# (`std/terminal`, `std/parseopt` style) helpers, mirroring the
# approach used by SweetSyntax.

import std/[os, terminal, strutils]

# ----------------------------------------------------------------------
# Version (read from `tim.nimble` at compile time)
# ----------------------------------------------------------------------

proc findTimNimble(base: string): string {.compileTime.} =
  ## Locate `tim.nimble` relative to this file. In the repo it sits three
  ## levels up (`src/tim/meta/` -> root); for an installed package it sits
  ## two levels up (`tim/meta/` -> package root).
  for rel in ["../../tim.nimble", "../../../tim.nimble"]:
    let cand = base / rel
    when defined(windows):
      let found = staticExec("cmd /c dir /b /a-d \"" & cand &
        "\" 2>nul").strip()
    else:
      let found = staticExec("ls \"" & cand & "\" 2>/dev/null").strip()
    if found.len > 0:
      return cand
  return ""

proc parseNimbleVersion(content: string): string {.compileTime.} =
  ## Extract `version = "..."` from a `.nimble` file's contents.
  for line in content.splitLines():
    let t = line.strip()
    if t.len == 0 or t[0] == '#':
      continue
    let eq = t.find('=')
    if eq < 0:
      continue
    if t[0 ..< eq].strip() != "version":
      continue
    var v = t[eq + 1 .. ^1].strip()
    if v.len >= 2 and v[0] == '"' and v[^1] == '"':
      v = v[1 .. ^2]
    return v
  return ""

const cliSrcDir = currentSourcePath().parentDir()
const timNimblePath = findTimNimble(cliSrcDir)

const timVersion* =
  when timNimblePath.len > 0:
    parseNimbleVersion(staticRead(timNimblePath))
  else:
    "unknown"

# ----------------------------------------------------------------------
# Colors
# ----------------------------------------------------------------------

const
  ansiReset = "\e[0m"
  ansiBoldWhite = "\e[1;37m"
  ansiGrey = "\e[90m"
  ansiCyan = "\e[36m"
  ansiGreen = "\e[32m"
  ansiYellow = "\e[33m"
  ansiRed = "\e[31m"

proc useColor*(): bool =
  getEnv("NO_COLOR") == "" and getEnv("TERM") != "dumb"

proc paint(s, code: string): string =
  if useColor():
    code & s & ansiReset
  else:
    s

proc label*(s: string): string =
  paint(s, ansiBoldWhite)

proc grey*(s: string): string =
  paint(s, ansiGrey)

proc cyan*(s: string): string =
  paint(s, ansiCyan)

proc errPrefix*(): string =
  paint("error:", ansiRed)

# ----------------------------------------------------------------------
# Display helpers (stdout, kapsis-compatible signatures)
# ----------------------------------------------------------------------

proc display*(s: string) =
  echo s

proc displayInfo*(x: string) =
  echo paint("Info:", ansiCyan) & " " & x

proc displaySuccess*(x: string) =
  echo paint("Success:", ansiGreen) & " " & x

proc displayWarning*(x: string) =
  echo paint("Warning:", ansiYellow) & " " & x

proc displayError*(x: string, quitProcess = false) =
  echo paint("Error:", ansiRed) & " " & x
  if quitProcess:
    quit(1)

# ----------------------------------------------------------------------
# Prompts (blocking stdin reads, no external deps)
# ----------------------------------------------------------------------

proc prompt*(label: string, default = ""): string =
  ## Ask a question and read one line. Returns `default` on empty input,
  ## quits the process on EOF (mirrors kapsis `prompt` behaviour).
  var q = label.strip()
  if default.len > 0:
    q = q & " (" & default & ")"
  if not (q.endsWith(":") or q.endsWith("?")):
    q.add(":")
  stdout.write(q & " ")
  stdout.flushFile()
  try:
    let input = stdin.readLine().strip()
    result = if input.len > 0: input else: default
  except EOFError, IOError:
    quit()

proc promptConfirm*(label: string): bool =
  ## Ask a yes/no question until a boolean answer is given.
  ## Accepts: `1/yes/true/y` (positive), `0/no/false/n` (negative).
  while true:
    let answer = prompt(label).strip()
    case answer
    of "true", "1", "yes", "True", "TRUE", "YES", "Yes", "y", "Y":
      return true
    of "false", "0", "no", "False", "FALSE", "NO", "No", "n", "N":
      return false
    else:
      discard

proc eraseSelection(answersLen: int) =
  ## Erases the rendered selection lines and restores the cursor.
  for i in 0 ..< answersLen:
    eraseLine(stdout)
    cursorDown(stdout)
  cursorUp(stdout, answersLen + 1)
  eraseLine(stdout)
  showCursor(stdout)

proc promptInteractive*(question: string, answers: openArray[string],
    width: Positive = 80, activeIcon = " "): int =
  ## Terminal prompt that asks a `question` and returns the index of the
  ## chosen answer (arrow keys / Tab to move, Space or Enter to confirm,
  ## Ctrl-C aborts and returns -1).
  assert question.len > 0, "Question must not be empty"
  assert answers.len > 0, "There must be at least one possible answer"
  stdout.styledWriteLine(styleBright, question)
  var
    current = 0
    selected = false
  # Incase the cursor is at the bottom of the terminal
  for arg in answers:
    stdout.write "\n"
  # Reset the cursor to the start of the selection prompt
  cursorUp(stdout, answers.len)
  hideCursor(stdout)

  # The selection loop
  while not selected:
    when defined(windows):
      setForegroundColor(fgWhite)
    else:
      setForegroundColor(fgDefault)
    # Loop through the options
    for i, arg in answers:
      # Check if the option is the current
      if i == current:
        stdout.styledWrite(activeIcon & " " & arg, {styleBright, styleUnderscore})
      else:
        stdout.styledWrite("   " & arg, {styleDim})
      # Move the cursor back to the start
      cursorBackward(stdout, arg.len + 4)
      # Move down for the next item
      cursorDown(stdout)
    # Move the cursor back up to the start of the selection prompt
    cursorUp(stdout, answers.len)
    resetAttributes(stdout)

    # Ensure that the screen is updated before input
    flushFile(stdout)
    # Begin key input
    while true:
      case getch():
      of '\t', '\x1B':
        current = (current + 1) mod answers.len
        break
      of '\r', ' ':
        selected = true
        break
      of '\3':
        for i in 0 ..< answers.len:
          eraseLine(stdout)
        cursorUp(stdout) # move back to question line
        eraseLine(stdout) # erase the question line
        showCursor(stdout)
        return -1
      else: discard

  # Erase all lines of the selection
  eraseSelection(answers.len)
  result = current
