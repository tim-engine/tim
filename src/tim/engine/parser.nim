# A super fast template engine for cool kids
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim | https://openpeeps.dev/packages/tim

import std/[macros, tables, strutils, critbits, options, memfiles]
import pkg/vancode/interpreter/[errors, ast]

from ./transpilers/private import minifyInlineJs, minifyRawHtml, minifyInlineCSS
import ./lexer

type
  Parser* = object
    lex: Lexer
    prev, curr, next: TokenTuple
    # internals
    parentNode: seq[Node]
    otherPaths: seq[string]
    classCacheAttr: CritBitTree[Node]
      # Cache for HTML class attributes
      # to optimize memory usage and speed up
      # the parsing process. Since class names
      # are often reused, caching them reduces
      # redundant allocations.
    lvl: int

  TimParserError* = object of ValueError
    file*: string
    ln*, col*: int

const
  MathOperators = {tkPlus, tkMinus, tkAsterisk, tkDivide}
  LogicalOperators = {tkAnd, tkAndAnd, tkOr, tkOrOr}
  ComparisonOperators = {tkEQ, tkNE, tkGT, tkGTE, tkLT, tkLTE}
  Operators = ComparisonOperators + MathOperators + {tkAmp, tkAssign}
  Strings = {tkSqString, tkString}
  Assignables = {tkBool, tkInteger, tkFloat, tkIdentifier} + Strings

proc error(tk: TokenTuple, msg: string) =
  ## Raise a parsing error on the given node.
  raise (ref TimParserError)(
          # file: node.file,
          ln: tk.line,
          col: tk.col,
          msg: ErrorFmt % ["", $tk.line, $tk.col, msg])

#
# Parser utility functions
#
proc skipNextComment(p: var Parser) =
  # Skip comments until the next token
  # This is used to skip inline comments.
  while true:
    case p.next.kind
    of tkComment:
      p.next = p.lex.getToken() # skip inline comments
    else: break

template ruleGuard(body) =
  ## Helper used by {.rule.} to update line info appropriately for nodes.
  when declared(result):
    let
      ln = p.curr.line
      col = p.curr.col
  body
  when declared(result):
    if result != nil:
      result.ln = ln
      result.col = col
      # result.file = scan.file

macro rule(pc) =
  ## Adds a ``scan`` parameter to a proc and wraps its body in a call to
  ## ``ruleGuard``.
  # pc[3].insert(1, newIdentDefs(ident"scan", newTree(nnkVarTy, ident"Scanner")))
  if pc[6].kind != nnkEmpty:
    pc[6] = newCall("ruleGuard", newStmtList(pc[6]))
  pc

type
  PrefixFunction* = proc (p: var Parser, minPrec = 0): Node

macro prefixHandle(name: untyped, body: untyped) =
  # Create a new prefix procedure with `name` and `body`
  name.newProc(
    [
      ident("Node"), # return type
      nnkIdentDefs.newTree(
        ident"p",
        nnkVarTy.newTree(
          ident"Parser"
        ),
        newEmptyNode()
      ),
      nnkIdentDefs.newTree(
        ident"minPrec",
        ident"int",
        newLit(0)
      )
    ],
    body,
    pragmas = nnkPragma.newTree(ident("rule"))
  )

proc walk(p: var Parser, offset = 1) =
  # Walk the parser state to the next token.
  # `offset` is the number of tokens to walk
  var i = 0
  while offset > i:
    inc i
    p.prev = p.curr
    p.curr = p.next
    p.next = p.lex.getToken()
    p.skipNextComment()

proc walkOpt(p: var Parser, kind: TokenKind) =
  # This is used to skip over tokens that are not needed
  # in the current context.
  if p.curr.kind == kind:
    walk(p)

proc walkOptSemiColon(p: var Parser) =
  # This is used to skip over the optional semicolon
  # at the end of a statement.
  if p.curr.kind == tkSColon:
    walk(p)
  elif p.curr.line <= p.prev.line:
    p.curr.error(ErrBadIndentation)

template expectWalk(k: TokenKind) =
  if likely(p.curr.kind == k):
    walk p
  else: return nil

template expectWalk(k: TokenKind, bdy) =
  if likely(p.curr.kind == k):
    walk p
    bdy
  else: return

proc skipComments(p: var Parser) =
  while p.curr.kind == tkComment:
    walk p

template caseNotNil(x: Node, body): untyped =
  if likely(x != nil):
    body
  else: return nil

template caseNotNil(x: Node, body, then): untyped =
  if likely(x != nil):
    body
  else: then

proc isChild(tk, parent: TokenTuple): bool {.inline.} =
  tk.col > parent.col and (tk.line > parent.line and tk.kind != tkEOF)

proc isInfix(p: var Parser): bool {.inline.} =
  p.curr.kind in Operators

proc isInfix(tk: TokenTuple): bool {.inline.} =
  tk.kind in Operators

proc `isnot`(tk: TokenTuple, kind: TokenKind): bool {.inline.} =
  tk.kind != kind

proc `is`(tk: TokenTuple, kind: TokenKind): bool {.inline.} =
  tk.kind == kind

proc `in`(tk: TokenTuple, kind: set[TokenKind]): bool {.inline.} =
  tk.kind in kind

proc `notin`(tk: TokenTuple, kind: set[TokenKind]): bool {.inline.} =
  tk.kind notin kind

#
# Parse handlers - forward declarations
#
proc parseStmt(p: var Parser, minPrec = 0): Node
proc parsePrefix(p: var Parser, minPrec = 0): Node
proc parseExpression(p: var Parser, minPrec = 0): Node
proc parseIdent(p: var Parser, minPrec = 0): Node
proc parseCall(p: var Parser, minPrec = 0): Node
proc parseMacroCall(p: var Parser, minPrec = 0): Node
proc parseScript*(astProgram: var Ast, code: string, sourcePath: string)

#
# Parse handlers
#
prefixHandle parseBoolean:
  # parse boolean
  let v =
    try:
      parseBool(p.curr.value)
    except ValueError:
      return nil
  result = ast.newBoolLit(v)
  walk p

prefixHandle parseInteger:
  # parse an interger
  let v =
    try:
      parseInt(p.curr.value)
    except ValueError:
      return nil
  result = ast.newIntLit(v)
  walk p

