# A super fast template engine for cool kids
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim | https://openpeeps.dev/packages/tim

include ./private

#
# Forward declarations
#
proc genStmt(node: Node, indent: int = 0): Rope {.codegen.}

proc error*(node: Node, msg: string) =
  raise (ref CodeGenError)(
          ln: node.ln,
          col: node.col,
          msg: ErrorFmt % ["", $node.ln, $node.col, msg]
        )

#
# Nim Transpiler
#

proc nimEscapeStr(s: string): string =
  result = newStringOfCap(s.len)
  for c in s:
    case c
    of '\n': result.add("\\n")
    of '\r': result.add("\\r")
    of '\t': result.add("\\t")
    of '\\': result.add("\\\\")
    of '"':  result.add("\\\"")
    else:    result.add(c)

const nimRuntimeHelpers* = """
when not declared(timShow):
  proc timShow*(s: string): string = s
  proc timShow*(i: int): string = $i
  proc timShow*(f: float): string = $f
  proc timShow*(b: bool): string = $b
  proc timShow*(j: JsonNode): string =
    if j == nil: ""
    elif j.kind == JString: j.getStr()
    elif j.kind == JNull: ""
    else: $j
  proc timShow*[T](s: openArray[T]): string =
    # native arrays render as empty output, mirroring the VM
    # (JsonNode arrays render as JSON via the overload above)
    ""
  proc timBool*(b: bool): bool = b
  proc timBool*(s: string): bool = s == "true"
  proc timBool*(i: int): bool = i != 0
  proc timBool*(f: float): bool = f != 0.0
  proc timBool*(j: JsonNode): bool =
    if j == nil: false
    else:
      case j.kind
      of JBool: j.getBool()
      of JNull: false
      else: true
  proc timInt*(j: JsonNode): int =
    case j.kind
    of JInt: j.getInt()
    of JFloat: int(j.getFloat())
    of JString:
      try: parseInt(j.getStr())
      except: 0
    of JBool: ord(j.getBool())
    else: 0
  proc timFloat*(j: JsonNode): float =
    case j.kind
    of JFloat: j.getFloat()
    of JInt: float(j.getInt())
    of JString:
      try: parseFloat(j.getStr())
      except: 0.0
    of JBool: float(ord(j.getBool()))
    else: 0.0
  proc timDiv(a, b: int): int = a div b
  proc timDiv(a, b: float): float = a / b
  proc timDiv(a: int, b: float): float = float(a) / b
  proc timDiv(a: float, b: int): float = a / float(b)
  proc timDiv(a, b: JsonNode): JsonNode =
    if a.kind == JInt and b.kind == JInt: %(a.getInt() div b.getInt())
    else: %(timFloat(a) / timFloat(b))
  proc timDiv(a: JsonNode, b: int): JsonNode =
    if a.kind == JInt: %(a.getInt() div b) else: %(timFloat(a) / float(b))
  proc timDiv(a: JsonNode, b: float): JsonNode = %(timFloat(a) / b)
  proc timDiv(a: int, b: JsonNode): JsonNode =
    if b.kind == JInt: %(a div b.getInt()) else: %(float(a) / timFloat(b))
  proc timDiv(a: float, b: JsonNode): JsonNode = %(a / timFloat(b))
  proc timEq[T](a, b: T): bool = a == b
  proc timEq*(a: JsonNode, b: string|int|float|bool): bool = a == %b
  proc timEq*(a: string|int|float|bool, b: JsonNode): bool = %a == b
  template timNe*(a, b): bool = not timEq(a, b)
  proc timLt[T](a, b: T): bool =
    when T is bool: ord(a) < ord(b)
    else: a < b
  proc timLt*(a: JsonNode, b: string|int|float|bool): bool =
    when b is string: timShow(a) < b
    elif b is int: timInt(a) < b
    elif b is float: timFloat(a) < b
    else: ord(timBool(a)) < ord(b)
  proc timLt*(a: string|int|float|bool, b: JsonNode): bool =
    when a is string: a < timShow(b)
    elif a is int: a < timInt(b)
    elif a is float: a < timFloat(b)
    else: ord(a) < ord(timBool(b))
  proc timLe[T](a, b: T): bool =
    when T is bool: ord(a) <= ord(b)
    else: a <= b
  proc timLe*(a: JsonNode, b: string|int|float|bool): bool =
    when b is string: timShow(a) <= b
    elif b is int: timInt(a) <= b
    elif b is float: timFloat(a) <= b
    else: ord(timBool(a)) <= ord(b)
  proc timLe*(a: string|int|float|bool, b: JsonNode): bool =
    when a is string: a <= timShow(b)
    elif a is int: a <= timInt(b)
    elif a is float: a <= timFloat(b)
    else: ord(a) <= ord(timBool(b))
  proc timGt[T](a, b: T): bool =
    when T is bool: ord(a) > ord(b)
    else: a > b
  proc timGt*(a: JsonNode, b: string|int|float|bool): bool =
    when b is string: timShow(a) > b
    elif b is int: timInt(a) > b
    elif b is float: timFloat(a) > b
    else: ord(timBool(a)) > ord(b)
  proc timGt*(a: string|int|float|bool, b: JsonNode): bool =
    when a is string: a > timShow(b)
    elif a is int: a > timInt(b)
    elif a is float: a > timFloat(b)
    else: ord(a) > ord(timBool(b))
  proc timGe[T](a, b: T): bool =
    when T is bool: ord(a) >= ord(b)
    else: a >= b
  proc timGe*(a: JsonNode, b: string|int|float|bool): bool =
    when b is string: timShow(a) >= b
    elif b is int: timInt(a) >= b
    elif b is float: timFloat(a) >= b
    else: ord(timBool(a)) >= ord(b)
  proc timGe*(a: string|int|float|bool, b: JsonNode): bool =
    when a is string: a >= timShow(b)
    elif a is int: a >= timInt(b)
    elif a is float: a >= timFloat(b)
    else: ord(a) >= ord(timBool(b))
  proc timSeq[T](s: openArray[T]): seq[T] = @s
  proc timSeq*(j: JsonNode): seq[JsonNode] =
    if j != nil and j.kind == JArray: j.elems else: @[]
  proc timPairs[T](s: openArray[T]): auto = toSeq(pairs(s))
  proc timPairs*(j: JsonNode): seq[(string, JsonNode)] =
    if j != nil and j.kind == JObject: toSeq(pairs(j)) else: @[]
  converter timJsonToStr*(j: JsonNode): string = timShow(j)
  converter timJsonToInt*(j: JsonNode): int = timInt(j)
  converter timJsonToFloat*(j: JsonNode): float = timFloat(j)
  converter timJsonToBool*(j: JsonNode): bool = timBool(j)
  converter timStrToJson*(s: string): JsonNode = %s
"""

