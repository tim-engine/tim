# Tim AST Validator — dedicated structural validator for cached/packed AST reuse
#
# This module is intentionally separate from VanCode codegen.
# It validates `Ast` loaded via `openparser/json.fromJson(astStr, Ast)` before
# it reaches `genScript` / VM, guarding against corrupted or malicious caches
# and allowing distribution of packed themes without `.timl` sources.
#
# Usage:
#   var ast = fromJson(readFile(path), Ast)
#   validateAst(ast)  # raises TimAstValidationError on first violation
#
# Or collect all errors:
#   var errs: seq[TimAstValidationError]
#   if not validateAst(ast, errs): ...

import std/[strutils, tables, sets, hashes, math]
import pkg/vancode/interpreter/ast
import pkg/openparser/json as ojson

export ast

type
  TimAstValidationError* = object of CatchableError
    ln*, col*: int
    nodeKind*: NodeKind
    path*: string

const
  MaxAstDepth* = 512
  MaxAstNodes* = 500_000
  MaxStringLength* = 1 shl 20
  MaxNodesPerAst = MaxAstNodes

proc fail(path: string, node: Node, msg: string) {.noreturn.} =
  var e = newException(TimAstValidationError, msg)
  e.path = path
  if node != nil:
    e.ln = node.ln
    e.col = node.col
    e.nodeKind = node.kind
  else:
    e.ln = -1
    e.col = -1
  raise e

proc isValidIdent*(s: string): bool =
  if s.len == 0 or s.len > 255: return false
  var t = s
  if t[0] in {'@', '$'}:
    if t.len == 1: return false
    t = t[1..^1]
    if t.len > 0 and t[0] in {'@', '$'}: return false
  if t.len == 0: return false
  if t[0].isDigit: return false
  for c in t:
    if c notin {'A'..'Z', 'a'..'z', '0'..'9', '_'}:
      return false
  true

proc isValidTag*(s: string): bool =
  if s.len == 0 or s.len > 128: return false
  if not s[0].isAlphaAscii: return false
  for c in s:
    if c notin {'A'..'Z', 'a'..'z', '0'..'9', '-', ':', '_'}:
      return false
  true

proc isValidTagCustom(s: string): bool = isValidTag(s)

proc checkStringLen(path: string, node: Node, s: string, field: string) =
  if s.len > MaxStringLength:
    fail(path, node, field & " exceeds maximum length " & $MaxStringLength)

proc ensureNotNil(path: string, n: Node, ctx: string) =
  if n == nil:
    fail(path, nil, ctx & " is nil")

proc ensureKindOne(path: string, n: Node, expect: NodeKind, ctx: string) =
  if n.kind != expect:
    fail(path, n, ctx & " expected " & $expect & " got " & $n.kind)

# forward
proc validateNode(node: Node, path: string, depth: int, visited: var HashSet[pointer], total: var int)

proc validateIdentDefs(node: Node, path: string, depth: int, visited: var HashSet[pointer], total: var int) =
  # Two forms:
  #  - flat: [names.., ty, val]  (used for formalParams, etc. via parseIdentDefs)
  #  - nested: [nkAssign(ident, ty, val), ...] (used for var/let via parseVarIdent)
  if node.len == 0:
    fail(path, node, "nkIdentDefs requires >=1 child got 0")
  # detect nested form by first child being nkAssign
  if node[0].kind == nkAssign:
    for i, child in node.children:
      let cPath = path & "[" & $i & "]"
      ensureKindOne(cPath, child, nkAssign, "IdentDefs nested entry must be nkAssign")
      if child.len != 3:
        fail(cPath, child, "nkAssign in IdentDefs requires 3 children got " & $child.len)
      # ident
      let identNode = child[0]
      ensureNotNil(cPath & "[0]", identNode, "assign ident")
      if identNode.kind == nkPostfix:
        if identNode.len != 2:
          fail(cPath & "[0]", identNode, "postfix requires 2 children")
        validateNode(identNode[0], cPath & "[0][0]", depth+1, visited, total)
        validateNode(identNode[1], cPath & "[0][1]", depth+1, visited, total)
      elif identNode.kind != nkIdent:
        fail(cPath & "[0]", identNode, "assign ident must be nkIdent or postfix")
      else:
        if not isValidIdent(identNode.ident):
          fail(cPath & "[0]", identNode, "invalid ident in IdentDefs")
      validateNode(child[1], cPath & "[1]", depth+1, visited, total)
      validateNode(child[2], cPath & "[2]", depth+1, visited, total)
    return
  # flat form
  if node.len < 3:
    fail(path, node, "nkIdentDefs requires >=3 children got " & $node.len)
  let ty = node[^2]
  let val = node[^1]
  ensureNotNil(path & ".ty", ty, "ty")
  ensureNotNil(path & ".val", val, "value")
  validateNode(ty, path & ".ty", depth+1, visited, total)
  validateNode(val, path & ".val", depth+1, visited, total)
  for i in 0 ..< node.len - 2:
    let n = node[i]
    ensureNotNil(path & "[" & $i & "]", n, "identDefs name")
    if n.kind == nkPostfix:
      if n.len != 2:
        fail(path & "[" & $i & "]", n, "postfix identDefs requires 2 children")
      if n[0].kind != nkIdent or n[0].ident != "*":
        fail(path & "[" & $i & "][0]", n[0], "postfix export marker must be '*'")
      if n[1].kind != nkIdent:
        fail(path & "[" & $i & "][1]", n[1], "postfix ident must be nkIdent")
      if not isValidIdent(n[1].ident):
        fail(path & "[" & $i & "][1]", n[1], "invalid ident in postfix")
      validateNode(n[0], path & "[" & $i & "][0]", depth+1, visited, total)
      validateNode(n[1], path & "[" & $i & "][1]", depth+1, visited, total)
    elif n.kind == nkIdent:
      if not isValidIdent(n.ident):
        fail(path & "[" & $i & "]", n, "invalid ident in IdentDefs")
    else:
      fail(path & "[" & $i & "]", n, "IdentDefs name must be nkIdent or nkPostfix(*)")

