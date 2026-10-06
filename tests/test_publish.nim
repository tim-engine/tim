import std/[unittest, strutils]
import pkg/openparser/json
import ../src/tim/app/publish

suite "publish — tags":
  test "splits commas and whitespace, dedupes, keeps order":
    check splitPublishTags("web, library  wrapper,web") == @["web", "library", "wrapper"]
    check splitPublishTags("") == newSeq[string]()
    check splitPublishTags("  tim   timl ") == @["tim", "timl"]

suite "publish — url normalization":
  test "https urls pass through, .git stripped":
    check normalizePublishUrl("https://github.com/tim-engine/bootstrap.timl") ==
      "https://github.com/tim-engine/bootstrap.timl"
    check normalizePublishUrl("https://github.com/tim-engine/bootstrap.timl.git") ==
      "https://github.com/tim-engine/bootstrap.timl"

  test "scp-like and ssh urls map to https":
    check normalizePublishUrl("git@github.com:tim-engine/bootstrap.timl.git") ==
      "https://github.com/tim-engine/bootstrap.timl"
    check normalizePublishUrl("ssh://git@github.com/tim-engine/bootstrap.timl") ==
      "https://github.com/tim-engine/bootstrap.timl"

  test "urls with credentials are rejected":
    expect ValueError:
      discard normalizePublishUrl("https://user:pass@github.com/org/repo")

  test "garbage is rejected":
    expect ValueError:
      discard normalizePublishUrl("not a url")

suite "publish — registry entry":
  test "entry matches the index schema":
    let e = publishEntry("my-pkg", "https://github.com/u/my-pkg",
      "Does things", "MIT", "https://github.com/u/my-pkg", @["tim", "ui"])
    check e["name"].getStr == "my-pkg"
    check e["url"].getStr == "https://github.com/u/my-pkg"
    check e["method"].getStr == "git"
    check e["description"].getStr == "Does things"
    check e["license"].getStr == "MIT"
    check e["web"].getStr == "https://github.com/u/my-pkg"
    check e["tags"].len == 2

  test "entryExists finds names":
    let reg = parseJson("""[{"name": "bootstrap", "url": "https://example.com/b"}]""")
    check entryExists(reg, "bootstrap")
    check not entryExists(reg, "other")
    check not entryExists(parseJson("{}"), "bootstrap")

  test "insertEntrySorted keeps alphabetical order":
    var reg = parseJson("""[{"name": "zebra"}, {"name": "mango"}]""")
    let entry = publishEntry("apple", "https://example.com/a",
      "A", "MIT", "https://example.com/a", @["tim"])
    reg = insertEntrySorted(reg, entry)
    check reg.len == 3
    check reg[0]["name"].getStr == "apple"
    check reg[1]["name"].getStr == "zebra"
    check reg[2]["name"].getStr == "mango"

  test "insertEntrySorted appends at the end":
    var reg = parseJson("""[{"name": "apple"}]""")
    let entry = publishEntry("zebra", "https://example.com/z",
      "Z", "MIT", "https://example.com/z", @["tim"])
    reg = insertEntrySorted(reg, entry)
    check reg[1]["name"].getStr == "zebra"

suite "publish — pr metadata":
  test "branch, title and body":
    let branch = publishBranchName("bootstrap")
    check branch.startsWith("add-bootstrap-")
    check prTitle("bootstrap", "0.1.0") == "Add bootstrap 0.1.0"
    let body = prBody("bootstrap", "0.1.0",
      "https://github.com/tim-engine/bootstrap.timl", "Does things", "", true)
    check "Does things" in body
    check "https://github.com/tim-engine/bootstrap.timl" in body
    check "semver tag" in body
