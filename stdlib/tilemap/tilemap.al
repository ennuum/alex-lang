# ALEX STANDARD LIBRARY — tilemap
#
# Cartes à tuiles 2D et import des cartes de l'éditeur Tiled (.tmj / .json et .tmx, jeux de tuiles externes .tsj /
# .tsx) : couches de tuiles (CSV, base64, zlib, gzip, cartes infinies par blocs), couches d'objets (rectangles,
# points, ellipses, polygones, polylignes, tuiles-objets), couches d'images, groupes, propriétés typées, tuiles
# animées, retournements (horizontal, vertical, diagonal). Requêtes de jeu : tuile sous un point, propriétés,
# rectangles solides fusionnés, déplacement avec collisions (plates-formes). Rendu GPU par blocs statiques
# (gl.render.QuadBuffer, un appel de dessin par bloc et par jeu de tuiles) ou sur un canvas ui.
#
#   use tilemap
#   use gl.render as gr
#   carte := tilemap.load("niveau1.tmj")                    # ou .tmx
#   rendu := tilemap.MapRenderer(carte, (chemin) => gr.load_texture(chemin, "nearest", "clamp", false))
#   sol := carte.layer("sol")
#   murs := carte.solid_rects(sol)                          # [[x, y, l, h], ...] fusionnés
#   r := carte.move(sol, [x, y, 14, 30], vx * dt, vy * dt)  # {"rect", "hit_x", "hit_y", "on_ground"}
#   for o in carte.objects("ennemi"):
#       creer_ennemi(o["x"], o["y"], o["properties"])
#   # à chaque image (batch : gl.render.SpriteBatch commencé avec la caméra) :
#   rendu.update(dt)                                         # tuiles animées
#   rendu.draw(batch, [cam_x, cam_y, largeur, hauteur])     # couches visibles, blocs dans la vue seulement
#
# REPÈRE : pixels de la carte, origine en haut à gauche, Y vers le bas (comme Tiled). Une tuile (tx, ty) occupe
#   [tx * tilewidth, ty * tileheight] en orthogonal ; les images plus hautes que la cellule sont alignées en bas.
# ORIENTATIONS dessinées : orthogonal et isométrique (losanges). Décalée / hexagonale : données lues, dessin refusé.
# GID : identifiant global ; bits de poids fort = retournements (FLIP_H, FLIP_V, FLIP_D) ; 0 = case vide.
#
# Erreurs : IoError (fichier), ValueError (format non pris en charge), KeyError (couche inconnue).

from core use len, type, to_int
from builtins use int, float
from collections use append
use math
use json
use xml
use io
use path as _path
use string as _s
use crypto as _crypto
use office.compression as _z
use gl.render as _gr
use ui.image as _uimage
use ui.canvas as _cv

const FLIP_H := 0x80000000
const FLIP_V := 0x40000000
const FLIP_D := 0x20000000
const GID_MASK := 0x0FFFFFFF
const CHUNK := 32

# ---------------------------------------------------------------------------------------------------------------------
# Jeux de tuiles
# ---------------------------------------------------------------------------------------------------------------------

class Tileset:
    func init(d, firstgid, base_dir):
        self.firstgid = firstgid
        self.name = d["name"] if "name" in d else ""
        self.tilewidth = d["tilewidth"]
        self.tileheight = d["tileheight"]
        self.spacing = d["spacing"] if "spacing" in d else 0
        self.margin = d["margin"] if "margin" in d else 0
        self.tilecount = d["tilecount"] if "tilecount" in d else 0
        self.columns = d["columns"] if "columns" in d else 0
        self.image = null
        self.imagewidth = d["imagewidth"] if "imagewidth" in d else 0
        self.imageheight = d["imageheight"] if "imageheight" in d else 0
        if "image" in d and d["image"] != null and d["image"] != "":
            self.image = _resolve(base_dir, d["image"])
        off := d["tileoffset"] if "tileoffset" in d else null
        self.offset = [off["x"], off["y"]] if off != null else [0, 0]
        self.properties = _props(d["properties"] if "properties" in d else null)
        self.tiles = {}                    # id local -> {"properties", "animation", "objects", "image", "type"}
        if "tiles" in d:
            for t in d["tiles"]:
                info := {"properties": _props(t["properties"] if "properties" in t else null), "animation": null,
                         "objects": [], "type": t["type"] if "type" in t else (t["class"] if "class" in t else "")}
                if "animation" in t and t["animation"] != null and len(t["animation"]) > 0:
                    info["animation"] = [[a["tileid"], a["duration"] / 1000.0] for a in t["animation"]]
                if "objectgroup" in t and t["objectgroup"] != null and "objects" in t["objectgroup"]:
                    info["objects"] = [_object(o, null) for o in t["objectgroup"]["objects"]]
                if "image" in t:
                    info["image"] = _resolve(base_dir, t["image"])
                    info["width"] = t["imagewidth"] if "imagewidth" in t else 0
                    info["height"] = t["imageheight"] if "imageheight" in t else 0
                self.tiles[t["id"]] = info
        if self.columns == 0 and self.imagewidth > 0:
            self.columns = to_int((self.imagewidth - 2 * self.margin + self.spacing) / (self.tilewidth + self.spacing))
        self.texture = null

    func contains(gid):
        return gid >= self.firstgid and gid < self.firstgid + (self.tilecount if self.tilecount > 0 else 1 << 27)

    # Zone source [x, y, l, h] de la tuile d'id local `lid` dans l'image du jeu de tuiles.
    func source_rect(lid):
        c := self.columns if self.columns > 0 else 1
        return [self.margin + (lid % c) * (self.tilewidth + self.spacing),
                self.margin + to_int(lid / c) * (self.tileheight + self.spacing), self.tilewidth, self.tileheight]

    func tile_properties(lid):
        if lid in self.tiles:
            return self.tiles[lid]["properties"]
        return {}