proc jsDocifyNim*(js: string): string =
  ## Same transform the VM applies to `@javascript` snippets: turn
  ## Tim-style typed JS vars (`var x: int = 5`) into JSDoc-annotated JS.
  ## (Mirrors the `jsDocify` copies in `jsgen` and `transformers`.)
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

proc nimIdent*(s: string): string =
  ## Map Tim's magic data idents onto the generated proc params
  ## (`locals`/`app: JsonNode`). `$this` lexes as ident `this`.
  if s == "this": "locals"
  else: s

proc objToNim(node: Node): string
proc exprToString(node: Node): string

proc getImplValue(node: Node): string =
  case node.kind
  of nkInt:     $node.intVal
  of nkFloat:   $node.floatVal
  of nkString:  "\"" & nimEscapeStr(node.stringVal) & "\""
  of nkBool:
    if node.boolVal: "true" else: "false"
  of nkNil: "\"\"" # nil renders as empty output, mirroring the VM
  of nkArray:
    "[" & node.children.mapIt(getImplValue(it)).join(", ") & "]"
  of nkObjectStorage:
    objToNim(node)
  else:
    # calls, idents, infix/prefix and other computed values
    # (e.g. `var payload = parseJson(...)`) render as expressions
    exprToString(node)

proc objToNim(node: Node): string =
  ## Render a `{key: value}` object literal as a JsonNode `%*` constructor.
  ## Children are `nkColon(key, value)` nodes (see the validator).
  result = "%*{"
  var first = true
  for child in node.children:
    if child.kind != nkColon or child.len < 2: continue
    let keyStr = case child[0].kind
      of nkIdent: "\"" & child[0].ident & "\""
      of nkString: "\"" & nimEscapeStr(child[0].stringVal) & "\""
      else: exprToString(child[0])
    if not first: result.add(", ")
    first = false
    result.add(keyStr & ": " & exprToString(child[1]))
  result.add("}")

