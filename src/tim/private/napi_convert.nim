## Shared converters for the Tim Engine Node.js addon.
##
## Included from `src/tim.nim` under `napibuild` only, so the library
## itself is unaffected. NOTE: `import std/json except %*` is
## deliberate — denim exports its own `%*` macro for napi values, and
## using std/json's `%*` here would resolve to denim's and fail to
## compile. Build JsonNode values explicitly with `%`, `newJObject`,
## `newJArray` instead.

import std/json except `%*`

template jsParse(node: JsonNode): napi_value =
  ## Bridge a JsonNode to a live JS object via JSON.parse.
  napiCall("JSON.parse", [%* $node])