# ---------------------------------------------------------------------------------------------------------------------
# Couches
# ---------------------------------------------------------------------------------------------------------------------

class TileLayer:
    func init(name, width, height, data):
        self.kind = "tile"
        self.name = name
        self.width = width
        self.height = height
        self.data = data                   # gids bruts (avec bits de retournement), ligne par ligne
        self.visible = true
        self.opacity = 1.0
        self.tint = [1.0, 1.0, 1.0, 1.0]
        self.offset = [0.0, 0.0]
        self.parallax = [1.0, 1.0]
        self.properties = {}
        self.origin = [0, 0]               # case de départ (cartes infinies)
        self.version = 0                   # incrémenté à chaque modification (reconstruction du rendu)

    func in_bounds(tx, ty):
        x := tx - self.origin[0]
        y := ty - self.origin[1]
        return x >= 0 and y >= 0 and x < self.width and y < self.height

    # GID brut de la case (0 hors de la couche).
    func raw(tx, ty):
        x := tx - self.origin[0]
        y := ty - self.origin[1]
        if x < 0 or y < 0 or x >= self.width or y >= self.height:
            return 0
        return self.data[y * self.width + x]

    # GID sans les bits de retournement.
    func gid(tx, ty):
        return self.raw(tx, ty) & GID_MASK

    func set(tx, ty, gid, flags=0):
        x := tx - self.origin[0]
        y := ty - self.origin[1]
        if x < 0 or y < 0 or x >= self.width or y >= self.height:
            raise("ValueError", "TileLayer.set : case hors de la couche (" + str(tx) + ", " + str(ty) + ")")
        self.data[y * self.width + x] = gid | flags
        self.version += 1

class ObjectLayer:
    func init(name, objects):
        self.kind = "object"
        self.name = name
        self.objects = objects
        self.visible = true
        self.opacity = 1.0
        self.offset = [0.0, 0.0]
        self.properties = {}

class ImageLayer:
    func init(name, image):
        self.kind = "image"
        self.name = name
        self.image = image
        self.visible = true
        self.opacity = 1.0
        self.offset = [0.0, 0.0]
        self.parallax = [1.0, 1.0]
        self.properties = {}
        self.texture = null

# ---------------------------------------------------------------------------------------------------------------------
# Carte
# ---------------------------------------------------------------------------------------------------------------------