proc writeVar(node: Node, indent: int = 0): string {.codegen.} =
  let ind = repeat(" ", indent)
  let kw = case node.kind
    of nkVar: "var"
    of nkLet: "let"
    of nkConst: "const"
    else: ""
  for child in node:
    if child.kind == nkIdentDefs:
      for decl in child:
        if decl.kind == nkAssign and decl[0].kind == nkIdent:
          let name = nimIdent(decl[0].ident)
          let tyNode = if decl.len > 1: decl[1] else: ast.newNode(nkEmpty)
          let valNode = if decl.len > 2: decl[2] else: ast.newNode(nkEmpty)
          if valNode.kind == nkEmpty:
            # declared without a value: keep the type when present,
            # otherwise default to an empty string
            if tyNode.kind != nkEmpty:
              result.add(ind & kw & " " & name & ": " & tyNode.render & "\n")
            else:
              result.add(ind & kw & " " & name & " = \"\"\n")
          else:
            let v = getImplValue(valNode)
            if v.len > 0:
              if tyNode.kind != nkEmpty:
                result.add(ind & kw & " " & name & ": " & tyNode.render & " = " & v & "\n")
              else:
                result.add(ind & kw & " " & name & " = " & v & "\n")
            else:
              # exotic initializer with no Nim representation; keep the
              # declared type (or string) so the file still compiles
              if tyNode.kind != nkEmpty:
                result.add(ind & "# unsupported initializer for " & name & "\n")
                result.add(ind & kw & " " & name & ": " & tyNode.render & "\n")
              else:
                result.add(ind & "# unsupported initializer for " & name & "\n")
                result.add(ind & kw & " " & name & " = \"\"\n")

proc exprToString(node: Node): string =
  case node.kind
  of nkString: "\"" & nimEscapeStr(node.stringVal) & "\""
  of nkInt: $node.intVal
  of nkFloat: $node.floatVal
  of nkBool:
    if node.boolVal: "true" else: "false"
  of nkNil: "\"\""
  of nkIdent: nimIdent(node.ident)
  of nkArray:
    "[" & node.children.mapIt(exprToString(it)).join(", ") & "]"
  of nkObjectStorage:
    objToNim(node)
  of nkPrefix:
    let op = if node[0].kind == nkIdent: node[0].ident else: node[0].render
    if op == "$":
      "timShow(" & exprToString(node[1]) & ")"
    else:
      op & exprToString(node[1])
  of nkPostfix:
    let op = if node[1].kind == nkIdent: node[1].ident else: node[1].render
    exprToString(node[0]) & op
  of nkInfix:
    let op = if node[0].kind == nkIdent: node[0].ident else: node[0].render
    case op
    of "&":
      # string concat; timShow keeps strings as-is and unquotes JSON
      "(timShow(" & exprToString(node[1]) & ") & timShow(" & exprToString(node[2]) & "))"
    of "==": "timEq(" & exprToString(node[1]) & ", " & exprToString(node[2]) & ")"
    of "!=": "timNe(" & exprToString(node[1]) & ", " & exprToString(node[2]) & ")"
    of "<": "timLt(" & exprToString(node[1]) & ", " & exprToString(node[2]) & ")"
    of "<=": "timLe(" & exprToString(node[1]) & ", " & exprToString(node[2]) & ")"
    of ">": "timGt(" & exprToString(node[1]) & ", " & exprToString(node[2]) & ")"
    of ">=": "timGe(" & exprToString(node[1]) & ", " & exprToString(node[2]) & ")"
    of "and", "&&":
      "(timBool(" & exprToString(node[1]) & ") and timBool(" & exprToString(node[2]) & "))"
    of "or", "||":
      "(timBool(" & exprToString(node[1]) & ") or timBool(" & exprToString(node[2]) & "))"
    of "/":
      # the VM divides ints with integer division (`div`)
      "timDiv(" & exprToString(node[1]) & ", " & exprToString(node[2]) & ")"
    else:
      "(" & exprToString(node[1]) & " " & op & " " & exprToString(node[2]) & ")"
  of nkCall:
    var callee = if node[0].kind == nkIdent: node[0].ident else: exprToString(node[0])
    if callee.startsWith("@"):
      callee = callee[1..^1]
    var args: seq[string] = @[]
    for i in 1 ..< node.len:
      let a = node[i]
      if a.kind == nkHtmlAttribute:
        continue # caller HTML attrs are VM-only; transpilers ignore them
      if a.kind == nkBlock:
        continue # trailing macro body is handled at statement level
      elif a.kind == nkColon and a.len >= 2:
        # named argument `name=value`
        let nm = if a[0].kind == nkIdent: nimIdent(a[0].ident) else: exprToString(a[0])
        args.add(nm & "=" & exprToString(a[1]))
      else:
        args.add(exprToString(a))
    callee & "(" & args.join(", ") & ")"
  of nkBracket:
    exprToString(node[0]) & "[" & exprToString(node[1]) & "]"
  of nkDot:
    exprToString(node[0]) & "." & exprToString(node[1])
  else:
    ""

