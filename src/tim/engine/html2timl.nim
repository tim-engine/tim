# A super fast template engine for cool kids
#
# (c) 2026 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[algorithm, sequtils, sets, strutils, tables]
import pkg/openparser/html

type
  Html2TimlError* = object of CatchableError
    path*: string

const
  TimlIndent* = "  "
  MaxHtml2TimlDepth* = 256
  RawMarkupMarkers = ["<!doctype", "<?", "<![cdata["]
  TemplateMarkers = ["{{", "{%", "{#", "<%", "%>"]
  VoidTagNames = ["area", "base", "br", "col", "embed", "hr", "img",
    "input", "link", "meta", "param", "source", "track", "wbr"]
  # Attribute names lexed as TIML keywords never reach Tim's attribute parser
  # (`type` is the verified exception, handled by `parseAttributes`).
  TimlKeywordAttrNames = ["case", "of", "if", "elif", "else", "and", "for",
    "while", "in", "or", "fn", "func", "iterator", "macro", "break", "var",
    "const", "return", "discard", "continue", "echo", "yield", "nil",
    "object", "true", "false"]

proc defaultHtml2TimlPolicy*(): HtmlParserPolicy =
  ## Use OpenParser's tolerant policy. Structural errors (unclosed or
  ## mismatched tags) are enforced separately by `assertBalanced`, because
  ## OpenParser's own strict unclosed-tag check also fires for correctly
  ## closed documents ending at EOF.
  result = defaulHtmlParsingPolicy()
  result.allowComments = true
  result.allowInvalidSyntax = false

proc failConversion(sourcePath, nodePath, detail: string) {.noreturn.} =
  let prefix =
    if sourcePath.len > 0:
      if nodePath.len > 0: sourcePath & ": " & nodePath & ": "
      else: sourcePath & ": "
    elif nodePath.len > 0:
      nodePath & ": "
    else:
      ""
  var e = newException(Html2TimlError, prefix & detail)
  e.path = sourcePath
  raise e

proc assertSupportedSource(source, sourcePath: string) =
  if '\0' in source:
    failConversion(sourcePath, "", "NUL bytes are not supported")
  let lowered = source.toLowerAscii()
  for marker in RawMarkupMarkers:
    if marker in lowered:
      failConversion(sourcePath, "",
        "DOCTYPE, processing instructions, and CDATA are not supported")

proc assertNoTemplateSyntax(value, sourcePath, nodePath, field: string) =
  for marker in TemplateMarkers:
    if marker in value:
      failConversion(sourcePath, nodePath,
        "template syntax in " & field & " is not supported: " & marker)

proc isTagChar(c: char): bool =
  c.isAlphaNumeric() or c in {'-', '_', ':', '.'}

proc skipTagSpaces(source: string, j: var int) =
  while j < source.len and source[j] in {' ', '\t', '\r', '\n'}:
    inc j

proc parseTagName(source: string, j: var int): string =
  let start = j
  while j < source.len and isTagChar(source[j]):
    inc j
  source[start ..< j]

proc assertBalanced(source, sourcePath: string) =
  ## Enforce the strict, well-formed subset of HTML that `h2t` supports.
  ## OpenParser silently repairs or normalizes malformed input (and drops
  ## `>`, `/`, `=` inside text), so structural validation happens here on
  ## the raw source before parsing.
  var stack: seq[string] = @[]
  var i = 0
  while i < source.len:
    if source[i] != '<':
      let start = i
      while i < source.len and source[i] != '<':
        inc i
      let text = source[start ..< i]
      if '>' in text:
        failConversion(sourcePath, "",
          "raw `>` in text is not preserved; use `&gt;`")
      if '/' in text:
        failConversion(sourcePath, "",
          "raw `/` in text is not preserved; use `&#47;`")
      if '=' in text:
        failConversion(sourcePath, "",
          "raw `=` in text is not preserved; use `&#61;`")
      continue
    if source.continuesWith("<!--", i):
      let close = source.find("-->", i + 4)
      if close < 0:
        failConversion(sourcePath, "", "unclosed comment")
      i = close + 3
      continue
    if i + 1 < source.len and source[i + 1] == '/':
      var j = i + 2
      skipTagSpaces(source, j)
      let name = parseTagName(source, j)
      if name.len == 0:
        failConversion(sourcePath, "", "malformed closing tag")
      skipTagSpaces(source, j)
      if j >= source.len or source[j] != '>':
        failConversion(sourcePath, "", "malformed closing tag </" & name & ">")
      if stack.len == 0:
        failConversion(sourcePath, "", "stray closing tag </" & name & ">")
      let open = stack.pop()
      if open != name.toLowerAscii():
        failConversion(sourcePath, "",
          "mismatched tags: <" & open & "> closed by </" & name & ">")
      i = j + 1
      continue
    if i + 1 < source.len and source[i + 1] in {'!', '?'}:
      failConversion(sourcePath, "", "unsupported markup declaration")
    var j = i + 1
    let name = parseTagName(source, j)
    if name.len == 0:
      failConversion(sourcePath, "", "stray `<` in text; escape it as `&lt;`")
    let lowered = name.toLowerAscii()
    # Scan the tag quote-aware to its closing `>`.
    var quote = '\0'
    var inValue = false
    var selfClose = false
    var k = j
    while k < source.len:
      let c = source[k]
      if quote != '\0':
        if c == quote:
          quote = '\0'
        elif c in {'<', '>'}:
          failConversion(sourcePath, "",
            "unsupported `<` or `>` inside attribute value")
      elif c in {'"', '\''}:
        quote = c
        inValue = false
      elif c == '=':
        inValue = true
      elif c in {' ', '\t', '\r', '\n'}:
        inValue = false
      elif c == '>':
        break
      elif c == '/' and k + 1 < source.len and source[k + 1] == '>':
        selfClose = true
        break
      elif c == '/' and inValue:
        failConversion(sourcePath, "",
          "unquoted `/` in attribute value is not supported; quote the value")
      k.inc()
    if k >= source.len:
      failConversion(sourcePath, "", "unclosed tag <" & name & ">")
    if quote != '\0':
      failConversion(sourcePath, "", "unterminated attribute value")
    if selfClose and lowered notin VoidTagNames:
      failConversion(sourcePath, "",
        "self-closing syntax on non-void <" & name & "> is ambiguous")
    if lowered in VoidTagNames or selfClose:
      i = k + 1
      continue
    if lowered in ["script", "style"]:
      # Treat the body as raw text up to the matching close tag.
      let rest = source[k .. ^1].toLowerAscii()
      let rel = rest.find("</" & lowered)
      if rel < 0:
        failConversion(sourcePath, "", "unclosed tag <" & name & ">")
      var m = k + rel + lowered.len + 2
      skipTagSpaces(source, m)
      if m >= source.len or source[m] != '>':
        failConversion(sourcePath, "", "malformed closing tag </" & name & ">")
      i = m + 1
      continue
    stack.add(lowered)
    i = k + 1
  if stack.len > 0:
    failConversion(sourcePath, "", "unclosed tag <" & stack[^1] & ">")

