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
# PHP Transpiler
#

proc phpEscapeStr(s: string): string =
  result = newStringOfCap(s.len)
  for c in s:
    case c
    of '\n': result.add("\\n")
    of '\r': result.add("\\r")
    of '\t': result.add("\\t")
    of '\\': result.add("\\\\")
    of '"':  result.add("\\\"")
    of '$':  result.add("\\$")
    else:    result.add(c)

proc inferPhpType(valNode: Node): string =
  case valNode.kind
  of nkString: "string"
  of nkInt: "int"
  of nkFloat: "float"
  of nkBool: "bool"
  of nkArray, nkObject: "array"
  of nkNil: "null"
  else: ""

proc phpOp(op: string): string =
  case op
  of "&": "."
  of "is": "==="
  of "isnot": "!=="
  of "and": "and"
  of "or": "or"
  of "not": "!"
  of "mod": "%"
  else: op

proc getImplValue(node: Node): string =
  case node.kind
  of nkInt:     $node.intVal
  of nkFloat:   $node.floatVal
  of nkString:  "\"" & phpEscapeStr(node.stringVal) & "\""
  of nkBool:    $node.boolVal
  of nkArray:
    "[" & node.children.mapIt(getImplValue(it)).join(", ") & "]"
  of nkObject:
    "[" & node.children.mapIt(
      if it.kind == nkIdentDefs:
        "'" & it[0].render & "' => " & getImplValue(it[^1])
      else:
        ""
    ).join(", ") & "]"
  else: ""

proc writeVar(node: Node) {.codegen.} =
  for child in node:
    if child.kind == nkIdentDefs:
      for decl in child:
        if decl.kind == nkAssign and decl[0].kind == nkIdent:
          result.add("$" & decl[0].ident & " = " & decl[2].getImplValue & ";\n")

proc exprToString(node: Node): string =
  case node.kind
  of nkString: "\"" & phpEscapeStr(node.stringVal) & "\""
  of nkInt: $node.intVal
  of nkFloat: $node.floatVal
  of nkBool: (if node.boolVal: "true" else: "false")
  of nkIdent: "$" & node.ident
  of nkPrefix:
    let op = if node[0].kind == nkIdent: phpOp(node[0].ident) else: phpOp(node[0].render)
    op & exprToString(node[1])
  of nkPostfix:
    let op = if node[1].kind == nkIdent: phpOp(node[1].ident) else: phpOp(node[1].render)
    exprToString(node[0]) & op
  of nkInfix:
    let op = if node[0].kind == nkIdent: phpOp(node[0].ident) else: phpOp(node[0].render)
    "(" & exprToString(node[1]) & " " & op & " " & exprToString(node[2]) & ")"
  of nkCall:
    let callee = if node[0].kind == nkIdent: node[0].ident else: exprToString(node[0])
    callee & "(" & node[1..^1].filterIt(it.kind != nkHtmlAttribute).mapIt(exprToString(it)).join(", ") & ")"
  of nkBracket:
    exprToString(node[0]) & "[" & exprToString(node[1]) & "]"
  of nkDot:
    exprToString(node[0]) & "->" & exprToString(node[1])
  else:
    ""

proc attrsToPhp(node: Node): (seq[string], string, seq[(string, string)]) =
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
          classNames.add("\" . " & exprToString(attr.attrNode) & " . \"")
        else: discard
      of htmlAttrId:
        case attr.attrNode.kind
        of nkString:
          idVal = attr.attrNode.stringVal
        of nkIdent:
          idVal = attr.attrNode.ident
        of nkInfix, nkCall:
          idVal = "\" . " & exprToString(attr.attrNode) & " . \""
        else: discard
      of htmlAttr:
        if attr.attrNode.kind == nkInfix and attr.attrNode.len >= 3:
          let keyNode = attr.attrNode[1]
          let valNode = attr.attrNode[2]
          let key = if keyNode.kind == nkIdent: keyNode.ident
                    elif keyNode.kind == nkString: keyNode.stringVal
                    else: $keyNode.render
          let valStr = case valNode.kind
            of nkString: phpEscapeStr(valNode.stringVal)
            of nkInt, nkFloat, nkBool: $valNode.render
            of nkIdent: "\" . " & exprToString(valNode) & " . \""
            else: "\" . " & exprToString(valNode) & " . \""
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
  let (classNames, idVal, customAttrs) = attrsToPhp(node)
  let ind = repeat("  ", indent)

  result.add(ind & "$html .= \"<" & tag)

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
  result.add(">\";\n")

  for child in node.childElements:
    case child.kind
    of nkString:
      result.add(ind & "$html .= \"" & phpEscapeStr(child.stringVal) & "\";\n")
    of nkBool, nkInt, nkFloat:
      result.add(ind & "$html .= " & $child.render & ";\n")
    of nkIdent:
      result.add(ind & "$html .= $" & child.ident & ";\n")
    of nkInfix, nkPrefix, nkPostfix, nkCall, nkBracket, nkDot:
      result.add(ind & "$html .= " & exprToString(child) & ";\n")
    else:
      result.add(gen.genStmt(child, indent))

  if node.tag notin voidHtmlElements:
    result.add(ind & "$html .= \"</" & tag & ">\";\n")