proc attrsToNim(node: Node): (seq[string], string, seq[(string, string)]) =
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
          classNames.add("\" & timShow(" & nimIdent(attr.attrNode.ident) & ") & \"")
        of nkInfix, nkCall:
          classNames.add("\" & timShow(" & exprToString(attr.attrNode) & ") & \"")
        else: discard
      of htmlAttrId:
        case attr.attrNode.kind
        of nkString:
          idVal = attr.attrNode.stringVal
        of nkIdent:
          idVal = "\" & timShow(" & nimIdent(attr.attrNode.ident) & ") & \""
        of nkInfix, nkCall:
          idVal = "\" & timShow(" & exprToString(attr.attrNode) & ") & \""
        else: discard
      of htmlAttr:
        if attr.attrNode.kind == nkInfix and attr.attrNode.len >= 3:
          let keyNode = attr.attrNode[1]
          let valNode = attr.attrNode[2]
          let key = if keyNode.kind == nkIdent: keyNode.ident
                    elif keyNode.kind == nkString: keyNode.stringVal
                    else: $keyNode.render
          let valStr = case valNode.kind
            of nkString: nimEscapeStr(valNode.stringVal)
            of nkInt, nkFloat, nkBool: $valNode.render
            of nkIdent: "\" & timShow(" & nimIdent(valNode.ident) & ") & \""
            else: "\" & timShow(" & exprToString(valNode) & ") & \""
          customAttrs.add((key, valStr))
        elif attr.attrNode.kind == nkString:
          customAttrs.add((attr.attrNode.stringVal, ""))
        elif attr.attrNode.kind == nkIdent:
          customAttrs.add((attr.attrNode.ident, ""))
        else: discard
      else: discard
  (classNames, idVal, customAttrs)

proc bodyProcDecl(gen: var CodeGen, body: Node, indent: int): tuple[name, decl: string] =
  ## Render a trailing macro block (`@col(6): ...`) as a nested proc
  ## returning its HTML. `body` is the `nkBlock` appended by the parser.
  ## Statements inside append to the nested proc's own `result`, so the
  ## call site passes `name()` as the macro's `body` argument.
  let name = "timBody" & $gen.counter
  inc(gen.counter)
  var decl = repeat(" ", indent) & "proc " & name & "(): string =\n"
  decl.add(repeat(" ", indent + 2) & "result = \"\"\n")
  decl.add($gen.genStmt(body, indent + 2))
  (name, decl)