proc validateFormalParams(node: Node, path: string, depth: int, visited: var HashSet[pointer], total: var int) =
  if node.len < 1:
    fail(path, node, "nkFormalParams requires at least 1 child (return type)")
  let ret = node[0]
  ensureNotNil(path & "[0]", ret, "return type")
  validateNode(ret, path & "[0]", depth+1, visited, total)
  for i in 1 ..< node.len:
    let d = node[i]
    ensureNotNil(path & "[" & $i & "]", d, "formal param")
    ensureKindOne(path & "[" & $i & "]", d, nkIdentDefs, "formal param must be nkIdentDefs")
    validateIdentDefs(d, path & "[" & $i & "]", depth+1, visited, total)

proc validateGenericParams(node: Node, path: string, depth: int, visited: var HashSet[pointer], total: var int) =
  for i, child in node.children:
    ensureNotNil(path & "[" & $i & "]", child, "generic param")
    if child.kind notin {nkIdent, nkIdentDefs}:
      fail(path & "[" & $i & "]", child, "generic param must be nkIdent or nkIdentDefs")
    validateNode(child, path & "[" & $i & "]", depth+1, visited, total)

when compiles(NodeKind.nkHtmlElement):
  proc validateHtmlAttribute(node: Node, path: string, depth: int, visited: var HashSet[pointer], total: var int) =
    if node.kind != nkHtmlAttribute:
      fail(path, node, "expected nkHtmlAttribute")
    if ord(node.attrType) < ord(low(HtmlAttributeType)) or ord(node.attrType) > ord(high(HtmlAttributeType)):
      fail(path, node, "invalid HtmlAttributeType ord " & $ord(node.attrType))
    ensureNotNil(path & ".attrNode", node.attrNode, "attrNode")
    validateNode(node.attrNode, path & ".attrNode", depth+1, visited, total)
    case node.attrType
    of htmlAttrClass, htmlAttrId:
      discard
    of htmlAttr:
      if node.attrNode.kind == nkInfix:
        if node.attrNode.len != 3:
          fail(path & ".attrNode", node.attrNode, "htmlAttr infix must have 3 children")
        if node.attrNode[0] != nil and node.attrNode[0].kind != nkIdent:
          fail(path & ".attrNode[0]", node.attrNode[0], "attr infix operator must be nkIdent or nil")
        ensureNotNil(path & ".attrNode[1]", node.attrNode[1], "attr key")
        ensureNotNil(path & ".attrNode[2]", node.attrNode[2], "attr value")
      elif node.attrNode.kind in {nkString, nkIdent}:
        discard
      else:
        discard
    of htmlAttrIdent:
      discard

  proc validateHtmlElement(node: Node, path: string, depth: int, visited: var HashSet[pointer], total: var int) =
    if node.kind != nkHtmlElement:
      fail(path, node, "expected nkHtmlElement")
    if node.tag.len == 0:
      fail(path, node, "tag must not be empty")
    checkStringLen(path, node, node.tag, "tag")
    if not isValidTag(node.tag):
      fail(path, node, "invalid tag: " & node.tag.escape)
    for i, attr in node.attributes:
      ensureNotNil(path & ".attributes[" & $i & "]", attr, "attribute")
      if attr.kind != nkHtmlAttribute:
        fail(path & ".attributes[" & $i & "]", attr, "attribute must be nkHtmlAttribute")
      validateHtmlAttribute(attr, path & ".attributes[" & $i & "]", depth+1, visited, total)
    for i, child in node.childElements:
      ensureNotNil(path & ".childElements[" & $i & "]", child, "childElement")
      validateNode(child, path & ".childElements[" & $i & "]", depth+1, visited, total)

