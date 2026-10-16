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
  TemplateMarkers = ["{{", "{%", "{#", "<%", "%>"]
  VoidTagNames = ["area", "base", "br", "col", "embed", "hr", "img",
    "input", "link", "meta", "param", "source", "track", "wbr"]
  # Attribute names lexed as TIML keywords never reach Tim's attribute parser.
  # `type`, `if`, `for`, `elif`, `else`, `or` and `in` are handled by
  # `parseAttributes` (including as first attribute), so only the
  # remaining keywords are rejected here.
  TimlKeywordAttrNames = ["case", "of", "and",
    "while", "fn", "func", "iterator", "macro", "break", "var",
    "const", "return", "discard", "continue", "echo", "yield", "nil",
    "object", "true", "false"]

proc defaultHtml2TimlPolicy*(): HtmlParserPolicy =
  ## Kept for API compatibility. The converter no longer relies on
  ## OpenParser for parsing (it preserves tag names and text exactly),
  ## so the policy is accepted but ignored.
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

proc assertNoTemplateSyntax(value, sourcePath, nodePath, field: string) =
  for marker in TemplateMarkers:
    if marker in value:
      failConversion(sourcePath, nodePath,
        "template syntax in " & field & " is not supported: " & marker)

type
  H2tNodeKind = enum
    h2tElement, h2tText, h2tComment

  H2tNode = ref object
    case kind: H2tNodeKind
    of h2tElement:
      tag*: string
      attrs*: TableRef[string, string]
      children*: seq[H2tNode]
    of h2tText:
      text*: string
    of h2tComment:
      comment*: string

proc isTagChar(c: char): bool =
  c.isAlphaNumeric() or c in {'-', '_', ':', '.'}

proc skipSpaces(s: string, j: var int) =
  while j < s.len and s[j] in {' ', '\t', '\r', '\n'}:
    inc j

proc parseTagName(s: string, j: var int): string =
  let start = j
  while j < s.len and isTagChar(s[j]):
    inc j
  s[start ..< j]

proc parseAttrName(s: string, j: var int): string =
  ## Parse an attribute name liberally (up to `=`, whitespace, `/`, `>`).
  ## Validity is checked later by `isSupportedAttributeName`, so framework
  ## syntax like `@click` is captured here and rejected with a clear error.
  let start = j
  while j < s.len and s[j] notin {' ', '\t', '\r', '\n', '=', '/', '>',
      '"', '\'', '<', '`'}:
    inc j
  s[start ..< j]

proc findRawClose(source: string, start: int, tagLower: string): int =
  ## Find `</tag` (case-insensitive) from `start` for script/style bodies.
  let needle = "</" & tagLower
  var i = start
  while i + needle.len <= source.len:
    if source[i ..< i + needle.len].toLowerAscii() == needle:
      return i
    inc i
  -1

