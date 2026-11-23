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
# Lua Transpiler
#

proc luaOp(op: string): string =
  case op
  of "&": ".."
  of "==": "=="
  of "!=": "~="
  of "is": "=="
  of "isnot": "~="
  of "and": "and"
  of "or": "or"
  of "not": "not"
  of "mod": "%"
  else: op

proc luaEscapeStr(s: string): string =
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
    if unquoted: "\"" & luaEscapeStr(node.stringVal) & "\""
    else: node.stringVal
  of nkBool:
    if node.boolVal: "true"
    else: "false"
  of nkArray:
    "{" & node.children.mapIt(getImplValue(it)).join(", ") & "}"
  of nkObject:
    "{ " & node.children.mapIt(
      if it.kind == nkIdentDefs:
        let key = it[0].render
        let value = getImplValue(it[^1])
        key & " = " & value
      else:
        ""
    ).join(", ") & " }"
  else: ""

proc writeVar(node: Node, indent: int = 0): string {.codegen.} =
  let ind = repeat("  ", indent)
  for decl in node[0]:
    let varName = if decl[0].kind == nkIdent: decl[0].ident else: decl[0][0].ident
    let value = decl[^1].getImplValue
    result.add(ind & "local " & varName & " = " & value & "\n")

proc exprToString(node: Node): string =
  case node.kind
  of nkString: "\"" & luaEscapeStr(node.stringVal) & "\""
  of nkInt: $node.intVal
  of nkFloat: $node.floatVal
  of nkBool:
    if node.boolVal: "true" else: "false"
  of nkIdent: node.ident
  of nkPrefix: luaOp(node[0].ident) & exprToString(node[1])
  of nkPostfix: exprToString(node[0]) & luaOp(node[1].ident)
  of nkInfix:
    let op = if node[0].kind == nkIdent: luaOp(node[0].ident) else: luaOp(node[0].render)
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

proc attrsToLua(node: Node): (seq[string], string, seq[(string, string)]) =
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
          classNames.add("\" .. " & exprToString(attr.attrNode) & " .. \"")
        else: discard
      of htmlAttrId:
        case attr.attrNode.kind
        of nkString:
          idVal = attr.attrNode.stringVal
        of nkIdent:
          idVal = attr.attrNode.ident
        of nkInfix, nkCall:
          idVal = "\" .. " & exprToString(attr.attrNode) & " .. \""
        else: discard
      of htmlAttr:
        if attr.attrNode.kind == nkInfix and attr.attrNode.len >= 3:
          let keyNode = attr.attrNode[1]
          let valNode = attr.attrNode[2]
          let key = if keyNode.kind == nkIdent: keyNode.ident
                    elif keyNode.kind == nkString: keyNode.stringVal
                    else: $keyNode.render
          let valStr = case valNode.kind
            of nkString: luaEscapeStr(valNode.stringVal)
            of nkInt, nkFloat, nkBool: $valNode.render
            of nkIdent: "\" .. " & valNode.ident & " .. \""
            else: "\" .. " & exprToString(valNode) & " .. \""
          customAttrs.add((key, valStr))
        elif attr.attrNode.kind == nkString:
          customAttrs.add((attr.attrNode.stringVal, ""))
        elif attr.attrNode.kind == nkIdent:
          customAttrs.add((attr.attrNode.ident, ""))
        else:
          discard
      else: discard
  (classNames, idVal, customAttrs)

proc writeHtml(node: Node, indent: int = 0): string {.codegen.} =
  let tag = node.getTag()
  let (classNames, idVal, customAttrs) = attrsToLua(node)
  let ind = repeat("  ", indent)

  result.add(ind & "html = html .. \"<" & tag)

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
  result.add(">\"\n")

  for child in node.childElements:
    case child.kind
    of nkString:
      result.add(ind & "html = html .. \"" & luaEscapeStr(child.stringVal) & "\"\n")
    of nkBool, nkInt, nkFloat:
      result.add(ind & "html = html .. tostring(" & $child.render & ")\n")
    of nkIdent:
      result.add(ind & "html = html .. tostring(" & child.ident & ")\n")
    of nkInfix, nkPrefix, nkPostfix, nkCall, nkBracket, nkDot:
      result.add(ind & "html = html .. tostring(" & exprToString(child) & ")\n")
    else:
      result.add(gen.genStmt(child, indent))

  if node.tag notin voidHtmlElements:
    result.add(ind & "html = html .. \"</" & tag & ">\"\n")

