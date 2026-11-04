# ALEX STANDARD LIBRARY — assets
#
# Gestionnaire de ressources de jeu : cache par chemin (une ressource chargée une seule fois, compteur de
# références), chargement SYNCHRONE ou EN ARRIÈRE-PLAN (fils parallèles : lecture et décodage hors du fil
# principal ; envoi à la carte graphique / au moteur audio sur le fil principal, dans un budget de temps par image),
# RECHARGEMENT À CHAUD (date de modification surveillée : la ressource est rechargée et ses rappels prévenus),
# chargeurs personnalisés.
#
#   use assets
#   am := assets.AssetManager("data")              # dossier racine (chemins relatifs)
#   am.audio = moteur_audio                        # audio.realtime.AudioEngine, pour les sons
#   herbe := am.get("textures/herbe.png")          # Asset synchrone : herbe.value = gl.render.Texture
#   niveau := am.load_async("niveaux/1.tmx")       # Asset en cours de chargement
#   am.watch(true)                                 # rechargement à chaud (toutes les 0,5 s)
#   while jeu:
#       am.update()                                # finalise les chargements (4 ms au plus par image)
#       if niveau.ready():
#           dessiner(niveau.value)
#   herbe.on_reload((a) => print("texture rechargée"))
#   am.release("textures/herbe.png")
#
# TYPES (d'après l'extension, ou `kind`) : "texture" (png, jpg, jpeg, bmp, ppm, pgm, pnm, dds, ktx2),
#   "sound" (wav, ogg), "model" (gltf, glb : animation.Model), "mesh" (obj), "tilemap" (tmx, tmj),
#   "atlas" (json TexturePacker / Aseprite, avec `options["texture"]`), "json", "text", "bytes".
# EN ARRIÈRE-PLAN : tout le travail lourd se fait dans un fil : décodage PNG / BMP / PNM / JPEG, lecture DDS / KTX2,
#   décodage WAV / Ogg Vorbis, analyse JSON et cartes Tiled, modèles glTF (animation.Model) et maillages OBJ
#   construits puis transmis sous forme de données ; le fil principal ne fait que l'envoi à la carte graphique et
#   la reconstitution des objets.
#
# Erreurs : un échec de chargement ne lève pas d'exception en arrière-plan : asset.state == "error", asset.error.
#   get() (synchrone) relève l'erreur.

from core use len, type, to_int
from collections use append
use os as _os
use io as _io
use json
use xml as _xml
use time as _time
use string as _s
use ffi
use thread as _thread
use thread.thread_pool as _tp
use multimedia.image.decode as _dec
use multimedia.image.jpeg as _jpeg
use gl.render as _gr
use gl.textures as _gtex
use audio.realtime as _rt
use audio.vorbis as _vorbis
use animation as _anim
use mesh as _mesh
use tilemap as _tm
use sprite as _sprite

const TEXTURE_EXT := [".png", ".jpg", ".jpeg", ".bmp", ".ppm", ".pgm", ".pnm", ".pbm", ".dds", ".ktx2"]

func kind_of(path):
    low := _s.lower(path)
    for e in TEXTURE_EXT:
        if _s.ends_with(low, e):
            return "texture"
    if _s.ends_with(low, ".wav") or _s.ends_with(low, ".ogg") or _s.ends_with(low, ".oga"):
        return "sound"
    if _s.ends_with(low, ".gltf") or _s.ends_with(low, ".glb"):
        return "model"
    if _s.ends_with(low, ".obj"):
        return "mesh"
    if _s.ends_with(low, ".tmx") or _s.ends_with(low, ".tmj"):
        return "tilemap"
    if _s.ends_with(low, ".json"):
        return "json"
    if _s.ends_with(low, ".txt") or _s.ends_with(low, ".csv") or _s.ends_with(low, ".glsl") or _s.ends_with(low, ".vert") or _s.ends_with(low, ".frag"):
        return "text"
    return "bytes"

# ---------------------------------------------------------------------------------------------------------------------
# Travail en arrière-plan (fonctions de premier niveau : exécutées dans un fil de la réserve)
# Elles ne rendent que des valeurs copiables : null, nombres, str, list, dict.
# ---------------------------------------------------------------------------------------------------------------------

