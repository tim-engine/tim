# import std/[unittest, os, strutils,
#   htmlparser, xmltree, strtabs, osproc, sequtils,
#   json, jsonutils]

# proc exec(x: openarray[string]): (string, int) =
#   execCmdEx(x.join(" "), options = {poEchoCmd, poUsePath, poStdErrToStdOut})

# proc getReadonlyData: string =
#   $(%*{
#     "global": {
#       "items": [1, 2, 3, 4, 5, 6]
#     },
#     "local": {}
#   })

# test "tim via cli":
#   # echo getReadonlyData()
#   echo exec(["tim", "src", "-t:html",
#     "tests/snippets/cli_data.timl", "--data:'" & getReadonlyData() & "'"])
