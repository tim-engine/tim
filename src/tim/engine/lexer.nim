# A super fast template engine for cool kids
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim | https://openpeeps.dev/packages/tim

import std/strutils

type
  TokenKind* = enum
    tkEof, tkIdentifier, tkInteger, tkFloat, tkString,
    tkPlus, tkMinus, tkAsterisk, tkDivide, tkMod, tkCaret,
    tkLC, tkRC, tkLP, tkRP, tkLB, tkRB, tkDot, tkId, tkTernary,
    tkExc, tkNe, tkAssign, tkEq, tkColon, tkComma, tkScolon,
    tkGt, tkGte, tkLt, tkLte, tkAmp, tkAndAnd, tkPipe, tkOrOr,
    tkBacktick, tkSqString,
    tkCase = "case",
    tkOf = "of",
    tkIf = "if",
    tkElif = "elif",
    tkElse = "else",
    tkAnd = "and",
    tkFor = "for",
    tkWhile = "while",
    tkIn = "in",
    tkOr = "or",
    tkBool, tkLitObject,
    tkAt, tkImport, tkSnippetHtml, tkSnippetJs, tkSnippetYaml,
    tkSnippetCSS, tkSnippetJson, tkSnippetMarkdown,
    tkPlaceholder, tkViewLoader,
    tkClient, tkEnd, tkInclude, tkDo, tkFn = "fn",
    tkFunc = "func",
    tkMacro = "macro",
    tkIterator = "iterator",
    tkYield = "yield",
    tkComponent, tkVar = "var",
    tkConst = "const",
    tkType = "type",
    tkReturnCmd = "return",
    tkDiscardCmd = "discard",
    tkBreakCmd = "break",
    tkContinueCmd = "continue",
    tkIdentVar, tkIdentVarSafe,
    tkStatic, tkEcho = "echo",
    tkComment, tkDoc, tkHtmlComment, tkNil = "nil",
    tkUnknown

  TokenTuple* = tuple
    kind: TokenKind
    value: string
    line: int
    col: int
    pos: int
    wsno: int
    # attr: seq[string] # Additional attributes for future use

  Lexer* = object
    input*: string
    pos*, line*, col*: int
    current*: char
    strbuf*: string # For building strings

  TimLexerError* = object of CatchableError

proc newLexer*(input: string): Lexer =
  result.input = input
  result.pos = 0
  result.line = 1
  result.col = 0
  result.strbuf = ""
  if input.len > 0:
    result.current = input[0]
  else:
    result.current = '\0'

proc charAt(l: Lexer, idx: int): char {.inline.} =
  if idx < 0 or idx >= l.input.len: return '\0'
  l.input[idx]

proc getContext(l: Lexer, posOverride: int = -1): string =
  # Show the full current line and place caret at exact token position.
  let rawPos = if posOverride >= 0: posOverride else: l.pos
  let atPos = max(0, min(rawPos, l.input.len))

  var lineStart = atPos
  while lineStart > 0 and l.charAt(lineStart - 1) != '\n':
    dec lineStart

  var lineEnd = atPos
  while lineEnd < l.input.len and l.charAt(lineEnd) notin {'\n', '\r'}:
    inc lineEnd

  var snippet: string
  if l.input.len > 0:
    snippet = l.input[lineStart ..< lineEnd]
  else:
    snippet = newStringOfCap(max(0, lineEnd - lineStart))
    for i in lineStart ..< lineEnd:
      snippet.add(l.charAt(i))

  let markerPos = max(0, min(snippet.len, atPos - lineStart))
  result = snippet & "\n" & " ".repeat(markerPos) & "^"

proc error*(l: var Lexer, msg: string) =
  # Raise a lexer error
  let context = getContext(l)
  raise newException(TimLexerError, ("\n" & context & "\n" & "Error ($1:$2) " % [$l.line, $l.col]) & msg)

proc advance(lex: var Lexer) =
  if lex.pos < lex.input.len:
    if lex.current == '\n':
      inc lex.line
      lex.col = 0
    else:
      inc lex.col
    inc lex.pos
    if lex.pos < lex.input.len:
      lex.current = lex.input[lex.pos]
    else:
      lex.current = '\0'

proc peek(lex: Lexer, offset = 1): char =
  let idx = lex.pos + offset
  if idx < lex.input.len: lex.input[idx] else: '\0'

proc skipWhitespace(lex: var Lexer) =
  while lex.current in {' ', '\t', '\r'}:
    lex.advance()

