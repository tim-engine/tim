# FBE serialization for Tim Ast — replaces flatty
#
# Provides `toFbe(ast: Ast): string` and `fromFbe(data: string): Ast`
# using openparser/fbe (FastBinaryEncoding) with manual handling for
# variant `Node` (including Tim extensions via `when compiles`).

import pkg/openparser/fbe
import pkg/vancode/interpreter/ast
import pkg/openparser/html/ast as htmlAst
import pkginfo
import semver

const NimbleVersion* = pkg().getVersion()
const NimbleVersionStr* = pkg().version

func semverToFbeVersion*(v: Version): uint32 =
  ## Encode semver as FBE uint32: major<<16 | minor<<8 | patch  (fits 0.0.0 - 255.255.255)
  ## For 0.2.9 => 0x000209 = 521
  result = uint32(((v.major and 0xFF) shl 16) or ((v.minor and 0xFF) shl 8) or (v.patch and 0xFF))

const FbeAstVersion* = semverToFbeVersion(NimbleVersion)
const FbeNodeVersion* = FbeAstVersion

proc isFbeVersionCompatible*(got, expected: uint32): bool =
  ## Allow exact match or legacy version 1 (pre-versioned files) for smooth migration
  if got == expected: return true
  if got == 1'u32 and expected != 1'u32: return true # legacy files with hardcoded 1
  return false

# ---------------------------------------------------------------------------
# Node helpers
# ---------------------------------------------------------------------------

proc writeNode(b: var Buffer, n: Node)

proc readNode(b: var Buffer): Node

proc writeNodeSeq(b: var Buffer, s: seq[Node]) =
  writeVector[Node](b, s, proc(bb: var Buffer; v: Node) = writeNode(bb, v))

proc readNodeSeq(b: var Buffer): seq[Node] =
  result = readVector[Node](b, proc(bb: var Buffer): Node = readNode(bb))

proc writeStringSeq(b: var Buffer, s: seq[string]) =
  writeVector[string](b, s, proc(bb: var Buffer; v: string) = bb.writeString(v))

proc readStringSeq(b: var Buffer): seq[string] =
  result = readVector[string](b, proc(bb: var Buffer): string = bb.readString())