prefixHandle parseFloat:
  # parse a float number
  let v =
    try:
      parseFloat(p.curr.value)
    except ValueError:
      return nil
  result = ast.newFloatLit(v)
  walk p

prefixHandle parseNil:
  # parse nil
  result = ast.newNil()
  walk p

prefixHandle parseString:
  # parse a string
  result = ast.newStringLit(p.curr.value)
  walk p

proc parseCommaList(p: var Parser, start, term: static TokenKind,
  results: var seq[Node], infixList: static bool = false,
  advanceToken: static bool = true): bool =
  # parse a comma separated list of expressions
  when advanceToken == true:
    # hacky way to handle the case where we dont' want to advance
    walk p # start
  if p.curr isnot term:
    while p.curr isnot tkEOF:
      when infixList == true:
        # handle colon expressions
        # a list of `key: value` pairs
        # where `key` is an identifier or a string
        if p.curr in {tkIdentifier, tkType} + Strings:
          let nodeKey: Node = p.createIdentNode()
          expectWalk tkColon:
            let nodeVal: Node = p.parseExpression()
            caseNotNil nodeVal:
              let colonExpr = ast.newNode(nkColon)
              colonExpr.add([nodeKey, nodeVal])
              results.add(colonExpr)
            do: return
        else: return
      else:
        let lhs: Node = p.parseExpression()
        caseNotNil lhs:
          results.add(lhs) # it's a normal array list
        do: return
      if p.curr is tkComma:
        walk p # skip commas
      if p.curr is term:
        walk p; break
  else: walk p # skip term, we have an empty list
  result = true

proc parseCommaIdentList(p: var Parser, start,
      term: static TokenKind, results: var seq[Node]): bool =
  # parse a comma separated list of expressions
  walk p # start
  if p.curr isnot term:
    while p.curr isnot tkEOF:
      let def: Node = p.parseIdentDefs()
      caseNotNil def:
        results.add(def)
      do: return false
      # checking for the next token
      # to determine if we have a comma separated list
      # or is the end of the list
      case p.curr.kind
      of tkComma, tkSColon:
        walk p # skip commas
      of term:
        walk p
        break # end of the list, break the loop
      else: return
  else: walk p # skip term, we have an empty list
  result = true

prefixHandle parseImportStmt:
  # parse an import statement
  result =
    case p.curr.kind
    of tkImport:
      ast.newTree(nkImport)
    else:
      ast.newTree(nkInclude)
  if p.next is tkLB:
    walk p, 2
    while p.curr isnot tkRB:
      # case p.curr.kind
      # of tkEOF: break # todo error
      # of tkComma: walk p # skip comma
      let path = p.parseExpression()
      caseNotNil path:
        result.add(path)
        if result.kind == nkInclude:
          p.otherPaths.add(path.stringVal)
  else:
    walk p # tkImport
    let path = p.parseExpression()
    caseNotNil path:
      result.add(path)
      if result.kind == nkInclude:
        p.otherPaths.add(path.stringVal)

const attrKinds = {tkIdentifier, tkType, tkIf,
                tkFor, tkElif, tkElse, tkOr, tkIn} + Strings
template anyAttrIdent: untyped =
  (
    ((p.curr in attrKinds and p.next is tkAssign) or
      (p.curr is tkIdentifier and p.curr.line == el.line)) and
    (p.curr.line == el.line or (
      p.curr.isChild(el) and p.next in {tkAssign, tkIdentifier}))
  )

proc parseAttributes(p: var Parser, attrs: var seq[Node], el: TokenTuple) =
  # parse attributes of an HTML element
  while true:
    case p.curr.kind
    of tkEOF: break
    of tkDot:
      walk p
      if likely(anyAttrIdent()):
        let cv = p.curr.value
        if cv in p.classCacheAttr:
          attrs.add(p.classCacheAttr[cv])
        else:
          let attrNode = newHtmlAttribute(htmlAttrClass, ast.newStringLit(cv))
          attrs.add(attrNode)
          p.classCacheAttr[cv] = attrNode
        walk p
      elif p.curr is tkIdentVar:
        let identNode = p.parseExpression()
        caseNotNil identNode:
          attrs.add(newHtmlAttribute(htmlAttrClass, identNode))
        do: return
      else: break
    of tkID:
      # parse a `#ident` html attribute
      walk p # tkID
      if likely(anyAttrIdent()):
        attrs.add(ast.newHtmlAttribute(htmlAttrID, ast.newStringLit(p.curr.value)))
        walk p
      elif p.curr is tkIdentVar:
        let identNode = p.parseExpression()
        caseNotNil identNode:
          attrs.add(ast.newHtmlAttribute(htmlAttrID, identNode))
        do: return
      else: break
    of tkIdentVar, tkIdentVarSafe:
      # parse a variable as an html attribute
      let identNode = p.parseExpression()
      caseNotNil identNode:
        attrs.add(ast.newHtmlAttribute(htmlAttr, identNode))
      do: return
    else:
      # parse a `key="value"` html attribute
      if anyAttrIdent():
        if p.curr.value == "class":
          # when `class` attribute is used will collect the class values
          # and create a single class attribute with all values
          walk p # tkIdentifier `class`
          expectWalk tkAssign:
            let attrValue: Node = p.parseExpression(minPrec = 5)
            caseNotNil attrValue:
              attrs.add(newHtmlAttribute(htmlAttrClass, attrValue))
              continue
            do: break
        if p.curr.value == "id":
          walk p # tkIdentifier `id`
          expectWalk tkAssign:
            let attrValue: Node = p.parseExpression(minPrec = 5)
            caseNotNil attrValue:
              attrs.add(newHtmlAttribute(htmlAttrID, attrValue))
              continue
            do: break
        var attr = ast.newStringLit(p.curr.value)
        walk p # tk any attribute name
        if p.curr is tkColon:
          if p.next is tkIdentifier and p.next.line == p.curr.line:
            # namespaced attribute e.g. xlink:href, xml:space
            attr = ast.newStringLit(attr.stringVal & ":" & p.next.value)
            walk p # tkColon
            walk p # tkIdentifier (namespace suffix)
          else:
            attrs.add(ast.newHtmlAttribute(htmlAttr, attr))
            break
        if p.curr is tkAssign:
          # parse an HTML attribute with a value
          walk p # tkAssign
          let infixNode: Node = ast.newInfix(nil, attr, p.parseExpression(minPrec = 5))
          let attrNode = ast.newHtmlAttribute(htmlAttr, infixNode)
          attrs.add(attrNode)
        else:
          # html attributes can be passed without a value
          attrs.add(ast.newHtmlAttribute(htmlAttr, attr))
      else: break