proc peekToken(lex: Lexer, expectToken: string): bool =
  # Peeks ahead to see if the next token matches expectToken without advancing the lexer
  var i = 0
  var pos = lex.pos
  # Skip whitespace
  while pos < lex.input.len and lex.input[pos] in {' ', '\t', '\r'}:
    inc pos
  # Now check for expectToken
  for ch in expectToken:
    if pos >= lex.input.len or lex.input[pos] != ch:
      return false
    inc pos
  return true

proc initToken(lex: var Lexer, kind: static TokenKind, line, col, pos, wsno: int): TokenTuple =
  (kind, "", line, col, pos, wsno)

proc initToken(lex: var Lexer, kind: TokenKind, value: sink string, line, col, pos, wsno: int): TokenTuple =
  (kind, value, line, col, pos, wsno)

template collectSnippet(tkKind: TokenKind, tkStr: string) =
  # Collects a magic code snippet until `@end` is found 
  result = initToken(lex, tkSnippetJs, "", line, col, pos, wsno)
  skipWhitespace(lex)
  while true:
    case lex.current
    of '\0':
      lex.error("EOF reached before closing @end for " & tkStr & " snippet")
    of '@':
      if lex.peek(1) == 'e' and lex.peek(2) == 'n' and lex.peek(3) == 'd':
        result.kind = tkKind
        lex.advance() # @
        lex.advance() # e
        lex.advance() # n
        lex.advance() # d
        break
      else:
        result.value.add(lex.current)
        lex.advance()
    else:
      result.value.add(lex.current)
      lex.advance()
      
