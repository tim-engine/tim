# Tim Engine — Ruby native extension showcase
require 'json'
require_relative '../build/Tim.bundle'

Tim.init("templates", "storage", __dir__)

data = {meta: {title: "Ruby Showcase"}}.to_json

puts "=== Index with layout ==="
puts Tim.render("index", data)

puts "=== Error standalone ==="
puts Tim.renderView("error", data)