proc wrapMultiply(el: Node, multiplier: Node): Node =
  if multiplier == nil: return el
  let i = ast.newIdent("i")
  let zero = ast.newIntLit(0)
  let lt = ast.newIdent("<")
  let varDecl = ast.newNode(nkVar)
  let identDefs = ast.newNode(nkIdentDefs)
  identDefs.add(ast.newTree(nkAssign, i, ast.newEmpty(), zero))
  varDecl.add(identDefs)
  let body = ast.newNode(nkBlock)
  body.add(el)
  body.add(ast.newCall(ast.newIdent("inc"), i))
  let whileLoop = ast.newTree(nkWhile,
    ast.newInfix(lt, i, multiplier), body)
  result = ast.newTree(nkBlock, varDecl, whileLoop)

prefixHandle parseElement:
  # parse an HTML element
  let tk = p.curr
  var multiplier: Node
  let tag = htmlTag(tk.value)
  result = ast.newHtmlElement(tag, tk.value)
  result.ln = p.curr.line
  result.col = p.curr.col
  walk p
  # if result.col != 0:
  #   result.col = p.lvl * 4 # set real indent size
  if p.parentNode.len == 0:
    add p.parentNode, result
  else:
    if result.ln > p.parentNode[^1].ln:
      add p.parentNode, result

  # parse the attributes
  case p.curr.kind
  of tkDot, tkID, tkIdentifier, tkType:
    p.parseAttributes(result.attributes, tk)
  of tkIdentVar, tkIdentVarSafe:
    let x = p.parseIdent()
    caseNotNil x:
      add result.attributes, x
    case p.curr.kind
    of tkDot, tkID, tkIdentifier, tkType:
      p.parseAttributes(result.attributes, tk)
    else: discard
  else:
    if p.curr is tkLP and
      (p.curr.line == tk.line or p.curr.col > tk.col):
        p.parseAttributes(result.attributes, tk)
    else: discard

  # parse optional element multiplication (*N)
  if p.curr.kind == tkAsterisk:
    walk p
    if p.curr.kind == tkInteger:
      multiplier = ast.newIntLit(p.curr.value.parseInt)
      walk p
    else:
      p.curr.error("Expected integer literal after '*'")

  # parse inline elements
  case p.curr.kind
  of tkColon:
    walk p
    if tag == tagScript:
      let js = minifyInlineJs(p.curr.value)
      result.childElements.add(ast.newStringLit(js))
      walk p
    else:
      let valNode = p.parseExpression()
      caseNotNil valNode:
        result.childElements.add(valNode)
  of Strings:
    result.childElements.add(p.parseString())
  of tkGT:
    # parse inline HTML tags
    var node: Node
    while p.curr is tkGT:
      inc p.lvl
      case p.next.kind
      of tkIdentifier:
        walk p
        p.curr.col = p.lvl
        node = p.parseElement()
        caseNotNil node:
          if p.curr isnot tkEOF and p.curr.col > 0:
            if p.curr.line > node.ln:
              let currentParent = p.parentNode[^1]
              while p.curr.col > currentParent.col:
                if p.curr is tkEOF: break
                var subNode = p.parseStmt()
                caseNotNil subNode:
                  node.childElements.add(subNode)
                if p.curr.col < currentParent.col:
                  try:
                    dec p.lvl, currentParent.col div p.curr.col
                  except DivByZeroDefect:
                    discard
                  p.parentNode.setLen(p.parentNode.high)
                  break
          result.childElements.add(node)
          if p.lvl != 0:
            dec p.lvl
          if multiplier != nil:
            return wrapMultiply(result, multiplier)
          return result
      of tkAt:
        walk p
        let blockNode: Node = p.parseMacroCall()
        caseNotNil blockNode:
          result.childElements.add(blockNode)
      else: return
  else: discard
  
  # parse multi-line nested nodes
  if p.curr isnot tkEOF:
    var currentParent = p.parentNode[^1]
    if p.curr.line > currentParent.ln:
      if p.curr.col > currentParent.col:
        inc p.lvl
        while p.curr.col > currentParent.col:
          if p.curr is tkEOF: break
          var subNode = p.parseStmt()
          caseNotNil subNode:
            add result.childElements, subNode
          if p.curr is tkEOF or p.curr.pos == 0:
            # prevent division by zero
            break
          if p.curr.col < currentParent.col:
            dec p.lvl
            p.parentNode.setLen(p.parentNode.high)
            break
          elif p.curr.col == currentParent.col:
            dec p.lvl
        if p.curr.col == 0:
          p.lvl = 0 # reset level
  if multiplier != nil:
    result = wrapMultiply(result, multiplier)

proc parseBlock(p: var Parser, indentPos = 0,
            parseFnBlock: static bool = false): Node {.rule.} =
  # parse a block of code
  var
    closingBlock: bool
    stmts = newSeq[Node](0)
  if p.curr is tkLC:
    closingBlock = true
    walk p # tkLC
  elif p.curr is (
      when parseFnBlock == true: tkAssign
                            else: tkColon
      ): walk p
  while p.curr isnot tkEOF:
    if closingBlock and p.curr is tkRC:
      walk p; break # tkRC
    elif not closingBlock and p.curr.col <= indentPos: break
    let subNode = p.parseStmt()
    caseNotNil subNode:
      stmts.add(subNode)
  result = ast.newTree(nkBlock, stmts)

prefixHandle parseForLoop:
  # parse a for loop
  let tokenFor: TokenTuple = p.curr
  if p.next.kind == tkIdentVar:
    walk p # tkFor
    var itemVar: Node
    if p.next is tkComma:
      itemVar = ast.newTree(nkBracket)
      itemVar.add(ast.newIdent(p.curr.value))
      walk p, 2 # tkComma
      itemVar.add(ast.newIdent(p.curr.value))
    else:
      itemVar = ast.newIdent(p.curr.value)
    walk p
    expectWalk(tkIN)
    let iterExpr: Node = p.parseExpression() 
    caseNotNil iterExpr:
      let body: Node = p.parseBlock(tokenFor.col)
      caseNotNil body:
        result = ast.newTree(nkFor, itemVar, iterExpr, body)