proc nextToken*(lex: var Lexer): TokenTuple =
  var wsno = 0
  # Skip whitespace and newlines before token
  while true:
    while lex.current in {' ', '\t', '\r'}:
      inc wsno
      lex.advance()
    if lex.current == '\n':
      lex.advance()
      wsno = 0
      continue
    break
  let line = lex.line
  let col = lex.col
  let pos = lex.pos
  case lex.current
  of '\0':
    result = initToken(lex, tkEof, line, col, pos, wsno)
  of '+':
    lex.advance()
    result = initToken(lex, tkPlus, line, col, pos, wsno)
  of '-':
    # Check if this is a negative number literal
    var peekPos = lex.pos + 1
    # Skip whitespace between '-' and potential digit
    while peekPos < lex.input.len and lex.input[peekPos] in {' ', '\t', '\r'}:
      inc peekPos
    if peekPos < lex.input.len and lex.input[peekPos] in {'0'..'9'}:
      # Tokenize as negative number
      lex.advance() # consume '-'
      # Skip whitespace
      while lex.current in {' ', '\t', '\r'}:
        lex.advance()
      lex.strbuf.setLen(0)
      lex.strbuf.add('-')
      var isFloat = false
      # Integer part
      while lex.current in {'0'..'9', '_'}:
        if lex.current != '_':
          lex.strbuf.add(lex.current)
        lex.advance()
      # Fractional part
      if lex.current == '.' and lex.peek().isDigit():
        isFloat = true
        lex.strbuf.add('.')
        lex.advance()
        while lex.current in {'0'..'9', '_'}:
          if lex.current != '_':
            lex.strbuf.add(lex.current)
          lex.advance()
      # Exponent part
      if isFloat and (lex.current == 'e' or lex.current == 'E'):
        lex.strbuf.add(lex.current)
        lex.advance()
        if lex.current == '+' or lex.current == '-':
          lex.strbuf.add(lex.current)
          lex.advance()
        while lex.current in {'0'..'9', '_'}:
          if lex.current != '_':
            lex.strbuf.add(lex.current)
          lex.advance()
        result = initToken(lex, tkFloat, move lex.strbuf, line, col, pos, wsno)
      elif isFloat:
        result = initToken(lex, tkFloat, move lex.strbuf, line, col, pos, wsno)
      else:
        result = initToken(lex, tkInteger, move lex.strbuf, line, col, pos, wsno)
    else:
      lex.advance()
      result = initToken(lex, tkMinus, line, col, pos, wsno)
  of '*':
    lex.advance()
    result = initToken(lex, tkAsterisk, line, col, pos, wsno)
  of '/':
    if lex.peek() == '/':
      lex.advance()
      lex.advance()
      lex.strbuf.setLen(0)
      while lex.current != '\n' and lex.current != '\0':
        lex.strbuf.add(lex.current)
        lex.advance()
      result = initToken(lex, tkComment, move lex.strbuf, line, col, pos, wsno)
    elif lex.peek() == '*':
      lex.advance()
      lex.advance()
      lex.strbuf.setLen(0)
      var prev = '\0'
      while not (prev == '*' and lex.current == '/') and lex.current != '\0':
        if prev != '\0':
          lex.strbuf.add(prev)
        prev = lex.current
        lex.advance()
      if prev != '\0' and not (prev == '*' and lex.current == '/'):
        lex.strbuf.add(prev)
      if lex.current == '/':
        lex.advance()
      result = initToken(lex, tkDoc, move lex.strbuf, line, col, pos, wsno)
    else:
      lex.advance()
      result = initToken(lex, tkDivide, line, col, pos, wsno)
  of '%':
    lex.advance()
    result = initToken(lex, tkMod, line, col, pos, wsno)
  of '^':
    lex.advance()
    result = initToken(lex, tkCaret, line, col, pos, wsno)
  of '{':
    lex.advance()
    result = initToken(lex, tkLC, line, col, pos, wsno)
  of '}':
    lex.advance()
    result = initToken(lex, tkRC, line, col, pos, wsno)
  of '(':
    lex.advance()
    result = initToken(lex, tkLP, line, col, pos, wsno)
  of ')':
    lex.advance()
    result = initToken(lex, tkRP, line, col, pos, wsno)
  of '[':
    lex.advance()
    result = initToken(lex, tkLB, line, col, pos, wsno)
  of ']':
    lex.advance()
    result = initToken(lex, tkRB, line, col, pos, wsno)
  of '.':
    lex.advance()
    result = initToken(lex, tkDot, line, col, pos, wsno)
  of '#':
    lex.advance()
    result = initToken(lex, tkId, line, col, pos, wsno)
  of '?':
    lex.advance()
    result = initToken(lex, tkTernary, line, col, pos, wsno)
  of ':':
    lex.advance()
    result = initToken(lex, tkColon, line, col, pos, wsno)
  of ',':
    lex.advance()
    result = initToken(lex, tkComma, line, col, pos, wsno)
  of ';':
    lex.advance()
    result = initToken(lex, tkScolon, line, col, pos, wsno)
  of '$':
    # todo handle `$$varName` as safe var
    lex.advance()
    case lex.current
    of IdentStartChars:
      lex.strbuf.setLen(0)
      # lex.strbuf.add('$')
      lex.strbuf.add(lex.current)
      lex.advance()
      while lex.current in IdentChars + {'-'}:
        lex.strbuf.add(lex.current)
        lex.advance()
      result = initToken(lex, tkIdentVar, move lex.strbuf, line, col, pos, wsno)
    else: discard
  # Multi-char tokens and tokens with value
  of '!':
    if lex.peek() == '=':
      lex.advance()
      lex.advance()
      result = initToken(lex, tkNe, "!=", line, col, pos, wsno)
    else:
      lex.advance()
      result = initToken(lex, tkExc, line, col, pos, wsno)
  of '=':
    if lex.peek() == '=':
      lex.advance()
      lex.advance()
      result = initToken(lex, tkEq, "==", line, col, pos, wsno)
    else:
      lex.advance()
      result = initToken(lex, tkAssign, line, col, pos, wsno)
  of '>':
    if lex.peek() == '=':
      lex.advance()
      lex.advance()
      result = initToken(lex, tkGte, ">=", line, col, pos, wsno)
    else:
      lex.advance()
      result = initToken(lex, tkGt, line, col, pos, wsno)
  of '<':
    if lex.peek() == '!' and lex.peek(2) == '-' and lex.peek(3) == '-':
      # HTML comment <!-- ... -->
      lex.advance() # <
      lex.advance() # !
      lex.advance() # -
      lex.advance() # -
      lex.strbuf.setLen(0)
      while true:
        if lex.current == '-' and lex.peek() == '-' and lex.peek(2) == '>':
          lex.advance() # -
          lex.advance() # -
          lex.advance() # >
          break
        if lex.current == '\0':
          lex.error("EOF reached before closing --> for HTML comment")
        lex.strbuf.add(lex.current)
        lex.advance()
      result = initToken(lex, tkHtmlComment, move lex.strbuf, line, col, pos, wsno)
    elif lex.peek() == '=':
      lex.advance()
      lex.advance()
      result = initToken(lex, tkLte, "<=", line, col, pos, wsno)
    else:
      lex.advance()
      result = initToken(lex, tkLt, line, col, pos, wsno)
  of '&':
    if lex.peek() == '&':
      lex.advance()
      lex.advance()
      result = initToken(lex, tkAndAnd, "&&", line, col, pos, wsno)
    else:
      lex.advance()
      result = initToken(lex, tkAmp, line, col, pos, wsno)
  of '|':
    if lex.peek() == '|':
      lex.advance()
      lex.advance()
      result = initToken(lex, tkOrOr, "||", line, col, pos, wsno)
    else:
      lex.advance()
      result = initToken(lex, tkPipe, line, col, pos, wsno)
  of '\'':
    lex.advance()
    lex.strbuf.setLen(0)
    while lex.current != '\'' and lex.current != '\0' and lex.current != '\n':
      lex.strbuf.add(lex.current)
      lex.advance()
    if lex.current == '\'':
      lex.advance()
    result = initToken(lex, tkSqString, move lex.strbuf, line, col, pos, wsno)
  of '"':
    if lex.peek() == '"' and lex.peek(2) == '"':
      # Triple-quoted string
      lex.advance() # "
      lex.advance() # "
      lex.advance() # "
      lex.strbuf.setLen(0)
      while not (lex.current == '"' and lex.peek() == '"' and lex.peek(2) == '"') and lex.current != '\0':
        lex.strbuf.add(lex.current)
        lex.advance()
      if lex.current == '"' and lex.peek() == '"' and lex.peek(2) == '"':
        lex.advance()
        lex.advance()
        lex.advance()
      result = initToken(lex, tkString, move lex.strbuf, line, col, pos, wsno)
    else:
      lex.advance()
      lex.strbuf.setLen(0)
      while lex.current != '"' and lex.current != '\0' and lex.current != '\n':
        if lex.current == '\\':
          lex.advance()
          case lex.current
          of 'n': lex.strbuf.add('\n')
          of 'r': lex.strbuf.add('\r')
          of 't': lex.strbuf.add('\t')
          of '"': lex.strbuf.add('"')
          of '\\': lex.strbuf.add('\\')
          of '0': lex.strbuf.add('\0')
          else: lex.strbuf.add(lex.current)
          lex.advance()
        else:
          lex.strbuf.add(lex.current)
          lex.advance()
      if lex.current == '"':
        lex.advance()
      result = initToken(lex, tkString, move lex.strbuf, line, col, pos, wsno)
  of '`':
    lex.advance()
    lex.strbuf.setLen(0)
    while lex.current != '`' and lex.current != '\0' and lex.current != '\n':
      lex.strbuf.add(lex.current)
      lex.advance()
    if lex.current == '`':
      lex.advance()
    result = initToken(lex, tkBacktick, move lex.strbuf, line, col, pos, wsno)
  of '@':
    lex.advance()
    lex.strbuf.setLen(0)
    let
      savePos = lex.pos
      saveCol = lex.col
    while lex.current.isAlphaAscii():
      lex.strbuf.add(lex.current)
      lex.advance()
    case lex.strbuf
    of "import":
      result = initToken(lex, tkImport, "@import", line, col, pos, wsno)
    of "include":
      result = initToken(lex, tkInclude, "@include", line, col, pos, wsno)
    of "javascript":
      collectSnippet(tkSnippetJs, "@javascript")
    of "css":
      collectSnippet(tkSnippetCSS, "@css")
    of "js":
      lex.error("The `@js` snippet is no longer supported. Use `@javascript` instead for better readability.")
    of "html":
      collectSnippet(tkSnippetHtml, "@html")
    of "yaml":
      result = initToken(lex, tkSnippetYaml, "@yaml", line, col, pos, wsno)
    of "json":
      result = initToken(lex, tkSnippetJson, "@json", line, col, pos, wsno)
    of "md":
      result = initToken(lex, tkSnippetMarkdown, "@md", line, col, pos, wsno)
    of "view":
      result = initToken(lex, tkViewLoader, "@view", line, col, pos, wsno)
    of "client":
      result = initToken(lex, tkClient, "@client", line, col, pos, wsno)
    of "end":
      result = initToken(lex, tkEnd, "@end", line, col, pos, wsno)
    of "static":
      result = initToken(lex, tkStatic, "@static", line, col, pos, wsno)
    else:
      if lex.strbuf.len > 0:
        lex.pos = savePos
        lex.col = saveCol
        if lex.pos < lex.input.len:
          lex.current = lex.input[lex.pos]
      result = initToken(lex, tkAt, line, col, pos, wsno)
  of '0'..'9':
    lex.strbuf.setLen(0)
    var isFloat = false
    # Integer part
    while lex.current in {'0'..'9', '_'}:
      if lex.current != '_':
        lex.strbuf.add(lex.current)
      lex.advance()
    # Fractional part
    if lex.current == '.' and lex.peek().isDigit():
      isFloat = true
      lex.strbuf.add('.')
      lex.advance()
      while lex.current in {'0'..'9', '_'}:
        if lex.current != '_':
          lex.strbuf.add(lex.current)
        lex.advance()
    # Exponent part
    if isFloat and (lex.current == 'e' or lex.current == 'E'):
      lex.strbuf.add(lex.current)
      lex.advance()
      if lex.current == '+' or lex.current == '-':
        lex.strbuf.add(lex.current)
        lex.advance()
      while lex.current in {'0'..'9', '_'}:
        if lex.current != '_':
          lex.strbuf.add(lex.current)
        lex.advance()
      return initToken(lex, tkFloat, move lex.strbuf, line, col, pos, wsno)
    result = initToken(lex, tkInteger, move lex.strbuf, line, col, pos, wsno)
  else:
    if lex.current.isAlphaAscii() or lex.current in {'_', '-'}:
      lex.strbuf.setLen(0)
      while lex.current.isAlphaNumeric() or lex.current in {'_', '-'}:
        lex.strbuf.add(lex.current)
        lex.advance()
      case lex.strbuf
      of "true", "false":
        result = initToken(lex, tkBool, move lex.strbuf, line, col, pos, wsno)
      of "case":
        result = initToken(lex, tkCase, move lex.strbuf, line, col, pos, wsno)
      of "of":
        result = initToken(lex, tkOf, move lex.strbuf, line, col, pos, wsno)
      of "if":
        result = initToken(lex, tkIf, move lex.strbuf, line, col, pos, wsno)
      of "elif":
        result = initToken(lex, tkElif, move lex.strbuf, line, col, pos, wsno)
      of "else":
        result = initToken(lex, tkElse, move lex.strbuf, line, col, pos, wsno)
      of "and":
        result = initToken(lex, tkAnd, move lex.strbuf, line, col, pos, wsno)
      of "for":
        result = initToken(lex, tkFor, move lex.strbuf, line, col, pos, wsno)
      of "while":
        result = initToken(lex, tkWhile, move lex.strbuf, line, col, pos, wsno)
      of "in":
        result = initToken(lex, tkIn, move lex.strbuf, line, col, pos, wsno)
      of "or":
        result = initToken(lex, tkOr, move lex.strbuf, line, col, pos, wsno)
      of "type":
        result = initToken(lex, tkType, move lex.strbuf, line, col, pos, wsno)
      of "object":
        result = initToken(lex, tkLitObject, move lex.strbuf, line, col, pos, wsno)
      of "fn":
        result = initToken(lex, tkFn, move lex.strbuf, line, col, pos, wsno)
      of "func":
        result = initToken(lex, tkFunc, move lex.strbuf, line, col, pos, wsno)
      of "iterator":
        result = initToken(lex, tkIterator, move lex.strbuf, line, col, pos, wsno)
      of "macro":
        result = initToken(lex, tkMacro, move lex.strbuf, line, col, pos, wsno)
      of "break":
        result = initToken(lex, tkBreakCmd, move lex.strbuf, line, col, pos, wsno)
      of "var":
        result = initToken(lex, tkVar, move lex.strbuf, line, col, pos, wsno)
      of "const":
        result = initToken(lex, tkConst, move lex.strbuf, line, col, pos, wsno)
      of "return":
        result = initToken(lex, tkReturnCmd, move lex.strbuf, line, col, pos, wsno)
      of "discard":
        result = initToken(lex, tkDiscardCmd, move lex.strbuf, line, col, pos, wsno)
      of "continue":
        result = initToken(lex, tkContinueCmd, move lex.strbuf, line, col, pos, wsno)
      of "echo":
        result = initToken(lex, tkEcho, move lex.strbuf, line, col, pos, wsno)
      of "yield":
        result = initToken(lex, tkYield, move lex.strbuf, line, col, pos, wsno)
      of "nil":
        result = initToken(lex, tkNil, move lex.strbuf, line, col, pos, wsno)
      else:
        result = initToken(lex, tkIdentifier, move lex.strbuf, line, col, pos, wsno)
    else:
      result = initToken(lex, tkUnknown, $lex.current, line, col, pos, wsno)
      lex.advance()

proc getToken*(lex: var Lexer): TokenTuple =
  result = lex.nextToken()