class TileMap:
    func init(width, height, tilewidth, tileheight, orientation="orthogonal"):
        self.width = width
        self.height = height
        self.tilewidth = tilewidth
        self.tileheight = tileheight
        self.orientation = orientation
        self.tilesets = []
        self.layers = []                   # couches à plat (groupes dépliés, décalages cumulés)
        self.properties = {}
        self.background = null
        self.path = null

    func layer(name):
        for l in self.layers:
            if l.name == name:
                return l
        raise("KeyError", "tilemap : couche inconnue '" + str(name) + "'")

    func has_layer(name):
        for l in self.layers:
            if l.name == name:
                return true
        return false

    func tile_layers():
        return [l for l in self.layers if l.kind == "tile"]

    # Nouvelle couche de tuiles vide (cartes générées par programme).
    func add_tile_layer(name):
        l := TileLayer(name, self.width, self.height, [0 for k in 0..(self.width * self.height)])
        append(self.layers, l)
        return l

    func add_tileset(ts):
        append(self.tilesets, ts)
        return ts

    # [jeu de tuiles, id local] d'un GID (bits de retournement ignorés), ou null.
    func tileset_of(gid):
        g := gid & GID_MASK
        if g == 0:
            return null
        best := null
        for ts in self.tilesets:
            if ts.firstgid <= g and (best == null or ts.firstgid > best.firstgid):
                best = ts
        if best == null:
            return null
        return [best, g - best.firstgid]

    # Propriétés d'une tuile (celles du jeu de tuiles pour cet id).
    func tile_properties(gid):
        t := self.tileset_of(gid)
        if t == null:
            return {}
        return t[0].tile_properties(t[1])

    # ---- coordonnées (orthogonal) ----
    func world_to_tile(x, y):
        return [to_int(math.floor(x / self.tilewidth)), to_int(math.floor(y / self.tileheight))]

    func tile_to_world(tx, ty):
        return [tx * self.tilewidth, ty * self.tileheight]

    # GID sous le point (x, y) du monde.
    func gid_at(layer, x, y):
        t := self.world_to_tile(x, y)
        return layer.gid(t[0], t[1])

    # ---- objets ----
    # Objets de toutes les couches d'objets, filtrés par type / classe (ou tous).
    func objects(kind=null):
        out := []
        for l in self.layers:
            if l.kind == "object":
                for o in l.objects:
                    if kind == null or o["type"] == kind:
                        append(out, o)
        return out

    func object_named(name):
        for o in self.objects():
            if o["name"] == name:
                return o
        return null

    # ---- collisions ----
    # Case solide ? Par défaut : toute tuile non vide ; `solid` : fn(gid, propriétés) -> bool.
    func _is_solid(layer, tx, ty, solid):
        g := layer.gid(tx, ty)
        if g == 0:
            return false
        if solid == null:
            return true
        return solid(g, self.tile_properties(g))

    # Rectangles [x, y, l, h] (pixels) couvrant les cases solides, fusionnés en lignes puis en blocs.
    func solid_rects(layer, solid=null):
        runs := {}
        out := []
        ty := layer.origin[1]
        while ty < layer.origin[1] + layer.height:
            tx := layer.origin[0]
            row := []
            while tx < layer.origin[0] + layer.width:
                if self._is_solid(layer, tx, ty, solid):
                    start := tx
                    while tx < layer.origin[0] + layer.width and self._is_solid(layer, tx, ty, solid):
                        tx += 1
                    append(row, [start, tx - start])
                else:
                    tx += 1
            nruns := {}
            for r in row:
                key := str(r[0]) + ":" + str(r[1])
                if key in runs:
                    runs[key][3] += self.tileheight
                    nruns[key] = runs[key]
                else:
                    rect := [r[0] * self.tilewidth, ty * self.tileheight, r[1] * self.tilewidth, self.tileheight]
                    append(out, rect)
                    nruns[key] = rect
            runs = nruns
            ty += 1
        return out

    # Le rectangle [x, y, l, h] touche-t-il une case solide ?
    func overlaps(layer, rect, solid=null):
        a := self.world_to_tile(rect[0], rect[1])
        b := self.world_to_tile(rect[0] + rect[2] - 0.001, rect[1] + rect[3] - 0.001)
        ty := a[1]
        while ty <= b[1]:
            tx := a[0]
            while tx <= b[0]:
                if self._is_solid(layer, tx, ty, solid):
                    return true
                tx += 1
            ty += 1
        return false

    # Déplace le rectangle de (dx, dy) en s'arrêtant contre les cases solides, axe X puis axe Y (jeux de
    # plates-formes, vue de dessus). Rend {"rect", "hit_x", "hit_y", "on_ground", "on_ceiling"}.
    func move(layer, rect, dx, dy, solid=null):
        r := [rect[0] * 1.0, rect[1] * 1.0, rect[2], rect[3]]
        hit_x := false
        hit_y := false
        ground := false
        ceiling := false
        # pas de déplacement plus grands qu'une demi-tuile : pas de traversée de murs fins
        steps := to_int(math.ceil(math.max(math.abs(dx) / (self.tilewidth * 0.5), math.abs(dy) / (self.tileheight * 0.5))))
        if steps < 1:
            steps = 1
        sx := dx / steps
        sy := dy / steps
        k := 0
        while k < steps:
            if sx != 0.0 and not hit_x:
                r[0] += sx
                if self.overlaps(layer, r, solid):
                    hit_x = true
                    if sx > 0:
                        t := self.world_to_tile(r[0] + r[2] - 0.001, r[1])
                        r[0] = t[0] * self.tilewidth - r[2]
                    else:
                        t := self.world_to_tile(r[0], r[1])
                        r[0] = (t[0] + 1) * self.tilewidth * 1.0
            if sy != 0.0 and not hit_y:
                r[1] += sy
                if self.overlaps(layer, r, solid):
                    hit_y = true
                    if sy > 0:
                        t := self.world_to_tile(r[0], r[1] + r[3] - 0.001)
                        r[1] = t[1] * self.tileheight - r[3]
                        ground = true
                    else:
                        t := self.world_to_tile(r[0], r[1])
                        r[1] = (t[1] + 1) * self.tileheight * 1.0
                        ceiling = true
            k += 1
        if not ground:
            probe := [r[0], r[1] + 1.0, r[2], r[3]]
            ground = self.overlaps(layer, probe, solid) and dy >= 0
        return {"rect": r, "hit_x": hit_x, "hit_y": hit_y, "on_ground": ground, "on_ceiling": ceiling}

    # Charge les textures des jeux de tuiles et des couches d'images : loader(chemin) -> texture.
    func load_textures(loader):
        for ts in self.tilesets:
            if ts.image != null and ts.texture == null:
                ts.texture = loader(ts.image)
        for l in self.layers:
            if l.kind == "image" and l.image != null and l.texture == null:
                l.texture = loader(l.image)

# ---------------------------------------------------------------------------------------------------------------------
# Lecture (Tiled JSON ; TMX converti dans la même forme)
# ---------------------------------------------------------------------------------------------------------------------

func _resolve(base_dir, p):
    if p == null or p == "":
        return p
    if base_dir == null or base_dir == "" or _path.is_absolute(p):
        return p
    return _path.normalize(_path.join(base_dir, p))

func _props(lst):
    out := {}
    if lst == null:
        return out
    if type(lst) == "dict":
        return lst
    for p in lst:
        out[p["name"]] = p["value"] if "value" in p else null
    return out

