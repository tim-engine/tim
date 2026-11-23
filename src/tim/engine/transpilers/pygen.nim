# A super fast template engine for cool kids
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim | https://openpeeps.dev/packages/tim

include ./private

#
# Forward declarations
#
proc genStmt(node: Node, indent: int = 0) {.codegen.}

#
# Python Transpiler
#

proc pyEscapeStr(s: string): string =
  result = newStringOfCap(s.len)
  for c in s:
    case c
    of '\n': result.add("\\n")
    of '\r': result.add("\\r")
    of '\t': result.add("\\t")
    of '\\': result.add("\\\\")
    of '\'': result.add("\\'")
    else:    result.add(c)

proc pyOp(op: string): string =
  case op
  of "&": "+"
  of "is": "=="
  of "isnot": "!="
  of "mod": "%"
  else: op

proc getImplValue(node: Node): string =
  case node.kind
  of nkInt:     $node.intVal
  of nkFloat:   $node.floatVal
  of nkString:  "'" & pyEscapeStr(node.stringVal) & "'"
  of nkBool:
    if node.boolVal: "True"
    else: "False"
  of nkArray:
    "[" & node.children.mapIt(getImplValue(it)).join(", ") & "]"
  of nkObject:
    "{" & node.children.mapIt(
      if it.kind == nkIdentDefs:
        "'" & it[0].render & "': " & getImplValue(it[^1])
      else:
        ""
    ).join(", ") & "}"
  else: ""

proc writeVar(node: Node, indent: int = 0): string {.codegen.} =
  let ind = repeat("    ", indent)
  for child in node:
    if child.kind == nkIdentDefs:
      for decl in child:
        if decl.kind == nkAssign and decl[0].kind == nkIdent:
          result.add(ind & decl[0].ident & " = " & decl[2].getImplValue & "\n")

proc exprToString(node: Node): string =
  case node.kind
  of nkString: "'" & pyEscapeStr(node.stringVal) & "'"
  of nkInt: $node.intVal
  of nkFloat: $node.floatVal
  of nkBool:
    if node.boolVal: "True" else: "False"
  of nkIdent: node.ident
  of nkPrefix:
    let op = if node[0].kind == nkIdent: pyOp(node[0].ident) else: pyOp(node[0].render)
    op & exprToString(node[1])
  of nkPostfix:
    let op = if node[1].kind == nkIdent: pyOp(node[1].ident) else: pyOp(node[1].render)
    exprToString(node[0]) & op
  of nkInfix:
    let origOp = if node[0].kind == nkIdent: node[0].ident else: node[0].render
    let op = pyOp(origOp)
    if origOp == "&":
      "(str(" & exprToString(node[1]) & ") + str(" & exprToString(node[2]) & "))"
    else:
      "(" & exprToString(node[1]) & " " & op & " " & exprToString(node[2]) & ")"
  of nkCall:
    let callee = if node[0].kind == nkIdent: node[0].ident else: exprToString(node[0])
    callee & "(" & node[1..^1].filterIt(it.kind != nkHtmlAttribute).mapIt(exprToString(it)).join(", ") & ")"
  of nkBracket:
    exprToString(node[0]) & "[" & exprToString(node[1]) & "]"
  of nkDot:
    exprToString(node[0]) & "." & exprToString(node[1])
  else:
    ""

proc attrsToPy(node: Node): (seq[string], string, seq[(string, string)]) =
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
          classNames.add("{ " & exprToString(attr.attrNode) & " }")
        else: discard
      of htmlAttrId:
        case attr.attrNode.kind
        of nkString:
          idVal = attr.attrNode.stringVal
        of nkIdent:
          idVal = attr.attrNode.ident
        of nkInfix, nkCall:
          idVal = "{ " & exprToString(attr.attrNode) & " }"
        else: discard
      of htmlAttr:
        if attr.attrNode.kind == nkInfix and attr.attrNode.len >= 3:
          let keyNode = attr.attrNode[1]
          let valNode = attr.attrNode[2]
          let key = if keyNode.kind == nkIdent: keyNode.ident
                    elif keyNode.kind == nkString: keyNode.stringVal
                    else: $keyNode.render
          let valStr = case valNode.kind
            of nkString: pyEscapeStr(valNode.stringVal)
            of nkInt, nkFloat, nkBool: $valNode.render
            of nkIdent: "{ " & valNode.ident & " }"
            else: "{ " & exprToString(valNode) & " }"
          customAttrs.add((key, valStr))
        elif attr.attrNode.kind == nkString:
          customAttrs.add((attr.attrNode.stringVal, ""))
        elif attr.attrNode.kind == nkIdent:
          customAttrs.add((attr.attrNode.ident, ""))
        else: discard
      else: discard
  (classNames, idVal, customAttrs)

