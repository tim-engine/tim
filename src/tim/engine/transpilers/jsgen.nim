# A super fast template engine for cool kids
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim | https://openpeeps.dev/packages/tim

include ./private

proc jsDocify(js: string): string =
  ## Transform Tim-style typed JS vars (var x: int = 5) to JSDoc-annotated JS
  result = newStringOfCap(js.len)
  for line in js.splitLines:
    let trimmed = line.strip
    let indentLen = line.len - trimmed.len
    var kw: string
    if trimmed.startsWith("var "): kw = "var "
    elif trimmed.startsWith("let "): kw = "let "
    elif trimmed.startsWith("const "): kw = "const "
    else:
      result.add(line & "\n")
      continue
    let rest = trimmed[kw.len..^1]
    let colonIdx = rest.find(':')
    let eqIdx = rest.find('=')
    if colonIdx >= 0 and (eqIdx < 0 or colonIdx < eqIdx):
      let varName = rest[0..<colonIdx].strip
      let afterType = rest[colonIdx+1..^1].strip
      let valueEq = afterType.find('=')
      let typeName = if valueEq >= 0: afterType[0..<valueEq].strip else: afterType
      let value = if valueEq >= 0: " = " & afterType[valueEq+1..^1].strip else: ""
      let jsType = case typeName
        of "int", "float": "number"
        of "bool": "boolean"
        of "string": "string"
        of "void": "void"
        of "any": "*"
        else: typeName
      let indent = repeat(' ', indentLen)
      result.add(indent & "/** @type {" & jsType & "} */\n")
      result.add(indent & kw & varName & value & "\n")
    else:
      result.add(line & "\n")

#
# Forward declarations
#
proc genStmt(node: Node, indent: int = 0) {.codegen.}

#
# JS Transpiler
#

const 
  jsVar = "var"
  jsLet = "let"
  jsConst = "const"
  jsAssign = "$1 = $2;"
  jsFunc = "function $1($2) {\n$3\n}"

proc jsIdent(ident: string): string =
  if ident.len > 0 and ident[0] == '$':
    ident[1..^1]
  else:
    ident

proc jsOp(op: string): string =
  case op
  of "&": "+"
  of "and": "&&"
  of "or": "||"
  of "not": "!"
  of "==": "==="
  of "!=": "!=="
  of "is": "==="
  of "isnot": "!=="
  of "mod": "%"
  else: op

proc inferJsType(valNode: Node): string =
  case valNode.kind
  of nkString: "string"
  of nkInt, nkFloat: "number"
  of nkBool: "boolean"
  of nkArray: "Array"
  of nkObject: "Object"
  of nkNil: "null"
  else: ""

proc jsEscapeStr(s: string): string =
  result = newStringOfCap(s.len)
  for c in s:
    case c
    of '\n': result.add("\\n")
    of '\r': result.add("\\r")
    of '\t': result.add("\\t")
    of '\\': result.add("\\\\")
    of '`':  result.add("\\`")
    of '$':  result.add("\\$")
    else:    result.add(c)

proc jsEscapeDQuote(s: string): string =
  result = newStringOfCap(s.len)
  for c in s:
    case c
    of '\n': result.add("\\n")
    of '\r': result.add("\\r")
    of '\t': result.add("\\t")
    of '\\': result.add("\\\\")
    of '"':  result.add("\\\"")
    else:    result.add(c)

proc getImplValue(node: Node, unquoted = true): string =
  case node.kind
  of nkInt:     $node.intVal
  of nkFloat:   $node.floatVal
  of nkString: 
    if unquoted: "\"" & jsEscapeDQuote(node.stringVal) & "\""
    else: node.stringVal
  of nkBool:    $node.boolVal
  of nkArray:
    "[" & node.children.mapIt(getImplValue(it)).join(", ") & "]"
  of nkObject:
    "{" & node.children.mapIt(
      if it.kind == nkIdentDefs:
        let key = it[0].render
        let value = getImplValue(it[^1])
        key & ": " & value
      else:
        ""
    ).join(", ") & "}"
  else: ""