func _object(o, base_dir):
    ob := {"id": o["id"] if "id" in o else 0, "name": o["name"] if "name" in o else "",
           "type": o["type"] if "type" in o and o["type"] != "" else (o["class"] if "class" in o else ""),
           "x": o["x"] if "x" in o else 0, "y": o["y"] if "y" in o else 0,
           "width": o["width"] if "width" in o else 0, "height": o["height"] if "height" in o else 0,
           "rotation": o["rotation"] if "rotation" in o else 0, "visible": o["visible"] if "visible" in o else true,
           "properties": _props(o["properties"] if "properties" in o else null), "shape": "rectangle",
           "gid": 0, "points": null, "text": null}
    if "gid" in o and o["gid"] != null and o["gid"] != 0:
        ob["gid"] = o["gid"]
        ob["shape"] = "tile"
    if "ellipse" in o and o["ellipse"]:
        ob["shape"] = "ellipse"
    if "point" in o and o["point"]:
        ob["shape"] = "point"
    if "polygon" in o and o["polygon"] != null:
        ob["shape"] = "polygon"
        ob["points"] = [[p["x"], p["y"]] for p in o["polygon"]]
    if "polyline" in o and o["polyline"] != null:
        ob["shape"] = "polyline"
        ob["points"] = [[p["x"], p["y"]] for p in o["polyline"]]
    if "text" in o and o["text"] != null:
        ob["shape"] = "text"
        ob["text"] = o["text"]
    return ob

# Octets little-endian -> GIDs 32 bits.
func _u32s(bytes):
    out := []
    k := 0
    n := len(bytes)
    while k + 3 < n:
        append(out, bytes[k] | (bytes[k + 1] << 8) | (bytes[k + 2] << 16) | (bytes[k + 3] << 24))
        k += 4
    return out

func _decode_data(data, encoding, compression):
    if type(data) == "list":
        return data
    if encoding == "base64":
        b := _crypto.base64_decode(_s.trim(data))
        if compression == "zlib":
            b = _z.decompress(b, "zlib")
        elif compression == "gzip":
            b = _z.decompress(b, "gzip")
        elif compression != null and compression != "":
            raise("ValueError", "tilemap : compression '" + compression + "' non prise en charge (zlib, gzip)")
        return _u32s(b)
    if encoding == "csv":
        out := []
        for part in _s.split(data, ","):
            t := _s.trim(part)
            if t != "":
                append(out, _parse_uint(t))
        return out
    raise("ValueError", "tilemap : encodage de couche inconnu '" + str(encoding) + "'")

func _parse_uint(t):
    v := 0
    for ch in t:
        v = v * 10 + (_s.ord(ch) - 48)
    return v

func _tile_layer(d, mapw, maph):
    enc := d["encoding"] if "encoding" in d else null
    comp := d["compression"] if "compression" in d else null
    if "chunks" in d and d["chunks"] != null:
        # carte infinie : couche finie couvrant tous les blocs
        minx := 1 << 30
        miny := 1 << 30
        maxx := 0 - (1 << 30)
        maxy := 0 - (1 << 30)
        for c in d["chunks"]:
            minx = math.min(minx, c["x"])
            miny = math.min(miny, c["y"])
            maxx = math.max(maxx, c["x"] + c["width"])
            maxy = math.max(maxy, c["y"] + c["height"])
        w := maxx - minx
        h := maxy - miny
        data := [0 for k in 0..(w * h)]
        for c in d["chunks"]:
            cd := _decode_data(c["data"], enc, comp)
            y := 0
            while y < c["height"]:
                x := 0
                while x < c["width"]:
                    data[(c["y"] - miny + y) * w + (c["x"] - minx + x)] = cd[y * c["width"] + x]
                    x += 1
                y += 1
        l := TileLayer(d["name"], w, h, data)
        l.origin = [minx, miny]
        return l
    w := d["width"] if "width" in d else mapw
    h := d["height"] if "height" in d else maph
    data := _decode_data(d["data"], enc, comp)
    if len(data) != w * h:
        raise("ValueError", "tilemap : couche '" + d["name"] + "' : " + str(w * h) + " cases attendues, " + str(len(data)) + " lues")
    return TileLayer(d["name"], w, h, data)

func _layers(m, lst, base_dir, ox, oy, opacity, visible):
    for d in lst:
        t := d["type"]
        lox := ox + (d["offsetx"] if "offsetx" in d else 0)
        loy := oy + (d["offsety"] if "offsety" in d else 0)
        op := opacity * (d["opacity"] if "opacity" in d else 1.0)
        vis := visible and (d["visible"] if "visible" in d else true)
        l := null
        if t == "tilelayer":
            l = _tile_layer(d, m.width, m.height)
            if "tintcolor" in d:
                l.tint = _color(d["tintcolor"])
        elif t == "objectgroup":
            l = ObjectLayer(d["name"], [_object(o, base_dir) for o in (d["objects"] if "objects" in d else [])])
        elif t == "imagelayer":
            l = ImageLayer(d["name"], _resolve(base_dir, d["image"] if "image" in d else null))
        elif t == "group":
            _layers(m, d["layers"] if "layers" in d else [], base_dir, lox, loy, op, vis)
        if l != null:
            l.offset = [lox * 1.0, loy * 1.0]
            l.opacity = op
            l.visible = vis
            l.properties = _props(d["properties"] if "properties" in d else null)
            if "parallaxx" in d or "parallaxy" in d:
                try:
                    l.parallax = [d["parallaxx"] if "parallaxx" in d else 1.0, d["parallaxy"] if "parallaxy" in d else 1.0]
                catch e:
                    pass
            append(m.layers, l)