proc macroCallArgs(node: Node): tuple[callee: string, args: seq[string], body: Node] =
  ## Split a macro call node into callee (without `@`), positional/named
  ## args and an optional trailing `nkBlock` body.
  var callee = if node[0].kind == nkIdent: node[0].ident else: exprToString(node[0])
  if callee.startsWith("@"):
    callee = callee[1..^1]
  var args: seq[string] = @[]
  result.body = nil
  for i in 1 ..< node.len:
    let a = node[i]
    if a.kind == nkHtmlAttribute:
      continue # caller HTML attrs are VM-only; transpilers ignore them
    if a.kind == nkBlock:
      result.body = a
    elif a.kind == nkColon and a.len >= 2:
      let nm = if a[0].kind == nkIdent: nimIdent(a[0].ident) else: exprToString(a[0])
      args.add(nm & "=" & exprToString(a[1]))
    else:
      args.add(exprToString(a))
  result.callee = callee
  result.args = args

proc writeHtml(node: Node, indent: int = 0) {.codegen.} =
  let tag = node.getTag()
  let (classNames, idVal, customAttrs) = attrsToNim(node)
  let ind = repeat(" ", indent)

  result.add(ind & "add result, \"<" & tag)

  # Attribute order mirrors the VM: id and custom attributes first
  # (in source order), merged classes last.
  if idVal.len > 0:
    result.add(" id=\\\"" & idVal & "\\\"")

  for (key, value) in customAttrs:
    if value.len > 0:
      result.add(" " & key & "=\\\"" & value & "\\\"")
    else:
      result.add(" " & key)

  if classNames.len > 0:
    result.add(" class=\\\"" & classNames.join(" ") & "\\\"")
  result.add(">\"\n")

  for child in node.childElements:
    case child.kind
    of nkString:
      result.add(ind & "add result, \"" & nimEscapeStr(child.stringVal) & "\"\n")
    of nkNil:
      result.add(ind & "add result, \"\"\n")
    of nkBool, nkInt, nkFloat:
      result.add(ind & "add result, timShow(" & $child.render & ")\n")
    of nkIdent:
      result.add(ind & "add result, timShow(" & nimIdent(child.ident) & ")\n")
    of nkCall:
      let (callee, args, body) = macroCallArgs(child)
      if callee == "statement":
        # trailing-block placeholder inside a macro body
        result.add(ind & "add result, body\n")
      elif body != nil:
        let (bname, decl) = bodyProcDecl(gen, body, indent)
        result.add(decl)
        if args.len > 0:
          result.add(ind & "add result, timShow(" & callee & "(" & args.join(", ") & ", " & bname & "()))\n")
        else:
          result.add(ind & "add result, timShow(" & callee & "(" & bname & "()))\n")
      else:
        result.add(ind & "add result, timShow(" & callee & "(" & args.join(", ") & "))\n")
    of nkInfix, nkPrefix, nkPostfix, nkBracket, nkDot:
      result.add(ind & "add result, timShow(" & exprToString(child) & ")\n")
    else:
      result.add(gen.genStmt(child, indent))

  if node.tag notin voidHtmlElements:
    result.add(ind & "add result, \"</" & tag & ">\"\n")

proc formalParamsToNim(params: Node): string =
  ## Render `nkFormalParams` as a Nim parameter list. Untyped parameters
  ## default to `string`; JSON values convert implicitly via the
  ## `timJsonTo*` converters in the runtime preamble.
  var parts: seq[string] = @[]
  if params != nil and params.kind == nkFormalParams:
    for i in 1 ..< params.len:
      let pdef = params[i]
      if pdef.kind != nkIdentDefs: continue
      if pdef.len < 3: continue
      let tyNode = pdef[^2]
      let hasDefault = pdef[^1].kind != nkEmpty
      let tyStr =
        if tyNode.kind != nkEmpty: tyNode.render
        elif hasDefault: ""
        else: "string"
      for j in 0 ..< pdef.len - 2:
        let nm = pdef[j]
        if nm.kind != nkIdent: continue
        if tyStr.len > 0:
          parts.add(nimIdent(nm.ident) & ": " & tyStr)
        else:
          parts.add(nimIdent(nm.ident))
      if hasDefault and tyStr.len == 0 and parts.len > 0:
        # `name = default`: Nim infers the type from the default value
        parts[^1] = parts[^1] & " = " & exprToString(pdef[^1])
  parts.join(", ")