# snippetCodeAttrs is seq[(string, Node)] — encode as vector of inner structs with 2 fields
proc writeSnippetAttrs(b: var Buffer, s: seq[(string, Node)]) =
  writeVector[(string, Node)](b, s, proc(bb: var Buffer; v: (string, Node)) =
    beginInnerStruct(bb, FbeNodeVersion)
    writeField(bb, 1'u16, proc(bbb: var Buffer) = bbb.writeString(v[0]))
    writeField(bb, 2'u16, proc(bbb: var Buffer) = writeNode(bbb, v[1]))
    endInnerStruct(bb)
  )

proc readSnippetAttrs(b: var Buffer): seq[(string, Node)] =
  let vec = readVector[(string, Node)](b, proc(bb: var Buffer): (string, Node) =
    let ver = beginReadInnerStruct(bb)
    if not isFbeVersionCompatible(ver, FbeNodeVersion):
      raise newException(CatchableError, "FBE Node snippet version mismatch: got " & $ver & " expected " & $FbeNodeVersion)
    var key: string
    var val: Node
    var fid: uint16
    var fsz: int
    while readFieldHeader(bb, fid, fsz):
      case fid
      of 1'u16: key = readFieldValue[string](bb, fsz, proc(b2: var Buffer): string = b2.readString())
      of 2'u16: val = readFieldValue[Node](bb, fsz, proc(b2: var Buffer): Node = readNode(b2))
      else: discard
    endReadInnerStruct(bb)
    result = (key, val)
  )
  result = vec

proc writeNode(b: var Buffer, n: Node) =
  # Encode nil as inner struct with isNil flag
  if n == nil:
    beginInnerStruct(b, FbeNodeVersion)
    writeField(b, 1'u16, proc(bb: var Buffer) = bb.writeBool(true)) # isNil = true
    endInnerStruct(b)
    return
  beginInnerStruct(b, FbeNodeVersion)
  # isNil = false
  writeField(b, 1'u16, proc(bb: var Buffer) = bb.writeBool(false))
  # kind
  writeField(b, 2'u16, proc(bb: var Buffer) = bb.writeInt32LE(int32(ord(n.kind))))
  # ln, col
  writeField(b, 3'u16, proc(bb: var Buffer) = bb.writeInt32LE(int32(n.ln)))
  writeField(b, 4'u16, proc(bb: var Buffer) = bb.writeInt32LE(int32(n.col)))

  # variant payloads
  case n.kind
  of nkBool:
    writeField(b, 5'u16, proc(bb: var Buffer) = bb.writeBool(n.boolVal))
  of nkInt:
    writeField(b, 6'u16, proc(bb: var Buffer) = bb.writeInt64LE(n.intVal))
  of nkFloat:
    writeField(b, 7'u16, proc(bb: var Buffer) = bb.writeFloat64LE(n.floatVal))
  of nkString:
    writeField(b, 8'u16, proc(bb: var Buffer) = bb.writeString(n.stringVal))
  of nkIdent:
    writeField(b, 9'u16, proc(bb: var Buffer) = bb.writeString(n.ident))
  of nkVarTy:
    writeField(b, 10'u16, proc(bb: var Buffer) = writeNode(bb, n.varType))
  of nkDocComment:
    writeField(b, 11'u16, proc(bb: var Buffer) = bb.writeString(n.comment))
  of nkEmpty, nkNil:
    discard
  else:
    # branch nodes: children seq
    # But Tim extensions have custom fields; handle them before generic children
    when compiles(NodeKind.nkHtmlElement):
      if n.kind == nkHtmlElement:
        writeField(b, 12'u16, proc(bb: var Buffer) = bb.writeInt32LE(int32(ord(n.tag))))
        writeField(b, 13'u16, proc(bb: var Buffer) = bb.writeString(n.tagCustom))
        writeField(b, 14'u16, proc(bb: var Buffer) = writeNodeSeq(bb, n.attributes))
        writeField(b, 15'u16, proc(bb: var Buffer) = writeNodeSeq(bb, n.childElements))
        # also write children as empty to keep generic handler from duplicating?
        # we still need to not write 17 below for this branch
      elif n.kind == nkHtmlAttribute:
        writeField(b, 16'u16, proc(bb: var Buffer) = bb.writeInt32LE(int32(ord(n.attrType))))
        writeField(b, 17'u16, proc(bb: var Buffer) = writeNode(bb, n.attrNode))
      elif n.kind == nkJavaScriptSnippet or n.kind == nkCssSnippet:
        writeField(b, 18'u16, proc(bb: var Buffer) = bb.writeString(n.snippetCode))
        writeField(b, 19'u16, proc(bb: var Buffer) = writeSnippetAttrs(bb, n.snippetCodeAttrs))
      elif n.kind == nkRawHtml:
        writeField(b, 20'u16, proc(bb: var Buffer) = bb.writeString(n.rawHtml))
      elif n.kind == nkTest:
        when compiles(n.testLabel):
          writeField(b, 22'u16, proc(bb: var Buffer) = bb.writeString(n.testLabel))
          writeField(b, 23'u16, proc(bb: var Buffer) = writeNode(bb, n.testBody))
        else:
          writeField(b, 22'u16, proc(bb: var Buffer) = bb.writeString(""))
      else:
        # generic children for other branch kinds
        if n.children.len > 0 or true:
          writeField(b, 21'u16, proc(bb: var Buffer) = writeNodeSeq(bb, n.children))
    else:
      writeField(b, 21'u16, proc(bb: var Buffer) = writeNodeSeq(bb, n.children))

  endInnerStruct(b)

proc readNode(b: var Buffer): Node =
  let ver = beginReadInnerStruct(b)
  if not isFbeVersionCompatible(ver, FbeNodeVersion):
    raise newException(CatchableError, "FBE Node version mismatch: got " & $ver & " expected " & $FbeNodeVersion & " (tim " & NimbleVersionStr & ")")
  var isNil = false
  var kindOrd = -1
  var ln, col: int32 = 0
  var boolVal: bool
  var intVal: int64
  var floatVal: float64
  var stringVal: string
  var ident: string
  var varType: Node
  var comment: string
  var children: seq[Node]
  var tagOrd = 0
  var tagCustom: string
  var attributes: seq[Node]
  var childElements: seq[Node]
  var attrTypeOrd = 0
  var attrNode: Node
  var snippetCode: string
  var snippetAttrs: seq[(string, Node)]
  var rawHtml: string
  var testLabel: string
  var testBody: Node
  var fid: uint16
  var fsz: int
  while readFieldHeader(b, fid, fsz):
    case fid
    of 1'u16: isNil = readFieldValue[bool](b, fsz, proc(bb: var Buffer): bool = bb.readBool())
    of 2'u16: kindOrd = int(readFieldValue[int32](b, fsz, proc(bb: var Buffer): int32 = bb.readInt32LE()))
    of 3'u16: ln = readFieldValue[int32](b, fsz, proc(bb: var Buffer): int32 = bb.readInt32LE())
    of 4'u16: col = readFieldValue[int32](b, fsz, proc(bb: var Buffer): int32 = bb.readInt32LE())
    of 5'u16: boolVal = readFieldValue[bool](b, fsz, proc(bb: var Buffer): bool = bb.readBool())
    of 6'u16: intVal = readFieldValue[int64](b, fsz, proc(bb: var Buffer): int64 = bb.readInt64LE())
    of 7'u16: floatVal = readFieldValue[float64](b, fsz, proc(bb: var Buffer): float64 = bb.readFloat64LE())
    of 8'u16: stringVal = readFieldValue[string](b, fsz, proc(bb: var Buffer): string = bb.readString())
    of 9'u16: ident = readFieldValue[string](b, fsz, proc(bb: var Buffer): string = bb.readString())
    of 10'u16: varType = readFieldValue[Node](b, fsz, proc(bb: var Buffer): Node = readNode(bb))
    of 11'u16: comment = readFieldValue[string](b, fsz, proc(bb: var Buffer): string = bb.readString())
    of 12'u16: tagOrd = int(readFieldValue[int32](b, fsz, proc(bb: var Buffer): int32 = bb.readInt32LE()))
    of 13'u16: tagCustom = readFieldValue[string](b, fsz, proc(bb: var Buffer): string = bb.readString())
    of 14'u16: attributes = readFieldValue[seq[Node]](b, fsz, proc(bb: var Buffer): seq[Node] = readNodeSeq(bb))
    of 15'u16: childElements = readFieldValue[seq[Node]](b, fsz, proc(bb: var Buffer): seq[Node] = readNodeSeq(bb))
    of 16'u16: attrTypeOrd = int(readFieldValue[int32](b, fsz, proc(bb: var Buffer): int32 = bb.readInt32LE()))
    of 17'u16: attrNode = readFieldValue[Node](b, fsz, proc(bb: var Buffer): Node = readNode(bb))
    of 18'u16: snippetCode = readFieldValue[string](b, fsz, proc(bb: var Buffer): string = bb.readString())
    of 19'u16: snippetAttrs = readFieldValue[seq[(string, Node)]](b, fsz, proc(bb: var Buffer): seq[(string, Node)] = readSnippetAttrs(bb))
    of 20'u16: rawHtml = readFieldValue[string](b, fsz, proc(bb: var Buffer): string = bb.readString())
    of 21'u16: children = readFieldValue[seq[Node]](b, fsz, proc(bb: var Buffer): seq[Node] = readNodeSeq(bb))
    of 22'u16: testLabel = readFieldValue[string](b, fsz, proc(bb: var Buffer): string = bb.readString())
    of 23'u16: testBody = readFieldValue[Node](b, fsz, proc(bb: var Buffer): Node = readNode(bb))
    else: discard
  endReadInnerStruct(b)
  if isNil:
    return nil
  if kindOrd < 0:
    # fallback: should not happen
    return nil
  let k = NodeKind(kindOrd)
  var n: Node
  case k
  of nkBool:
    n = newNode(k)
    n.boolVal = boolVal
  of nkInt:
    n = newNode(k)
    n.intVal = intVal
  of nkFloat:
    n = newNode(k)
    n.floatVal = floatVal
  of nkString:
    n = newNode(k)
    n.stringVal = stringVal
  of nkIdent:
    n = newNode(k)
    n.ident = ident
  of nkVarTy:
    n = newNode(k)
    n.varType = varType
  of nkDocComment:
    n = newNode(k)
    n.comment = comment
  of nkEmpty, nkNil:
    n = newNode(k)
  else:
    when compiles(NodeKind.nkHtmlElement):
      if k == nkHtmlElement:
        let t = HtmlTag(tagOrd)
        if t == tagUnknown:
          n = newNode(k)
          n.tag = t
          n.tagCustom = tagCustom
        else:
          n = newNode(k)
          n.tag = t
          n.tagCustom = tagCustom
        n.attributes = attributes
        n.childElements = childElements
        # also ensure children empty
        if children.len > 0:
          # if generic children were written, ignore
          discard
      elif k == nkHtmlAttribute:
        n = newNode(k)
        n.attrType = HtmlAttributeType(attrTypeOrd)
        n.attrNode = attrNode
      elif k == nkJavaScriptSnippet or k == nkCssSnippet:
        n = newNode(k)
        n.snippetCode = snippetCode
        n.snippetCodeAttrs = snippetAttrs
      elif k == nkRawHtml:
        n = newNode(k)
        n.rawHtml = rawHtml
      elif k == nkTest:
        n = newNode(k)
        when compiles(n.testLabel):
          n.testLabel = testLabel
          n.testBody = testBody
        else:
          n.children = children
      else:
        n = newNode(k)
        n.children = children
        # if this was HtmlElement but we already handled, not reached
    else:
      n = newNode(k)
      n.children = children
  n.ln = int(ln)
  n.col = int(col)
  result = n

# ---------------------------------------------------------------------------
# Ast helpers
# ---------------------------------------------------------------------------

proc writeAstInner(b: var Buffer, a: Ast) =
  # sourcePath
  writeField(b, 1'u16, proc(bb: var Buffer) = bb.writeString(a.sourcePath))
  # otherPaths
  writeField(b, 2'u16, proc(bb: var Buffer) = writeStringSeq(bb, a.otherPaths))
  # nodes
  writeField(b, 3'u16, proc(bb: var Buffer) = writeNodeSeq(bb, a.nodes))
  # forwardDecl (Tim extension, when available)
  when compiles(a.forwardDecl):
    writeField(b, 4'u16, proc(bb: var Buffer) = writeNodeSeq(bb, a.forwardDecl))

proc readAstInner(b: var Buffer, a: Ast) =
  var sourcePath: string
  var otherPaths: seq[string]
  var nodes: seq[Node]
  var forwardDecl: seq[Node]
  var fid: uint16
  var fsz: int
  while readFieldHeader(b, fid, fsz):
    case fid
    of 1'u16: sourcePath = readFieldValue[string](b, fsz, proc(bb: var Buffer): string = bb.readString())
    of 2'u16: otherPaths = readFieldValue[seq[string]](b, fsz, proc(bb: var Buffer): seq[string] = readStringSeq(bb))
    of 3'u16: nodes = readFieldValue[seq[Node]](b, fsz, proc(bb: var Buffer): seq[Node] = readNodeSeq(bb))
    of 4'u16:
      when compiles(a.forwardDecl):
        forwardDecl = readFieldValue[seq[Node]](b, fsz, proc(bb: var Buffer): seq[Node] = readNodeSeq(bb))
      else: discard
    else: discard
  a.sourcePath = sourcePath
  a.otherPaths = otherPaths
  a.nodes = nodes
  when compiles(a.forwardDecl):
    a.forwardDecl = forwardDecl

proc toFbe*(ast: Ast): string =
  ## Encode Ast to FBE binary string (for file storage) — versioned via NimbleVersion
  var b = initBuffer(1024)
  b.reset()
  beginRootStruct(b, FbeAstVersion)
  writeAstInner(b, ast)
  endRootStruct(b)
  # copy buffer data to string
  result = newStringOfCap(b.data.len)
  result.setLen(b.data.len)
  if b.data.len > 0:
    copyMem(addr result[0], addr b.data[0], b.data.len)

proc fromFbe*(data: string, T: type Ast): Ast =
  ## Decode Ast from FBE binary string — checks FBE version from header
  var b = initBuffer(data.len)
  b.data = newSeq[uint8](data.len)
  if data.len > 0:
    copyMem(addr b.data[0], unsafeAddr data[0], data.len)
  b.pos = 0
  let ver = beginReadRootStruct(b)
  if not isFbeVersionCompatible(ver, FbeAstVersion):
    raise newException(CatchableError, "FBE Ast version mismatch: got " & $ver & " expected " & $FbeAstVersion & " (tim " & NimbleVersionStr & ")")
  result = Ast()
  readAstInner(b, result)
  endReadRootStruct(b)

proc toFbeFile*(path: string, ast: Ast) =
  writeFile(path, toFbe(ast))

proc fromFbeFile*(path: string, T: type Ast): Ast =
  let data = readFile(path)
  result = fromFbe(data, Ast)