func _bg_load(path, kind, options):
    if kind == "texture":
        low := _s.lower(path)
        if _s.ends_with(low, ".dds") or _s.ends_with(low, ".ktx2"):
            return {"raw": _io.read_bytes(path)}
        data := _io.read_bytes(path)
        if len(data) >= 3 and data[0] == 255 and data[1] == 216:
            r := _jpeg.decode_rgba(data, null, true)
            px := r["buffer"].read_bytes(0, r["width"] * r["height"] * 4)
            r["buffer"].free()
            return {"w": r["width"], "h": r["height"], "c": 4, "px": px}
        img := _dec.decode(data)
        return {"w": img.width, "h": img.height, "c": img.channels, "px": _s.byte_pack(img.pixels)}
    if kind == "sound":
        low := _s.lower(path)
        if _s.ends_with(low, ".ogg") or _s.ends_with(low, ".oga"):
            d := _vorbis.load_pcm16(path)
            pcm := d["buffer"].read_bytes(0, d["frames"] * d["channels"] * 2)
            d["buffer"].free()
            return {"frames": d["frames"], "channels": d["channels"], "rate": d["rate"], "pcm": pcm}
        s := _rt.load_wav(path)
        pcm := s.buffer.read_bytes(0, s.frames * s.channels * 2)
        s.free()
        return {"frames": s.frames, "channels": s.channels, "rate": s.rate, "pcm": pcm}
    if kind == "model":
        return {"model": _anim.model_to_dict(_anim.load_gltf(path))}
    if kind == "mesh":
        m := _mesh.load_obj(path)
        return {"mesh": {"name": m.name, "positions": m.positions, "normals": m.normals, "uvs": m.uvs,
                         "indices": m.indices, "groups": m.groups}}
    if kind == "json":
        return {"value": json.parse(_io.read_file(path))}
    if kind == "text":
        return {"value": _io.read_file(path)}
    if kind == "bytes":
        return {"value": _io.read_bytes(path)}
    if kind == "tilemap":
        low := _s.lower(path)
        if _s.ends_with(low, ".tmx"):
            return {"dict": _tm._tmx_dict(_xml.parse(_io.read_file(path)))}
        return {"dict": json.parse(_io.read_file(path))}
    return {"path": path}

# ---------------------------------------------------------------------------------------------------------------------
# Asset
# ---------------------------------------------------------------------------------------------------------------------

class Asset:
    func init(manager, path, kind, options):
        self.manager = manager
        self.path = path
        self.kind = kind
        self.options = options if options != null else {}
        self.state = "new"            # new | loading | ready | error
        self.value = null
        self.error = null
        self.refs = 0
        self.mtime = null
        self.version = 0
        self.extra = null              # modèle : gl.render.ModelRenderer si le gestionnaire a un renderer
        self._ready_cbs = []
        self._reload_cbs = []
        self._future = null

    func ready():
        return self.state == "ready"

    func failed():
        return self.state == "error"

    # Rappel quand la ressource est prête (immédiat si elle l'est déjà).
    func on_ready(fn):
        if self.state == "ready":
            fn(self)
        else:
            append(self._ready_cbs, fn)
        return self

    # Rappel à chaque rechargement à chaud.
    func on_reload(fn):
        append(self._reload_cbs, fn)
        return self

    # Attend la fin d'un chargement en arrière-plan (bloquant) ; rend la valeur.
    func wait(timeout=null):
        if self.state == "loading" and self._future != null:
            data := self._future.result(timeout)
            self.manager._finish(self, data)
        if self.state == "error":
            raise("AssetError", self.error)
        return self.value

# ---------------------------------------------------------------------------------------------------------------------
# Gestionnaire
# ---------------------------------------------------------------------------------------------------------------------