proc validateNode(node: Node, path: string, depth: int, visited: var HashSet[pointer], total: var int) =
  if node == nil:
    fail(path, nil, "node is nil")
  inc total
  if total > MaxNodesPerAst:
    fail(path, node, "AST exceeds maximum node count " & $MaxNodesPerAst)
  if depth > MaxAstDepth:
    fail(path, node, "AST exceeds maximum depth " & $MaxAstDepth)
  let ptrVal = cast[pointer](node)
  if ptrVal in visited:
    fail(path, node, "cycle detected at " & path)
  visited.incl(ptrVal)

  if node.ln < 0 or node.col < 0:
    fail(path, node, "invalid line/col negative")
  if node.ln > 1_000_000 or node.col > 10_000:
    fail(path, node, "implausible line/col large")

  let kOrd = ord(node.kind)
  if kOrd < ord(low(NodeKind)) or kOrd > ord(high(NodeKind)):
    fail(path, node, "invalid NodeKind ord " & $kOrd)

  # leaf-like
  case node.kind
  of nkEmpty, nkNil:
    return
  of nkBool:
    return
  of nkInt:
    return
  of nkFloat:
    return
  of nkString:
    checkStringLen(path, node, node.stringVal, "stringVal")
    return
  of nkIdent:
    if not isValidIdent(node.ident):
      fail(path, node, "invalid ident: " & node.ident.escape)
    checkStringLen(path, node, node.ident, "ident")
    return
  of nkVarTy:
    ensureNotNil(path & ".varType", node.varType, "varType")
    validateNode(node.varType, path & ".varType", depth+1, visited, total)
    return
  of nkDocComment:
    checkStringLen(path, node, node.comment, "comment")
    return
  else:
    discard

  # Tim-specific leaf-like shunts
  when compiles(NodeKind.nkHtmlAttribute):
    if node.kind == nkHtmlAttribute:
      validateHtmlAttribute(node, path, depth, visited, total)
      return
  when compiles(NodeKind.nkHtmlElement):
    if node.kind == nkHtmlElement:
      validateHtmlElement(node, path, depth, visited, total)
      return
  when compiles(NodeKind.nkRawHtml):
    if node.kind == nkRawHtml:
      checkStringLen(path, node, node.rawHtml, "rawHtml")
      if node.rawHtml.len == 0:
        fail(path, node, "nkRawHtml rawHtml must not be empty")
      return
  when compiles(NodeKind.nkJavaScriptSnippet):
    if node.kind == nkJavaScriptSnippet or node.kind == nkCssSnippet:
      checkStringLen(path, node, node.snippetCode, "snippetCode")
      for i, kv in node.snippetCodeAttrs:
        checkStringLen(path & ".snippetCodeAttrs[" & $i & "]", node, kv[0], "snippetCodeAttr key")
        if kv[1] != nil:
          validateNode(kv[1], path & ".snippetCodeAttrs[" & $i & "].val", depth+1, visited, total)
      return
  when compiles(NodeKind.nkViewLoader):
    if node.kind == nkViewLoader:
      if node.len != 0:
        fail(path, node, "nkViewLoader must have 0 children")
      return

  template checkChildren(expectedMin: int, expectedMax: int) =
    if node.len < expectedMin or (expectedMax >= 0 and node.len > expectedMax):
      fail(path, node, $node.kind & " expects children in [" & $expectedMin & "," & $expectedMax & "] got " & $node.len)

  case node.kind
  of nkIdentDefs:
    validateIdentDefs(node, path, depth, visited, total)
  of nkFormalParams:
    validateFormalParams(node, path, depth, visited, total)
  of nkGenericParams:
    validateGenericParams(node, path, depth, visited, total)
  of nkRecFields:
    for i, child in node.children:
      ensureNotNil(path & "[" & $i & "]", child, "rec field")
      ensureKindOne(path & "[" & $i & "]", child, nkIdentDefs, "rec field must be nkIdentDefs")
      validateIdentDefs(child, path & "[" & $i & "]", depth+1, visited, total)
  of nkPrefix:
    checkChildren(2, 2)
    ensureKindOne(path & "[0]", node[0], nkIdent, "prefix op must be nkIdent")
    validateNode(node[0], path & "[0]", depth+1, visited, total)
    validateNode(node[1], path & "[1]", depth+1, visited, total)
  of nkPostfix:
    checkChildren(2, 2)
    validateNode(node[0], path & "[0]", depth+1, visited, total)
    validateNode(node[1], path & "[1]", depth+1, visited, total)
  of nkInfix:
    checkChildren(3, 3)
    if node[0] != nil:
      if node[0].kind != nkIdent:
        fail(path & "[0]", node[0], "infix operator must be nkIdent or nil")
      validateNode(node[0], path & "[0]", depth+1, visited, total)
    ensureNotNil(path & "[1]", node[1], "infix left")
    ensureNotNil(path & "[2]", node[2], "infix right")
    validateNode(node[1], path & "[1]", depth+1, visited, total)
    validateNode(node[2], path & "[2]", depth+1, visited, total)
  of nkDot:
    checkChildren(2, 2)
    validateNode(node[0], path & "[0]", depth+1, visited, total)
    validateNode(node[1], path & "[1]", depth+1, visited, total)
  of nkBracket:
    checkChildren(2, 2)
    validateNode(node[0], path & "[0]", depth+1, visited, total)
    validateNode(node[1], path & "[1]", depth+1, visited, total)
  of nkColon:
    checkChildren(2, 2)
    validateNode(node[0], path & "[0]", depth+1, visited, total)
    validateNode(node[1], path & "[1]", depth+1, visited, total)
  of nkIndex:
    checkChildren(2, 2)
    validateNode(node[0], path & "[0]", depth+1, visited, total)
    validateNode(node[1], path & "[1]", depth+1, visited, total)
  of nkCall:
    if node.len < 1:
      fail(path, node, "nkCall requires at least 1 child (callee)")
    validateNode(node[0], path & "[0]", depth+1, visited, total)
    for i in 1 ..< node.len:
      ensureNotNil(path & "[" & $i & "]", node[i], "call arg")
      validateNode(node[i], path & "[" & $i & "]", depth+1, visited, total)
  of nkIf:
    if node.len < 2:
      fail(path, node, "nkIf requires at least 2 children (cond + then)")
    validateNode(node[0], path & "[0]", depth+1, visited, total)
    if node[1].kind != nkBlock:
      fail(path & "[1]", node[1], "nkIf then branch must be nkBlock")
    validateNode(node[1], path & "[1]", depth+1, visited, total)
    let hasElse = node.len mod 2 == 1
    let elifEnd = if hasElse: node.len - 2 else: node.len - 1
    var i = 2
    while i <= elifEnd:
      validateNode(node[i], path & "[" & $i & "]", depth+1, visited, total)
      if node[i+1].kind != nkBlock:
        fail(path & "[" & $(i+1) & "]", node[i+1], "nkIf elif branch must be nkBlock")
      validateNode(node[i+1], path & "[" & $(i+1) & "]", depth+1, visited, total)
      i += 2
    if hasElse:
      if node[^1].kind != nkBlock:
        fail(path & "[^1]", node[^1], "nkIf else branch must be nkBlock")
      validateNode(node[^1], path & "[^1]", depth+1, visited, total)
  of nkAssign:
    checkChildren(2, 2)
    validateNode(node[0], path & "[0]", depth+1, visited, total)
    validateNode(node[1], path & "[1]", depth+1, visited, total)
  of nkProcTy:
    checkChildren(1, 1)
    validateNode(node[0], path & "[0]", depth+1, visited, total)
  of nkTypeDef:
    checkChildren(1, 1)
    validateNode(node[0], path & "[0]", depth+1, visited, total)
  of nkVar, nkLet, nkConst:
    checkChildren(1, 1)
    ensureKindOne(path & "[0]", node[0], nkIdentDefs, $node.kind & " child must be nkIdentDefs")
    validateIdentDefs(node[0], path & "[0]", depth+1, visited, total)
  of nkWhile:
    checkChildren(2, 2)
    validateNode(node[0], path & "[0]", depth+1, visited, total)
    if node[1].kind != nkBlock:
      fail(path & "[1]", node[1], "nkWhile body must be nkBlock")
    validateNode(node[1], path & "[1]", depth+1, visited, total)
  of nkFor:
    checkChildren(3, 3)
    if node[0].kind notin {nkIdent, nkBracket}:
      fail(path & "[0]", node[0], "nkFor var must be nkIdent or nkBracket")
    validateNode(node[0], path & "[0]", depth+1, visited, total)
    validateNode(node[1], path & "[1]", depth+1, visited, total)
    if node[2].kind != nkBlock:
      fail(path & "[2]", node[2], "nkFor body must be nkBlock")
    validateNode(node[2], path & "[2]", depth+1, visited, total)
  of nkBreak, nkContinue:
    if node.len != 0:
      fail(path, node, $node.kind & " must have 0 children")
  of nkDiscard:
    if node.len > 1:
      fail(path, node, "nkDiscard must have 0 or 1 children")
    if node.len == 1:
      validateNode(node[0], path & "[0]", depth+1, visited, total)
  of nkReturn, nkYield:
    if node.len > 1:
      fail(path, node, $node.kind & " must have 0 or 1 children")
    if node.len == 1:
      if node[0].kind != nkEmpty:
        validateNode(node[0], path & "[0]", depth+1, visited, total)
  of nkImport, nkInclude:
    if node.len < 1:
      fail(path, node, $node.kind & " requires at least 1 child")
    for i, child in node.children:
      ensureNotNil(path & "[" & $i & "]", child, "import/include path")
      if child.kind != nkString:
        fail(path & "[" & $i & "]", child, $node.kind & " path must be nkString")
      checkStringLen(path & "[" & $i & "]", child, child.stringVal, "import path")
      validateNode(child, path & "[" & $i & "]", depth+1, visited, total)
  of nkStatic:
    for i, child in node.children:
      validateNode(child, path & "[" & $i & "]", depth+1, visited, total)
  of nkObject:
    if node.len < 2 or node.len > 3:
      fail(path, node, "nkObject expects 2 or 3 children got " & $node.len)
    validateNode(node[0], path & "[0]", depth+1, visited, total)
    for i in 1 ..< node.len:
      validateNode(node[i], path & "[" & $i & "]", depth+1, visited, total)
  of nkArray:
    for i, child in node.children:
      validateNode(child, path & "[" & $i & "]", depth+1, visited, total)
  of nkProc, nkIterator, nkCoroutine:
    checkChildren(4, 4)
    if node[0].kind notin {nkIdent, nkEmpty, nkPostfix}:
      fail(path & "[0]", node[0], $node.kind & " name must be nkIdent|nkEmpty|nkPostfix")
    validateNode(node[0], path & "[0]", depth+1, visited, total)
    if node[1].kind notin {nkEmpty, nkGenericParams}:
      fail(path & "[1]", node[1], $node.kind & " genericParams must be nkEmpty or nkGenericParams")
    validateNode(node[1], path & "[1]", depth+1, visited, total)
    if node[2].kind notin {nkEmpty, nkFormalParams}:
      fail(path & "[2]", node[2], $node.kind & " formalParams must be nkEmpty or nkFormalParams")
    validateNode(node[2], path & "[2]", depth+1, visited, total)
    if node[3].kind != nkBlock:
      fail(path & "[3]", node[3], $node.kind & " body must be nkBlock")
    validateNode(node[3], path & "[3]", depth+1, visited, total)
  of nkObjectStorage:
    for i, child in node.children:
      if child.kind != nkColon:
        fail(path & "[" & $i & "]", child, "nkObjectStorage child must be nkColon")
      validateNode(child, path & "[" & $i & "]", depth+1, visited, total)
  of nkBlock, nkScript:
    for i, child in node.children:
      validateNode(child, path & "[" & $i & "]", depth+1, visited, total)
  else:
    when compiles(NodeKind.nkClientBlock):
      if node.kind == nkClientBlock:
        checkChildren(1, 1)
        if node[0].kind != nkBlock:
          fail(path & "[0]", node[0], "nkClientBlock child must be nkBlock")
        validateNode(node[0], path & "[0]", depth+1, visited, total)
        return
    when compiles(NodeKind.nkCustomElement):
      if node.kind == nkCustomElement:
        checkChildren(4, 4)
        ensureKindOne(path & "[0]", node[0], nkIdent, "customElement className must be nkIdent")
        ensureKindOne(path & "[1]", node[1], nkString, "customElement tagName must be nkString")
        validateNode(node[0], path & "[0]", depth+1, visited, total)
        validateNode(node[1], path & "[1]", depth+1, visited, total)
        validateNode(node[2], path & "[2]", depth+1, visited, total)
        validateNode(node[3], path & "[3]", depth+1, visited, total)
        return
    when compiles(NodeKind.nkMacro):
      if node.kind == nkMacro:
        checkChildren(4, 4)
        if node[0].kind notin {nkIdent, nkPostfix, nkEmpty}:
          fail(path & "[0]", node[0], "nkMacro name must be nkIdent|nkPostfix|nkEmpty")
        validateNode(node[0], path & "[0]", depth+1, visited, total)
        validateNode(node[1], path & "[1]", depth+1, visited, total)
        validateNode(node[2], path & "[2]", depth+1, visited, total)
        if node[3].kind != nkBlock:
          fail(path & "[3]", node[3], "nkMacro body must be nkBlock")
        validateNode(node[3], path & "[3]", depth+1, visited, total)
        return
    when compiles(NodeKind.nkTest):
      if node.kind == nkTest:
        checkStringLen(path, node, node.testLabel, "testLabel")
        if node.testLabel.len == 0:
          fail(path, node, "nkTest label must not be empty")
        ensureNotNil(path & ".testBody", node.testBody, "testBody")
        if node.testBody.kind != nkBlock:
          fail(path & ".testBody", node.testBody, "nkTest body must be nkBlock")
        validateNode(node.testBody, path & ".testBody", depth+1, visited, total)
        return
    for i, child in node.children:
      ensureNotNil(path & "[" & $i & "]", child, "child")
      validateNode(child, path & "[" & $i & "]", depth+1, visited, total)

