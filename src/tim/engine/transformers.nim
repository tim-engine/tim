import std/os
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
    nkMacro          # a block - {...}

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
        case tag*: HtmlTag
        of tagUnknown:
          tagCustom*: string
        else: discard
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
      discard gen.pushConst(ast.newStringLit(node.snippetCode))
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
      tagParam, tagSource, tagTrack, tagWbr, tagCommand,
      tagKeygen, tagFrame]

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
        of tagAcronym: "acronym"
        of tagAddress: "address"
        of tagApplet: "applet"
        of tagArea: "area"
        of tagArticle: "article"
        of tagAside: "aside"
        of tagAudio: "audio"
        of tagB: "b"
        of tagBase: "base"
        of tagBasefont: "basefont"
        of tagBdi: "bdi"
        of tagBdo: "bdo"
        of tagBig: "big"
        of tagBlockquote: "blockquote"
        of tagBody: "body"
        of tagBr: "br"
        of tagButton: "button"
        of tagCanvas: "canvas"
        of tagCaption: "caption"
        of tagCenter: "center"
        of tagCite: "cite"
        of tagCode: "code"
        of tagCol: "col"
        of tagColgroup: "colgroup"
        of tagCommand: "command"
        of tagDatalist: "datalist"
        of tagDd: "dd"
        of tagDel: "del"
        of tagDetails: "details"
        of tagDfn: "dfn"
        of tagDialog: "dialog"
        of tagDiv: "div"
        of tagDir: "dir"
        of tagDl: "dl"
        of tagDt: "dt"
        of tagEm: "em"
        of tagEmbed: "embed"
        of tagFieldset: "fieldset"
        of tagFigcaption: "figcaption"
        of tagFigure: "figure"
        of tagFont: "font"
        of tagFooter: "footer"
        of tagForm: "form"
        of tagFrame: "frame"
        of tagFrameset: "frameset"
        of tagH1: "h1"
        of tagH2: "h2"
        of tagH3: "h3"
        of tagH4: "h4"
        of tagH5: "h5"
        of tagH6: "h6"
        of tagHead: "head"
        of tagHeader: "header"
        of tagHgroup: "hgroup"
        of tagHtml: "html"
        of tagHr: "hr"
        of tagI: "i"
        of tagIframe: "iframe"
        of tagImg: "img"
        of tagInput: "input"
        of tagIns: "ins"
        of tagIsindex: "isindex"
        of tagKbd: "kbd"
        of tagKeygen: "keygen"
        of tagLabel: "label"
        of tagLegend: "legend"
        of tagLi: "li"
        of tagLink: "link"
        of tagMap: "map"
        of tagMark: "mark"
        of tagMenu: "menu"
        of tagMeta: "meta"
        of tagMeter: "meter"
        of tagNav: "nav"
        of tagNobr: "nobr"
        of tagNoframes: "noframes"
        of tagNoscript: "noscript"
        of tagObject: "object"
        of tagOl: "ol"
        of tagOptgroup: "optgroup"
        of tagOption: "option"
        of tagOutput: "output"
        of tagP: "p"
        of tagParam: "param"
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
        of tagStrike: "strike"
        of tagStrong: "strong"
        of tagStyle: "style"
        of tagSub: "sub"
        of tagSummary: "summary"
        of tagSup: "sup"
        of tagTable: "table"
        of tagTbody: "tbody"
        of tagTd: "td"
        of tagTextarea: "textarea"
        of tagTfoot: "tfoot"
        of tagTh: "th"
        of tagThead: "thead"
        of tagTime: "time"
        of tagTitle: "title"
        of tagTr: "tr"
        of tagTrack: "track"
        of tagTt: "tt"
        of tagU: "u"
        of tagUl: "ul"
        of tagVar: "var"
        of tagVideo: "video"
        of tagWbr: "wbr"
        else: "" # non-standard HTML tag / custom tag
      
    proc newHtmlElement*(tag: HtmlTag, tagStr: string): Node =
      ## Construct a new HTML element node.
      case tag
      of tagUnknown:
        result = Node(
          kind: nkHtmlElement,
          tag: tagUnknown,
          tagCustom: tagStr
        )
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

    proc genMacro*(node: Node, isInstantiation = false): Sym {.codegen.}
    
    const procCallOverwrite = true
    proc procCall*(node: Node, procSym: Sym): Sym {.codegen.} =
      var argTypes: seq[Sym]
      let hasTrailingStmt = node.len > 1 and (node[^1].kind in {nkHtmlElement, nkIf, nkFor, nkCall})
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
    
    extendCaseStmt "vmParseChunkCase":
      case oc:
      of opcAttrClass, opcAttrId, opcBeginHtmlWithAttrs, opcBeginHtml, opcCloseHtml:
        let sid = readArg[uint16](pc)
        addOp(oc, sid.int64, 0, akString)
    
    injectSnippet "VanCodeVMBeforeMainLoop":
      # a Voodoo injected snippet to initialize the `result` variable
      vm.globals["app"] = initValue(globalData)
      vm.globals["this"] = initValue(localData)
      result = initValue("")

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