# Couleur Tiled "#aarrggbb" ou "#rrggbb" -> [r, g, b, a] (0..1).
func _color(c):
    if c == null:
        return null
    h := _s.lower(_s.replace(c, "#", ""))
    v := []
    k := 0
    while k + 1 < len(h):
        append(v, _hex(h[k:k + 2]) / 255.0)
        k += 2
    if len(v) == 4:
        return [v[1], v[2], v[3], v[0]]
    if len(v) == 3:
        return [v[0], v[1], v[2], 1.0]
    return [1.0, 1.0, 1.0, 1.0]

func _hex(t):
    v := 0
    for ch in t:
        c := _s.ord(ch)
        d := c - 48 if c <= 57 else c - 87
        v = v * 16 + d
    return v

# Carte depuis un dict au format Tiled JSON.
func from_dict(d, base_dir=""):
    m := TileMap(d["width"], d["height"], d["tilewidth"], d["tileheight"], d["orientation"] if "orientation" in d else "orthogonal")
    m.properties = _props(d["properties"] if "properties" in d else null)
    if "backgroundcolor" in d:
        m.background = _color(d["backgroundcolor"])
    for t in d["tilesets"]:
        if "source" in t:
            src := _resolve(base_dir, t["source"])
            td := _load_tileset_file(src)
            append(m.tilesets, Tileset(td, t["firstgid"], _path.dirname(src)))
        else:
            append(m.tilesets, Tileset(t, t["firstgid"], base_dir))
    _layers(m, d["layers"], base_dir, 0, 0, 1.0, true)
    return m

func _load_tileset_file(p):
    low := _s.lower(p)
    if _s.ends_with(low, ".tsx"):
        return _tsx_dict(xml.parse(io.read_file(p)), _path.dirname(p))
    return json.parse(io.read_file(p))

# Charge une carte Tiled : .tmj / .json (JSON) ou .tmx (XML).
func load(p):
    low := _s.lower(p)
    base := _path.dirname(p)
    m := null
    if _s.ends_with(low, ".tmx"):
        m = from_dict(_tmx_dict(xml.parse(io.read_file(p))), base)
    else:
        m = from_dict(json.parse(io.read_file(p)), base)
    m.path = p
    return m

# ---- TMX -> forme JSON ----

func _num(v):
    if v == null:
        return null
    t := _s.trim(v)
    if _s.contains(t, ".") or _s.contains(t, "e"):
        return float(t)
    return int(t)

func _a(node, name, default=null):
    v := xml.attr(node, name)
    if v == null:
        return default
    return v

func _an(node, name, default=null):
    v := xml.attr(node, name)
    if v == null:
        return default
    return _num(v)

func _tmx_props(node):
    p := xml.find(node, "properties")
    if p == null:
        return []
    out := []
    for e in xml.children(p, "property"):
        t := _a(e, "type", "string")
        v := _a(e, "value")
        if v == null:
            v = xml.text(e)
        if t == "int" or t == "object":
            v = int(v)
        elif t == "float":
            v = float(v)
        elif t == "bool":
            v = v == "true"
        append(out, {"name": _a(e, "name"), "type": t, "value": v})
    return out

func _tsx_dict(node, base):
    d := {"name": _a(node, "name", ""), "tilewidth": _an(node, "tilewidth"), "tileheight": _an(node, "tileheight"),
          "spacing": _an(node, "spacing", 0), "margin": _an(node, "margin", 0), "tilecount": _an(node, "tilecount", 0),
          "columns": _an(node, "columns", 0), "properties": _tmx_props(node), "tiles": []}
    img := xml.find(node, "image")
    if img != null:
        d["image"] = _a(img, "source")
        d["imagewidth"] = _an(img, "width", 0)
        d["imageheight"] = _an(img, "height", 0)
    off := xml.find(node, "tileoffset")
    if off != null:
        d["tileoffset"] = {"x": _an(off, "x", 0), "y": _an(off, "y", 0)}
    for t in xml.children(node, "tile"):
        td := {"id": _an(t, "id"), "properties": _tmx_props(t)}
        if _a(t, "type") != null:
            td["type"] = _a(t, "type")
        if _a(t, "class") != null:
            td["class"] = _a(t, "class")
        an := xml.find(t, "animation")
        if an != null:
            td["animation"] = [{"tileid": _an(f, "tileid"), "duration": _an(f, "duration")} for f in xml.children(an, "frame")]
        og := xml.find(t, "objectgroup")
        if og != null:
            td["objectgroup"] = {"objects": [_tmx_object(o) for o in xml.children(og, "object")]}
        ti := xml.find(t, "image")
        if ti != null:
            td["image"] = _a(ti, "source")
            td["imagewidth"] = _an(ti, "width", 0)
            td["imageheight"] = _an(ti, "height", 0)
        append(d["tiles"], td)
    return d