proc writeVar(node: Node) {.codegen.} =
  case node.kind
  of nkVar:
    result.add(jsLet)
  else:
    result.add(jsConst)
  result.add(" ")
  for decl in node[0]:
    let ident = if decl[0].kind == nkIdent: decl[0].ident else: decl[0].render
    let val = decl[^1].getImplValue
    result.add(jsIdent(ident) & " = " & val)

proc exprToString(node: Node): string =
  case node.kind
  of nkString: "\"" & jsEscapeDQuote(node.stringVal) & "\""
  of nkInt: $node.intVal
  of nkFloat: $node.floatVal
  of nkBool: $node.boolVal
  of nkIdent: jsIdent(node.ident)
  of nkPrefix: jsOp(node[0].ident) & exprToString(node[1])
  of nkPostfix: exprToString(node[0]) & jsOp(node[1].ident)
  of nkInfix:
    let op = if node[0].kind == nkIdent: jsOp(node[0].ident) else: jsOp(node[0].render)
    "(" & exprToString(node[1]) & " " & op & " " & exprToString(node[2]) & ")"
  of nkCall:
    let callee = if node[0].kind == nkIdent: jsIdent(node[0].ident) else: exprToString(node[0])
    callee & "(" & node[1..^1].mapIt(exprToString(it)).join(", ") & ")"
  of nkBracket:
    exprToString(node[0]) & "[" & exprToString(node[1]) & "]"
  of nkDot:
    exprToString(node[0]) & "." & exprToString(node[1])
  else:
    node.render

proc attrsToJs(node: Node): (seq[string], string, seq[(string, string)]) =
  var classNames: seq[string] = @[]
  var idVal: string = ""
  var customAttrs: seq[(string, string)] = @[]
  for attr in node.attributes:
    if attr.kind == nkHtmlAttribute:
      case attr.attrType
      of htmlAttrClass:
        case attr.attrNode.kind
        of nkString:
          classNames.add(attr.attrNode.stringVal)
        of nkIdent:
          classNames.add(attr.attrNode.ident)
        of nkInfix, nkCall:
          classNames.add("${" & exprToString(attr.attrNode) & "}")
        else: discard
      of htmlAttrId:
        case attr.attrNode.kind
        of nkString:
          idVal = attr.attrNode.stringVal
        of nkIdent:
          idVal = attr.attrNode.ident
        of nkInfix, nkCall:
          idVal = "${" & exprToString(attr.attrNode) & "}"
        else: discard
      of htmlAttr:
        if attr.attrNode.kind == nkInfix and attr.attrNode.len >= 3:
          let keyNode = attr.attrNode[1]
          let valNode = attr.attrNode[2]
          let key = if keyNode.kind == nkIdent: keyNode.ident
                    elif keyNode.kind == nkString: keyNode.stringVal
                    else: $keyNode.render
          let valStr = case valNode.kind
            of nkString: jsEscapeDQuote(valNode.stringVal)
            of nkInt, nkFloat, nkBool: $valNode.render
            of nkIdent: valNode.ident
            else: "${" & exprToString(valNode) & "}"
          customAttrs.add((key, valStr))
        elif attr.attrNode.kind == nkString:
          customAttrs.add((attr.attrNode.stringVal, ""))
        elif attr.attrNode.kind == nkIdent:
          customAttrs.add((attr.attrNode.ident, ""))
        else:
          customAttrs.add(("${" & exprToString(attr.attrNode) & "}", ""))
      else: discard
  (classNames, idVal, customAttrs)

proc writeHtml(node: Node, indent: int = 0) {.codegen.} =
  let tag = node.getTag()
  let (classNames, idVal, customAttrs) = attrsToJs(node)
  let ind = repeat("  ", indent)

  result.add(ind & "html += `<" & tag)

  if classNames.len > 0:
    result.add(" class=\\\"")
    var first = true
    for c in classNames:
      if not first: result.add(" ")
      first = false
      result.add(c)
    result.add("\\\"")

  if idVal.len > 0:
    result.add(" id=\\\"" & idVal & "\\\"")

  for (key, value) in customAttrs:
    if value.len > 0:
      result.add(" " & key & "=\\\"" & value & "\\\"")
    else:
      result.add(" " & key)
  result.add(">`;\n")

  for child in node.childElements:
    case child.kind
    of nkString:
      result.add(ind & "html += `" & jsEscapeStr(child.stringVal) & "`;\n")
    of nkBool, nkInt, nkFloat:
      result.add(ind & "html += `" & child.render & "`;\n")
    of nkIdent:
      result.add(ind & "html += String(" & jsIdent(child.ident) & ");\n")
    of nkInfix, nkPrefix, nkPostfix, nkCall, nkBracket, nkDot:
      result.add(ind & "html += String(" & exprToString(child) & ");\n")
    else:
      result.add(gen.genStmt(child, indent))

  if node.tag notin voidHtmlElements:
    result.add(ind & "html += `</" & tag & ">`;\n")

