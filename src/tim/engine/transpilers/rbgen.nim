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
# Ruby Transpiler
#

proc rubyEscapeStr(s: string): string =
  result = newStringOfCap(s.len)
  for c in s:
    case c
    of '\n': result.add("\\n")
    of '\r': result.add("\\r")
    of '\t': result.add("\\t")
    of '\\': result.add("\\\\")
    of '"':  result.add("\\\"")
    of '#':  result.add("\\#")
    else:    result.add(c)

proc rubyOp(op: string): string =
  case op
  of "&": "+"
  of "is": "=="
  of "isnot": "!="
  of "and": "&&"
  of "or": "||"
  of "not": "!"
  of "mod": "%"
  else: op

proc getImplValue(node: Node): string =
  case node.kind
  of nkInt:     $node.intVal
  of nkFloat:   $node.floatVal
  of nkString:  "\"" & rubyEscapeStr(node.stringVal) & "\""
  of nkBool:
    if node.boolVal: "true"
    else: "false"
  of nkArray:
    "[" & node.children.mapIt(getImplValue(it)).join(", ") & "]"
  of nkObject:
    "{" & node.children.mapIt(
      if it.kind == nkIdentDefs:
        let key = it[0].render
        let value = getImplValue(it[^1])
        ":" & key & " => " & value
      else:
        ""
    ).join(", ") & "}"
  else: ""

proc writeVar(node: Node, indent: int = 0): string {.codegen.} =
  let ind = repeat("  ", indent)
  for child in node:
    if child.kind == nkIdentDefs:
      for decl in child:
        if decl.kind == nkAssign and decl[0].kind == nkIdent:
          result.add(ind & decl[0].ident & " = " & decl[2].getImplValue & "\n")

proc exprToString(node: Node): string =
  case node.kind
  of nkString: "\"" & rubyEscapeStr(node.stringVal) & "\""
  of nkInt: $node.intVal
  of nkFloat: $node.floatVal
  of nkBool:
    if node.boolVal: "true" else: "false"
  of nkIdent: node.ident
  of nkPrefix:
    let op = if node[0].kind == nkIdent: rubyOp(node[0].ident) else: rubyOp(node[0].render)
    op & exprToString(node[1])
  of nkPostfix:
    let op = if node[1].kind == nkIdent: rubyOp(node[1].ident) else: rubyOp(node[1].render)
    exprToString(node[0]) & op
  of nkInfix:
    let origOp = if node[0].kind == nkIdent: node[0].ident else: node[0].render
    let op = rubyOp(origOp)
    if origOp == "&":
      "(" & exprToString(node[1]) & ".to_s + " & exprToString(node[2]) & ".to_s)"
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

proc attrsToRb(node: Node): (seq[string], string, seq[(string, string)]) =
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
          classNames.add("#{ " & exprToString(attr.attrNode) & " }")
        else: discard
      of htmlAttrId:
        case attr.attrNode.kind
        of nkString:
          idVal = attr.attrNode.stringVal
        of nkIdent:
          idVal = attr.attrNode.ident
        of nkInfix, nkCall:
          idVal = "#{ " & exprToString(attr.attrNode) & " }"
        else: discard
      of htmlAttr:
        if attr.attrNode.kind == nkInfix and attr.attrNode.len >= 3:
          let keyNode = attr.attrNode[1]
          let valNode = attr.attrNode[2]
          let key = if keyNode.kind == nkIdent: keyNode.ident
                    elif keyNode.kind == nkString: keyNode.stringVal
                    else: $keyNode.render
          let valStr = case valNode.kind
            of nkString: rubyEscapeStr(valNode.stringVal)
            of nkInt, nkFloat, nkBool: $valNode.render
            of nkIdent: "#{ " & valNode.ident & " }"
            else: "#{ " & exprToString(valNode) & " }"
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
  let (classNames, idVal, customAttrs) = attrsToRb(node)
  let ind = repeat("  ", indent)

  result.add(ind & "html << \"<" & tag)

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
      result.add(ind & "html << \"" & rubyEscapeStr(child.stringVal) & "\"\n")
    of nkBool, nkInt, nkFloat:
      result.add(ind & "html << \"#{ " & $child.render & " }\"\n")
    of nkIdent:
      result.add(ind & "html << \"#{ " & child.ident & " }\"\n")
    of nkInfix, nkPrefix, nkPostfix, nkCall, nkBracket, nkDot:
      result.add(ind & "html << \"#{ " & exprToString(child) & " }\"\n")
    else:
      result.add(gen.genStmt(child, indent))

  if node.tag notin voidHtmlElements:
    result.add(ind & "html << \"</" & tag & ">\"\n")

