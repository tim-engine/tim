# Tim package manager — encrypted local secrets
#
# (c) 2026 George Lemon | MIT License
# Made by Humans from OpenPeeps
#
# Stores sensitive tokens (currently the GitHub token used by
# `tim publish`) encrypted at rest in `<root>/secret`, protected by a
# user password. Crypto: Argon2id key derivation + XChaCha20-Poly1305
# AEAD via nimcypher. File format (JSON, mode 0600):
#
#   {"v":1,"kdf":"argon2id","salt":hex,"nonce":hex,"mac":hex,"ct":hex}
#
# The ciphertext decrypts to `{"github_token":"..."}` so more entries can
# be added later without changing the format.

import std/[os, strutils]
import pkg/openparser/json
import pkg/nimcypher/[utils, secret, encrypt, password]

type SecretError* = object of CatchableError

const
  secretFileName* = "secret"
  secretPayloadVersion* = 1

proc secretFilePath*(rootPath: string): string =
  ## Absolute path of the encrypted secret file for a tim home directory.
  rootPath / secretFileName

proc hasSecretFile*(rootPath: string): bool =
  fileExists(secretFilePath(rootPath))

proc deleteSecretFile*(rootPath: string) =
  ## Remove the secret file when present (token rotation entry point).
  let p = secretFilePath(rootPath)
  if fileExists(p):
    removeFile(p)

proc hexToBytes(s: string): seq[byte] =
  ## Decode variable-length hex (ciphertext). Raises SecretError on malformed input.
  if s.len == 0 or s.len mod 2 != 0:
    raise newException(SecretError, "secret file is corrupt (bad hex length)")
  for i in countup(0, s.len - 2, 2):
    try:
      result.add(byte(parseHexInt(s[i .. i + 1])))
    except ValueError:
      raise newException(SecretError, "secret file is corrupt (bad hex data)")

proc secretDoc(path: string): JsonNode =
  try:
    result = parseJson(readFile(path))
  except CatchableError:
    raise newException(SecretError, "secret file is corrupt (unreadable JSON)")
  if result.kind != JObject:
    raise newException(SecretError, "secret file is corrupt (bad envelope)")

proc storeGithubToken*(rootPath, token, password: string) =
  ## Encrypt `token` under `password` and write the secret file with
  ## owner-only permissions. Overwrites any previous secret.
  if token.strip().len == 0:
    raise newException(SecretError, "cannot store an empty token")
  if password.len == 0:
    raise newException(SecretError, "cannot encrypt with an empty password")
  let salt = generateSalt()
  let key = deriveKeyFromPassword(password, salt)
  let payload = $(%*{"github_token": token})
  let sealed = seal(payload, key.data)
  let doc = %*{
    "v": secretPayloadVersion,
    "kdf": "argon2id",
    "salt": toHex(salt),
    "nonce": toHex(sealed.nonce),
    "mac": toHex(sealed.mac),
    "ct": toHex(sealed.cipherText)
  }
  if not dirExists(rootPath):
    createDir(rootPath)
  let p = secretFilePath(rootPath)
  writeFile(p, $doc)
  setFilePermissions(p, {fpUserRead, fpUserWrite})

proc loadGithubToken*(rootPath, password: string): string =
  ## Decrypt the secret file with `password` and return the stored token.
  ## Raises SecretError when the file is missing or corrupt, and
  ## SecretError("wrong password...") when the MAC does not verify.
  let p = secretFilePath(rootPath)
  if not fileExists(p):
    raise newException(SecretError,
      "no secret file at " & p & " — run `tim publish` once to set it up")
  let doc = secretDoc(p)
  if not doc.hasKey("v") or doc["v"].getInt != secretPayloadVersion:
    raise newException(SecretError, "secret file uses an unsupported version")
  for field in ["salt", "nonce", "mac", "ct"]:
    if not doc.hasKey(field) or doc[field].kind != JString:
      raise newException(SecretError, "secret file is corrupt (missing " & field & ")")
  let salt =
    try: fromHex[16, uint8](doc["salt"].getStr)
    except ValueError:
      raise newException(SecretError, "secret file is corrupt (bad salt)")
  let nonce =
    try: fromHex[24, uint8](doc["nonce"].getStr)
    except ValueError:
      raise newException(SecretError, "secret file is corrupt (bad nonce)")
  let mac =
    try: fromHex[16, uint8](doc["mac"].getStr)
    except ValueError:
      raise newException(SecretError, "secret file is corrupt (bad mac)")
  let ct = hexToBytes(doc["ct"].getStr)
  let key = deriveKeyFromPassword(password, salt)
  let plain =
    try: unseal(SealedMessage(nonce: nonce, mac: mac, cipherText: ct), key.data)
    except ValueError:
      raise newException(SecretError, "wrong password for " & p)
  var payload: JsonNode
  try:
    payload = parseJson(toString(plain))
  except CatchableError:
    raise newException(SecretError, "secret file is corrupt (bad payload)")
  if not payload.hasKey("github_token") or payload["github_token"].kind != JString:
    raise newException(SecretError, "secret file holds no github_token")
  result = payload["github_token"].getStr
  if result.len == 0:
    raise newException(SecretError, "secret file holds an empty github_token")
