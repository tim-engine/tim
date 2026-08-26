import std/[unittest, os, options, times]
import pkg/openparser/json
import ../src/tim/meta/cache

suite "Cache — fetch caching layer":
  test "cache is inactive until initialized":
    check fetchCacheGet("key") == none(string)
    fetchCachePut("key", "value")
    check fetchCacheGet("key") == none(string)

  test "cache module put / get / delete":
    let dir = getTempDir() / "tim_cache_test_" & $epochTime().int
    defer: removeDir(dir)
    initFetchCache(dir, 60)
    check fetchCacheGet("a") == none(string)
    fetchCachePut("a", "hello")
    check fetchCacheGet("a").get() == "hello"
    fetchCacheDelete("a")
    check fetchCacheGet("a") == none(string)
    closeFetchCache()
    check fetchCacheGet("a") == none(string)

  test "cache key is deterministic":
    let a = fetchCacheKey("GET", "https://example.com/a", "")
    check a == fetchCacheKey("GET", "https://example.com/a", "")
    check a == fetchCacheKey("GET", "https://example.com/a", "")
    check a != fetchCacheKey("POST", "https://example.com/a", "")
    check a != fetchCacheKey("GET", "https://example.com/b", "")
    check a != fetchCacheKey("GET", "https://example.com/a", "body")

  test "hit returns cached response within ttl, expired entries are dropped":
    let dir = getTempDir() / "tim_cache_ttl_" & $epochTime().int
    defer: removeDir(dir)
    initFetchCache(dir, 60)
    let key = fetchCacheKey("GET", "http://127.0.0.1:1/x", "")
    let now = int(epochTime())
    let resp = %*{"ok": true, "status": 200, "body": "hello"}

    check fetchCacheHit(key, now).isNone

    fetchCacheStore(key, resp, 60, now)
    let hit = fetchCacheHit(key, now)
    check hit.isSome
    check hit.get()["ok"].getBool()
    check hit.get()["body"].getStr() == "hello"

    check fetchCacheHit(key, now + 30).isSome
    check fetchCacheHit(key, now + 61).isNone
    check fetchCacheGet(key) == none(string)

    closeFetchCache()
    check fetchCacheHit(key, now).isNone

  test "malformed cache entry is treated as a miss and cleaned up":
    let dir = getTempDir() / "tim_cache_bad_" & $epochTime().int
    defer: removeDir(dir)
    initFetchCache(dir, 60)
    let key = fetchCacheKey("GET", "http://127.0.0.1:1/y", "")
    fetchCachePut(key, "this is not json")
    let now = int(epochTime())
    check fetchCacheHit(key, now).isNone
    check fetchCacheGet(key) == none(string)
    closeFetchCache()