prefixHandle parseWhileLoop:
  # parse a while loop
  let tokenWhile: TokenTuple = p.curr
  walk p # tkWhile
  let whileExpr: Node = p.parseExpression()
  caseNotNil whileExpr:
    let whileBlock: Node = p.parseBlock(tokenWhile.col)
    caseNotNil whileBlock:
      result = ast.newTree(nkWhile, whileExpr, whileBlock)

prefixHandle parseIf:
  # parse an if/elif/else statement
  let tokenIf: TokenTuple = p.curr
  walk p # tkIf
  let ifExpr: Node = p.parseExpression()
  caseNotNil ifExpr:
    var children = @[ifExpr]
    let ifBlock: Node = p.parseBlock(tokenIf.col)
    caseNotNil ifBlock:
      children.add(ifBlock)
    
    # handle elif statements
    while p.curr is tkELIF and p.curr.col == tokenIf.col:
      let tokenElif = p.curr
      walk p # tkELIF
      let elifExpr: Node = p.parseExpression()
      caseNotNil elifExpr:
        let elifBlock: Node = p.parseBlock(tokenIf.col)
        caseNotNil elifBlock:
          children.add(@[elifExpr, elifBlock])

    # handle else statement, if available
    if p.curr is tkELSE and p.curr.col == tokenIf.col:
      let tokenElse = p.curr
      walk p # tkELSE
      let elseBlock: Node = p.parseBlock(tokenIf.col)
      caseNotNil elseBlock:
        children.add(elseBlock)
    result = ast.newTree(nkIf, children)

proc captureStaticBody(source: string, colonLine, staticCol: int): string =
  ## Capture indented body text from source lines after colonLine (1-indexed).
  ## Returns lines indented deeper than staticCol, stopping at the first
  ## non-empty line at or above staticCol.
  let lines = source.split('\n')
  result = ""
  for i in colonLine..<lines.high:
    let line = lines[i]
    if line.strip().len == 0:
      if result.len > 0:
        result.add('\n')
      continue
    var indent = 0
    for c in line:
      if c == ' ': indent += 1
      elif c == '\t': indent += 1
      else: break
    if indent <= staticCol:
      break
    if result.len > 0:
      result.add('\n')
    result.add(line)

proc walkPastBody(p: var Parser, staticCol: int) =
  ## Walk tokens forward until we're back at or above staticCol indentation.
  while p.curr.kind != tkEOF and p.curr.col > staticCol:
    walk p

proc substituteStaticVar(body, varName, bareVal, exprVal: string): string =
  ## Substitute both `{$varName}` (bare) and standalone `$varName` (expr) in body.
  let dollarVar = "$" & varName
  let braceVar = "{$" & varName & "}"
  result = body.replace(braceVar, bareVal)
  var i = 0
  while i < result.len:
    let pos = result.find(dollarVar, i)
    if pos < 0: break
    let nextIdx = pos + dollarVar.len
    if nextIdx >= result.len or result[nextIdx] notin {'a'..'z', 'A'..'Z', '0'..'9', '_', '-'}:
      result = result[0..<pos] & exprVal & result[nextIdx..^1]
      i = pos + exprVal.len
    else:
      i = pos + 1

prefixHandle parseStaticStmt:
  let staticCol = p.curr.col
  walk p # tkStatic
  result = ast.newNode(nkStatic)

  if p.curr.kind == tkFor:
    # Parse for loop header
    walk p # tkFor
    var itemVar: Node
    if p.next.kind == tkComma:
      itemVar = ast.newTree(nkBracket)
      itemVar.add(ast.newIdent(p.curr.value))
      walk p, 2
      itemVar.add(ast.newIdent(p.curr.value))
    else:
      itemVar = ast.newIdent(p.curr.value)
    walk p
    expectWalk(tkIN)
    let iterExpr = p.parseExpression()
    if iterExpr == nil: return
    if p.curr.kind != tkColon: return
    let colonLine = p.curr.line
    walk p # colon

    let bodyStr = captureStaticBody(p.lex.input, colonLine, staticCol)
    walkPastBody(p, staticCol)

    # Expand for loop
    let varName = itemVar.ident
    if iterExpr.kind == nkArray:
      for child in iterExpr.children:
        if child.kind == nkString:
          let substituted = substituteStaticVar(bodyStr, varName,
            child.stringVal, "\"" & child.stringVal & "\"")
          var innerAst: Ast
          parseScript(innerAst, substituted, "")
          for n in innerAst.nodes:
            result.add(n)
    elif iterExpr.kind == nkCall and iterExpr[0].ident == "..":
      if iterExpr[1].kind == nkInt and iterExpr[2].kind == nkInt:
        let rangeStart = iterExpr[1].intVal
        let rangeEnd = iterExpr[2].intVal
        for val in rangeStart..rangeEnd:
          let substituted = substituteStaticVar(bodyStr, varName, $val, $val)
          var innerAst: Ast
          parseScript(innerAst, substituted, "")
          for n in innerAst.nodes:
            result.add(n)

  elif p.curr.kind == tkIf:
    walk p # tkIf
    let condExpr = p.parseExpression()
    if condExpr == nil: return
    if p.curr.kind != tkColon: return
    let ifColonLine = p.curr.line
    walk p # colon

    var matched = false
    var matchedBody = ""

    # Evaluate if condition
    if condExpr.kind == nkBool and condExpr.boolVal == true:
      matched = true
      matchedBody = captureStaticBody(p.lex.input, ifColonLine, staticCol)
      walkPastBody(p, staticCol)
    else:
      walkPastBody(p, staticCol)

    # Handle elif
    while p.curr.kind == tkElif and p.curr.col == staticCol:
      walk p # tkElif
      let elifCond = p.parseExpression()
      if elifCond == nil: return
      if p.curr.kind != tkColon: return
      let elifColonLine = p.curr.line
      walk p

      if not matched and elifCond.kind == nkBool and elifCond.boolVal == true:
        matched = true
        matchedBody = captureStaticBody(p.lex.input, elifColonLine, staticCol)
      walkPastBody(p, staticCol)

    # Handle else
    if p.curr.kind == tkElse and p.curr.col == staticCol:
      walk p # tkElse
      if p.curr.kind != tkColon: return
      let elseColonLine = p.curr.line
      walk p

      if not matched:
        matchedBody = captureStaticBody(p.lex.input, elseColonLine, staticCol)
      walkPastBody(p, staticCol)

    if matchedBody.len > 0:
      var innerAst: Ast
      parseScript(innerAst, matchedBody, "")
      for n in innerAst.nodes:
        result.add(n)