proc parseHtmlSource(source, sourcePath: string): seq[H2tNode] =
  if '\0' in source:
    failConversion(sourcePath, "", "NUL bytes are not supported")
  var top: seq[H2tNode] = @[]
  var stack: seq[H2tNode] = @[]
  var i = 0

  template addNode(n: H2tNode) =
    if stack.len > 0:
      stack[^1].children.add(n)
    else:
      top.add(n)

  while i < source.len:
    if source[i] != '<':
      let start = i
      while i < source.len and source[i] != '<':
        inc i
      addNode(H2tNode(kind: h2tText, text: source[start ..< i]))
      continue
    # comments
    if source.continuesWith("<!--", i):
      let close = source.find("-->", i + 4)
      if close < 0:
        failConversion(sourcePath, "", "unclosed comment")
      addNode(H2tNode(kind: h2tComment,
        comment: source[i + 4 ..< close]))
      i = close + 3
      continue
    # CDATA: preserve inner as text
    if source.len >= i + 9 and source[i ..< i + 9].toLowerAscii() == "<![cdata[":
      let close = source.find("]]>", i + 9)
      if close < 0:
        failConversion(sourcePath, "", "unclosed CDATA section")
      addNode(H2tNode(kind: h2tText, text: source[i + 9 ..< close]))
      i = close + 3
      continue
    # DOCTYPE: strip (Tim re-adds `<!DOCTYPE html>` at render time)
    if source.len >= i + 9 and source[i ..< i + 9].toLowerAscii() == "<!doctype":
      let ge = source.find(">", i + 9)
      if ge < 0:
        failConversion(sourcePath, "", "unclosed DOCTYPE declaration")
      i = ge + 1
      continue
    # other markup declarations are not supported
    if i + 1 < source.len and source[i + 1] == '!':
      failConversion(sourcePath, "", "unsupported markup declaration")
    # processing instructions: skip (no TIML representation)
    if i + 1 < source.len and source[i + 1] == '?':
      let close = source.find("?>", i + 2)
      if close < 0:
        failConversion(sourcePath, "", "unclosed processing instruction")
      i = close + 2
      continue
    # closing tag
    if i + 1 < source.len and source[i + 1] == '/':
      var j = i + 2
      skipSpaces(source, j)
      let name = parseTagName(source, j)
      if name.len == 0:
        failConversion(sourcePath, "", "malformed closing tag")
      skipSpaces(source, j)
      if j >= source.len or source[j] != '>':
        failConversion(sourcePath, "", "malformed closing tag </" & name & ">")
      if stack.len == 0:
        failConversion(sourcePath, "", "stray closing tag </" & name & ">")
      let open = stack.pop()
      if open.tag.toLowerAscii() != name.toLowerAscii():
        failConversion(sourcePath, "",
          "mismatched tags: <" & open.tag & "> closed by </" & name & ">")
      i = j + 1
      continue
    # opening tag
    var j = i + 1
    let name = parseTagName(source, j)
    if name.len == 0:
      failConversion(sourcePath, "", "stray `<` in text; escape it as `&lt;`")
    let lowered = name.toLowerAscii()
    var attrs = newTable[string, string]()
    var selfClose = false
    var closed = false
    while true:
      skipSpaces(source, j)
      if j >= source.len:
        failConversion(sourcePath, "", "unclosed tag <" & name & ">")
      if source[j] == '>':
        inc j
        closed = true
        break
      if source[j] == '/' and j + 1 < source.len and source[j + 1] == '>':
        selfClose = true
        closed = true
        j += 2
        break
      if source[j] == '/':
        # `/` outside `/>` only valid inside unquoted values (handled
        # below) or as stray; treat lone `/` before attrs as malformed
        # to catch `<div class="x" <p>`-style mistakes.
        if j + 1 < source.len and source[j + 1] notin {' ', '\t', '\r', '\n', '>'}:
          failConversion(sourcePath, "",
            "malformed tag <" & name & ">")
        inc j
        continue
      let attrName = parseAttrName(source, j)
      if attrName.len == 0:
        failConversion(sourcePath, "", "malformed tag <" & name & ">")
      skipSpaces(source, j)
      var attrValue = ""
      if j < source.len and source[j] == '=':
        inc j
        skipSpaces(source, j)
        if j >= source.len:
          failConversion(sourcePath, "", "unclosed tag <" & name & ">")
        if source[j] == '"' or source[j] == '\'':
          let quote = source[j]
          inc j
          let start = j
          let close = source.find(quote, start)
          if close < 0:
            failConversion(sourcePath, "", "unterminated attribute value")
          attrValue = source[start ..< close]
          j = close + 1
        else:
          let start = j
          while j < source.len and source[j] notin {' ', '\t', '\r', '\n',
              '"', '\'', '=', '<', '>', '`'}:
            inc j
          attrValue = source[start ..< j]
      if attrName in attrs:
        failConversion(sourcePath, "", "duplicate attribute `" &
          attrName & "` in <" & name & ">")
      attrs[attrName] = attrValue
    if not closed:
      failConversion(sourcePath, "", "unclosed tag <" & name & ">")
    let node = H2tNode(kind: h2tElement, tag: name, attrs: attrs,
      children: @[])
    if selfClose or lowered in VoidTagNames:
      addNode(node)
      i = j
      continue
    if lowered in ["script", "style"]:
      let rel = findRawClose(source, j, lowered)
      if rel < 0:
        failConversion(sourcePath, "", "unclosed tag <" & name & ">")
      let body = source[j ..< rel]
      var m = rel + lowered.len + 2
      skipSpaces(source, m)
      if m >= source.len or source[m] != '>':
        failConversion(sourcePath, "", "malformed closing tag </" & name & ">")
      if body.len > 0:
        node.children.add(H2tNode(kind: h2tText, text: body))
      addNode(node)
      i = m + 1
      continue
    addNode(node)
    stack.add(node)
    i = j
  if stack.len > 0:
    failConversion(sourcePath, "", "unclosed tag <" & stack[^1].tag & ">")
  result = move(top)

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

