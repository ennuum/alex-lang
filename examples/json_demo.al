# Démo du module json (ALEX pur) : ./alex run examples/json_demo.al
use json

texte := "{\"projet\": \"Alex\", \"version\": 1.5, \"modules\": [\"json\", \"channel\"], \"actif\": true, \"licence\": null}"
cfg := json.parse(texte)
print(cfg["projet"], cfg["version"], cfg["modules"][0])

cfg["modules"] = [cfg["modules"][0], cfg["modules"][1], "complex"]
cfg["note"] = "accentué : é à ñ — « ok »"
print(json.stringify(cfg))
print(json.pretty(cfg))

try:
    json.parse("{\"a\": [1, 2,\n  oops]}")
catch e:
    print(e)