prefixHandle parseIdent:
  # parse an identifier
  result = ast.newIdent(p.curr.value)
  walk p # tkIdentifier

prefixHandle parseIdentVar:
  # parse a variable identifier.
  result = ast.newIdent(p.curr.value)
  result.ln = p.curr.line
  result.col = p.curr.col
  walk p # tkIdentVar
  if p.curr is tkAssign:
    # handle variable assignment
    # not sure if this should be here
    walk p # tkAssign
    let valNode: Node = p.parseExpression()
    caseNotNil valNode:
      result = ast.newInfix(ast.newIdent("="), result, valNode)

prefixHandle parseJavaScript:
  result = ast.newNode(nkJavaScriptSnippet)
  result.snippetCode = minifyInlineJs(p.curr.value)
  # for attr in p.curr.attr:
  #   let identNode = ast.newNode(nkIdent)
  #   let id = attr.split("_")
  #   identNode.ident = id[1]
  #   add result.snippetCodeAttrs, (attr, identNode)
  walk p

prefixHandle parseCSS:
  result = ast.newNode(nkCssSnippet)
  result.snippetCode = minifyInlineCSS(p.curr.value)
  walk p

prefixHandle parseRawHtml:
  result = ast.newNode(nkRawHtml)
  let raw =move p.curr.value
  var output = newStringOfCap(raw.len)
  minifyRawHtml(raw, output)
  result.rawHtml =move output
  walk p

prefixHandle parseHtmlComment:
  result = ast.newNode(nkRawHtml)
  result.rawHtml = "<!-- " & strip(p.curr.value) & " -->"
  walk p

#
# Identifier & Variable Definitions
#
proc parseGenericType(p: var Parser, lhs: Node): Node =
  walk p # tkLB
  let genericType = p.parseIdent()
  caseNotNil genericType:
    result = ast.newNode(nkIndex).add(lhs)
    result.add(genericType)
    if p.curr is tkLB:
      result = p.parseGenericType(result)
    expectWalk(tkRB) # expect a right bracket

proc createIdentNode(p: var Parser): Node {.rule.} = 
  result = ast.newIdent(p.curr.value)
  walk p # tkIdentifier

proc getVarIdent(p: var Parser, varIdent: bool): Node {.rule.} =
  # get the identifier name from the current token
  result = p.createIdentNode()
  if varIdent:
    # variable definitions can be suffixed with an asterisk
    # to mark them as exported (public)
    if p.curr is tkAsterisk:
      walk p
      return ast.newNode(nkPostfix).add([ast.newIdent("*"), result])

proc parseIdentDefs(p: var Parser): Node {.rule.} =
  # parse identifier definitions
  result = newNode(nkIdentDefs)
  if p.curr.kind == tkIdentifier:
    let identNode = p.getVarIdent(true)
    var
      ty = newEmpty()
      val = newEmpty()
      vars: seq[Node]
    vars.add(identNode)
    while p.curr.kind != tkEOF:
      case p.curr.kind
      of tkColon:
        walk p # tkColon
        if p.curr is tkIdentifier:
          ty = p.parseIdent()
          if p.curr is tkLB:
            ty = p.parseGenericType(ty)
        elif p.curr is tkVar:
          ty = ast.newNode(nkVarTy)
          if p.next is tkIdentifier:
            ty.varType = ast.newIdent(p.next.value)
            walk p, 2
      of tkAssign:
        # parse an implicit assignment
        walk p # tkAssign
        val = p.parseExpression(minPrec = 0)
        break
      of tkComma:
        # parse a comma separated list of identifiers
        if ty.kind == nkEmpty and p.next is tkIdentifier:
          walk p # tkComma
          # parse another variable separated by a comma
          vars.add(p.parseExpression())
        else: break
      else: break
    vars.add([ty, val])
    result.add(vars)

proc parseVarIdent(p: var Parser): Node {.rule.} =
  # Parse identifier definitions
  result = ast.newNode(nkIdentDefs)
  while true:
    let identNode = p.getVarIdent(true)
    var
      ty = newEmpty()
      val = newEmpty()
    # check for a type annotation
    if p.curr.kind == tkColon:
      walk p  # Consume `:`
      if p.curr.kind == tkIdentifier:
        ty = p.parseIdent()
        if p.curr.kind == tkLB:
          ty = p.parseGenericType(ty)
      else:
        p.curr.error("Expected type after ':'")
    # check for an assignment
    if p.curr.kind == tkAssign:
      walk p  # Consume `=`
      val = p.parseExpression()
    # add the identifier, type, and value to the result
    result.add(ast.newTree(nkAssign, identNode, ty, val))
    if p.curr.kind == tkComma:
      if p.next.kind == tkIdentifier and p.next.col == identNode.col:
        walk p # tkComma
      else: break
    else: break

prefixHandle parseVar:
  # parse a variable definition
  case p.curr.kind
  of tkVar:
    result = ast.newNode(nkVar)
  of tkConst:
    result = ast.newNode(nkConst)
  else: discard
  walk p # tkVar/tkConst
  result.add(p.parseVarIdent())

#
# Functions
#
proc parseFunctionHead(p: var Parser, isAnon: bool;
                name, genericParams, formalParams: var Node) =
  if not isAnon:
    name = ast.newIdent(p.curr.value)
    walk p
    if p.curr is tkAsterisk:
      # suffixed with an asterisk marks the function as exported (public)
      walk p # tkAsterisk
      name = ast.newNode(nkPostfix).add([ast.newIdent("*"), name])
  else:
    name = ast.newEmpty()
  
  if p.curr is tkLB:
    # parse generic parameters
    genericParams = ast.newNode(nkGenericParams)
    var params: seq[Node]
    if p.parseCommaIdentList(tkLB, tkRB, params):
      genericParams.add(params)
  else:
    genericParams = ast.newEmpty() # no generic parameters, use an empty node
  
  # parse function parameters
  # `formalParams` is a list of parameters
  formalParams = newTree(nkFormalParams, newEmpty())
  if p.curr is tkLP:
    var params: seq[Node]
    if p.parseCommaIdentList(tkLP, tkRP, params):
      formalParams.add(params)

  # parse a return type
  if p.curr is tkColon and p.next in {tkIdentifier, tkLitObject}:
    walk p # tkColon
    formalParams[0] = p.parseIdent()