proc appendNodes(nodes: seq[H2tNode], buf: var string,
    sourcePath, parentPath: string, indent, depth: int)

proc appendAttributes(buf: var string, node: H2tNode,
    sourcePath, nodePath: string) =
  if node.attrs == nil:
    return
  var names = toSeq(node.attrs.keys)
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
      classValue = node.attrs[name]
    elif name.toLowerAscii() == "id":
      hasId = true
      id = node.attrs[name]

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
    if name in TimlKeywordAttrNames or lowered in TimlKeywordAttrNames:
      failConversion(sourcePath, nodePath,
        "attribute `" & name & "` collides with TIML syntax")
    let value = node.attrs[name]
    assertNoTemplateSyntax(value, sourcePath, nodePath,
      "attribute `" & name & "`")
    buf.add(' ')
    buf.add(name)
    if value.len > 0:
      buf.add('=')
      buf.add(quoteTiml(value, sourcePath, nodePath,
        "attribute `" & name & "`"))

proc appendElement(buf: var string, node: H2tNode, indent, depth: int,
    sourcePath, nodePath: string) =
  var line = node.tag
  var attrs = ""
  appendAttributes(attrs, node, sourcePath, nodePath)
  line.add(attrs)

  if node.children.len == 1 and node.children[0] != nil and
      node.children[0].kind == h2tText:
    let text = node.children[0].text
    # Skip whitespace-only single children (e.g. `<script src=".."></script>`
    # is parsed as empty; formatting whitespace between tags is dropped).
    # An element with only whitespace content is emitted bare.
    if text.strip().len == 0:
      appendLine(buf, indent, line)
      return
    assertNoTemplateSyntax(text, sourcePath, nodePath & ".children[0]", "text")
    line.add(": ")
    line.add(quoteTiml(text, sourcePath, nodePath & ".children[0]", "text"))
    appendLine(buf, indent, line)
    return

  appendLine(buf, indent, line)
  appendNodes(node.children, buf, sourcePath, nodePath, indent + 1, depth + 1)

proc appendNode(buf: var string, node: H2tNode, indent, depth: int,
    sourcePath, nodePath: string) =
  if node == nil:
    failConversion(sourcePath, nodePath, "HTML node is nil")
  if depth > MaxHtml2TimlDepth:
    failConversion(sourcePath, nodePath, "HTML exceeds maximum nesting depth")
  case node.kind
  of h2tText:
    if node.text.strip().len == 0:
      return
    appendText(buf, indent, node.text, sourcePath, nodePath)
  of h2tComment:
    appendComment(buf, indent, node.comment, sourcePath, nodePath)
  of h2tElement:
    appendElement(buf, node, indent, depth, sourcePath, nodePath)

proc appendNodes(nodes: seq[H2tNode], buf: var string,
    sourcePath, parentPath: string, indent, depth: int) =
  for i, node in nodes:
    let nodePath =
      if parentPath.len > 0: parentPath & ".children[" & $i & "]"
      else: "nodes[" & $i & "]"
    if node != nil and node.kind == h2tText:
      if node.text.strip().len == 0:
        continue
      if parentPath.len == 0:
        failConversion(sourcePath, nodePath,
          "top-level text must be wrapped in an HTML element")
    appendNode(buf, node, indent, depth, sourcePath, nodePath)

