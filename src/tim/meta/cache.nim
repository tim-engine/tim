# A super fast template engine for cool kids
#
# (c) 2025 George Lemon | LGPL-v3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/tim

import std/options
import pkg/openparser/json
when not defined(wasm):
  import std/[os, locks]
  import pkg/openparser/uuid
  import pkg/boogie/stores/kv
else:
  import std/[tables, strutils]
  import pkg/checksums/sha1

## A WAL-backed response cache used by the `fetch` (libsystem) function in
## the `tim serve` development server. Backed by the Boogie KV store.
##
## On wasm32-standalone (browser playground) there is no filesystem, so the
## cache is a plain in-memory table instead: `path` is ignored and nothing
## is ever persisted. The fetch procs themselves are disabled in that build
## (see libsystem), but the cache API stays available and safe to call.
##
## The store is a process-wide singleton. It is only active after
## `initFetchCache` has been called (from `tim serve` when the `cache`
## config section is enabled). In any other context `cacheStore` is nil
## and all accessors become no-ops.
##
## Cached entries are stored as a JSON envelope:
##   {"cachedAt": <unix seconds>, "ttl": <seconds>, "resp": <response json>}

when not defined(wasm):
  var cacheStore*: KvStore
  var cacheDefaultTTL*: int
  var fetchCacheLock: Lock
  initLock(fetchCacheLock)

  proc initFetchCache*(path: string, defaultTTL: int) =
    ## Initialize the process-wide fetch response cache backed by a Boogie
    ## KV store at `path`. Must be called before the server starts serving
    ## requests (single-threaded), so no lock is required here.
    discard existsOrCreateDir(path)
    cacheDefaultTTL = defaultTTL
    cacheStore = newKvStore(
      path / "fetch",
      ksmDisk,
      enableWal = true,
      checkpointEveryOps = 1000'u32
    )

  proc closeFetchCache*() =
    ## Flush and tear down the fetch response cache.
    if cacheStore != nil:
      cacheStore.checkpoint()
    cacheStore = nil

  proc fetchCacheGet*(key: string): Option[string] {.gcsafe.} =
    ## Retrieve a cached value by key, if the cache is active.
    {.gcsafe.}:
      if cacheStore == nil:
        return none(string)
      acquire(fetchCacheLock)
      result = cacheStore.get(key)
      release(fetchCacheLock)

  proc fetchCachePut*(key, value: string) {.gcsafe.} =
    ## Store a value by key, if the cache is active.
    {.gcsafe.}:
      if cacheStore == nil:
        return
      acquire(fetchCacheLock)
      cacheStore.put(key, value)
      release(fetchCacheLock)

  proc fetchCacheDelete*(key: string) {.gcsafe.} =
    ## Delete a value by key, if the cache is active.
    {.gcsafe.}:
      if cacheStore == nil:
        return
      acquire(fetchCacheLock)
      discard cacheStore.delete(key)
      release(fetchCacheLock)

  proc fetchCacheKey*(httpMethod, url, body: string): string =
    ## Derive a deterministic name-based UUID for a fetch request.
    ## The same request always maps to the same key; a change in method,
    ## url or body produces a different key.
    $newUuidV3(nsURL, httpMethod & "|" & url & "|" & body)

else:
  var cacheTable = initTable[string, string]()
  var cacheDefaultTTL*: int

  proc initFetchCache*(path: string, defaultTTL: int) =
    ## In-memory cache: `path` is ignored (no filesystem in the browser).
    cacheDefaultTTL = defaultTTL
    cacheTable.clear()

  proc closeFetchCache*() =
    cacheTable.clear()

  proc fetchCacheGet*(key: string): Option[string] {.gcsafe.} =
    if cacheTable.hasKey(key):
      some(cacheTable[key])
    else:
      none(string)

  proc fetchCachePut*(key, value: string) {.gcsafe.} =
    cacheTable[key] = value

  proc fetchCacheDelete*(key: string) {.gcsafe.} =
    cacheTable.del(key)

  proc fetchCacheKey*(httpMethod, url, body: string): string =
    ## Deterministic sha1 key (uuid needs wall-clock time, unavailable here).
    toLowerAscii($(sha1.secureHash(httpMethod & "|" & url & "|" & body)))

proc fetchCacheHit*(key: string, now: int): Option[JsonNode] {.gcsafe.} =
  ## Look up `key` and return the cached response if it is still fresh
  ## (cachedAt + ttl > now). Expired or malformed entries are removed
  ## and treated as a miss. Returns `none` when the cache is inactive.
  {.gcsafe.}:
    when not defined(wasm):
      if cacheStore == nil:
        return none(JsonNode)
      acquire(fetchCacheLock)
      let cached = cacheStore.get(key)
      release(fetchCacheLock)
    else:
      let cached = fetchCacheGet(key)
    if cached.isNone:
      return none(JsonNode)
    try:
      let entry = fromJson(cached.get())
      if entry.hasKey("cachedAt") and entry.hasKey("ttl") and entry.hasKey("resp") and
          now - entry["cachedAt"].getInt() < entry["ttl"].getInt():
        return some(entry["resp"])
    except:
      discard
    fetchCacheDelete(key)
    none(JsonNode)

proc fetchCacheStore*(key: string, resp: JsonNode, ttl, now: int) {.gcsafe.} =
  ## Store `resp` under `key` with the given TTL (seconds), stamping
  ## `now` as the cached-at time. No-op when the cache is inactive.
  {.gcsafe.}:
    when not defined(wasm):
      if cacheStore == nil:
        return
    fetchCachePut(key, toJson(%*{
      "cachedAt": now,
      "ttl": ttl,
      "resp": resp
    }))
