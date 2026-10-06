import std/[unittest, os]
import ../src/tim/pkgmanager/secrets

proc tempHome(suffix: string): string =
  result = getTempDir() / ("tim_secrets_" & suffix & "_" & $getCurrentProcessId())
  createDir(result)

suite "secrets — setup and roundtrip":
  test "no secret file initially":
    let home = tempHome("empty")
    defer: removeDir(home)
    check not hasSecretFile(home)

  test "store then load returns the token":
    let home = tempHome("roundtrip")
    defer: removeDir(home)
    storeGithubToken(home, "gho_test123", "correct horse")
    check hasSecretFile(home)
    check loadGithubToken(home, "correct horse") == "gho_test123"

  test "secret file is owner-only":
    let home = tempHome("perms")
    defer: removeDir(home)
    storeGithubToken(home, "gho_test123", "some password")
    check getFilePermissions(secretFilePath(home)) == {fpUserRead, fpUserWrite}

  test "wrong password raises SecretError":
    let home = tempHome("wrongpw")
    defer: removeDir(home)
    storeGithubToken(home, "gho_test123", "right password")
    expect SecretError:
      discard loadGithubToken(home, "wrong password")

  test "missing file raises SecretError":
    let home = tempHome("missing")
    defer: removeDir(home)
    expect SecretError:
      discard loadGithubToken(home, "whatever")

  test "corrupt file raises SecretError":
    let home = tempHome("corrupt")
    defer: removeDir(home)
    writeFile(secretFilePath(home), "this is not json")
    expect SecretError:
      discard loadGithubToken(home, "whatever")

  test "empty token or password are rejected":
    let home = tempHome("emptyvals")
    defer: removeDir(home)
    expect SecretError:
      storeGithubToken(home, "", "some password")
    expect SecretError:
      storeGithubToken(home, "gho_test123", "")

  test "overwrite rotates the token":
    let home = tempHome("rotate")
    defer: removeDir(home)
    storeGithubToken(home, "gho_first", "pw one")
    storeGithubToken(home, "gho_second", "pw two")
    expect SecretError:
      discard loadGithubToken(home, "pw one")
    check loadGithubToken(home, "pw two") == "gho_second"

  test "deleteSecretFile removes the secret":
    let home = tempHome("delete")
    defer: removeDir(home)
    storeGithubToken(home, "gho_test123", "some password")
    check hasSecretFile(home)
    deleteSecretFile(home)
    check not hasSecretFile(home)
