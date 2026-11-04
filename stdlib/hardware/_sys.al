# ALEX STANDARD LIBRARY — hardware._sys (privé)
#
# Lecture de l'inventaire du matériel exposé par Linux (/sys, /proc, /dev), commune aux modules hardware.*.
# set_root(dossier) (ou la variable ALEX_HW_ROOT) fait lire une copie de ces arborescences (tests).

from core use len, type
from collections use append, sort
use string as _s
use os as _os
use file as _file
use process as _proc
use _native_fd as _f

_root := [_os.getenv("ALEX_HW_ROOT", "")]

# Préfixe ajouté à /sys, /proc, /dev ("" : le vrai système).
func set_root(path):
    if path == null:
        path = ""
    _root[0] = path

func root():
    return _root[0]

func p(path):
    return _root[0] + path

func is_linux():
    return _os.platform() == "linux" or _root[0] != ""

func exists(path):
    return _os.exists(p(path))

# Contenu d'un fichier (sans espaces autour), ou null.
func read(path):
    full := p(path)
    try:
        if not _os.isfile(full):
            return null
        return _s.trim(_file.read(full))
    catch e:
        return null

# Noms d'un dossier, triés ; [] s'il n'existe pas.
func list(path):
    full := p(path)
    try:
        if not _os.isdir(full):
            return []
        names := _os.list_dir(full)
        sort(names)
        return names
    catch e:
        return []

# Dernier élément de la cible d'un lien symbolique (« virtio-pci » pour .../driver), ou null.
func link_name(path):
    t := _f.readlink(p(path))
    if t == null:
        return null
    return _os.basename(t)

func hex(text):
    if text == null:
        return null
    t := _s.lower(_s.trim(text))
    if _s.starts_with(t, "0x"):
        t = _s.slice(t, 2)
    if t == "":
        return null
    v := 0
    for c in t:
        d := _s.ord(c)
        if d >= 48 and d <= 57:
            v = v * 16 + d - 48
        elif d >= 97 and d <= 102:
            v = v * 16 + d - 87
        else:
            return null
    return v

func dec(text):
    if text == null:
        return null
    t := _s.trim(text)
    if t == "":
        return null
    v := 0
    neg := false
    if _s.starts_with(t, "-"):
        neg = true
        t = _s.slice(t, 1)
    for c in t:
        d := _s.ord(c)
        if d < 48 or d > 57:
            return null
        v = v * 10 + d - 48
    if neg:
        return -v
    return v

# « 4 hex chiffres » d'un identifiant (0x10de -> "10de").
func hex4(v):
    if v == null:
        return null
    digits := "0123456789abcdef"
    out := ""
    n := v
    k := 0
    while k < 4:
        out = str(digits[n % 16]) + out
        n = n // 16
        k += 1
    return out

func split_words(text):
    return [w for w in _s.split(text, " ") if w != ""]

# Périphériques d'entrée de /proc/bus/input/devices : list de dict name, phys, sysfs, handlers, events
# (chemins /dev/input/eventN), ev (masque des types d'événements), bus, vendor, product, key (masque des touches
# en liste de mots hexadécimaux, du plus fort au plus faible).
func input_devices():
    text := read("/proc/bus/input/devices")
    out := []
    if text == null:
        return out
    cur := null
    for line in _s.split(text + "\n", "\n"):
        if _s.trim(line) == "":
            if cur != null:
                append(out, cur)
            cur = null
            continue
        if cur == null:
            cur = {"name": "", "phys": "", "sysfs": "", "handlers": [], "events": [], "ev": 0, "bus": null, "vendor": null, "product": null, "key": [], "rel": 0, "abs": []}
        kind := _s.slice(line, 0, 1)
        body := _s.slice(line, 3)
        if kind == "N":
            v := _s.slice(body, _s.find(body, "=") + 1)
            if _s.starts_with(v, "\"") and _s.ends_with(v, "\""):
                v = _s.slice(v, 1, len(v) - 1)
            cur["name"] = v
        elif kind == "P":
            cur["phys"] = _s.slice(body, _s.find(body, "=") + 1)
        elif kind == "S":
            cur["sysfs"] = _s.slice(body, _s.find(body, "=") + 1)
        elif kind == "H":
            hs := split_words(_s.slice(body, _s.find(body, "=") + 1))
            cur["handlers"] = hs
            for h in hs:
                if _s.starts_with(h, "event"):
                    append(cur["events"], "/dev/input/" + h)
        elif kind == "I":
            for part in split_words(body):
                k := _s.find(part, "=")
                if k > 0:
                    name := _s.lower(_s.slice(part, 0, k))
                    if name == "bus" or name == "vendor" or name == "product":
                        cur[name] = hex(_s.slice(part, k + 1))
        elif kind == "B":
            k := _s.find(body, "=")
            name := _s.slice(body, 0, k)
            value := _s.slice(body, k + 1)
            if name == "EV":
                cur["ev"] = hex(value)
            elif name == "KEY":
                cur["key"] = split_words(value)
            elif name == "REL":
                cur["rel"] = hex(value)
            elif name == "ABS":
                cur["abs"] = split_words(value)
    if cur != null:
        append(out, cur)
    return out

# Vrai si le bit n est mis dans un masque donné en mots hexadécimaux (du plus fort au plus faible, mots de
# 64 bits sur une machine 64 bits).
func mask_bit(words, n):
    if len(words) == 0:
        return false
    idx := len(words) - 1 - n // 64
    if idx < 0:
        return false
    w := hex(words[idx])
    if w == null:
        return false
    return (w >> (n % 64)) & 1 == 1

# Premier programme disponible parmi names (list), ou null.
func find_tool(names):
    for n in names:
        path := _proc.which(n)
        if path != null:
            return n
    return null

# Version majeure de ffmpeg / ffplay (« ffmpeg version 9.0.2 », « n6.1 », « 4.4.2-0ubuntu... ») ; 99 pour une
# version de développement (« N-113000-g... ») ; 0 si l'outil ne répond pas. Lue une fois par outil.
_ffver := {}

func ffmpeg_major(tool="ffmpeg"):
    if tool in _ffver:
        return _ffver[tool]
    v := 0
    try:
        r := _proc.run(tool, ["-hide_banner", "-version"], null, 15)
        words := split_words(_s.trim(_s.split(r.stdout + "\n", "\n")[0]))
        if len(words) >= 3 and words[1] == "version":
            t := words[2]
            if _s.starts_with(t, "N-"):
                v = 99
            else:
                if _s.starts_with(t, "n"):
                    t = _s.slice(t, 1)
                d := dec(_s.split(t, ".")[0])
                v = d if d != null else 0
    catch e:
        v = 0
    _ffver[tool] = v
    return v

# Nombre de canaux d'une ENTRÉE brute (s16le, f32le...) de ffmpeg / ffplay : « -ac n » jusqu'à ffmpeg 6,
# « -ch_layout » à partir de ffmpeg 7 (qui a retiré -ac en entrée).
func raw_channels_args(channels, tool="ffmpeg"):
    if ffmpeg_major(tool) >= 7:
        layout := "mono" if channels == 1 else ("stereo" if channels == 2 else str(channels) + "c")
        return ["-ch_layout", layout]
    return ["-ac", str(channels)]

func fail(op, message):
    raise("HardwareError", op + " : " + message)