class AssetManager:
    func init(root="", workers=2):
        self.root = root
        self.assets = {}
        self.audio = null                 # audio.realtime.AudioEngine (sons rééchantillonnés à sa fréquence)
        self.renderer = null              # gl.render.Renderer (modèles prêts à dessiner : asset.extra)
        self.workers = workers
        self.pool = null
        self.pending = []
        self.loaders = {}                 # type -> {"load": fn(gestionnaire, chemin, options), "free": fn(valeur)}
        self.watching = false
        self.interval = 0.5
        self._last_check = 0.0
        self.texture_filter = "linear"
        self.texture_wrap = "repeat"
        self.loaded = 0
        self.reloaded = 0

    func full_path(path):
        if self.root == "" or _s.starts_with(path, "/") or (len(path) > 1 and str(path[1]) == ":"):
            return path
        return self.root + "/" + path

    # Chargeur personnalisé : load(gestionnaire, chemin_complet, options) -> valeur ; free(valeur) facultatif.
    func register(kind, load, free=null):
        self.loaders[kind] = {"load": load, "free": free}

    func _asset(path, kind, options):
        key := path
        if key in self.assets:
            a := self.assets[key]
            a.refs += 1
            return a
        a := Asset(self, path, kind if kind != null else kind_of(path), options)
        a.refs = 1
        self.assets[key] = a
        return a

    # Ressource chargée immédiatement (cache) ; relève l'erreur éventuelle.
    func get(path, kind=null, options=null):
        a := self._asset(path, kind, options)
        if a.state == "loading":
            a.wait()
        if a.state != "ready":
            self._load_now(a)
        if a.state == "error":
            raise("AssetError", a.error)
        return a

    # Raccourcis : valeur directement.
    func texture(path, options=null):
        return self.get(path, "texture", options).value

    func sound(path):
        return self.get(path, "sound").value

    func model(path):
        return self.get(path, "model").value

    # Lance le chargement en arrière-plan ; rend l'Asset (état "loading" puis "ready" après update()).
    func load_async(path, kind=null, options=null):
        a := self._asset(path, kind, options)
        if a.state == "ready" or a.state == "loading":
            return a
        if a.kind in self.loaders:
            self._load_now(a)
            return a
        if self.pool == null:
            if not _thread.is_main():
                self._load_now(a)
                return a
            try:
                self.pool = _tp.ThreadPool(self.workers, "assets")
            catch e:
                self.pool = null
        if self.pool == null:
            self._load_now(a)
            return a
        a.state = "loading"
        a._future = self.pool.submit(_bg_load, [self.full_path(path), a.kind, a.options])
        append(self.pending, a)
        return a

    # Chargements en cours (0 = tout est prêt).
    func pending_count():
        return len(self.pending)

    # Proportion chargée parmi les ressources demandées (écran de chargement).
    func progress():
        total := len(self.assets)
        if total == 0:
            return 1.0
        done := 0
        for k in self.assets:
            if self.assets[k].state == "ready" or self.assets[k].state == "error":
                done += 1
        return done * 1.0 / total

    # À chaque image : finalise les chargements terminés (au plus `budget` secondes) et surveille les fichiers.
    func update(budget=0.004):
        t0 := _time.monotonic()
        rest := []
        k := 0
        while k < len(self.pending):
            a := self.pending[k]
            if _time.monotonic() - t0 < budget and a._future != null and a._future.done():
                data := null
                err := null
                try:
                    data = a._future.result(0)
                catch e:
                    err = e.message
                if err != null:
                    a.state = "error"
                    a.error = err
                else:
                    self._finish(a, data)
            elif a.state == "loading":
                append(rest, a)
            k += 1
        self.pending = rest
        if self.watching and _time.monotonic() - self._last_check >= self.interval:
            self._last_check = _time.monotonic()
            self.check_reload()

    # Rechargement à chaud : surveiller les fichiers modifiés.
    func watch(on=true, interval=0.5):
        self.watching = on
        self.interval = interval
        for k in self.assets:
            a := self.assets[k]
            if a.mtime == null:
                a.mtime = self._mtime(a)

    func _mtime(a):
        try:
            return _os.mtime(self.full_path(a.path))
        catch e:
            return null

    # Vérifie les dates de modification et recharge ce qui a changé ; rend la liste des chemins rechargés.
    func check_reload():
        out := []
        for k in self.assets:
            a := self.assets[k]
            if a.state != "ready":
                continue
            m := self._mtime(a)
            if m != null and a.mtime != null and m != a.mtime:
                old := a.value
                a.mtime = m
                self._load_now(a)
                if a.state == "ready":
                    self._free_value(a.kind, old)
                    a.version += 1
                    self.reloaded += 1
                    append(out, a.path)
                    for cb in a._reload_cbs:
                        cb(a)
            elif a.mtime == null:
                a.mtime = m
        return out

    func reload(path):
        if path in self.assets:
            a := self.assets[path]
            old := a.value
            self._load_now(a)
            if a.state == "ready":
                self._free_value(a.kind, old)
                a.version += 1
                for cb in a._reload_cbs:
                    cb(a)
        return self.assets[path] if path in self.assets else null

    # Libère une référence ; la ressource est déchargée à la dernière.
    func release(path):
        if not (path in self.assets):
            return
        a := self.assets[path]
        a.refs -= 1
        if a.refs <= 0:
            self._free_value(a.kind, a.value)
            a.value = null
            a.state = "new"
            nd := {}
            for k in self.assets:
                if k != path:
                    nd[k] = self.assets[k]
            self.assets = nd

    func clear():
        for k in self.assets:
            self._free_value(self.assets[k].kind, self.assets[k].value)
        self.assets = {}

    func shutdown():
        self.clear()
        if self.pool != null:
            self.pool.shutdown(false)
            self.pool = null

    func stats():
        kinds := {}
        for k in self.assets:
            a := self.assets[k]
            kinds[a.kind] = (kinds[a.kind] if a.kind in kinds else 0) + 1
        return {"assets": len(self.assets), "pending": len(self.pending), "loaded": self.loaded,
                "reloaded": self.reloaded, "kinds": kinds}

    # ---- chargement ----
    func _load_now(a):
        try:
            if a.kind in self.loaders:
                a.value = self.loaders[a.kind]["load"](self, self.full_path(a.path), a.options)
            else:
                self._finish_value(a, _bg_load(self.full_path(a.path), a.kind, a.options))
            a.state = "ready"
            a.error = null
            self.loaded += 1
            if a.mtime == null:
                a.mtime = self._mtime(a)
            self._fire_ready(a)
        catch e:
            a.state = "error"
            a.error = e.message

    func _finish(a, data):
        try:
            self._finish_value(a, data)
            a.state = "ready"
            self.loaded += 1
            a.mtime = self._mtime(a)
            self._fire_ready(a)
        catch e:
            a.state = "error"
            a.error = e.message

    func _fire_ready(a):
        cbs := a._ready_cbs
        a._ready_cbs = []
        for cb in cbs:
            cb(a)

    # Données (de _bg_load) -> valeur finale, sur le fil principal.
    func _finish_value(a, d):
        p := self.full_path(a.path)
        k := a.kind
        opt := a.options
        if k == "texture":
            filt := opt["filter"] if "filter" in opt else self.texture_filter
            wrap := opt["wrap"] if "wrap" in opt else self.texture_wrap
            mip := opt["mipmaps"] if "mipmaps" in opt else true
            if "raw" in d:
                low := _s.lower(p)
                a.value = _gtex.ktx2_texture(d["raw"], filt, wrap, mip) if _s.ends_with(low, ".ktx2") else _gtex.dds_texture(d["raw"], filt, wrap, mip)
            else:
                b := ffi.Buffer(len_bytes(d["px"]))
                b.write_bytes(d["px"])
                a.value = _gr.Texture(d["w"], d["h"], b, d["c"], filt, wrap, mip)
                b.free()
        elif k == "sound":
            b := ffi.Buffer(len_bytes(d["pcm"]))
            b.write_bytes(d["pcm"])
            s := _rt.Sound(b, d["frames"], d["channels"], d["rate"], a.path)
            if self.audio != null:
                s = s.resampled(self.audio.rate)
            a.value = s
        elif k == "model":
            m := _anim.model_from_dict(d["model"]) if "model" in d else _anim.load_gltf(p)
            a.value = m
            if self.renderer != null:
                a.extra = _gr.ModelRenderer(self.renderer, m)
        elif k == "mesh":
            if "mesh" in d:
                md := d["mesh"]
                mm := _mesh.Mesh(md["name"])
                mm.positions = md["positions"]
                mm.normals = md["normals"]
                mm.uvs = md["uvs"]
                mm.indices = md["indices"]
                mm.groups = md["groups"]
                a.value = mm
            else:
                a.value = _mesh.load_obj(p)
        elif k == "tilemap":
            m := _tm.from_dict(d["dict"], _dirname(p))
            m.path = p
            a.value = m
        elif k == "atlas":
            tex := opt["texture"] if "texture" in opt else null
            if type(tex) == "str":
                tex = self.texture(tex)
            a.value = _sprite.load_atlas_json(p, tex)
        else:
            a.value = d["value"] if "value" in d else d

    func _free_value(kind, v):
        if v == null:
            return
        if kind in self.loaders and self.loaders[kind]["free"] != null:
            self.loaders[kind]["free"](v)
            return
        try:
            if kind == "texture":
                v.delete()
            elif kind == "sound":
                v.free()
        catch e:
            pass

func len_bytes(s):
    return _s.byte_len(s)

func _dirname(p):
    i := len(p) - 1
    while i >= 0:
        ch := str(p[i])
        if ch == "/" or ch == "\\":
            return _s.slice(p, 0, i)
        i -= 1
    return ""