func _pts(t):
    out := []
    for pair in _s.split(_s.trim(t), " "):
        if pair != "":
            xy := _s.split(pair, ",")
            append(out, {"x": float(xy[0]), "y": float(xy[1])})
    return out

func _tmx_object(o):
    d := {"id": _an(o, "id", 0), "name": _a(o, "name", ""), "type": _a(o, "type", _a(o, "class", "")),
          "x": _an(o, "x", 0), "y": _an(o, "y", 0), "width": _an(o, "width", 0), "height": _an(o, "height", 0),
          "rotation": _an(o, "rotation", 0), "visible": _a(o, "visible", "1") != "0", "properties": _tmx_props(o)}
    if _a(o, "gid") != null:
        d["gid"] = _an(o, "gid")
    if xml.find(o, "ellipse") != null:
        d["ellipse"] = true
    if xml.find(o, "point") != null:
        d["point"] = true
    pg := xml.find(o, "polygon")
    if pg != null:
        d["polygon"] = _pts(_a(pg, "points", ""))
    pl := xml.find(o, "polyline")
    if pl != null:
        d["polyline"] = _pts(_a(pl, "points", ""))
    tx := xml.find(o, "text")
    if tx != null:
        d["text"] = {"text": xml.text(tx)}
    return d

func _tmx_data(dn):
    enc := _a(dn, "encoding")
    comp := _a(dn, "compression")
    tiles := xml.children(dn, "tile")
    if enc == null:
        return [[_an(t, "gid", 0) for t in tiles], null, null]
    return [xml.text(dn), enc, comp]

func _tmx_layers(node):
    out := []
    for c in node["children"]:
        if type(c) != "dict":
            continue
        tag := c["tag"]
        base := {"name": _a(c, "name", ""), "opacity": _an(c, "opacity", 1.0), "visible": _a(c, "visible", "1") != "0",
                 "offsetx": _an(c, "offsetx", 0), "offsety": _an(c, "offsety", 0), "properties": _tmx_props(c)}
        if _a(c, "parallaxx") != null:
            base["parallaxx"] = _an(c, "parallaxx")
        if _a(c, "parallaxy") != null:
            base["parallaxy"] = _an(c, "parallaxy")
        if _a(c, "tintcolor") != null:
            base["tintcolor"] = _a(c, "tintcolor")
        if tag == "layer":
            base["type"] = "tilelayer"
            base["width"] = _an(c, "width")
            base["height"] = _an(c, "height")
            dn := xml.find(c, "data")
            chunks := xml.children(dn, "chunk")
            if len(chunks) > 0:
                base["chunks"] = []
                for ch in chunks:
                    r := _tmx_data(ch)
                    append(base["chunks"], {"x": _an(ch, "x"), "y": _an(ch, "y"), "width": _an(ch, "width"),
                                            "height": _an(ch, "height"), "data": r[0]})
                    base["encoding"] = r[1]
                    base["compression"] = r[2]
            else:
                r := _tmx_data(dn)
                base["data"] = r[0]
                base["encoding"] = r[1]
                base["compression"] = r[2]
            append(out, base)
        elif tag == "objectgroup":
            base["type"] = "objectgroup"
            base["objects"] = [_tmx_object(o) for o in xml.children(c, "object")]
            append(out, base)
        elif tag == "imagelayer":
            base["type"] = "imagelayer"
            img := xml.find(c, "image")
            base["image"] = _a(img, "source") if img != null else null
            append(out, base)
        elif tag == "group":
            base["type"] = "group"
            base["layers"] = _tmx_layers(c)
            append(out, base)
    return out

func _tmx_dict(node):
    if node["tag"] != "map":
        raise("ValueError", "tilemap : élément racine <map> attendu")
    d := {"width": _an(node, "width"), "height": _an(node, "height"), "tilewidth": _an(node, "tilewidth"),
          "tileheight": _an(node, "tileheight"), "orientation": _a(node, "orientation", "orthogonal"),
          "properties": _tmx_props(node), "tilesets": [], "layers": _tmx_layers(node)}
    if _a(node, "backgroundcolor") != null:
        d["backgroundcolor"] = _a(node, "backgroundcolor")
    for t in xml.children(node, "tileset"):
        if _a(t, "source") != null:
            append(d["tilesets"], {"firstgid": _an(t, "firstgid"), "source": _a(t, "source")})
        else:
            td := _tsx_dict(t, "")
            td["firstgid"] = _an(t, "firstgid")
            append(d["tilesets"], td)
    return d

# ---------------------------------------------------------------------------------------------------------------------
# Rendu GPU (gl.render)
# ---------------------------------------------------------------------------------------------------------------------

# Bits de retournement d'un GID -> drapeaux de SpriteBatch.draw_tile (4 = H, 2 = V, 1 = diagonal).
func flip_flags(raw):
    f := 0
    if (raw & FLIP_H) != 0:
        f = f | 4
    if (raw & FLIP_V) != 0:
        f = f | 2
    if (raw & FLIP_D) != 0:
        f = f | 1
    return f