proc genStmt(node: Node, indent: int = 0): Rope {.codegen.} =
  result = Rope()
  let ind = repeat("  ", indent)
  case node.kind
  of nkVar, nkLet, nkConst:
    result.add(gen.writeVar(node, indent))
  of nkProc:
    let fnName = node[0].render
    let params = node[2]
    result.add(ind & "def " & fnName & "(")
    result.add(params[1..^1].mapIt(it[0].render).join(", "))
    result.add(")\n")
    result.add(ind & "  # " & fnName & " function\n")
    for param in params[1..^1]:
      if param.kind == nkIdentDefs:
        let pname = param[0].render
        result.add(ind & "  # @param " & pname & "\n")
    result.add(gen.genStmt(node[3], indent + 1))
    result.add(ind & "end\n")
  of nkMacro:
    let fnName = node[0].ident[1..^1]
    let params = node[2]
    result.add(ind & "def " & fnName & "(")
    result.add(params[1..^1].mapIt(it[0].render).join(", "))
    result.add(")\n")
    result.add(ind & "  # " & fnName & " macro\n")
    for param in params[1..^1]:
      if param.kind == nkIdentDefs:
        let pname = param[0].render
        result.add(ind & "  # @param " & pname & "\n")
    result.add(ind & "  # @return [String] HTML\n")
    result.add(ind & "  html = ''\n")
    result.add(gen.genStmt(node[3], indent + 1))
    result.add(ind & "  html\n")
    result.add(ind & "end\n")
  of nkHtmlElement:
    result.add(gen.writeHtml(node, indent))
  of nkIf:
    result.add(ind & "if " & exprToString(node[0]) & "\n")
    result.add(gen.genStmt(node[1], indent + 1))
    let hasElse = node.children.len mod 2 == 1
    let elifBranches = if hasElse: node[2..^2] else: node[2..^1]
    for i in countup(0, elifBranches.len - 1, 2):
      result.add(ind & "elsif " & exprToString(elifBranches[i]) & "\n")
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
      result.add(ind & "(" & startVal & ".." & endVal & ").each do |" & varName & "|\n")
      result.add(gen.genStmt(node[2], indent + 1))
      result.add(ind & "end\n")
    else:
      let iterExpr = exprToString(iterable)
      result.add(ind & iterExpr & ".each do |" & varName & "|\n")
      result.add(gen.genStmt(node[2], indent + 1))
      result.add(ind & "end\n")
  of nkWhile:
    result.add(ind & "while " & exprToString(node[0]) & "\n")
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
    result.add(ind & "next\n")
  of nkCall:
    let callee = if node[0].kind == nkIdent: node[0].ident else: exprToString(node[0])
    if callee == "echo":
      result.add(ind & "puts " & node[1..^1].filterIt(it.kind != nkHtmlAttribute).mapIt(exprToString(it)).join(", ") & "\n")
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
    result.add(ind & "html << \"" & rubyEscapeStr(node.rawHtml) & "\"\n")
  of nkCssSnippet:
    let css = node.snippetCode
    result.add(ind & "html << \"<style>\"\n")
    result.add(ind & "html << \"" & rubyEscapeStr(css) & "\"\n")
    result.add(ind & "html << \"</style>\"\n")
  of nkJavaScriptSnippet:
    let js = node.snippetCode
    result.add(ind & "html << \"<script>\"\n")
    result.add(ind & js & "\n")
    result.add(ind & "html << \"</script>\"\n")
  of nkDocComment:
    if node.comment.len > 0:
      result.add(ind & "# " & node.comment & "\n")
  else: discard

proc genScript*(program: Ast, includePath: Option[string],
            isMainScript: static bool = false,
            isSnippet: static bool = false) {.codegen.} =
  let modName = gen.module.getModuleName()
  result.add("class $1\n" % [modName])
  result.add("  # @param locals [Hash] Local data\n")
  result.add("  # @param app [Hash] Global data\n")
  result.add("  # @return [String] The generated HTML.\n")
  result.add("  def self.render(locals = {}, app = {})\n")
  result.add("    html = +\"\"\n")
  for node in program.nodes:
    result.add(gen.genStmt(node, 2))
  result.add("    html\n")
  result.add("  end\nend\n")