proc genStmt(node: Node, indent: int = 0): Rope {.codegen.} =
  result = Rope()
  let ind = repeat("  ", indent)
  case node.kind
  of nkVar, nkLet, nkConst:
    result.add(gen.writeVar(node, indent))
  of nkProc:
    let fnName = node[0].render
    let params = node[2]
    result.add(ind & "function " & fnName & "(")
    result.add(params[1..^1].mapIt(it[0].render).join(", "))
    result.add(")\n")
    for param in params[1..^1]:
      if param.kind == nkIdentDefs:
        let pname = param[0].render
        result.add(ind & "  -- @param " & pname & "\n")
    result.add(gen.genStmt(node[3], indent + 1))
    result.add(ind & "end\n")
  of nkMacro:
    let fnName = node[0].ident[1..^1]
    let params = node[2]
    result.add(ind & "function " & fnName & "(")
    result.add(params[1..^1].mapIt(it[0].render).join(", "))
    result.add(")\n")
    for param in params[1..^1]:
      if param.kind == nkIdentDefs:
        let pname = param[0].render
        result.add(ind & "  -- @param " & pname & "\n")
    result.add(ind & "  -- @return string HTML\n")
    result.add(ind & "  local html = ''\n")
    result.add(gen.genStmt(node[3], indent + 1))
    result.add(ind & "  return html\n")
    result.add(ind & "end\n")
  of nkHtmlElement:
    result.add(gen.writeHtml(node, indent))
  of nkIf:
    result.add(ind & "if " & exprToString(node[0]) & " then\n")
    result.add(gen.genStmt(node[1], indent + 1))
    let hasElse = node.children.len mod 2 == 1
    let elifBranches = if hasElse: node[2..^2] else: node[2..^1]
    for i in countup(0, elifBranches.len - 1, 2):
      result.add(ind & "elseif " & exprToString(elifBranches[i]) & " then\n")
      result.add(gen.genStmt(elifBranches[i + 1], indent + 1))
    if hasElse:
      result.add(ind & "else\n")
      result.add(gen.genStmt(node[^1], indent + 1))
    result.add(ind & "end\n")
  of nkFor:
    let varName = node[0].render
    let iterable = node[1]
    if iterable.kind == nkCall and iterable[0].kind == nkIdent and iterable[0].ident == "..":
      let startVal = exprToString(iterable[1])
      let endVal = exprToString(iterable[2])
      result.add(ind & "for " & varName & " = " & startVal & ", " & endVal & " do\n")
      result.add(gen.genStmt(node[2], indent + 1))
      result.add(ind & "end\n")
    else:
      let iterExpr = exprToString(iterable)
      result.add(ind & "for _, " & varName & " in ipairs(" & iterExpr & ") do\n")
      result.add(gen.genStmt(node[2], indent + 1))
      result.add(ind & "end\n")
  of nkWhile:
    result.add(ind & "while " & exprToString(node[0]) & " do\n")
    result.add(gen.genStmt(node[1], indent + 1))
    result.add(ind & "end\n")
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
    result.add(ind & "goto continue\n")
  of nkCall:
    let callee = if node[0].kind == nkIdent: node[0].ident else: exprToString(node[0])
    if callee == "echo":
      result.add(ind & "print(" & node[1..^1].filterIt(it.kind != nkHtmlAttribute).mapIt(exprToString(it)).join(", ") & ")\n")
    else:
      result.add(ind & callee & "(" & node[1..^1].filterIt(it.kind != nkHtmlAttribute).mapIt(exprToString(it)).join(", ") & ")\n")
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
    result.add(ind & "html = html .. [[" & node.rawHtml & "]]\n")
  of nkCssSnippet:
    let css = node.snippetCode
    result.add(ind & "html = html .. \"<style>\"\n")
    result.add(ind & "html = html .. [[" & css & "]]\n")
    result.add(ind & "html = html .. \"</style>\"\n")
  of nkJavaScriptSnippet:
    let js = node.snippetCode
    result.add(ind & "html = html .. \"<script>\"\n")
    result.add(ind & js & "\n")
    result.add(ind & "html = html .. \"</script>\"\n")
  of nkDocComment:
    if node.comment.len > 0:
      result.add(ind & "--[[ " & node.comment & " ]]\n")
  else: discard

proc genScript*(program: Ast, includePath: Option[string],
            isMainScript: static bool = false,
            isSnippet: static bool = false,
            withReturnStmt: static bool = true) {.codegen.} =
  let modName = gen.module.getModuleName()
  result.add("local $1 = {}\n" % [modName])
  result.add("\n-- @param args Table\n-- @return string The generated HTML.\n")
  result.add("function $1.render(args)\n" % [modName])
  result.add("  local app = args.app or {}\n")
  result.add("  local this = args.this or {}\n")
  result.add("  local html = ''\n")
  for node in program.nodes:
    result.add(gen.genStmt(node, 1))
  result.add("  return html\n")
  result.add("end\n")
  when withReturnStmt == true:
    result.add("return $1\n" % [modName])