proc writeHtml(node: Node, indent: int = 0) {.codegen.} =
  let tag = node.getTag()
  let (classNames, idVal, customAttrs) = attrsToPy(node)
  let ind = repeat("    ", indent)

  result.add(ind & "html.append(f'<" & tag)

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
  result.add(">')\n")

  for child in node.childElements:
    case child.kind
    of nkString:
      result.add(ind & "html.append('" & pyEscapeStr(child.stringVal) & "')\n")
    of nkBool, nkInt, nkFloat:
      result.add(ind & "html.append(" & $child.render & ")\n")
    of nkIdent:
      result.add(ind & "html.append(str(" & child.ident & "))\n")
    of nkInfix, nkPrefix, nkPostfix, nkCall, nkBracket, nkDot:
      result.add(ind & "html.append(str(" & exprToString(child) & "))\n")
    else:
      result.add(gen.genStmt(child, indent))

  if node.tag notin voidHtmlElements:
    result.add(ind & "html.append('</" & tag & ">')\n")

proc genStmt(node: Node, indent: int = 0): Rope {.codegen.} =
  result = Rope()
  let ind = repeat("    ", indent)
  case node.kind
  of nkVar, nkLet, nkConst:
    for decl in node:
      if decl.kind == nkIdentDefs:
        for d in decl:
          if d.kind == nkAssign and d[0].kind == nkIdent:
            let varName = d[0].ident
            let varType = if d[1].kind != nkEmpty: d[1].render else: "Any"
            result.add(ind & "# type: " & varName & ": " & varType & "\n")
        result.add(gen.writeVar(node, indent))
  of nkProc:
    let fnName = node[0].render
    let params = node[2]
    let retType = if params[0].kind != nkEmpty: params[0].render else: "Any"
    result.add(ind & "def " & fnName & "(")
    result.add(params[1..^1].mapIt(it[0].render).join(", "))
    result.add("):\n")
    result.add(ind & "    \"\"\"\n")
    for param in params[1..^1]:
      if param.kind == nkIdentDefs:
        let pname = param[0].render
        let ptype = if param[1].kind != nkEmpty: param[1].render else: "Any"
        result.add(ind & "    :param " & pname & ": " & ptype & "\n")
    result.add(ind & "    :returns: " & retType & "\n")
    result.add(ind & "    \"\"\"\n")
    result.add(gen.genStmt(node[3], indent + 1))
  of nkMacro:
    let fnName = node[0].ident[1..^1]
    let params = node[2]
    result.add(ind & "def " & fnName & "(")
    result.add(params[1..^1].mapIt(it[0].render).join(", "))
    result.add("):\n")
    result.add(ind & "    \"\"\"\n")
    for param in params[1..^1]:
      if param.kind == nkIdentDefs:
        let pname = param[0].render
        let ptype = if param[1].kind != nkEmpty: param[1].render else: "Any"
        result.add(ind & "    :param " & pname & ": " & ptype & "\n")
    result.add(ind & "    :returns: str\n")
    result.add(ind & "    \"\"\"\n")
    result.add(ind & "    html = ''\n")
    result.add(gen.genStmt(node[3], indent + 1))
    result.add(ind & "    return html\n")
  of nkHtmlElement:
    result.add(gen.writeHtml(node, indent))
  of nkIf:
    result.add(ind & "if " & exprToString(node[0]) & ":\n")
    result.add(gen.genStmt(node[1], indent + 1))
    let hasElse = node.children.len mod 2 == 1
    let elifBranches = if hasElse: node[2..^2] else: node[2..^1]
    for i in countup(0, elifBranches.len - 1, 2):
      result.add(ind & "elif " & exprToString(elifBranches[i]) & ":\n")
      result.add(gen.genStmt(elifBranches[i + 1], indent + 1))
    if hasElse:
      result.add(ind & "else:\n")
      result.add(gen.genStmt(node[^1], indent + 1))
  of nkFor:
    let varName = node[0].render
    let iterable = node[1]
    if iterable.kind == nkCall and iterable[0].kind == nkIdent and iterable[0].ident == "..":
      let startVal = exprToString(iterable[1])
      let endVal = exprToString(iterable[2])
      result.add(ind & "for " & varName & " in range(" & startVal & ", " & endVal & " + 1):\n")
      result.add(gen.genStmt(node[2], indent + 1))
    else:
      let iterExpr = exprToString(iterable)
      result.add(ind & "for " & varName & " in " & iterExpr & ":\n")
      result.add(gen.genStmt(node[2], indent + 1))
  of nkWhile:
    result.add(ind & "while " & exprToString(node[0]) & ":\n")
    result.add(gen.genStmt(node[1], indent + 1))
  of nkBlock:
    for i, s in node:
      result.add(gen.genStmt(s, indent))
  of nkReturn:
    if node[0].kind != nkEmpty:
      result.add(ind & "return " & exprToString(node[0]) & "\n")
    else:
      result.add(ind & "return\n")
  of nkBreak:
    result.add(ind & "break\n")
  of nkContinue:
    result.add(ind & "continue\n")
  of nkCall:
    let callee = if node[0].kind == nkIdent: node[0].ident else: exprToString(node[0])
    if callee == "echo":
      result.add(ind & "print(" & node[1..^1].filterIt(it.kind != nkHtmlAttribute).mapIt(exprToString(it)).join(", ") & ")\n")
    else:
      result.add(ind & callee & "(" & node[1..^1].filterIt(it.kind != nkHtmlAttribute).mapIt(exprToString(it)).join(", ") & ")\n")
  of nkAssign:
    result.add(ind & exprToString(node[0]) & " = " & exprToString(node[1]) & "\n")
  of nkInfix, nkPrefix, nkPostfix:
    let op = if node.kind == nkInfix and node[0].kind == nkIdent: node[0].ident
             elif node.kind == nkInfix: node[0].render
             else: ""
    if op == "=":
      result.add(ind & exprToString(node[1]) & " = " & exprToString(node[2]) & "\n")
    else:
      result.add(ind & exprToString(node) & "\n")
  of nkIdent:
    result.add(ind & node.ident & "\n")
  of nkRawHtml:
    result.add(ind & "html.append('" & pyEscapeStr(node.rawHtml) & "')\n")
  of nkCssSnippet:
    let css = node.snippetCode
    result.add(ind & "html.append('<style>')\n")
    result.add(ind & "html.append('" & pyEscapeStr(css) & "')\n")
    result.add(ind & "html.append('</style>')\n")
  of nkJavaScriptSnippet:
    let js = node.snippetCode
    result.add(ind & "html.append('<script>')\n")
    result.add(ind & js & "\n")
    result.add(ind & "html.append('</script>')\n")
  of nkDocComment:
    if node.comment.len > 0:
      result.add(ind & "# " & node.comment & "\n")
  else: discard

proc genScript*(program: Ast, includePath: Option[string],
            isMainScript: static bool = false,
            isSnippet: static bool = false) {.codegen.} =
  let modName = gen.module.getModuleName()
  result.add("class $1:\n" % [modName])
  result.add("    @staticmethod\n")
  result.add("    def render(locals=None, app=None):\n")
  result.add("        html = []\n")
  for node in program.nodes:
    result.add(gen.genStmt(node, 2))
  result.add("        return ''.join(html)\n")