proc validateAst*(ast: Ast) =
  if ast == nil:
    raise newException(TimAstValidationError, "Ast is nil")
  var visited = initHashSet[pointer]()
  var total = 0
  if ast.sourcePath.len > 0:
    checkStringLen("ast.sourcePath", nil, ast.sourcePath, "sourcePath")
    if ast.sourcePath.len > 4096:
      raise newException(TimAstValidationError, "sourcePath too long")
  var seen = initHashSet[string]()
  for i, p in ast.otherPaths:
    if p.len == 0:
      fail("ast.otherPaths[" & $i & "]", nil, "otherPath is empty")
    if p.len > 4096:
      fail("ast.otherPaths[" & $i & "]", nil, "otherPath too long")
    if p.contains("..") and (p.contains("/..") or p.contains("../") or p == ".."):
      fail("ast.otherPaths[" & $i & "]", nil, "otherPath contains parent traversal: " & p)
    if p in seen:
      fail("ast.otherPaths[" & $i & "]", nil, "duplicate otherPath: " & p)
    seen.incl(p)
  if ast.nodes.len > MaxNodesPerAst:
    raise newException(TimAstValidationError, "Ast.nodes exceeds maximum " & $MaxNodesPerAst)
  for i, node in ast.nodes:
    ensureNotNil("ast.nodes[" & $i & "]", node, "top-level node")
    validateNode(node, "ast.nodes[" & $i & "]", 0, visited, total)
  when compiles(ast.forwardDecl):
    # forwardDecl is Tim extension on Ast
    for i, node in ast.forwardDecl:
      if node != nil:
        validateNode(node, "ast.forwardDecl[" & $i & "]", 0, visited, total)

proc validateAst*(ast: Ast, errors: var seq[ref TimAstValidationError]): bool =
  errors = @[]
  try:
    validateAst(ast)
    return true
  except TimAstValidationError as e:
    errors.add(e)
    return false
  except Exception as e:
    var ve = newException(TimAstValidationError, e.msg)
    errors.add(ve)
    return false

proc isValidAst*(ast: Ast): bool =
  try:
    validateAst(ast)
    return true
  except CatchableError:
    return false

proc loadValidatedAst*(jsonStr: string, sourcePath: string = ""): Ast =
  try:
    result = ojson.fromJson(jsonStr, Ast)
  except Exception as e:
    var ve = newException(TimAstValidationError, "Failed to deserialize AST JSON: " & e.msg)
    ve.path = sourcePath
    raise ve
  if sourcePath.len > 0:
    result.sourcePath = sourcePath
  validateAst(result)

proc loadValidatedAstFile*(path: string): Ast =
  let data = readFile(path)
  result = loadValidatedAst(data, path)