class MapRenderer:
    # loader(chemin) -> gl.render.Texture (par défaut : texture « nearest », sans répétition ni mipmaps).
    func init(tmap, loader=null):
        self.map = tmap
        ld := loader
        if ld == null:
            ld = (p) => _gr.load_texture(p, "nearest", "clamp", false)
        tmap.load_textures(ld)
        if tmap.orientation != "orthogonal" and tmap.orientation != "isometric":
            raise("ValueError", "tilemap : orientation '" + tmap.orientation + "' non dessinée (orthogonal, isometric)")
        self.time = 0.0
        self.chunks = {}                   # (couche, bloc) -> [version, {jeu de tuiles: QuadBuffer}, animées]
        self.uv = {}                       # gid -> [texture, u0, v0, u1, v1, l, h, ox, oy] (cache)

    func update(dt):
        self.time += dt

    func _tile(gid):
        if gid in self.uv:
            return self.uv[gid]
        t := self.map.tileset_of(gid)
        if t == null or t[0].texture == null:
            self.uv[gid] = null
            return null
        ts := t[0]
        r := ts.source_rect(t[1])
        tw := ts.texture.width * 1.0
        th := ts.texture.height * 1.0
        e := [ts.texture, r[0] / tw, r[1] / th, (r[0] + r[2]) / tw, (r[1] + r[3]) / th, r[2], r[3], ts.offset[0], ts.offset[1], ts, t[1]]
        self.uv[gid] = e
        return e

    # Position écran (haut gauche de l'image) de la case (tx, ty) pour une tuile de hauteur h.
    func _pos(tx, ty, w, h):
        m := self.map
        if m.orientation == "isometric":
            return [(tx - ty) * m.tilewidth * 0.5 + m.height * m.tilewidth * 0.5 - m.tilewidth * 0.5,
                    (tx + ty) * m.tileheight * 0.5 + m.tileheight - h]
        return [tx * m.tilewidth * 1.0, (ty + 1) * m.tileheight - h * 1.0]

    func _animated(e):
        return e[10] in e[9].tiles and e[9].tiles[e[10]]["animation"] != null

    func _build(layer, cx, cy):
        bufs := {}
        anim := []
        ty := cy * CHUNK
        while ty < cy * CHUNK + CHUNK and ty < layer.height:
            tx := cx * CHUNK
            while tx < cx * CHUNK + CHUNK and tx < layer.width:
                raw := layer.data[ty * layer.width + tx]
                g := raw & GID_MASK
                if g != 0:
                    e := self._tile(g)
                    if e != null:
                        wx := tx + layer.origin[0]
                        wy := ty + layer.origin[1]
                        if self._animated(e):
                            append(anim, [wx, wy, raw, e])
                        else:
                            p := self._pos(wx, wy, e[5], e[6])
                            tex := e[0]
                            key := e[9].firstgid
                            if not (key in bufs):
                                bufs[key] = _gr.QuadBuffer(tex)
                            bufs[key].add(p[0] + e[7], p[1] + e[8], e[5], e[6], e[1], e[2], e[3], e[4], flip_flags(raw))
                tx += 1
            ty += 1
        for k in bufs:
            bufs[k].upload()
        return [layer.version, bufs, anim]

    func _chunk(li, layer, cx, cy):
        key := str(li) + ":" + str(cx) + ":" + str(cy)
        c := self.chunks[key] if key in self.chunks else null
        if c == null or c[0] != layer.version:
            if c != null:
                for k in c[1]:
                    c[1][k].delete()
            c = self._build(layer, cx, cy)
            self.chunks[key] = c
        return c

    # Image courante d'une tuile animée -> entrée de cache de la tuile affichée.
    func _anim_entry(e):
        frames := e[9].tiles[e[10]]["animation"]
        total := 0.0
        for f in frames:
            total += f[1]
        t := self.time % total if total > 0 else 0.0
        for f in frames:
            if t < f[1]:
                return self._tile(e[9].firstgid + f[0])
            t -= f[1]
        return self._tile(e[9].firstgid + frames[0][0])

    # Dessine les couches visibles (ou la couche / la liste donnée) dans `batch` (SpriteBatch commencé).
    # view : [x, y, l, h] visible en pixels de la carte (sans couche de parallaxe : position de la caméra).
    func draw(batch, view=null, layers=null):
        m := self.map
        lst := m.layers
        if layers != null:
            lst = layers if type(layers) == "list" else [layers]
        li := 0
        for layer in m.layers:
            if layer in lst and layer.visible:
                if layer.kind == "tile":
                    self._draw_layer(batch, li, layer, view)
                elif layer.kind == "image" and layer.texture != null:
                    batch.draw(layer.texture, layer.offset[0], layer.offset[1], null, null, [1.0, 1.0, 1.0, layer.opacity])
            li += 1

    func _draw_layer(batch, li, layer, view):
        m := self.map
        ncx := to_int(math.ceil(layer.width / (CHUNK * 1.0)))
        ncy := to_int(math.ceil(layer.height / (CHUNK * 1.0)))
        cx0 := 0
        cy0 := 0
        cx1 := ncx - 1
        cy1 := ncy - 1
        if view != null and m.orientation == "orthogonal":
            px := view[0] * layer.parallax[0] - layer.offset[0]
            py := view[1] * layer.parallax[1] - layer.offset[1]
            cw := CHUNK * m.tilewidth
            ch := CHUNK * m.tileheight
            ox := layer.origin[0] * m.tilewidth
            oy := layer.origin[1] * m.tileheight
            cx0 = to_int(math.floor((px - ox - m.tilewidth) / cw))
            cy0 = to_int(math.floor((py - oy - m.tileheight) / ch))
            cx1 = to_int(math.floor((px - ox + view[2] + m.tilewidth) / cw))
            cy1 = to_int(math.floor((py - oy + view[3] + 4 * m.tileheight) / ch))
            if cx0 < 0:
                cx0 = 0
            if cy0 < 0:
                cy0 = 0
            if cx1 > ncx - 1:
                cx1 = ncx - 1
            if cy1 > ncy - 1:
                cy1 = ncy - 1
        shift := [layer.offset[0], layer.offset[1]]
        if view != null:
            shift = [layer.offset[0] + view[0] * (1.0 - layer.parallax[0]), layer.offset[1] + view[1] * (1.0 - layer.parallax[1])]
        moved := shift[0] != 0.0 or shift[1] != 0.0
        saved := batch.proj
        if moved:
            batch.flush()
            batch.proj = _translate(saved, shift[0], shift[1])
        col := [layer.tint[0], layer.tint[1], layer.tint[2], layer.tint[3] * layer.opacity]
        cy := cy0
        while cy <= cy1:
            cx := cx0
            while cx <= cx1:
                c := self._chunk(li, layer, cx, cy)
                for k in c[1]:
                    c[1][k].draw(batch)
                for a in c[2]:
                    e := self._anim_entry(a[3])
                    if e != null:
                        p := self._pos(a[0], a[1], e[5], e[6])
                        batch.draw_tile(e[0], p[0] + e[7], p[1] + e[8], e[5], e[6], e[1], e[2], e[3], e[4], flip_flags(a[2]), col)
                cx += 1
            cy += 1
        if moved:
            batch.flush()
            batch.proj = saved

    func delete():
        for k in self.chunks:
            for b in self.chunks[k][1]:
                self.chunks[k][1][b].delete()
        self.chunks = {}