proc isSimpleName(value: string): bool =
  if value.len == 0 or value.len > 128:
    return false
  if value[0] notin {'A'..'Z', 'a'..'z', '_'}:
    return false
  for c in value:
    if c notin {'A'..'Z', 'a'..'z', '0'..'9', '_', '-'}:
      return false
  true

proc isSupportedAttributeName(name: string): bool =
  if name.len == 0 or name.len > 128:
    return false
  if name[0] notin {'A'..'Z', 'a'..'z', '_'}:
    return false
  for c in name:
    if c notin {'A'..'Z', 'a'..'z', '0'..'9', '_', '-', ':'}:
      return false
  true

proc quoteTiml(value, sourcePath, nodePath, field: string): string =
  ## Quote a value as a TIML string literal. Double-quoted strings process
  ## backslash escapes; triple-quoted strings keep raw text (including real
  ## newlines) because the TIML lexer does not process escapes in them.
  var multiline = false
  for c in value:
    if c in {'\n', '\r'}:
      multiline = true
      break
  if not multiline:
    result = "\""
    for c in value:
      case c
      of '\\': result.add("\\\\")
      of '"': result.add("\\\"")
      else: result.add(c)
    result.add('"')
    return
  if "\"\"\"" in value:
    failConversion(sourcePath, nodePath,
      "text in " & field & " cannot be represented in TIML")
  result = "\"\"\"" & value & "\"\"\""

proc appendLine(buf: var string, indent: int, line: string) =
  if buf.len > 0:
    buf.add('\n')
  for _ in 0 ..< indent:
    buf.add(TimlIndent)
  buf.add(line)

proc appendText(buf: var string, indent: int, value, sourcePath, nodePath: string) =
  assertNoTemplateSyntax(value, sourcePath, nodePath, "text")
  appendLine(buf, indent, quoteTiml(value, sourcePath, nodePath, "text"))

proc appendComment(buf: var string, indent: int, value, sourcePath, nodePath: string) =
  assertNoTemplateSyntax(value, sourcePath, nodePath, "comment")
  appendLine(buf, indent, "<!-- " & value.strip() & " -->")

proc appendNodes(nodes: seq[HtmlNode], buf: var string,
    sourcePath, parentPath: string, indent, depth: int)

