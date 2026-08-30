import std/[os, strutils]
import ./test_state

import pkg/openparser/html/ast as htmlAst
template HtmlTag*: untyped = htmlAst.HtmlTag
template getHtmlTag*(a: string): untyped = htmlAst.getHtmlTag(a)
import pkg/voodoo/extensibles

# Extend vancode AST and CodeGen to support
# HTML elements and other Tim Engine specific nodes
block extendvancodeAstAndCodeGen:

  extendEnum NodeKind:
    # Extend `NodeKind` enum to support HTML
    # elements and attributes in the AST
    nkRawHtml
    nkHtmlElement
    nkHtmlAttribute
    nkJavaScriptSnippet
    nkCssSnippet
    nkViewLoader     # view loader using `@view` placeholder\
    nkClientBlock    # client block using `@client ... @end`
    nkCustomElement  # custom element using @LitElement, ClassName
    nkMacro          # a block - {...}
    nkTest           # test block using `@test "label":`

  extendObject do:
    type Ast = ref object        # required by `extendCase`
      forwardDecl*: seq[Node]

  extendCase do:
    # Extend the Node variant to support HTML elements
    # attributes and JavaScript snippets
    type Node = ref object        # required by `extendCase`
      case kind: NodeKind
      # the branches we add to the Node variant
      of nkHtmlElement:
        tag*: HtmlTag
        tagCustom*: string
        attributes*: seq[Node]
        childElements*: seq[Node]
      of nkHtmlAttribute:
        attrType*: HtmlAttributeType
        attrNode*: Node
      of nkJavaScriptSnippet, nkCssSnippet:
        snippetCode*: string
        snippetCodeAttrs*: seq[(string, Node)]
      of nkRawHtml:
        rawHtml*: string
      of nkTest:
        testLabel*: string
        testBody*: Node

  # Extend the case statement by adding new branches
  # for code generation of the new node kinds we added to the AST
  #
  # Note that `case node.kind` is already defined in the original
  # `genStmt` procedure, the `extendCaseStmt` macro just allows us
  # to add new branches to it
  extendCaseStmt "codeGenStmt":
    case node.kind:
    of nkHtmlElement:
      # HTML element construction
      discard gen.htmlConstr(node)
    of nkJavaScriptSnippet:
      # JavaScript snippet construction
      let tag = "script"
      let tagPos = gen.chunk.getString(tag)
      gen.chunk.emit(opcBeginHtml)
      gen.chunk.emit(tagPos)
      discard gen.pushConst(ast.newStringLit(jsDocify(node.snippetCode)))
      gen.chunk.emit(opcTextHtml)
      gen.chunk.emit(opcCloseHtml)
      gen.chunk.emit(tagPos)
    of nkCssSnippet:
      # CSS snippet construction
      let tag = "style"
      let tagPos = gen.chunk.getString(tag)
      gen.chunk.emit(opcBeginHtml)
      gen.chunk.emit(tagPos)
      discard gen.pushConst(ast.newStringLit(node.snippetCode))
      gen.chunk.emit(opcTextHtml)
      gen.chunk.emit(opcCloseHtml)
      gen.chunk.emit(tagPos)
    of nkMacro: discard gen.genMacro(node)
    of nkViewLoader: gen.chunk.emit(opcViewLoader)
    of nkRawHtml:
      # inject raw HTML directly into the output without any escaping
      # or processing; this is used for the `@html` snippet
      discard gen.pushConst(ast.newStringLit(node.rawHtml))
      gen.chunk.emit(opcRawHtml)
    of nkClientBlock:
      # gen.chunk.emit(opcClientBlock)
      # var jst = jsgen.initCodeGen(gen.script, gen.module, gen.chunk)
      # let jsSnippet: Rope = jsgen.genScript(jst, node[0].children)
      # gen.chunk.emit(opcClientBlockEnd)
      discard
    of nkTest:
      discard gen.genTest(node)
    of nkCustomElement:
      let className = node[0].ident
      let tagName = node[1].stringVal
      let classJsBody = node[2]
      let renderBody = node[3]
      # Extract var declarations and constructor code from @javascript blocks
      var staticProps: seq[string]
      var constructorLines: seq[string]
      for child in classJsBody.children:
        if child.kind == nkJavaScriptSnippet:
          let js = jsDocify(child.snippetCode)
          let lines = js.split('\n')
          var i = 0
          while i < lines.len:
            let line = lines[i]
            let trimmed = line.strip()
            if trimmed.startsWith("/** @type {"):
              let typeStart = trimmed.find("{") + 1
              let typeEnd = trimmed.find("}")
              var prevType = ""
              if typeStart > 0 and typeEnd > typeStart:
                prevType = trimmed[typeStart..<typeEnd]
              i += 1
              if i < lines.len:
                let nextLine = lines[i].strip()
                var kw: string
                if nextLine.startsWith("var "): kw = "var "
                elif nextLine.startsWith("let "): kw = "let "
                elif nextLine.startsWith("const "): kw = "const "
                if kw.len > 0:
                  let rest = nextLine[kw.len..^1]
                  let eqIdx = rest.find('=')
                  let varName = if eqIdx >= 0: rest[0..<eqIdx].strip else: rest.strip()
                  let value = if eqIdx >= 0: rest[eqIdx+1..^1].strip else: ""
                  if prevType.len > 0:
                    let litType = case prevType
                      of "number": "Number"
                      of "boolean": "Boolean"
                      of "string": "String"
                      else: prevType
                    staticProps.add("    " & varName & ": {type: " & litType & "}")
                  if value.len > 0:
                    constructorLines.add("    this." & varName & " = " & value & ";")
                else:
                  constructorLines.add("  " & lines[i])
            elif trimmed.startsWith("var ") or trimmed.startsWith("let ") or trimmed.startsWith("const "):
              var kw: string
              if trimmed.startsWith("var "): kw = "var "
              elif trimmed.startsWith("let "): kw = "let "
              else: kw = "const "
              let rest = trimmed[kw.len..^1]
              let eqIdx = rest.find('=')
              let varName = if eqIdx >= 0: rest[0..<eqIdx].strip else: rest.strip()
              let value = if eqIdx >= 0: rest[eqIdx+1..^1].strip else: ""
              if value.len > 0:
                constructorLines.add("    this." & varName & " = " & value & ";")
            else:
              if trimmed.len > 0:
                constructorLines.add("  " & line)
            i += 1
      var jsCode = "class " & className & " extends LitElement {\n"
      if staticProps.len > 0:
        jsCode &= "  static properties = {\n"
        for p in staticProps:
          jsCode &= p & ",\n"
        jsCode &= "  };\n"
      jsCode &= "  constructor() {\n"
      jsCode &= "    super();\n"
      for cl in constructorLines:
        jsCode &= cl & "\n"
      jsCode &= "  }\n"
      jsCode &= "  render() {\n"
      if renderBody.kind == nkClientBlock:
        jsCode &= "    return html`\n"
        for child in renderBody[0].children:
          jsCode &= genClientRender(child, 6, asTemplate = true)
        jsCode &= "\n    `;\n"
      else:
        jsCode &= "    return html``;\n"
      jsCode &= "  }\n"
      jsCode &= "}\n"
      jsCode &= "customElements.define('" & tagName & "', " & className & ");\n"
      let tag = "script"
      let tagPos = gen.chunk.getString(tag)
      gen.chunk.emit(opcBeginHtml)
      gen.chunk.emit(tagPos)
      discard gen.pushConst(ast.newStringLit(jsCode))
      gen.chunk.emit(opcTextHtml)
      gen.chunk.emit(opcCloseHtml)
      gen.chunk.emit(tagPos)

  # Extends the AST module with new node constructors and utilities
  # for HTML elements and macros

  extendCaseStmt "astHashCase":
    case node.kind
    of nkHtmlElement:
      h = h !& hash(node.tag)
      for attr in node.attributes:
        h = h !& hash(attr.attrType)
        h = h !& hash(attr.attrNode)
      for child in node.childElements:
        h = h !& hash(child)
    of nkTest:
      h = h !& hash(node.testLabel)
      h = h !& hash(node.testBody)
    of nkCustomElement:
      for child in node.children:
        h = h !& hash(child)
    of nkHtmlAttribute:
      h = h !& hash(node.attrType)
      if node.attrNode != nil:
        if node.attrNode.kind == nkInfix:
          # HTML key=value attributes use nkInfix with a nil operator
          # child[0] (the `=` is implied); skip nil children
          for child in node.attrNode.children:
            if child != nil: h = h !& hash(child)
        else:
          h = h !& hash(node.attrNode)

  extendModule "vancode" / "interpreter" / "ast.nim":
    const voidHtmlElements* = [tagArea, tagBase, tagBr, tagCol,
      tagEmbed, tagHr, tagImg, tagInput, tagLink, tagMeta,
      tagParam, tagSource, tagTrack, tagWbr]

    proc newMacro*(children: varargs[Node]): Node =
      ## Construct a new block.
      newNode(nkMacro)

    proc newHtmlAttribute*(attrType: static HtmlAttributeType, attrNode: Node): Node =
      ## Construct a new HTML attribute node.
      result = Node(
        kind: nkHtmlAttribute,
        attrType: attrType,
        attrNode: attrNode
      )

    proc `$`*(tag: HtmlTag): string =
      result = case tag
        of tagA: "a"
        of tagAbbr: "abbr"
        of tagAddress: "address"
        of tagArea: "area"
        of tagArticle: "article"
        of tagAside: "aside"
        of tagAudio: "audio"
        of tagB: "b"
        of tagBase: "base"
        of tagBdi: "bdi"
        of tagBdo: "bdo"
        of tagBlockquote: "blockquote"
        of tagBody: "body"
        of tagBr: "br"
        of tagButton: "button"
        of tagCanvas: "canvas"
        of tagCaption: "caption"
        of tagCite: "cite"
        of tagCode: "code"
        of tagCol: "col"
        of tagColgroup: "colgroup"
        of tagData: "data"
        of tagDatalist: "datalist"
        of tagDd: "dd"
        of tagDel: "del"
        of tagDetails: "details"
        of tagDfn: "dfn"
        of tagDialog: "dialog"
        of tagDiv: "div"
        of tagDl: "dl"
        of tagDt: "dt"
        of tagEm: "em"
        of tagEmbed: "embed"
        of tagFieldset: "fieldset"
        of tagFigcaption: "figcaption"
        of tagFigure: "figure"
        of tagFooter: "footer"
        of tagForm: "form"
        of tagH1: "h1"
        of tagH2: "h2"
        of tagH3: "h3"
        of tagH4: "h4"
        of tagH5: "h5"
        of tagH6: "h6"
        of tagHead: "head"
        of tagHeader: "header"
        of tagHtml: "html"
        of tagHr: "hr"
        of tagI: "i"
        of tagIframe: "iframe"
        of tagImg: "img"
        of tagInput: "input"
        of tagIns: "ins"
        of tagKbd: "kbd"
        of tagLabel: "label"
        of tagLegend: "legend"
        of tagLi: "li"
        of tagLink: "link"
        of tagMain: "main"
        of tagMap: "map"
        of tagMark: "mark"
        of tagMeta: "meta"
        of tagMeter: "meter"
        of tagNav: "nav"
        of tagNoscript: "noscript"
        of tagObject: "object"
        of tagOl: "ol"
        of tagOptgroup: "optgroup"
        of tagOption: "option"
        of tagOutput: "output"
        of tagP: "p"
        of tagParam: "param"
        of tagPicture: "picture"
        of tagPre: "pre"
        of tagProgress: "progress"
        of tagQ: "q"
        of tagRp: "rp"
        of tagRt: "rt"
        of tagRuby: "ruby"
        of tagS: "s"
        of tagSamp: "samp"
        of tagScript: "script"
        of tagSection: "section"
        of tagSelect: "select"
        of tagSmall: "small"
        of tagSource: "source"
        of tagSpan: "span"
        of tagStrong: "strong"
        of tagStyle: "style"
        of tagSub: "sub"
        of tagSummary: "summary"
        of tagSup: "sup"
        of tagTable: "table"
        of tagTbody: "tbody"
        of tagTd: "td"
        of tagTemplate: "template"
        of tagTextarea: "textarea"
        of tagTfoot: "tfoot"
        of tagTh: "th"
        of tagThead: "thead"
        of tagTime: "time"
        of tagTitle: "title"
        of tagTr: "tr"
        of tagTrack: "track"
        of tagU: "u"
        of tagUl: "ul"
        of tagVar: "var"
        of tagVideo: "video"
        of tagWbr: "wbr"
        of tagSlot: "slot"
        else: "" # non-standard HTML tag / custom tag
      
    proc newHtmlElement*(tag: HtmlTag, tagStr: string): Node =
      ## Construct a new HTML element node.
      case tag
      of tagUnknown:
        result = Node(kind: nkHtmlElement, tag: tagUnknown, tagCustom: tagStr)
      else:
        result = Node(kind: nkHtmlElement, tag: tag)

    proc getTag*(node: Node): string =
      # Retrieves the HTML tag name from an HTML element node
      case node.tag
      of tagUnknown:
        result = node.tagCustom
      else:
        result = $node.tag

  extendModule "vancode" / "interpreter" / "codegen.nim":

    proc jsDocify*(js: string): string =
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

    proc clientExpr(node: Node): string =
      case node.kind
      of nkString: "\"" & jsEscapeDQuote(node.stringVal) & "\""
      of nkInt: $node.intVal
      of nkFloat: $node.floatVal
      of nkBool: $node.boolVal
      of nkIdent: jsIdent(node.ident)
      of nkPrefix: jsOp(node[0].ident) & clientExpr(node[1])
      of nkPostfix: clientExpr(node[0]) & jsOp(node[1].ident)
      of nkInfix:
        let op = if node[0].kind == nkIdent: jsOp(node[0].ident) else: jsOp(node[0].render)
        "(" & clientExpr(node[1]) & " " & op & " " & clientExpr(node[2]) & ")"
      of nkCall:
        let callee = if node[0].kind == nkIdent: jsIdent(node[0].ident) else: clientExpr(node[0])
        callee & "(" & node[1..^1].mapIt(clientExpr(it)).join(", ") & ")"
      of nkBracket:
        clientExpr(node[0]) & "[" & clientExpr(node[1]) & "]"
      of nkDot:
        clientExpr(node[0]) & "." & clientExpr(node[1])
      else:
        node.render

    proc genClientRender(node: Node, indent: int, asTemplate: bool = false): string =
      let i = if asTemplate: "" else: repeat(' ', indent)
      let ni = if asTemplate: "" else: repeat(' ', indent + 2)
      if asTemplate:
        case node.kind
        of nkHtmlElement:
          let tag = node.getTag()
          result = "<" & tag
          for attr in node.attributes:
            if attr.kind == nkHtmlAttribute:
              case attr.attrType
              of htmlAttrClass:
                case attr.attrNode.kind
                of nkString:
                  result.add(" class=\"" & attr.attrNode.stringVal & "\"")
                of nkIdent:
                  result.add(" class=\"${" & jsIdent(attr.attrNode.ident) & "}\"")
                else:
                  result.add(" class=\"${" & clientExpr(attr.attrNode) & "}\"")
              of htmlAttrId:
                case attr.attrNode.kind
                of nkString:
                  result.add(" id=\"" & attr.attrNode.stringVal & "\"")
                else:
                  result.add(" id=\"${" & clientExpr(attr.attrNode) & "}\"")
              of htmlAttr:
                if attr.attrNode.kind == nkInfix and attr.attrNode.len >= 3:
                  let keyNode = attr.attrNode[1]
                  let valNode = attr.attrNode[2]
                  let key = if keyNode.kind == nkString: keyNode.stringVal
                            elif keyNode.kind == nkIdent: jsIdent(keyNode.ident)
                            else: clientExpr(keyNode)
                  let val = if valNode.kind == nkString: valNode.stringVal
                            else: "${" & clientExpr(valNode) & "}"
                  result.add(" " & key & "=\"" & val & "\"")
                elif attr.attrNode.kind == nkString:
                  result.add(" " & attr.attrNode.stringVal)
                elif attr.attrNode.kind == nkIdent:
                  result.add(" " & jsIdent(attr.attrNode.ident))
              else: discard
          result.add(">")
          for child in node.childElements:
            result.add(genClientRender(child, indent, asTemplate))
          if node.tag notin voidHtmlElements:
            result.add("</" & tag & ">")
        of nkString:
          result = jsEscapeStr(node.stringVal)
        of nkInt:
          result = "${" & $node.intVal & "}"
        of nkFloat:
          result = "${" & $node.floatVal & "}"
        of nkBool:
          result = "${" & $node.boolVal & "}"
        of nkIdent:
          result = "${" & jsIdent(node.ident) & "}"
        of nkBlock:
          for child in node.children:
            result.add(genClientRender(child, indent, asTemplate))
        of nkIf:
          result = "${" & clientExpr(node[0]) & " ? html`" & genClientRender(node[1], indent, asTemplate) & "`"
          let hasElse = node.children.len mod 2 == 1
          let elifBranches = if hasElse: node[2..^2] else: node[2..^1]
          for idx in countup(0, elifBranches.len - 1, 2):
            result.add(" : " & clientExpr(elifBranches[idx]) & " ? html`" & genClientRender(elifBranches[idx + 1], indent, asTemplate) & "`")
          if hasElse:
            result.add(" : html`" & genClientRender(node[^1], indent, asTemplate) & "`")
          else:
            result.add(" : ''")
          result.add("}")
        of nkFor:
          let varName = if node[0].kind == nkIdent: jsIdent(node[0].ident) else: node[0].render
          let iterable = node[1]
          if iterable.kind == nkCall and iterable[0].kind == nkIdent and iterable[0].ident == "..":
            let start = clientExpr(iterable[1])
            let endVal = clientExpr(iterable[2])
            result = "${Array.from({length: (" & endVal & " - " & start & " + 1)}, (_, i) => i + " & start & ").map(" & varName & " => html`" & genClientRender(node[2], indent, asTemplate) & "`)}"
          else:
            let iterExpr = clientExpr(iterable)
            result = "${" & iterExpr & ".map(" & varName & " => html`" & genClientRender(node[2], indent, asTemplate) & "`)}"
        of nkWhile:
          result = ""
        of nkCall:
          result = "${" & clientExpr(node) & "}"
        of nkInfix, nkPrefix, nkPostfix:
          result = "${" & clientExpr(node) & "}"
        of nkReturn, nkBreak, nkContinue:
          result = ""
        of nkVar, nkLet, nkConst:
          result = ""
        of nkRawHtml:
          result = jsEscapeStr(node.rawHtml)
        of nkJavaScriptSnippet:
          result = "${" & node.snippetCode & "}"
        of nkDocComment:
          if node.comment.len > 0:
            result = "/* " & node.comment & " */"
        else:
          result = ""
      else:
        case node.kind
        of nkHtmlElement:
          let tag = node.getTag()
          result = i & "html += `<" & tag
          for attr in node.attributes:
            if attr.kind == nkHtmlAttribute:
              case attr.attrType
              of htmlAttrClass:
                case attr.attrNode.kind
                of nkString:
                  result.add(" class=\\\"" & attr.attrNode.stringVal & "\\\"")
                of nkIdent:
                  result.add(" class=\\\"${" & jsIdent(attr.attrNode.ident) & "}\\\"")
                else:
                  result.add(" class=\\\"${" & clientExpr(attr.attrNode) & "}\\\"")
              of htmlAttrId:
                case attr.attrNode.kind
                of nkString:
                  result.add(" id=\\\"" & attr.attrNode.stringVal & "\\\"")
                else:
                  result.add(" id=\\\"${" & clientExpr(attr.attrNode) & "}\\\"")
              of htmlAttr:
                if attr.attrNode.kind == nkInfix and attr.attrNode.len >= 3:
                  let keyNode = attr.attrNode[1]
                  let valNode = attr.attrNode[2]
                  let key = if keyNode.kind == nkString: keyNode.stringVal
                            elif keyNode.kind == nkIdent: jsIdent(keyNode.ident)
                            else: clientExpr(keyNode)
                  let val = if valNode.kind == nkString: valNode.stringVal
                            else: "${" & clientExpr(valNode) & "}"
                  result.add(" " & key & "=\\\"" & val & "\\\"")
                elif attr.attrNode.kind == nkString:
                  result.add(" " & attr.attrNode.stringVal)
                elif attr.attrNode.kind == nkIdent:
                  result.add(" " & jsIdent(attr.attrNode.ident))
              else: discard
          result.add(">`;\n")
          for child in node.childElements:
            result.add(genClientRender(child, indent, asTemplate))
          if node.tag notin voidHtmlElements:
            result.add(i & "html += `</" & tag & ">`;\n")
        of nkString:
          result = i & "html += `" & jsEscapeStr(node.stringVal) & "`;\n"
        of nkInt:
          result = i & "html += " & $node.intVal & ";\n"
        of nkFloat:
          result = i & "html += " & $node.floatVal & ";\n"
        of nkBool:
          result = i & "html += " & $node.boolVal & ";\n"
        of nkIdent:
          result = i & "html += String(" & jsIdent(node.ident) & ");\n"
        of nkBlock:
          for child in node.children:
            result.add(genClientRender(child, indent, asTemplate))
        of nkVar, nkLet, nkConst:
          for decl in node[0]:
            let varName = if decl[0].kind == nkIdent: jsIdent(decl[0].ident) else: decl[0].render
            let varValue = if decl[2].kind != nkEmpty: " = " & clientExpr(decl[2]) else: ""
            result.add(i & $node.kind & " " & varName & varValue & ";\n")
        of nkIf:
          result = i & "if (" & clientExpr(node[0]) & ") {\n"
          result.add(genClientRender(node[1], indent + 2, asTemplate))
          result.add(i & "}\n")
          let hasElse = node.children.len mod 2 == 1
          let elifBranches = if hasElse: node[2..^2] else: node[2..^1]
          for idx in countup(0, elifBranches.len - 1, 2):
            result.add(ni & "else if (" & clientExpr(elifBranches[idx]) & ") {\n")
            result.add(genClientRender(elifBranches[idx + 1], indent + 4, asTemplate))
            result.add(ni & "}\n")
          if hasElse:
            result.add(ni & "else {\n")
            result.add(genClientRender(node[^1], indent + 4, asTemplate))
            result.add(ni & "}\n")
        of nkFor:
          let varName = if node[0].kind == nkIdent: jsIdent(node[0].ident) else: node[0].render
          let iterable = node[1]
          if iterable.kind == nkCall and iterable[0].kind == nkIdent and iterable[0].ident == "..":
            result = i & "for (let " & varName & " = " & clientExpr(iterable[1]) & "; " & varName & " <= " & clientExpr(iterable[2]) & "; " & varName & "++) {\n"
          else:
            result = i & "for (let " & varName & " of " & clientExpr(iterable) & ") {\n"
          result.add(genClientRender(node[2], indent + 2, asTemplate))
          result.add(i & "}\n")
        of nkWhile:
          result = i & "while (" & clientExpr(node[0]) & ") {\n"
          result.add(genClientRender(node[1], indent + 2, asTemplate))
          result.add(i & "}\n")
        of nkCall:
          let callee = if node[0].kind == nkIdent: jsIdent(node[0].ident) else: clientExpr(node[0])
          if callee == "echo" or callee == "console.log":
            result = i & "console.log(" & node[1..^1].mapIt(clientExpr(it)).join(", ") & ");\n"
          else:
            result = i & callee & "(" & node[1..^1].mapIt(clientExpr(it)).join(", ") & ");\n"
        of nkInfix, nkPrefix, nkPostfix:
          result = i & clientExpr(node) & ";\n"
        of nkReturn:
          if node[0].kind != nkEmpty:
            result = i & "return " & clientExpr(node[0]) & ";\n"
          else:
            result = i & "return;\n"
        of nkBreak:
          result = i & "break;\n"
        of nkRawHtml:
          result = i & "html += `" & jsEscapeStr(node.rawHtml) & "`;\n"
        of nkJavaScriptSnippet:
          let js = jsDocify(node.snippetCode)
          for line in js.split('\n'):
            result.add(i & line & "\n")
        of nkDocComment:
          if node.comment.len > 0:
            result = i & "/* " & node.comment & " */\n"
        else:
          result = ""

    proc genMacro*(node: Node, isInstantiation = false): Sym {.codegen.}
    
    const procCallOverwrite = true
    proc procCall*(node: Node, procSym: Sym): Sym {.codegen.} =
      var argTypes: seq[Sym]
      let hasTrailingStmt = node.len > 1 and (node[^1].kind in {nkBlock, nkHtmlElement, nkIf, nkFor, nkWhile, nkCall, nkRawHtml, nkViewLoader})
      let isMacroSym = procSym.kind == skProc and procSym.procType == ProcType.procTypeMacro

      proc bindStatementBody(macroImpl: Node, injectedStmt: Node) =
        if macroImpl == nil or macroImpl.len < 4: return
        let body = macroImpl[3]
        if body == nil or body.kind != nkBlock: return

        for i in 0..body.children.high:
          let child = body[i]
          if child.kind == nkMacro and child.len >= 4 and child[0].kind == nkIdent and child[0].ident == "@statement":
            var blk = ast.newNode(nkBlock)
            if injectedStmt.kind == nkBlock:
              blk = deepCopy(injectedStmt)
            else:
              blk.add(deepCopy(injectedStmt))
            child[3] = blk
            return

      if isMacroSym and hasTrailingStmt:
        let injectedBlock = node[^1]
        let keyHash = hash(procSym).int64 xor int64(injectedBlock.hash())
          # if gen.instantiationCache.hasKey(keyHash):
          #   result = gen.instantiationCache[keyHash]
          # else:
        let macroImpl = procSym.impl
        if macroImpl == nil: 
          node.error("macro implementation missing")

        var clonedImpl = deepCopy(macroImpl)
        # unique name for cloned instantiation
        let uniqueName = procSym.name.ident & "$inst$" & $(gen.count())
        clonedImpl[0] = newIdent(uniqueName)

        # move trailing stmt into inner @statement macro body
        bindStatementBody(clonedImpl, injectedBlock)

        # remove synthetic `body` param from clone; statement is now baked in
        clonedImpl[2].children.delete(clonedImpl[2].len - 1)

        # compile clone as instantiation (no extra macro injections)
        let instSym = gen.genMacro(clonedImpl, isInstantiation = true)

        # gen.instantiationCache[keyHash] = instSym
        result = instSym

        if node.len > 2:
          for arg in node[1..^2]:
            let argSym: Sym = gen.genExpr(arg)
            assert argSym != nil, "Expression must return a symbol"
            argTypes.add(argSym)
        return gen.callProc(result, argTypes, errorNode = node)
      else:
        if node.len > 1:
          for arg in node[1..^1]:
            let argSym: Sym = gen.genExpr(arg)
            assert argSym != nil, "Expression must return a symbol"
            argTypes.add(argSym)
        return gen.callProc(procSym, argTypes, errorNode = node)

    proc hasParamNamed(formalParams: Node, paramName: string): bool =
      if formalParams == nil or formalParams.kind == nkEmpty or formalParams.len <= 1:
        return false
      for defs in formalParams[1..^1]:
        if defs.len < 3: continue
        for i in 0..(defs.len - 3):
          var n = defs[i]
          if n.kind == nkPostfix and n.len == 2:
            n = n[1]
          if n.kind == nkIdent and n.ident == paramName:
            return true
      false

    proc genInnerMacro: Node =
      # reserved macro slot where trailing statement gets injected
      result = ast.newNode(nkMacro)
      result.add(ast.newIdent("@statement"))      # name
      result.add(ast.newNode(nkEmpty))            # generic params
      let fp = ast.newNode(nkFormalParams)        # formal params
      fp.add(ast.newNode(nkEmpty))                # return type
      result.add(fp)
      result.add(ast.newNode(nkBlock))            # body

    proc hasInnerStatementMacro(body: Node): bool =
      if body == nil or body.kind != nkBlock: return false
      for child in body.children:
        if child.kind == nkMacro and child.len > 0 and child[0].kind == nkIdent and child[0].ident == "@statement":
          return true
      false

    proc genMacro(node: Node, isInstantiation = false): Sym {.codegen.} =
      ## Generates code for a block of code that contains a procedure.
      if not isInstantiation and node[1].kind != nkEmpty:
        gen.pushScope()
      var name: Node
      if node[0].kind == nkIdent:
        name = node[0]
      elif node[0].kind == nkPostfix:
        name = node[0][1] # a public macro postfixed with `*`
      else:
        node.error("invalid macro name")
          
      if not isInstantiation and name.ident != "@statement":
        if not hasParamNamed(node[2], "body"):
          let bodyParam = ast.newNode(nkIdentDefs)
          bodyParam.add(ast.newIdent("body"))
          bodyParam.add(ast.newIdent("stmt"))
          bodyParam.add(ast.newNode(nkNil))
          node[2].add(bodyParam)

        if not hasInnerStatementMacro(node[3]):
          node[3].children.insert(genInnerMacro(), 0)

      # get some basic metadata
      let
        formalParams = node[2]
        body = node[3]
        genericParams =
          if not isInstantiation:
            # collect generic params if we're not instantiating
            gen.collectGenericParams(node[1])
          else: none(seq[Sym])
      
      var params = gen.collectParams(formalParams, genericParams)
      # macros always return the `stmt` (HTML) type
      let returnTy = gen.module.sym"void"
      
      # create a new proc
      let isExported = node[0].kind == nkPostfix
      var (sym, theProc) =
            gen.script.newProc(name, impl = node,
                        params, returnTy, kind = pkNative,
                        exported = isExported,
                        genKind = gen.kind)
      sym.genericParams = genericParams
      sym.procType = ProcType.procTypeMacro

      # add the proc into the declaration scope
      # we need to do this here, otherwise recursive calls will be broken
      gen.addSym(sym, scopeOffset = ord(sym.genericParams.isSome))

      # if we're in an instantiation or the proc is not generic, generate its code
      if not sym.isGeneric or isInstantiation:
        var
          chunk = newChunk(gen.chunk.file)
          procGen = initCodeGen(gen.script, gen.module, chunk, gkBlockProc,
            ctxAllocator =
              if gen.kind == gkToplevel: nil
              else: gen.ctxAllocator
          )
        
        # pass down some context from the parent codegen to the proc codegen so it can
        procGen.includeBasePath = gen.includeBasePath
        procGen.parserCallback = gen.parserCallback
        procGen.resolver = gen.resolver
        procGen.manager = gen.manager
        procGen.pkgr = gen.pkgr
        procGen.stdlibs = gen.stdlibs
        # procGen.scopes = gen.scopes

        theProc.chunk = chunk
        chunk.file = gen.chunk.file
        procGen.procReturnTy = returnTy

        # add the proc's parameters as locals
        procGen.pushScope()
        for (name, ty, implValTy, isMut, isOpt) in params:
          var varType = if isMut: skVar else: skLet
          let param = procGen.declareVar(name, varType, ty)
          param.varSet = true  # arguments are not assignable
        
        # declare ``result`` if applicable
        let returnNode = newIdent("result")
        if returnTy.tyKind != ttyVoid:
          let res = newIdent("result")
          procGen.declareVar(res, skVar, returnTy, isMagic = true)
          procGen.pushDefault(returnTy)
          procGen.popVar(res)

        # define the default `attrs` variable
        # this is used to store the attributes of the block.
        let attrs = newIdent("attrs")
        procGen.declareVar(attrs, skVar, gen.module.sym"string", isMagic = true)
        procGen.pushDefault(gen.module.sym"string")
        procGen.popVar(attrs)
        
        # add the proc into the script
        gen.script.procs.add(theProc)
        if sym.procExport:
          # if the proc is exported, we also add it to the export list so it can be
          gen.script.procsExport.add(theProc)

        # compile the proc's body
        discard procGen.genBlock(body, isStmt = true)
        
        # finally, return ``result`` if applicable
        if returnTy.tyKind != ttyVoid:
          let resultSym = procGen.lookup(returnNode)
          procGen.chunk.emit(opcPushL)
          procGen.chunk.emit(resultSym.varStackPos.uint8)
          procGen.chunk.emit(opcReturnVal)
        else:
          procGen.chunk.emit(opcReturnVoid)
        procGen.popScope()

      # pop the generic declaration scope
      if not isInstantiation and sym.isGeneric:
        gen.popScope()
      result = sym

    proc genTest(node: Node): Sym {.codegen.} =
      # node is nkTest with testLabel string and testBody block
      let label = node.testLabel
      let body = node.testBody
      let labelPos = gen.chunk.getString(label)
      gen.chunk.emit(opcTestBegin)
      gen.chunk.emit(labelPos)
      gen.pushScope()
      discard gen.genBlock(body, isStmt = true)
      gen.popScope()
      gen.chunk.emit(opcTestEnd)
      gen.chunk.emit(labelPos)
      result = gen.module.sym"void"

    proc htmlConstr(node: Node): Sym {.codegen.} =
      # Constructs a new HTML element from Html object
      if gen.kind == gkProc:
        node.error(ErrOnlyUsableInAMacro % "HTML")
      let tag = node.getTag()
      let tagIdent = ast.newIdent(tag & "_" & $(gen.counter))
      let tagPos = gen.chunk.getString(tag)
      result = Sym(
        name: tagIdent,
        kind: skHtmlType,
        isVoidElement: node.tag in voidHtmlElements
      )
      if node.attributes.len > 0:
        gen.chunk.emit(opcBeginHtmlWithAttrs)
        gen.chunk.emit(tagPos)
        var classAttributes: seq[string]
        for attr in node.attributes:
          case attr.attrType:
          of htmlAttrClass:
            if attr.attrNode.kind in {nkString, nkInt, nkFloat, nkBool}:
              classAttributes.add(attr.attrNode.stringVal)
            else:
              gen.chunk.emit(opcWSpace)
              discard gen.genExpr(attr.attrNode)
              discard gen.pushConst(ast.newStringLit("class"))
              gen.chunk.emit(opcAttr)
          of htmlAttrId:
            if attr.attrNode.kind in {nkString, nkInt, nkFloat, nkBool}:
              gen.chunk.emit(opcWSpace)
              gen.chunk.emit(opcAttrId)
              gen.chunk.emit(gen.chunk.getString(attr.attrNode.stringVal))
            else:
              gen.chunk.emit(opcWSpace)
              discard gen.genExpr(attr.attrNode)
              discard gen.pushConst(ast.newStringLit("id"))
              gen.chunk.emit(opcAttr)
          of htmlAttr:
            if attr.attrNode.kind == nkInfix:
              gen.chunk.emit(opcWSpace) # add a space before the attribute
              discard gen.genExpr(attr.attrNode[2]) # value
              discard gen.genExpr(attr.attrNode[1]) # key
              gen.chunk.emit(opcAttr) # emit the attribute opcode
            else:
              # if the attribute is a simple identifier, we just emit it
              discard gen.genExpr(attr.attrNode)
              gen.chunk.emit(opcAttrKey)
          else: discard
        if classAttributes.len > 0:
          # if there are any classes, we emit them as a stringified value
          # TODO `--optimize` should enable deduplication of classes
          classAttributes = classAttributes.deduplicate()
          gen.chunk.emit(opcWSpace)
          gen.chunk.emit(opcAttrClass)
          gen.chunk.emit(gen.chunk.getString(classAttributes.join(" ")))
        gen.chunk.emit(opcAttrEnd)
      else:
        gen.chunk.emit(opcBeginHtml)
        gen.chunk.emit(tagPos)
      inc(gen.counter)

      if gen.kind == gkToplevel:
        gen.kind = gkHtmlNest

      if node.childElements.len > 0:
        gen.pushScope()
        for subNode in node.childElements:
          case subNode.kind
          of nkBool, nkInt, nkFloat, nkString:
            discard gen.pushConst(subNode)
            gen.chunk.emit(opcTextHtml)
          of nkIdent, nkDot, nkInfix, nkBracket:
            discard gen.genExpr(subNode)
            gen.chunk.emit(opcTextHtml)
          of nkCall:
            if subNode[0].ident[0] == '@':
              gen.chunk.emit(opcInnerHtml)
              gen.genStmt(subNode)
            else:
              let returnType: Sym = gen.genExpr(subNode)
              if returnType.tyKind != ttyVoid:
                # if the return type is not void, we emit it as text
                # so the returned value is rendered as text
                # inside the HTML element
                gen.chunk.emit(opcTextHtml)
          else:
            gen.chunk.emit(opcInnerHtml)
            gen.genStmt(subNode)
        gen.popScope()
      
      # add the generated symbol to the module
      if not result.isVoidElement:
        gen.chunk.emit(opcCloseHtml)
        gen.chunk.emit(tagPos)

      if gen.kind == gkHtmlNest:
        gen.kind = gkToplevel

  block extendVM:
    extendEnum Opcode:
      opcBeginHtml = "beginHtml"    ## construct HTML object
      opcBeginHtmlWithAttrs = "behinHtmlWithAttrs" ## construct HTML object with attributes
      opcRawHtml = "rawHtml"        ## inject raw HTML into output
      opcAttrEnd = "attrEnd"        ## ends HTML object
      opcInnerHtml = "innerHtml"    ## ends HTML object
      opcTextHtml = "textHtml"      ## adds text to HTML object
      opcCloseHtml = "closeHtml"    ## closes HTML object

      opcAttrClass = "attrClass"    ## adds class to HTML object
      opcAttrId = "attrId"          ## adds id to HTML object
      opcAttr = "attr"
      opcAttrKey = "attrKey"        ## adds a key to HTML object attribute
      opcWSpace = "space"           ## adds whitespace to HTML result
      opcViewLoader = "viewLoader"  ## loads a view using the `@view` placeholder
      opcTestBegin = "testBegin"
      opcTestEnd = "testEnd"
    
    extendCaseStmt "vmParseChunkCase":
      case oc:
      of opcAttrClass, opcAttrId, opcBeginHtmlWithAttrs, opcBeginHtml, opcCloseHtml, opcTestBegin, opcTestEnd:
        let sid = readArg[uint16](pc)
        addOp(oc, sid.int64, 0, akString)
    
    injectSnippet "VanCodeVMBeforeMainLoop":
      # a Voodoo injected snippet to initialize the `result` variable
      vm.globals["app"] = initValue(globalData)
      vm.globals["this"] = initValue(localData)
      result = initValue("")

      var gTestLabel {.inject.}: string
      var gTestMsg {.inject.}: string
      var gTestFailed {.inject.} = false

    extendCaseStmt "vmInterpretCase":
      case oc:
      # HTML generation
      of opcAttrClass:
        # special case for class attribute
        result.stringVal[].add("class=\"" & co.getArg1Str(pcIdx, currentChunk) & "\"")
      of opcAttrId:
        result.stringVal[].add("id=\"" & co.getArg1Str(pcIdx, currentChunk) & "\"")
      of opcWSpace:
        result.stringVal[].add(" ")
      of opcAttrEnd:
        result.stringVal[].add(">")
      of opcAttr:
        let key = stack.pop().stringVal[]
        let value = stack.pop()
        result.stringVal[].add(key & "=\"")
        case value.typeId
        of tyString: result.stringVal[].add(value.stringVal[])
        of tyInt:    result.stringVal[].add($value.intVal)
        of tyFloat:  result.stringVal[].add($value.floatVal)
        of tyBool:   result.stringVal[].add($(value.boolVal))
        of tyJsonStorage:
          result.stringVal[].add(value.jsonVal.toString())
        else: discard
        result.stringVal[].add("\"")
      of opcAttrKey:
        let attr = stack.pop()
        if attr.stringVal[].len > 0:
          result.stringVal[].add(" ") # leading space
          result.stringVal[].add(attr.stringVal[])
      of opcBeginHtmlWithAttrs:
        result.stringVal[].add("<" & co.getArg1Str(pcIdx, currentChunk))
      of opcBeginHtml:
        result.stringVal[].add("<" & co.getArg1Str(pcIdx, currentChunk) & ">")
      of opcRawHtml:
        let v = stack.pop()
        if v.typeId == tyString:
          result.stringVal[].add(v.stringVal[])
      of opcTextHtml:
        let v = stack.pop()
        case v.typeId
        of tyString: result.stringVal[].add(v.stringVal[])
        of tyInt: result.stringVal[].add($v.intVal)
        of tyFloat: result.stringVal[].add($v.floatVal)
        of tyBool: result.stringVal[].add($(v.boolVal))
        of tyJsonStorage: result.stringVal[].add(v.jsonVal.toString())
        else: discard
      of opcInnerHtml:
        discard
      of opcCloseHtml:
        result.stringVal[].add("</" & co.getArg1Str(pcIdx, currentChunk) & ">")
      of opcViewLoader:
        result.stringVal[].add(staticString.get())
      of opcTestBegin:
        gTestFailed = false
        gTestLabel = co.getArg1Str(pcIdx, currentChunk)
        gTestMsg = ""
      of opcTestEnd:
        let label = co.getArg1Str(pcIdx, currentChunk)
        if gTestFailed:
          echo "  \x1b[31m[FAILED]\x1b[0m " & label & (if gTestMsg.len > 0: ": " & gTestMsg else: "")
        else:
          echo "  \x1b[32m[OK]\x1b[0m " & label
        gTestLabel = ""
        gTestMsg = ""
        gTestFailed = false