# Projection décalée de (dx, dy) pixels (Mat4 en ordre colonne).
func _translate(p, dx, dy):
    q := [x for x in p]
    q[12] = p[0] * dx + p[4] * dy + p[12]
    q[13] = p[1] * dx + p[5] * dy + p[13]
    q[14] = p[2] * dx + p[6] * dy + p[14]
    q[15] = p[3] * dx + p[7] * dy + p[15]
    return q

# ---------------------------------------------------------------------------------------------------------------------
# Rendu sur un canvas ui (gui) : textures = images ui
# ---------------------------------------------------------------------------------------------------------------------

# Dessine les couches de tuiles visibles (orthogonal) sur un canvas ; loader(chemin) -> image ui (ui.image.load par
# défaut). view : [x, y, l, h] visible en pixels (la carte est dessinée décalée de -x, -y).
func draw_canvas(canvas, tmap, view=null, loader=null):
    ld := loader
    if ld == null:
        ld = (p) => _uiimage_load(p)
    tmap.load_textures(ld)
    vx := view[0] if view != null else 0
    vy := view[1] if view != null else 0
    vw := view[2] if view != null else tmap.width * tmap.tilewidth
    vh := view[3] if view != null else tmap.height * tmap.tileheight
    for layer in tmap.layers:
        if layer.kind == "tile" and layer.visible:
            a := tmap.world_to_tile(vx - layer.offset[0], vy - layer.offset[1])
            b := tmap.world_to_tile(vx - layer.offset[0] + vw, vy - layer.offset[1] + vh)
            ty := a[1] - 1
            while ty <= b[1] + 1:
                tx := a[0] - 1
                while tx <= b[0] + 1:
                    raw := layer.raw(tx, ty)
                    g := raw & GID_MASK
                    if g != 0:
                        t := tmap.tileset_of(g)
                        if t != null and t[0].texture != null:
                            r := t[0].source_rect(t[1])
                            x := tx * tmap.tilewidth + layer.offset[0] - vx
                            y := (ty + 1) * tmap.tileheight - r[3] + layer.offset[1] - vy
                            _canvas_tile(canvas, t[0].texture, r, x, y, raw, layer.opacity)
                    tx += 1
                ty += 1

func _uiimage_load(p):
    return _uimage.load(p)

func _canvas_tile(canvas, tex, r, x, y, raw, opacity):
    f := flip_flags(raw)
    if f == 0:
        _cv.image_region(canvas, tex, r[0], r[1], r[2], r[3], x, y, r[2], r[3], opacity)
        return
    # retournements par la transformation du canvas, autour du centre de la tuile
    a := 1.0
    b := 0.0
    c := 0.0
    d := 1.0
    if (f & 1) != 0:
        a = 0.0
        b = 1.0
        c = 1.0
        d = 0.0
    if (f & 4) != 0:
        a = 0.0 - a
        b = 0.0 - b
    if (f & 2) != 0:
        c = 0.0 - c
        d = 0.0 - d
    cx := x + r[2] * 0.5
    cy := y + r[3] * 0.5
    _cv.transform(canvas, {"m11": a, "m12": b, "m21": c, "m22": d, "dx": cx, "dy": cy})
    _cv.image_region(canvas, tex, r[0], r[1], r[2], r[3], 0.0 - r[2] * 0.5, 0.0 - r[3] * 0.5, r[2], r[3], opacity)
    _cv.reset_transform(canvas)
