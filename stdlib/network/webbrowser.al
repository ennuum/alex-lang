# ALEX STANDARD LIBRARY — network.webbrowser
#
# Ouverture d'une URL dans le navigateur de l'utilisateur, comme le module webbrowser de Python.
#
#   open(url)            ouvre l'URL (onglet ou fenêtre selon le navigateur) ; true si un navigateur a été lancé
#   open_new / open_new_tab
#   get(nom) -> Browser  navigateur précis (« firefox », « chromium », « xdg-open »...)
#   register(nom, commande)   ajoute un navigateur : commande = liste d'arguments, « %s » remplacé par l'URL
#   command_for(url)     arguments qui seraient exécutés (sans rien lancer)
#   file_url(chemin)     « file:///chemin/absolu » pour ouvrir un fichier local
#
# Choix : la variable BROWSER (liste séparée par « : », « %s » pour l'URL) l'emporte ; sinon l'ouvreur du système
# (xdg-open, gio sous Linux ; open sous macOS ; start sous Windows), puis les navigateurs connus présents dans le
# PATH. Sans affichage graphique (ni DISPLAY ni WAYLAND_DISPLAY), seuls les navigateurs en mode texte sont
# essayés. L'URL est passée comme UN argument (jamais à un interpréteur de commandes) : pas d'injection possible.
# Seuls les schémas http, https, file, ftp et mailto sont acceptés.
#
# Exemple
#   use network.webbrowser as wb
#   wb.open("https://exemple.org/")
#   wb.open(wb.file_url("rapport.html"))

from core use len, type
from collections use append, keys, contains_key, clear
use string as _s
use os as _os
use process as _proc
use network.url as _url

const ALLOWED_SCHEMES := ["http", "https", "file", "ftp", "mailto"]

class Browser:
    # command : liste d'arguments ; « %s » est remplacé par l'URL (ajoutée à la fin s'il n'y figure pas).
    # new_window / new_tab : arguments ajoutés pour open_new / open_new_tab (null : comme open).
    func init(name, command, new_window=null, new_tab=null, terminal=false):
        self.name = name
        self.command = command
        self.new_window = new_window
        self.new_tab = new_tab
        self.terminal = terminal     # navigateur en mode texte (prend le terminal : attendu jusqu'à sa fin)

    func args_for(url, new=0):
        out := []
        extra := null
        if new == 1:
            extra = self.new_window
        elif new == 2:
            extra = self.new_tab
        placed := false
        first := true
        for a in self.command:
            if first:
                first = false
                if extra != null:
                    append(out, a)
                    for x in extra:
                        append(out, x)
                    continue
            if _s.contains(a, "%s"):
                append(out, _s.replace(a, "%s", url))
                placed = true
            else:
                append(out, a)
        if not placed:
            append(out, url)
        return out

    func available():
        return _proc.which(self.command[0]) != null

    # Lance le navigateur ; true s'il a démarré.
    func open(url, new=0):
        args := self.args_for(_check(url), new)
        try:
            cmd := _proc.Command(args[0]).args(args[1:len(args)])
            if self.terminal:
                r := cmd.run()
                return r.code == 0
            cmd.stdin("null").stdout("null").stderr("null").spawn()
            return true
        catch e:
            return false

_REGISTRY := {}
_ORDER := []

# Ajoute (ou remplace) un navigateur ; preferred=true le place en tête de la liste d'essai.
func register(name, command, preferred=false, new_window=null, new_tab=null, terminal=false):
    cmd := command
    if type(command) == "str":
        cmd = _s.split(command, " ")
    _REGISTRY[name] = Browser(name, cmd, new_window, new_tab, terminal)
    kept := []
    for n in _ORDER:
        if n != name:
            append(kept, n)
    if preferred:
        clear(_ORDER)
        append(_ORDER, name)
        for n in kept:
            append(_ORDER, n)
    else:
        clear(_ORDER)
        for n in kept:
            append(_ORDER, n)
        append(_ORDER, name)

func _graphical():
    plat := _s.lower(_os.platform())
    if _s.contains(plat, "darwin") or _s.contains(plat, "mac") or _s.contains(plat, "win"):
        return true
    return _os.getenv("DISPLAY") != null or _os.getenv("WAYLAND_DISPLAY") != null