proc appendAttributes(buf: var string, node: HtmlNode,
    sourcePath, nodePath: string) =
  if node.attributes == nil:
    return
  var names = toSeq(node.attributes.keys)
  names.sort()
  var classes: seq[string] = @[]
  var classSeen = initHashSet[string]()
  var id = ""
  var hasId = false
  var classValue = ""
  var hasClass = false

  for name in names:
    if name.toLowerAscii() == "class":
      hasClass = true
      classValue = node.attributes[name]
    elif name.toLowerAscii() == "id":
      hasId = true
      id = node.attributes[name]

  if hasClass:
    assertNoTemplateSyntax(classValue, sourcePath, nodePath, "class attribute")
    for className in classValue.splitWhitespace():
      if not isSimpleName(className):
        classes = @[]
        break
      if className notin classSeen:
        classSeen.incl(className)
        classes.add(className)
  if hasId:
    assertNoTemplateSyntax(id, sourcePath, nodePath, "id attribute")

  for className in classes:
    buf.add('.')
    buf.add(className)
  if hasId and isSimpleName(id):
    buf.add('#')
    buf.add(id)

  for name in names:
    let lowered = name.toLowerAscii()
    if lowered == "class" and classes.len > 0:
      continue
    if lowered == "id" and hasId and isSimpleName(id):
      continue
    if not isSupportedAttributeName(name):
      failConversion(sourcePath, nodePath,
        "unsupported attribute name: " & name)
    if name in TimlKeywordAttrNames:
      failConversion(sourcePath, nodePath,
        "attribute `" & name & "` collides with TIML syntax")
    let value = node.attributes[name]
    assertNoTemplateSyntax(value, sourcePath, nodePath,
      "attribute `" & name & "`")
    buf.add(' ')
    buf.add(name)
    if value.len > 0:
      buf.add('=')
      buf.add(quoteTiml(value, sourcePath, nodePath,
        "attribute `" & name & "`"))

proc appendElement(buf: var string, node: HtmlNode, indent, depth: int,
    sourcePath, nodePath: string) =
  if node.tag == tagUnknown:
    failConversion(sourcePath, nodePath, "unknown or custom tags are not supported")
  let tag = $node.tag
  if node.tag in {tagScript, tagStyle} and node.children.len > 0:
    failConversion(sourcePath, nodePath,
      "inline `" & tag & "` content is not supported")
  if node.tag in {tagPre, tagTextarea}:
    failConversion(sourcePath, nodePath,
      "exact whitespace in `" & tag & "` is not preserved")

  var line = tag
  var attrs = ""
  appendAttributes(attrs, node, sourcePath, nodePath)
  line.add(attrs)

  if node.children.len == 1 and node.children[0] != nil and
      node.children[0].kind == htmlInnerText:
    let text = node.children[0].value.text
    assertNoTemplateSyntax(text, sourcePath, nodePath & ".children[0]", "text")
    line.add(": ")
    line.add(quoteTiml(text, sourcePath, nodePath & ".children[0]", "text"))
    appendLine(buf, indent, line)
    return

  appendLine(buf, indent, line)
  appendNodes(node.children, buf, sourcePath, nodePath, indent + 1, depth + 1)

proc appendNode(buf: var string, node: HtmlNode, indent, depth: int,
    sourcePath, nodePath: string) =
  if node == nil:
    failConversion(sourcePath, nodePath, "HTML node is nil")
  if depth > MaxHtml2TimlDepth:
    failConversion(sourcePath, nodePath, "HTML exceeds maximum nesting depth")
  case node.kind
  of htmlInnerText:
    if node.value.text.strip().len == 0:
      return
    appendText(buf, indent, node.value.text, sourcePath, nodePath)
  of htmlComment:
    appendComment(buf, indent, node.comment, sourcePath, nodePath)
  of htmlTag:
    appendElement(buf, node, indent, depth, sourcePath, nodePath)

proc appendNodes(nodes: seq[HtmlNode], buf: var string,
    sourcePath, parentPath: string, indent, depth: int) =
  for i, node in nodes:
    let nodePath =
      if parentPath.len > 0: parentPath & ".children[" & $i & "]"
      else: "nodes[" & $i & "]"
    if node != nil and node.kind == htmlInnerText:
      if node.value.text.strip().len == 0:
        continue
      if parentPath.len == 0:
        failConversion(sourcePath, nodePath,
          "top-level text must be wrapped in an HTML element")
    appendNode(buf, node, indent, depth, sourcePath, nodePath)

proc htmlToTiml*(doc: HtmlDocument, sourcePath = ""): string =
  ## Convert an OpenParser HTML document to TIML source.
  ##
  ## The conversion is intentionally limited to static, known HTML tags.
  ## Whitespace is normalized by OpenParser, while entities and attribute
  ## values are preserved literally.
  result = ""
  appendNodes(doc.nodes, result, sourcePath, "", 0, 0)
  if result.strip().len == 0:
    failConversion(sourcePath, "", "HTML document contains no convertible nodes")

proc parseHtmlToTiml*(source: string, sourcePath = "",
    policy: HtmlParserPolicy = defaultHtml2TimlPolicy()): string =
  assertSupportedSource(source, sourcePath)
  assertBalanced(source, sourcePath)
  var doc: HtmlDocument
  try:
    doc = parseHtml(source, policy)
  except HtmlParserError as e:
    failConversion(sourcePath, "", "invalid HTML: " & e.msg)
  htmlToTiml(doc, sourcePath)

proc parseHtmlFileToTiml*(path: string,
    policy: HtmlParserPolicy = defaultHtml2TimlPolicy()): string =
  var source: string
  try:
    source = readFile(path)
  except IOError as e:
    failConversion(path, "", "cannot read HTML file: " & e.msg)
  except OSError as e:
    failConversion(path, "", "cannot read HTML file: " & e.msg)
  parseHtmlToTiml(source, path, policy)