proc genStmt(node: Node, indent: int = 0): Rope {.codegen.} =
  result = rope()
  let ind = repeat(" ", indent)
  case node.kind
  of nkHtmlElement:
    result.add(gen.writeHtml(node, indent))
  of nkVar, nkLet, nkConst:
    result.add(gen.writeVar(node, indent))
  of nkProc:
    let fnName = node[0].render
    result.add(ind & "proc " & fnName & "(" & formalParamsToNim(node[2]) & ")")
    if node[2].kind == nkFormalParams and node[2].len > 0 and node[2][0].kind != nkEmpty:
      result.add(": " & node[2][0].render)
    else:
      result.add(": void")
    result.add(" =\n")
    result.add(gen.genStmt(node[3], indent + 2))
  of nkMacro:
    let fnName = node[0].ident[1..^1]
    let params = formalParamsToNim(node[2])
    result.add(ind & "proc " & fnName & "(" & params)
    if params.len > 0: result.add(", ")
    result.add("body: string = \"\"")
    result.add("): string =\n")
    result.add(ind & "  result = \"\"\n")
    result.add(gen.genStmt(node[3], indent + 2))
  of nkIf:
    result.add(ind & "if timBool(" & exprToString(node[0]) & "):\n")
    result.add(gen.genStmt(node[1], indent + 2))
    let hasElse = node.children.len mod 2 == 1
    let elifBranches = if hasElse: node[2..^2] else: node[2..^1]
    for i in countup(0, elifBranches.len - 1, 2):
      result.add(ind & "elif timBool(" & exprToString(elifBranches[i]) & "):\n")
      result.add(gen.genStmt(elifBranches[i + 1], indent + 2))
    if hasElse:
      result.add(ind & "else:\n")
      result.add(gen.genStmt(node[^1], indent + 2))
  of nkFor:
    let varNode = node[0]
    let iterable = node[1]
    if iterable.kind == nkCall and iterable[0].kind == nkIdent and iterable[0].ident == "..":
      let varName = if varNode.kind == nkIdent: nimIdent(varNode.ident) else: varNode.render
      let startVal = exprToString(iterable[1])
      let endVal = exprToString(iterable[2])
      result.add(ind & "for " & varName & " in " & startVal & " .. " & endVal & ":\n")
      result.add(gen.genStmt(node[2], indent + 2))
    elif varNode.kind == nkBracket and varNode.len >= 2:
      # key, value form: `for $k, $v in $obj`. Parenthesised loop
      # vars are required: without them Nim binds (index, item).
      let k = if varNode[0].kind == nkIdent: nimIdent(varNode[0].ident) else: varNode[0].render
      let v = if varNode[1].kind == nkIdent: nimIdent(varNode[1].ident) else: varNode[1].render
      result.add(ind & "for (" & k & ", " & v & ") in timPairs(" & exprToString(iterable) & "):\n")
      result.add(gen.genStmt(node[2], indent + 2))
    else:
      let varName = if varNode.kind == nkIdent: nimIdent(varNode.ident) else: varNode.render
      result.add(ind & "for " & varName & " in timSeq(" & exprToString(iterable) & "):\n")
      result.add(gen.genStmt(node[2], indent + 2))
  of nkWhile:
    result.add(ind & "while timBool(" & exprToString(node[0]) & "):\n")
    result.add(gen.genStmt(node[1], indent + 2))
  of nkBlock:
    for s in node:
      result.add(gen.genStmt(s, indent))
  of nkStatic:
    # `static for` / `static if` are expanded at parse time; the
    # children are plain nodes that render like any other block
    for s in node:
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
  of nkDiscard:
    if node.len > 0 and node[0].kind != nkEmpty:
      result.add(ind & "discard " & exprToString(node[0]) & "\n")
    else:
      result.add(ind & "discard\n")
  of nkCall:
    let rawCallee = if node[0].kind == nkIdent: node[0].ident else: exprToString(node[0])
    if rawCallee == "@statement":
      # trailing-block placeholder inside a macro body
      result.add(ind & "add result, body\n")
    elif rawCallee == "@doc":
      var doc = ""
      for i in 1 ..< node.len:
        if node[i].kind == nkString:
          if doc.len > 0: doc.add(" ")
          doc.add(node[i].stringVal)
      if doc.len > 0:
        result.add(ind & "# " & doc.replace("\n", "\n" & ind & "# ") & "\n")
    elif rawCallee.startsWith("@") or (node.len > 1 and node[^1].kind == nkBlock):
      # macro invocation: its return value is HTML, append it
      let (callee, args, body) = macroCallArgs(node)
      var call = callee & "("
      if args.len > 0: call.add(args.join(", "))
      if body != nil:
        let (bname, decl) = bodyProcDecl(gen, body, indent)
        result.add(decl)
        if args.len > 0: call.add(", ")
        call.add(bname & "()")
      call.add(")")
      result.add(ind & "add result, " & call & "\n")
    else:
      let callee = rawCallee
      if callee == "echo":
        result.add(ind & "echo " & node[1..^1].filterIt(it.kind != nkHtmlAttribute).mapIt(exprToString(it)).join(", ") & "\n")
      else:
        result.add(ind & callee & "(" & node[1..^1].filterIt(it.kind != nkHtmlAttribute).mapIt(exprToString(it)).join(", ") & ")\n")
  of nkAssign:
    let lhs = if node[0].kind == nkIdent: nimIdent(node[0].ident) elif node[0].kind == nkPrefix and node[0][1].kind == nkIdent: nimIdent(node[0][1].ident) else: exprToString(node[0])
    result.add(ind & lhs & " = " & exprToString(node[1]) & "\n")
  of nkInfix, nkPrefix, nkPostfix:
    let op = if node.kind == nkInfix and node[0].kind == nkIdent: node[0].ident
             elif node.kind == nkInfix: node[0].render
             else: ""
    if op == "=":
      result.add(ind & exprToString(node[1]) & " = " & exprToString(node[2]) & "\n")
    else:
      result.add(ind & exprToString(node) & "\n")
  of nkIdent:
    result.add(ind & "timShow(" & nimIdent(node.ident) & ")\n")
  of nkRawHtml:
    result.add(ind & "add result, \"" & nimEscapeStr(node.rawHtml) & "\"\n")
  of nkCssSnippet:
    let css = node.snippetCode
    result.add(ind & "add result, \"<style>\"\n")
    result.add(ind & "add result, \"" & nimEscapeStr(css) & "\"\n")
    result.add(ind & "add result, \"</style>\"\n")
  of nkJavaScriptSnippet:
    let js = jsDocifyNim(node.snippetCode)
    result.add(ind & "add result, \"<script>\"\n")
    result.add(ind & "add result, \"" & nimEscapeStr(js) & "\"\n")
    result.add(ind & "add result, \"</script>\"\n")
  of nkDocComment:
    if node.comment.len > 0:
      result.add(ind & "# " & node.comment.replace("\n", "\n" & ind & "# ") & "\n")
  of nkImport:
    # `@import "std/..."` only pulls VM stdlib modules; the static
    # backend links what's needed directly, so imports are no-ops here
    result.add(ind & "# import: " & node.children.mapIt(if it.kind == nkString: it.stringVal else: it.render).join(", ") & "\n")
  of nkInclude:
    node.error("@include is not supported by the Nim backend yet: pre-resolve partials before transpiling")
  of nkClientBlock:
    # client-only content is handled by the SPA runtime, like the VM
    # which emits no HTML for it either
    discard
  of nkCustomElement:
    node.error("@LitElement is not supported by the Nim backend yet")
  of nkViewLoader:
    # `@view` is composed by the caller (view + layout procs)
    discard
  of nkTest:
    # test blocks run under the VM test runner, not in static output
    discard
  else: discard

proc genScript*(program: Ast, includePath: Option[string],
            isMainScript: static bool = false,
            isSnippet: static bool = false,
            isView: static bool = true) {.codegen.} =
  let modName = gen.module.getModuleName()
  result.add("import std/[json, sequtils, strutils]\n")
  result.add(nimRuntimeHelpers)
  result.add("\n")
  when isView == true:
    result.add("proc get$1View*(locals, app: JsonNode = newJObject()): string =\n" % modName)
  else:
    result.add("proc get$1Layout*(locals, app: JsonNode = newJObject()): string =\n" % modName)
  result.add("  var result = \"\"\n")
  for node in program.nodes:
    result.add(gen.genStmt(node, 2))
  result.add("  move(result)")