func _defaults():
    if len(_ORDER) > 0:
        return
    plat := _s.lower(_os.platform())
    if _s.contains(plat, "darwin") or _s.contains(plat, "mac"):
        register("macosx", ["open"], false, null, null)
        register("safari", ["open", "-a", "Safari"])
        register("chrome", ["open", "-a", "Google Chrome"])
        register("firefox", ["open", "-a", "Firefox"])
    elif _s.contains(plat, "win"):
        register("windows-default", ["cmd", "/c", "start", "", "%s"])
    if _graphical():
        register("xdg-open", ["xdg-open"])
        register("gio", ["gio", "open"])
        register("sensible-browser", ["sensible-browser"])
        register("x-www-browser", ["x-www-browser"])
        register("firefox", ["firefox"], false, ["-new-window"], ["-new-tab"])
        register("chromium", ["chromium"], false, ["--new-window"], null)
        register("chromium-browser", ["chromium-browser"], false, ["--new-window"], null)
        register("google-chrome", ["google-chrome"], false, ["--new-window"], null)
        register("brave-browser", ["brave-browser"], false, ["--new-window"], null)
        register("epiphany", ["epiphany"])
        register("konqueror", ["konqueror"])
    register("www-browser", ["www-browser"], false, null, null, true)
    register("w3m", ["w3m"], false, null, null, true)
    register("lynx", ["lynx"], false, null, null, true)
    register("links", ["links"], false, null, null, true)
    register("elinks", ["elinks"], false, null, null, true)

func _from_env():
    v := _os.getenv("BROWSER")
    if v == null or v == "":
        return []
    out := []
    i := 0
    for part in _s.split(v, ":"):
        p := _s.trim(part)
        if p == "":
            continue
        args := []
        for a in _s.split(p, " "):
            if a != "":
                append(args, a)
        append(out, Browser("env" + str(i), args))
        i += 1
    return out

# Navigateurs essayés, dans l'ordre (BROWSER d'abord).
func candidates():
    _defaults()
    out := _from_env()
    for n in _ORDER:
        append(out, _REGISTRY[n])
    return out

# Navigateurs présents sur la machine (noms).
func available():
    out := []
    for b in candidates():
        if b.available():
            append(out, b.name)
    return out

# Navigateur nommé (ou le premier disponible si name=null) ; ValueError s'il est inconnu ou absent.
func get(name=null):
    if name == null:
        for b in candidates():
            if b.available():
                return b
        raise("ValueError", "webbrowser : aucun navigateur disponible")
    _defaults()
    if contains_key(_REGISTRY, name):
        return _REGISTRY[name]
    if _proc.which(name) != null:
        return Browser(name, [name])
    raise("ValueError", "webbrowser : navigateur inconnu « " + name + " »")

func _check(target):
    if type(target) != "str" or target == "":
        raise("TypeError", "webbrowser : URL str non vide attendue")
    for c in target:
        if _s.ord(c) < 32:
            raise("ValueError", "webbrowser : caractère de contrôle dans l'URL")
    u := null
    try:
        u = _url.parse(target)
    catch e:
        raise("ValueError", "webbrowser : URL invalide « " + target + " »")
    for s in ALLOWED_SCHEMES:
        if s == u.scheme:
            return target
    raise("ValueError", "webbrowser : schéma « " + u.scheme + " » refusé (http, https, file, ftp, mailto)")

# Arguments du premier navigateur disponible pour cette URL (rien n'est lancé), ou null.
func command_for(target, new=0):
    _check(target)
    for b in candidates():
        if b.available():
            return b.args_for(target, new)
    return null

# Ouvre l'URL : new = 0 (même fenêtre si possible), 1 (nouvelle fenêtre), 2 (nouvel onglet). true si un
# navigateur a été lancé.
func open(target, new=0, autoraise=true):
    _check(target)
    for b in candidates():
        if b.available() and b.open(target, new):
            return true
    return false

func open_new(target):
    return open(target, 1)

func open_new_tab(target):
    return open(target, 2)

# URL « file:// » d'un chemin local (rendu absolu, caractères spéciaux encodés).
func file_url(path):
    p := _os.absolute(path)
    p = _s.replace(p, "\\", "/")
    if not _s.starts_with(p, "/"):
        p = "/" + p
    return "file://" + _url.quote(p, "/:")