proc genStmt(node: Node, indent: int = 0): Rope {.codegen.} =
  result = Rope()
  let ind = repeat("  ", indent)
  case node.kind
  of nkVar, nkLet, nkConst:
    for decl in node[0]:
      let varName = if decl[0].kind == nkIdent: decl[0].ident else: decl[0].render
      let varType =
        if decl[1].kind != nkEmpty: decl[1].render
        else:
          let inferred = inferJsType(decl[2])
          if inferred.len > 0: inferred else: "any"
      result.add(ind & "/** @type {" & varType & "} */\n")
      result.add(ind & gen.writeVar(node) & ";\n")
  of nkProc:
    let fnName = node[0].render
    let params = node[2]
    let retType = if node[2][0].kind != nkEmpty: node[2][0].render else: "any"
    result.add(ind & "/**\n")
    for param in params[1..^1]:
      if param.kind == nkIdentDefs:
        let pname = param[0].render
        let ptype = if param[1].kind != nkEmpty: param[1].render else: "any"
        result.add(ind & " * @param {" & ptype & "} " & pname & "\n")
    result.add(ind & " * @returns {" & retType & "}\n")
    result.add(ind & " */\n")
    result.add(ind & "function " & fnName & "(")
    result.add(params[1..^1].mapIt(it[0].render).join(", "))
    result.add(") {\n")
    result.add(gen.genStmt(node[3], indent + 1))
    result.add(ind & "}\n")
  of nkMacro:
    let fnName = node[0].ident[1..^1]
    let params = node[2]
    result.add(ind & "/**\n")
    for param in params[1..^1]:
      if param.kind == nkIdentDefs:
        let pname = param[0].render
        let ptype = if param[1].kind != nkEmpty: param[1].render else: "any"
        result.add(ind & " * @param {" & ptype & "} " & pname & "\n")
    result.add(ind & " * @returns {string} HTML\n")
    result.add(ind & " */\n")
    result.add(ind & "function " & fnName & "(")
    result.add(params[1..^1].mapIt(it[0].render).join(", "))
    result.add(") {\n")
    result.add(ind & "  let html = \"\";\n")
    result.add(gen.genStmt(node[3], indent + 1))
    result.add(ind & "  return html;\n")
    result.add(ind & "}\n")
  of nkHtmlElement:
    result.add(gen.writeHtml(node, indent))
  of nkIf:
    result.add(ind & "if (" & exprToString(node[0]) & ") {\n")
    result.add(gen.genStmt(node[1], indent + 1))
    result.add(ind & "}\n")
    let hasElse = node.children.len mod 2 == 1
    let elifBranches = if hasElse: node[2..^2] else: node[2..^1]
    for i in countup(0, elifBranches.len - 1, 2):
      result.add(ind & "else if (" & exprToString(elifBranches[i]) & ") {\n")
      result.add(gen.genStmt(elifBranches[i + 1], indent + 1))
      result.add(ind & "}\n")
    if hasElse:
      result.add(ind & "else {\n")
      result.add(gen.genStmt(node[^1], indent + 1))
      result.add(ind & "}\n")
  of nkFor:
    let varName = if node[0].kind == nkIdent: jsIdent(node[0].ident) else: node[0].render
    let iterable = node[1]
    if iterable.kind == nkCall and iterable[0].kind == nkIdent and iterable[0].ident == "..":
      let startVal = exprToString(iterable[1])
      let endVal = exprToString(iterable[2])
      result.add(ind & "for (let " & varName & " = " & startVal & "; " & varName & " <= " & endVal & "; " & varName & "++) {\n")
      result.add(gen.genStmt(node[2], indent + 1))
      result.add(ind & "}\n")
    else:
      let iterExpr = exprToString(iterable)
      result.add(ind & "for (let " & varName & " of " & iterExpr & ") {\n")
      result.add(gen.genStmt(node[2], indent + 1))
      result.add(ind & "}\n")
  of nkWhile:
    result.add(ind & "while (" & exprToString(node[0]) & ") {\n")
    result.add(gen.genStmt(node[1], indent + 1))
    result.add(ind & "}\n")
  of nkBlock:
    for i, s in node:
      result.add(gen.genStmt(s, indent))
  of nkReturn:
    if node[0].kind != nkEmpty:
      result.add(ind & "return " & exprToString(node[0]) & ";\n")
    else:
      result.add(ind & "return;\n")
  of nkBreak:
    result.add(ind & "break;\n")
  of nkContinue:
    result.add(ind & "continue;\n")
  of nkCall:
    let callee = if node[0].kind == nkIdent: jsIdent(node[0].ident) else: exprToString(node[0])
    if callee == "echo" or callee == "console.log":
      result.add(ind & "console.log(" & node[1..^1].mapIt(exprToString(it)).join(", ") & ");\n")
    else:
      result.add(ind & callee & "(" & node[1..^1].mapIt(exprToString(it)).join(", ") & ");\n")
  of nkInfix, nkPrefix, nkPostfix:
    result.add(ind & exprToString(node) & ";\n")
  of nkIdent:
    result.add(ind & jsIdent(node.ident) & ";\n")
  of nkRawHtml:
    result.add(ind & "html += `" & jsEscapeStr(node.rawHtml) & "`;\n")
  of nkCssSnippet:
    let css = node.snippetCode
    result.add(ind & "html += `<style>`" & ";\n")
    result.add(ind & "html += `" & jsEscapeStr(css) & "`;\n")
    result.add(ind & "html += `</style>`;\n")
  of nkJavaScriptSnippet:
    let js = jsDocify(node.snippetCode)
    result.add(ind & "html += `<script>`" & ";\n")
    result.add(ind & js & "\n")
    result.add(ind & "html += `</script>`;\n")
  of nkDocComment:
    if node.comment.len > 0:
      result.add(ind & "/* " & node.comment & " */\n")
  of nkCustomElement:
    let className = node[0].ident
    let tagName = node[1].stringVal
    let classJsBody = node[2]
    let renderBody = node[3]
    result.add(ind & "class " & className & " extends LitElement {\n")
    for child in classJsBody.children:
      if child.kind == nkJavaScriptSnippet:
        for line in jsDocify(child.snippetCode).split('\n'):
          result.add(ind & "  " & line & "\n")
      else:
        result.add(gen.genStmt(child, indent + 1))
    result.add(ind & "  connectedCallback() { this.render(); }\n")
    result.add(ind & "  render() {\n")
    result.add(ind & "    let html = ``;\n")
    if renderBody.kind == nkClientBlock:
      for stmt in renderBody[0].children:
        result.add(gen.genStmt(stmt, indent + 2))
    result.add(ind & "    this.innerHTML = html;\n")
    result.add(ind & "  }\n")
    result.add(ind & "}\n")
    result.add(ind & "customElements.define('" & tagName & "', " & className & ");\n")
  else: discard

proc genScript*(program: Ast, includePath: Option[string],
            isMainScript: static bool = false,
            isSnippet: static bool = false,
            commonJs = true) {.codegen.} =
  let modName = gen.module.getModuleName()
  if not commonJs:
    result.add("export default class $1 {\n" % [modName])
  else:
    result.add("class $1 {\n" % [modName])
  result.add("  static render(locals = {}, app = {}) {\n")
  result.add("    let html = \"\";\n")
  for node in program.nodes:
    result.add(gen.genStmt(node, 2))
  result.add("    return html;\n")
  result.add("  }\n}")
  if commonJs:
    result.add("\nmodule.exports = $1;\n" % [modName])

proc genScript*(nodes: seq[Node]) {.codegen.} =
  for node in nodes:
    result.add(gen.genStmt(node, 2))
