-- Tim Engine — Lua native extension showcase
package.cpath = package.cpath .. ";./build/?.so;../build/?.so"
local tim = require("tim")

tim.init("templates", "storage", ".")

local data = '{"meta":{"title":"Lua Showcase"}}'

print("=== Index with layout ===")
print(tim.render("index", data))

print("=== Error standalone ===")
print(tim.renderView("error", data))
