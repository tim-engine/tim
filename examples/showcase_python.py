# Tim Engine — Python native extension showcase
import sys, json, os

sys.path.insert(0, os.path.dirname(__file__) + '/../build')
import tim

d = os.path.dirname(__file__)
tim.init("templates", "storage", d)

data = json.dumps({"meta": {"title": "Python Showcase"}})

print("=== Index with layout ===")
print(tim.render("index", data))

print("=== Error standalone ===")
print(tim.renderView("error", data))