proc genStmt(node: Node, indent: int = 0): Rope {.codegen.} =
  result = Rope()
  let ind = repeat("  ", indent)
  case node.kind
  of nkVar, nkLet, nkConst:
    for decl in node:
      if decl.kind == nkIdentDefs and decl[0].kind == nkAssign:
        let varName = decl[0][0].ident
        let varType =
          if decl[0][1].kind != nkEmpty: decl[0][1].render
          else:
            let inferred = inferPhpType(decl[0][2])
            if inferred.len > 0: inferred else: "mixed"
        result.add(ind & "// @var $" & varName & ": " & varType & "\n")
      result.add(ind & gen.writeVar(node))
  of nkProc:
    let fnName = node[0].render
    let params = node[2]
    let retType = if node[2][0].kind != nkEmpty: node[2][0].render else: "mixed"
    result.add(ind & "/**\n")
    for param in params[1..^1]:
      if param.kind == nkIdentDefs:
        let pname = param[0].render
        let ptype = if param[1].kind != nkEmpty: param[1].render else: "mixed"
        result.add(ind & " * @param " & ptype & " $" & pname & "\n")
    result.add(ind & " * @return " & retType & "\n")
    result.add(ind & " */\n")
    result.add(ind & "function " & fnName & "(")
    result.add(params[1..^1].mapIt("$" & it[0].render).join(", "))
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
        let ptype = if param[1].kind != nkEmpty: param[1].render else: "mixed"
        result.add(ind & " * @param " & ptype & " $" & pname & "\n")
    result.add(ind & " * @return string HTML\n")
    result.add(ind & " */\n")
    result.add(ind & "function " & fnName & "(")
    result.add(params[1..^1].mapIt("$" & it[0].render).join(", "))
    result.add(") {\n")
    result.add(ind & "  $html = '';\n")
    result.add(gen.genStmt(node[3], indent + 1))
    result.add(ind & "  return $html;\n")
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
      result.add(ind & "elseif (" & exprToString(elifBranches[i]) & ") {\n")
      result.add(gen.genStmt(elifBranches[i + 1], indent + 1))
      result.add(ind & "}\n")
    if hasElse:
      result.add(ind & "else {\n")
      result.add(gen.genStmt(node[^1], indent + 1))
      result.add(ind & "}\n")
  of nkFor:
    let varName = node[0].render
    let iterable = node[1]
    if iterable.kind == nkCall and iterable[0].kind == nkIdent and iterable[0].ident == "..":
      let startVal = exprToString(iterable[1])
      let endVal = exprToString(iterable[2])
      result.add(ind & "for ($" & varName & " = " & startVal & "; $" & varName & " <= " & endVal & "; $" & varName & "++) {\n")
      result.add(gen.genStmt(node[2], indent + 1))
      result.add(ind & "}\n")
    else:
      let iterExpr = exprToString(iterable)
      result.add(ind & "foreach (" & iterExpr & " as $" & varName & ") {\n")
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
    let callee = if node[0].kind == nkIdent: node[0].ident else: exprToString(node[0])
    if callee == "echo":
      result.add(ind & "echo " & node[1..^1].filterIt(it.kind != nkHtmlAttribute).mapIt(exprToString(it)).join(", ") & ";\n")
    else:
      result.add(ind & callee & "(" & node[1..^1].filterIt(it.kind != nkHtmlAttribute).mapIt(exprToString(it)).join(", ") & ");\n")
  of nkAssign:
    result.add(ind & exprToString(node[0]) & " = " & exprToString(node[1]) & ";\n")
  of nkInfix, nkPrefix, nkPostfix:
    result.add(ind & exprToString(node) & ";\n")
  of nkIdent:
    result.add(ind & "$" & node.ident & ";\n")
  of nkRawHtml:
    result.add(ind & "$html .= \"" & phpEscapeStr(node.rawHtml) & "\";\n")
  of nkCssSnippet:
    let css = node.snippetCode
    result.add(ind & "$html .= \"<style>\"\n")
    result.add(ind & "$html .= \"" & phpEscapeStr(css) & "\";\n")
    result.add(ind & "$html .= \"</style>\"\n")
  of nkJavaScriptSnippet:
    let js = node.snippetCode
    result.add(ind & "$html .= \"<script>\"\n")
    result.add(ind & js & "\n")
    result.add(ind & "$html .= \"</script>\"\n")
  of nkDocComment:
    if node.comment.len > 0:
      result.add(ind & "/* " & node.comment & " */\n")
  else: discard

proc genScript*(program: Ast, includePath: Option[string],
            isMainScript: static bool = false,
            isSnippet: static bool = false) {.codegen.} =
  let modName = gen.module.getModuleName()
  result.add("<?php\n")
  result.add("class $1 {\n" % [modName])
  result.add("  static function render($locals = [], $app = []) {\n")
  result.add("    $html = '';\n")
  for node in program.nodes:
    result.add(gen.genStmt(node, 2))
  result.add("    return $html;\n")
  result.add("  }\n}\n")
