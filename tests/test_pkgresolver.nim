import std/[unittest, os, options]

include ../src/tim/engine/transformers

from ../src/tim/meta/initializer import resolveTimPackageDir, resolvePkgImport

proc makePkg(root, name, version: string, files: openArray[string]) =
  ## Create `root/packages/<name>/<version>/` with `src/` files.
  for f in files:
    let p = root / "packages" / name / version / "src" / f
    createDir(p.parentDir())
    writeFile(p, "// fixture")

proc makeDev(root, name: string, files: openArray[string]) =
  ## Create `root/develop/<name>/` with `src/` files (editable install).
  for f in files:
    let p = root / "develop" / name / "src" / f
    createDir(p.parentDir())
    writeFile(p, "// fixture")

suite "pkg resolver":
  var root = ""

  setup:
    root = getTempDir() / "tim-pkgresolver-test"
    removeDir(root)
    createDir(root)

  teardown:
    removeDir(root)

  test "develop install wins over registry versions":
    makeDev(root, "mail", ["mail.timl"])
    makePkg(root, "mail", "9.9.9", ["mail.timl"])
    check resolveTimPackageDir("mail", root) == root / "develop" / "mail"
    check resolvePkgImport("pkg/mail", root).get() ==
      normalizedPath(root / "develop" / "mail" / "src" / "mail.timl")

  test "highest semver wins (not lexicographic)":
    makePkg(root, "ui", "0.2.0", ["ui.timl"])
    makePkg(root, "ui", "0.10.0", ["ui.timl"])
    makePkg(root, "ui", "0.9.9", ["ui.timl"])
    check resolveTimPackageDir("ui", root) ==
      root / "packages" / "ui" / "0.10.0"

  test "main entry and deep paths":
    makePkg(root, "widgets", "1.0.0", ["widgets.timl", "grid.timl"])
    check resolvePkgImport("pkg/widgets", root).get() ==
      normalizedPath(root / "packages" / "widgets" / "1.0.0" / "src" / "widgets.timl")
    check resolvePkgImport("pkg/widgets/grid", root).get() ==
      normalizedPath(root / "packages" / "widgets" / "1.0.0" / "src" / "grid.timl")
    check resolvePkgImport("pkg/widgets/grid.timl", root).get() ==
      normalizedPath(root / "packages" / "widgets" / "1.0.0" / "src" / "grid.timl")

  test "HEAD fallback and unknown packages":
    makePkg(root, "legacy", "HEAD", ["legacy.timl"])
    check resolveTimPackageDir("legacy", root) ==
      root / "packages" / "legacy" / "HEAD"
    check resolveTimPackageDir("nope", root) == ""
    check resolvePkgImport("pkg/nope", root).isNone
    check resolvePkgImport("pkg/widgets/missing", root).isNone
    check resolvePkgImport("pkg/", root).isNone
