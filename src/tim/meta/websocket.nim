# A super fast template engine for cool kids
#
# (c) 2025 George Lemon | LGPL License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/[net, strutils, base64, tables, os, nativesockets, selectors, locks]
import pkg/checksums/sha1

## This module implements a very basic websocket server that can be used 
## to notify connected clients when a new change is detected in the templates directory.
## 
## This is not a full featured websocket server and is only intended for Tim's internal use.

const
  GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

type
  OnMessageProc = proc(client: Socket, data: seq[byte])
  OnConnectProc = proc(client: Socket)
  OnCloseProc = proc(client: Socket)

  ClientState = enum
    Handshaking, Open

  ClientInfo = object
    sock: Socket
    buf: string
    state: ClientState

  WebSocketServer* = ref object
    port: Port
    connections: seq[Socket]
    lock: Lock
    thread: Thread[tuple[server: WebSocketServer]]

proc acceptWebSocket(client: Socket, key: string) =
  let digest = sha1.secureHash(key & GUID)
  let shaArray = cast[array[0 .. 19, uint8]](digest)
  let acceptKey = base64.encode(shaArray)
  client.send("HTTP/1.1 101 Switching Protocols\r\n" &
              "Upgrade: websocket\r\n" &
              "Connection: Upgrade\r\n" &
              "Sec-WebSocket-Accept: " & acceptKey & "\r\n\r\n")

proc getWebSocketKey(header: string): string =
  for line in header.splitLines():
    if line.startsWith("Sec-WebSocket-Key:"):
      return line.split(":")[1].strip()
  return ""

proc readHttpHeader(client: Socket): string =
  var header = ""
  while true:
    let line = client.recvLine()
    if line.len == 0: break
    header.add(line & "\n")
  return header

proc wsFrameText(data: string): string =
  result = newStringOfCap(2 + 8 + data.len)
  result.add char(0x81) # FIN + text frame
  let L = data.len
  if L <= 125:
    result.add char(L)
  elif L <= 0xFFFF:
    result.add char(126)
    result.add char((L shr 8) and 0xFF)
    result.add char(L and 0xFF)
  else:
    result.add char(127)
    for i in countdown(7, 0):
      result.add char((uint64(L) shr (i * 8)) and 0xFF)
  result.add data

proc wsSendText*(client: Socket, data: string) =
  client.send(wsFrameText(data))

proc notifyAllClients*(server: WebSocketServer) =
  ## Notify all connected WebSocket clients for this server
  if server == nil: return
  var conns: seq[Socket]
  withLock server.lock:
    conns = server.connections
  for client in conns:
    if client != nil:
      try:
        client.wsSendText("1")
      except OSError, ValueError:
        discard

proc onMessage(server: WebSocketServer, client: Socket, data: seq[byte]) =
  discard

proc onConnect(server: WebSocketServer, client: Socket) =
  withLock server.lock:
    server.connections.add(client)

proc onClose(server: WebSocketServer, client: Socket) =
  withLock server.lock:
    while true:
      let idx = server.connections.find(client)
      if idx == -1: break
      server.connections.delete(idx)

proc startWebSocket*(port: Port = Port(9000)): WebSocketServer =
  ## Start a new WebSocket server instance on the given port
  let server = WebSocketServer(port: port, connections: @[])
  initLock(server.lock)
  proc run(args: tuple[server: WebSocketServer]) {.thread.} =
    {.gcsafe.}:
      let ws = args.server
      let sock = newSocket()
      sock.setSockOpt(OptReusePort, true)
      sock.bindAddr(ws.port)
      sock.listen()

      var selector = newSelector[int]()
      selector.registerHandle(sock.getFd, {Event.Read}, 0)

      var clientSockets = initTable[int, ClientInfo]()

      while true:
        let events = selector.select(-1)
        for event in events:
          if SocketHandle(event.fd) == sock.getFd:
            var client: Socket
            sock.accept(client)
            client.getFd.setBlocking(false)
            selector.registerHandle(client.getFd, {Event.Read}, 0)
            clientSockets[client.getFd.int] = ClientInfo(sock: client, buf: "", state: Handshaking)
          else:
            var info = clientSockets.getOrDefault(event.fd)
            if info.sock != nil:
              var tmp = newString(4096)
              let n = info.sock.recv(tmp, tmp.len)
              if n <= 0:
                ws.onClose(info.sock)
                selector.unregister(SocketHandle(event.fd))
                info.sock.close()
                clientSockets.del(event.fd)
              else:
                info.buf.add tmp[0 ..< n]
                if info.state == Handshaking:
                  let sep = "\r\n\r\n"
                  let p = info.buf.find(sep)
                  if p >= 0:
                    let headerEnd = p + sep.len
                    let header = info.buf[0 ..< headerEnd]
                    let key = getWebSocketKey(header)
                    if key.len > 0:
                      acceptWebSocket(info.sock, key)
                      ws.onConnect(info.sock)
                      info.state = Open
                    # drop header from buffer
                    if headerEnd < info.buf.len:
                      let remaining = info.buf[headerEnd .. ^1]
                      if remaining.len > 0:
                        ws.onMessage(info.sock, cast[seq[byte]](remaining))
                    info.buf.setLen(0)
                else:
                  ws.onMessage(info.sock, cast[seq[byte]](info.buf))
                  info.buf.setLen(0)
                clientSockets[event.fd] = info
  let args = (server: server)
  createThread(server.thread, run, args)
  return server