prefixHandle parseFunction:
  # parse a function definition
  let fnpos = p.curr.col
  walk p # tkFunction
  var name, genericParams, formalParams: Node
  let isAnon = p.curr.kind != tkIdentifier
  parseFunctionHead(p, isAnon, name, genericParams, formalParams)
  if p.curr in {tkAssign, tkLC}:
    # parse function statement
    let fnBlock: Node = p.parseBlock(fnpos, parseFnBlock = true)
    caseNotNil fnBlock:
      result = ast.newTree(nkProc, name, genericParams, formalParams, fnBlock)

prefixHandle parseIterator:
  # parse an iterator
  let tokenIterator = p.curr.col
  walk p # tkIterator
  var name, genericParams, formalParams: Node
  parseFunctionHead(p, isAnon = false, name, genericParams, formalParams)
  if p.curr in {tkAssign, tkLC}:
    # parse function statement
    let fnBlock: Node = p.parseBlock(tokenIterator, parseFnBlock = true)
    caseNotNil fnBlock:
      result = ast.newTree(nkIterator, name, genericParams, formalParams, fnBlock)

#
# Block Functions
#
proc parseMacroFunctionHead(p: var Parser, isAnon: bool;
    name, genericParams, formalParams: var Node) =
  # parse a block function head
  if not isAnon:
    name = ast.newIdent("@" & p.curr.value)
    walk p # tkIdentifier
    if p.curr is tkAsterisk:
      # suffixed with an asterisk marks the function as exported (public)
      walk p # tkAsterisk
      name = ast.newNode(nkPostfix).add([ast.newIdent("*"), name])
  else:
    name = ast.newEmpty()
  genericParams = ast.newEmpty() # todo

  formalParams = newTree(nkFormalParams, newSeq[Node](0))
  formalParams.add(ast.newNode(nkEmpty)) # no need for return type

  if p.curr is tkLP:
    var params: seq[Node]
    if p.parseCommaIdentList(tkLP, tkRP, params):
      formalParams.add(params)  

prefixHandle parseMacroFunction:
  # parse a block function
  let fnpos = p.curr.col
  walk p # tkFunction
  var name, genericParams, formalParams: Node
  let isAnon = p.curr.kind != tkIdentifier
  parseMacroFunctionHead(p, isAnon, name, genericParams, formalParams)
  if p.curr in {tkAssign, tkLC}:
    # parse function statement
    let fnBlock: Node = p.parseBlock(fnpos, parseFnBlock = true)
    caseNotNil fnBlock:
      result = ast.newTree(nkMacro, name, genericParams, formalParams, fnBlock)

prefixHandle parseMacroCall:
  # parse a block call
  let tokenAt = p.curr
  walk p # tkAt
  if p.curr is tkIdentifier:
    p.curr.value = "@" & p.curr.value

    result = ast.newCall(ast.newIdent(p.curr.value))
    var expectRP: bool
    walk p # tkIdentifier
    
    var attrs: seq[Node]
    p.parseAttributes(attrs, tokenAt)
    
    if p.curr.kind == tkLP:
      # parse function arguments wrapped in parentheses
      # and mark expectRP as true to expect a closing parenthesis
      expectRP = true
      walk p # tkLP
    elif p.curr.col <= tokenAt.col: return # result

    # parse arguments separated by comma
    while true:
      case p.curr.kind
      of tkComma:
        walk p # skip to next argument
      of tkRP:
        if expectRP:
          walk p # the end of comma separated arg list
          if p.curr.col > tokenAt.col:
            continue
        break
      of Assignables + {tkIdentVar}:
        if not expectRP and p.curr.col <= tokenAt.col: break
        elif p.curr.line > tokenAt.line and p.curr.col > tokenAt.col: break
        let arg = p.parseExpression()
        caseNotNil arg:
          result.add(arg)
      of tkColon:
        # parse a statement
        walk p # tkColon
        let stmtNode: Node = p.parseStmt()
        caseNotNil stmtNode:
          result.add(stmtNode)
          break # break the loop after adding the statement
        do: break
      else: break # nothing to add

    # Inline nest support: @container() > @container() / @container() > div
    # Only treat '>' as nesting if followed by an element or another macro.
    while p.curr is tkGT and (p.next.kind in {tkIdentifier, tkAt}):
      walk p # consume '>'
      case p.curr.kind
      of tkIdentifier:
        let elNode = p.parseElement()
        caseNotNil elNode:
          result.add(elNode)
      of tkAt:
        let callNode = p.parseMacroCall()
        caseNotNil callNode:
          result.add(callNode)
      else:
        break

prefixHandle parseCall:
  # parse a function call
  let fnName = ast.newIdent(p.curr.value, p.curr.line, p.curr.col)
  result = ast.newCall(fnName)
  var expectRP: bool
  walk p # tkIdentifier
  
  if p.curr.kind == tkLP:
    # parse function arguments wrapped in parentheses
    # and mark expectRP as true to expect a closing parenthesis
    expectRP = true
    walk p # tkLP
  if p.curr isnot tkRP:
    while true:
      if p.curr.kind == tkIdentVar and p.next.kind == tkAssign:
        # parse a named argument
        let name = ast.newIdent(p.curr.value)
        walk p # tkIdentifier
        walk p # tkAssign
        let value = p.parseExpression()
        let namedArg = ast.newTree(nkColon, name, value)
        result.add(namedArg)
      else:
        # parse a normal argument
        if p.next.kind == tkColon:
          discard p.parseCommaList(tkLP, tkRP, result.children,
                                 infixList = true, advanceToken = false)
          break # parseCommaList will handle the rest of the arguments in this case, so we can break the loop
        else:
          let arg = p.parseExpression()
          caseNotNil arg:
            result.add(arg)
      
      # checking for the next token
      case p.curr.kind
      of tkComma:
        walk p # skip to next argument
      of tkRP:
        if expectRP:
          walk p # tkRP
        break
      of tkEOF:
        break # todo error EOF before closing parenthesis
      else: break
  else: walk p # tkRP
    