proc htmlToTiml*(doc: HtmlDocument, sourcePath = ""): string =
  ## Convert an OpenParser HTML document to TIML source.
  ##
  ## Kept for API compatibility. New code parses with the built-in
  ## whitespace-preserving parser (`parseHtmlToTiml`); this overload
  ## re-serializes an OpenParser document through the same TIML emitter
  ## for callers that already have a document. Unknown tags are emitted
  ## by enum name (`tagUnknown`); prefer `parseHtmlToTiml` for full
  ## documents (SVG, custom elements) so original tag names are kept.
  result = ""
  proc cvt(nodes: seq[HtmlNode], buf: var string, parentPath: string,
      indent, depth: int)
  proc cvtOne(node: HtmlNode, buf: var string, nodePath: string,
      indent, depth: int) =
    if node == nil:
      failConversion(sourcePath, nodePath, "HTML node is nil")
    if depth > MaxHtml2TimlDepth:
      failConversion(sourcePath, nodePath, "HTML exceeds maximum nesting depth")
    case node.kind
    of htmlInnerText:
      if node.value.text.strip().len == 0: return
      assertNoTemplateSyntax(node.value.text, sourcePath, nodePath, "text")
      appendLine(buf, indent, quoteTiml(node.value.text, sourcePath,
        nodePath, "text"))
    of htmlComment:
      appendComment(buf, indent, node.comment, sourcePath, nodePath)
    of htmlTag:
      let tag = $node.tag
      var line = tag
      if node.attributes != nil:
        var names = toSeq(node.attributes.keys)
        names.sort()
        for name in names:
          if not isSupportedAttributeName(name):
            failConversion(sourcePath, nodePath,
              "unsupported attribute name: " & name)
          if name in TimlKeywordAttrNames or
              name.toLowerAscii() in TimlKeywordAttrNames:
            failConversion(sourcePath, nodePath,
              "attribute `" & name & "` collides with TIML syntax")
          let value = node.attributes[name]
          assertNoTemplateSyntax(value, sourcePath, nodePath,
            "attribute `" & name & "`")
          line.add(' ')
          line.add(name)
          if value.len > 0:
            line.add('=')
            line.add(quoteTiml(value, sourcePath, nodePath,
              "attribute `" & name & "`"))
      if node.children.len == 1 and node.children[0] != nil and
          node.children[0].kind == htmlInnerText:
        let text = node.children[0].value.text
        if text.strip().len == 0:
          appendLine(buf, indent, line)
          return
        assertNoTemplateSyntax(text, sourcePath, nodePath & ".children[0]",
          "text")
        line.add(": ")
        line.add(quoteTiml(text, sourcePath, nodePath & ".children[0]",
          "text"))
        appendLine(buf, indent, line)
        return
      appendLine(buf, indent, line)
      cvt(node.children, buf, nodePath, indent + 1, depth + 1)
  proc cvt(nodes: seq[HtmlNode], buf: var string, parentPath: string,
      indent, depth: int) =
    for i, node in nodes:
      let nodePath =
        if parentPath.len > 0: parentPath & ".children[" & $i & "]"
        else: "nodes[" & $i & "]"
      if node != nil and node.kind == htmlInnerText:
        if node.value.text.strip().len == 0: continue
        if parentPath.len == 0:
          failConversion(sourcePath, nodePath,
            "top-level text must be wrapped in an HTML element")
      cvtOne(node, buf, nodePath, indent, depth)
  cvt(doc.nodes, result, "", 0, 0)
  if result.strip().len == 0:
    failConversion(sourcePath, "", "HTML document contains no convertible nodes")

proc parseHtmlToTiml*(source: string, sourcePath = "",
    policy: HtmlParserPolicy = defaultHtml2TimlPolicy()): string =
  ## Convert static HTML to TIML source.
  ##
  ## Full documents are supported: `<!DOCTYPE ...>` and processing
  ## instructions are skipped, any tag names (HTML, SVG, custom elements)
  ## are preserved, and text (including `/`, `=` and `>`) plus inline
  ## `<script>`/`<style>` bodies are kept exactly. `policy` is accepted
  ## for compatibility and ignored.
  discard policy
  let nodes = parseHtmlSource(source, sourcePath)
  result = ""
  appendNodes(nodes, result, sourcePath, "", 0, 0)
  if result.strip().len == 0:
    failConversion(sourcePath, "", "HTML document contains no convertible nodes")

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