prefixHandle parseArray:
  # parse an array storage
  result = ast.newTree(nkArray)
  discard p.parseCommaList(tkLB, tkRB, result.children)
  p.walkOpt(tkSColon)

prefixHandle parseObjectStorage:
  # parse an object storage
  result = ast.newTree(nkObjectStorage)
  discard p.parseCommaList(tkLC, tkRC, result.children, infixList = true)

prefixHandle parseParExpr:
  # parse a parenthesized expression
  walk p # tkLP
  result = p.parseExpression()
  expectWalk(tkRP) # expect a right parenthesis

prefixHandle parseBreak:
  # parse a break command
  result = ast.newTree(nkBreak)
  walk p # tkBreakCmd
  p.walkOpt(tkSColon)

prefixHandle parseReturn:
  # parse a return statement
  result = ast.newTree(nkReturn)
  walk p # tkReturn
  if p.curr.line == p.prev.line:
    let exprNode: Node = p.parseExpression()
    caseNotNil exprNode:
      result.add(exprNode)
      p.walkOpt(tkSColon)

prefixHandle parseYield:
  # parse a yield statement
  result = ast.newTree(nkYield)
  walk p # tkYield
  let exprNode: Node = p.parseExpression()
  caseNotNil exprNode:
    result.add(exprNode)
    p.walkOpt(tkSColon) # optional semicolon

prefixHandle parseEcho:
  # parse an echo statement
  result = ast.newTree(nkCall)
  result.add(ast.newIdent("echo"))
  walk p # tkEcho
  let exprNode: Node = p.parseExpression()
  caseNotNil exprNode:
    result.add(exprNode)
    p.walkOpt(tkSColon) # optional semicolon

prefixHandle parseDocComment:
  # parse a documentation comment
  # this will be transpiled to a HTML block comment <!-- doc comment -->
  result = ast.newNode(nkDocComment)
  result.comment = p.curr.value
  walk p

# prefixHandle parseObject:
#   # parse an object
#   result = ast.newTree(nkObject)
#   if p.next is tkIdentifier:
#     walk p # tkLitObject
#     var id = ast.newIdent(p.curr.value)
#     if p.next is tkAsterisk:
#       id = ast.newNode(nkPostfix).add([ast.newIdent("*"), id])
#       walk p, 2
#     else:
#       walk p # tkIdentifier
#     expectWalk(tkLC) # expect a left curly brace
#     # add the object identifier to the result
#     # the empty node is used to define generic
#     # parameters (todo)
#     result.add([id, ast.newEmpty()])
#     # parse the object fields
#     var fields = newNode(nkRecFields)
#     while true:
#       case p.curr.kind
#       of tkEOF: break
#       of tkRC:
#         walk p; break # end of the object
#       of Strings + {tkIdentifier}:
#         # parse a field name. it can be either a string or an identifier
#         # let fieldName = p.curr
#         # walk p # tkIdentifier/tkString
#         # expectWalk(tkColon)
#         # parse the field value
#         let kvNode: Node = p.parseIdentDefs()
#         caseNotNil kvNode:
#           fields.add(kvNode)
#         if p.curr is tkComma and p.next isnot tkRC:
#           walk p # tkComma
#       else: break # todo error
#     result.add(fields)

prefixHandle parseTypeDef:
  # parse a type definition
  result = ast.newTree(nkTypeDef)
  result.ln = p.curr.line
  result.col = p.curr.col
  walk p # tkType
  
  var typeIdent = ast.newIdent(p.curr.value)
  typeIdent.ln = p.curr.line
  typeIdent.col = p.curr.col
  walk p # tkIdentifier

  let typeDefCol = 
    if result.ln == typeIdent.ln: result.col # use the column of `type` keyword
    else: typeIdent.col # use the column of the identifier, in case of multi-line type definitions

  # handle generic type definitions like `type MyType[T] = ...`
  if p.curr is tkLB:
    typeIdent = p.parseGenericType(typeIdent)
  
  expectWalk(tkAssign)
  # parse the type definition
  case p.curr.kind
  of tkLitObject:
    # parse `key: type = value` defintions
    walk p # tkLitObject
    var objectDef = newNode(nkObject)
    var fieldDefs = newNode(nkRecFields)
    while p.curr.kind != tkEOF:
      if p.curr.kind == tkIdentifier and p.curr.col > typeDefCol:
        let fieldDef: Node = p.parseIdentDefs()
        caseNotNil fieldDef:
          fieldDefs.add(fieldDef)
      else: break
    objectDef.add(typeIdent)
    objectDef.add(fieldDefs)
    result.add(objectDef)
  else: discard # TODO

prefixHandle parseViewPlaceholder:
  ## Parse a view placeholder
  result = ast.newNode(nkViewLoader)
  walk p

prefixHandle parseClientBlock:
  ## Parse a client block
  result = ast.newNode(nkClientBlock)
  walk p # tkClient
  let blockNode: Node = p.parseBlock(p.curr.col)
  caseNotNil blockNode:
    result.add(blockNode)
  if p.curr is tkEnd:
    walk p # tkEnd should not be necessary if 

proc getPrefixFn(p: var Parser, minPrec: int): PrefixFunction =
  # Get the prefix function for the current token
  # This is used to parse the current token
  # and return the corresponding node
  result = 
    case p.curr.kind
    of tkBool: parseBoolean
    of tkInteger: parseInteger
    of tkFloat: parseFloat
    of tkNil: parseNil
    of Strings: parseString
    of tkIdentVar: parseIdentVar
    of tkIf: parseIf
    of tkIdentifier:
      if p.next is tkLP and p.next.line == p.curr.line:
        parseCall
      else:
        if minPrec < 45:
          parseElement
        else:
          parseIdent
    of tkType:
      if p.next is tkLP and p.next.line == p.curr.line:
        parseCall
      elif p.next is tkLC and p.next.line == p.curr.line:
        parseTypeDef
      elif p.next is tkIdentifier:
        parseTypeDef
      else:
        if minPrec < 45:
          parseElement
        else:
          parseIdent
    of tkAt: parseMacroCall
    of tkLP:  parseParExpr
    of tkWhile: parseWhileLoop
    of tkFor: parseForLoop
    of tkReturnCmd: parseReturn
    of tkBreakCmd: parseBreak
    of tkFunc, tkFn: parseFunction
    of tkIterator: parseIterator
    of tkImport, tkInclude: parseImportStmt
    of tkLB: parseArray
    of tkLC: parseObjectStorage
    of tkYield: parseYield
    of tkEcho: parseEcho
    of tkDoc: parseDocComment
    of tkSnippetJs: parseJavaScript
    of tkSnippetCSS: parseCSS
    of tkSnippetHtml: parseRawHtml
    of tkHtmlComment: parseHtmlComment
    of tkViewLoader: parseViewPlaceholder
    of tkClient: parseClientBlock
    else: nil

prefixHandle parsePrefix:
  let parseFn = p.getPrefixFn(minPrec)
  if parseFn != nil: 
    return parseFn(p)

#
# Infix Handlers
#
proc getPrecedence(op: string): int {.inline.} =
  case op
  of "+", "-": 10
  of "*", "/": 20
  of ".": 45
  of "[": 40
  of "==", "!=", ">", "<", ">=", "<=": 5
  of "and", "&&": 3
  of "or", "||": 2
  of "&": 6
  else: 0

proc isInfix(kind: TokenKind, minPrec = 0): (bool, int, string) {.inline.} =
  var opStr: string
  case kind
  of tkPlus: opStr = "+"
  of tkMinus: opStr = "-"
  of tkAsterisk: opStr = "*"
  of tkDivide: opStr = "/"
  of tkGT: opStr = ">"
  of tkGTE: opStr = ">="
  of tkLT: opStr = "<"
  of tkLTE: opStr = "<="
  of tkEQ: opStr = "=="
  of tkNE: opStr = "!="
  of tkAmp: opStr = "&"
  of tkAssign: opStr = "="
  of tkDot: opStr = "."
  of tkLB: opStr = "["
  of tkAnd: opStr = "and"
  of tkAndAnd: opStr = "&&"
  of tkOr: opStr = "or"
  of tkOrOr: opStr = "||"
  else: return (false, 0, "")
  let prec = getPrecedence(opStr)
  result = (prec > minPrec, prec, opStr)

proc parseExpression(p: var Parser, minPrec = 0): Node =
  var lhs = p.parsePrefix(minPrec)
  caseNotNil lhs:
    while true:
      # handle infix operators
      # including dot and bracket access
      var opStr: string
      var prec: int
      var isBracket = false
      var isDot = false

      # Check for infix, dot, or bracket
      case p.curr.kind
      of Operators, LogicalOperators:
        let inf = p.curr.kind.isInfix(minPrec)
        if not inf[0]: break
        opStr = inf[2]
        prec = inf[1]
      of tkDot:
        opStr = "."
        prec = getPrecedence(".")
        isDot = true
      of tkLB:
        opStr = "["
        prec = getPrecedence("[")
        isBracket = true
      else: break

      # Only continue if precedence is high enough
      if prec < minPrec: break

      walk p # consume operator

      if isBracket:
        # Parse bracket access: lhs[index]
        let indexNode = p.parseExpression()
        expectWalk tkRB
        lhs = ast.newNode(nkBracket).add([lhs, indexNode])
      elif isDot:
        # Parse dot access: lhs.rhs
        if p.curr is tkDot and p.curr.wsno == 0:
          # Handle double dot access `..`
          walk p # tkDot
          let rhs = p.parseExpression(minPrec = prec + 1)
          caseNotNil rhs:
            return ast.newCall(ast.newIdent(".."), lhs, rhs)
        let rhs = p.parseExpression(minPrec = prec + 1)
        lhs = ast.newTree(nkDot, lhs, rhs)
      else:
        # Normal infix operator
        let rhs = p.parseExpression(minPrec = prec)
        lhs = ast.newInfix(ast.newIdent(opStr), lhs, rhs)
    result = lhs

prefixHandle parseStmt:
  # Parse a statement node
  let prefixFn: PrefixFunction = 
    case p.curr.kind
    of tkIdentifier:
      if p.next.line == p.curr.line and p.next is tkLP:
        parseCall
      else: parseElement
    of tkType:
      if p.next.line == p.curr.line and p.next is tkLP:
        parseCall
      elif p.next.line == p.curr.line and p.next is tkLC:
        parseTypeDef
      elif p.next is tkIdentifier:
        parseTypeDef
      else: parseElement
    of tkAt:
      parseMacroCall
    of tkVar, tkConst: parseVar
    of tkIf: parseIf
    of tkWhile: parseWhileLoop
    of tkFor: parseForLoop
    of tkImport, tkInclude: parseImportStmt
    of tkFunc, tkFn: parseFunction
    of tkMacro: parseMacroFunction
    of tkIterator: parseIterator
    of tkStatic: parseStaticStmt
    of tkEcho: parseEcho
    of tkDoc: parseDocComment
    of tkSnippetJs: parseJavaScript
    of tkSnippetCSS: parseCSS
    of tkSnippetHtml: parseRawHtml
    of tkHtmlComment: parseHtmlComment
    of tkViewLoader: parseViewPlaceholder
    of tkClient: parseClientBlock
    else: parseExpression
  if prefixFn != nil:
    return prefixFn(p)

proc parseScript*(astProgram: var Ast, code: string, sourcePath: string) =
  var p = Parser(lex: newLexer(code))
  # defer: p.lex.close()
  p.curr = p.lex.getToken()
  p.next = p.lex.getToken()
  p.skipComments()
  astProgram = Ast()
  astProgram.sourcePath = sourcePath
  while p.curr.kind != tkEOF:
    let node: Node = p.parseStmt()
    caseNotNil node:
      if node.kind == nkStatic:
        # Flatten @static expansion children into top-level nodes
        for child in node.children:
          astProgram.nodes.add(child)
      else:
        astProgram.nodes.add(node)
    do:
      p.curr.error(ErrUnexpectedToken % $p.curr.kind)
  astProgram.otherPaths = move(p.otherPaths)