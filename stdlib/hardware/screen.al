# ALEX STANDARD LIBRARY — hardware.screen
#
# Écrans physiques : sorties vidéo de la carte graphique (Linux : /sys/class/drm), avec état (branché,
# allumé), modes (résolutions), et, d'après l'EDID de l'écran, fabricant, modèle et taille physique.
# Sans /sys/class/drm (machine virtuelle, autre système), xrandr est interrogé s'il est disponible. Les
# tampons d'image du noyau (/dev/fb*) sont listés par framebuffers().
#
# Pour une fenêtre et son contenu, voir le module ui ; pour le terminal, io.console.size().
#
# Exemple
#   use hardware.screen as screen
#   s := screen.primary()
#   if s != null:
#       print(s.name, s.resolution, s.model, s.diagonal_inches())

from core use len, type, to_int, to_float
from collections use append
use string as _s
use math as _m
use os as _os
use file as _file
use process as _proc
use hardware._sys as _sys

class Screen:
    func init(name):
        self.name = name                  # « HDMI-A-1 », « eDP-1 »...
        self.card = null                  # « card0 »
        self.connected = false
        self.enabled = null
        self.modes = []                   # [[largeur, hauteur], ...], le mode préféré en premier
        self.resolution = null            # [largeur, hauteur] du mode préféré (ou courant), null si inconnu
        self.width_mm = null
        self.height_mm = null
        self.manufacturer = null          # code EDID à 3 lettres (« DEL », « SAM »...)
        self.model = null                 # nom donné par l'écran (« DELL U2720Q »)
        self.product_code = null
        self.serial = null
        self.year = null                  # année de fabrication (EDID)

    # Diagonale en pouces (d'après la taille physique), ou null.
    func diagonal_inches():
        if self.width_mm == null or self.height_mm == null or self.width_mm == 0:
            return null
        d := _m.sqrt(self.width_mm * self.width_mm + self.height_mm * self.height_mm) / 25.4
        return to_int(d * 10 + 0.5) / 10.0

    # Points par pouce horizontaux, ou null.
    func dpi():
        if self.resolution == null or self.width_mm == null or self.width_mm == 0:
            return null
        return to_int(self.resolution[0] * 25.4 / self.width_mm + 0.5)

func _mode(text):
    t := _s.trim(text)
    k := _s.find(t, "x")
    if k <= 0:
        return null
    w := _sys.dec(_s.slice(t, 0, k))
    rest := _s.slice(t, k + 1)
    end := 0
    while end < len(rest) and rest[end] >= '0' and rest[end] <= '9':
        end += 1
    h := _sys.dec(_s.slice(rest, 0, end))
    if w == null or h == null:
        return null
    return [w, h]

# Décode un bloc EDID (list[int] de 128 octets ou plus) : dict manufacturer, product_code, serial, year,
# width_mm, height_mm, model, preferred ([largeur, hauteur]) ; null si l'en-tête est invalide.
func parse_edid(edid):
    if type(edid) != "list" or len(edid) < 128:
        return null
    header := [0, 255, 255, 255, 255, 255, 255, 0]
    i := 0
    while i < 8:
        if edid[i] != header[i]:
            return null
        i += 1
    m := edid[8] * 256 + edid[9]
    letters := ""
    for shift in [10, 5, 0]:
        letters += str(_s.chr(((m >> shift) & 31) + 64))
    info := {"manufacturer": letters, "product_code": edid[10] + edid[11] * 256, "serial": null, "year": edid[17] + 1990, "width_mm": edid[21] * 10, "height_mm": edid[22] * 10, "model": null, "preferred": null}
    # 1er descripteur de mode détaillé : mode préféré, et taille en mm plus précise.
    if edid[54] != 0 or edid[55] != 0:
        w := edid[56] + ((edid[58] >> 4) << 8)
        h := edid[59] + ((edid[61] >> 4) << 8)
        info["preferred"] = [w, h]
        wmm := edid[66] + ((edid[68] >> 4) << 8)
        hmm := edid[67] + ((edid[68] & 15) << 8)
        if wmm > 0 and hmm > 0:
            info["width_mm"] = wmm
            info["height_mm"] = hmm
    for base in [54, 72, 90, 108]:
        if edid[base] == 0 and edid[base + 1] == 0 and edid[base + 2] == 0 and (edid[base + 3] == 252 or edid[base + 3] == 255):
            text := ""
            k := base + 5
            while k < base + 18 and edid[k] != 10:
                text += str(_s.chr(edid[k]))
                k += 1
            if edid[base + 3] == 252:
                info["model"] = _s.trim(text)
            else:
                info["serial"] = _s.trim(text)
    return info

func _from_drm():
    out := []
    for entry in _sys.list("/sys/class/drm"):
        k := _s.find(entry, "-")
        if not _s.starts_with(entry, "card") or k < 0:
            continue
        base := "/sys/class/drm/" + entry
        sc := Screen(_s.slice(entry, k + 1))
        sc.card = _s.slice(entry, 0, k)
        sc.connected = _sys.read(base + "/status") == "connected"
        en := _sys.read(base + "/enabled")
        if en != null:
            sc.enabled = en == "enabled"
        modes := _sys.read(base + "/modes")
        if modes != null:
            for line in _s.split(modes, "\n"):
                md := _mode(line)
                if md != null and not _contains_mode(sc.modes, md):
                    append(sc.modes, md)
        if len(sc.modes) > 0:
            sc.resolution = sc.modes[0]
        edid_path := _sys.p(base + "/edid")
        if _os.isfile(edid_path):
            data := null
            try:
                data = _file.read_bytes(edid_path)
            catch e:
                data = null
            info := parse_edid(data)
            if info != null:
                sc.manufacturer = info["manufacturer"]
                sc.model = info["model"]
                sc.product_code = info["product_code"]
                sc.serial = info["serial"]
                sc.year = info["year"]
                sc.width_mm = info["width_mm"]
                sc.height_mm = info["height_mm"]
                if sc.resolution == null:
                    sc.resolution = info["preferred"]
        append(out, sc)
    return out

func _contains_mode(modes, md):
    for x in modes:
        if x[0] == md[0] and x[1] == md[1]:
            return true
    return false

# Analyse la sortie de « xrandr --query ».
func parse_xrandr(text):
    out := []
    cur := null
    for line in _s.split(text, "\n"):
        if line == "" or _s.starts_with(line, "Screen "):
            continue
        if not _s.starts_with(line, " "):
            words := _sys.split_words(line)
            if len(words) < 2:
                continue
            cur = Screen(words[0])
            cur.connected = words[1] == "connected"
            cur.enabled = false
            for w in words:
                g := _s.find(w, "+")
                if g > 0 and _mode(_s.slice(w, 0, g)) != null:
                    cur.resolution = _mode(_s.slice(w, 0, g))
                    cur.enabled = true
            i := 0
            while i + 2 < len(words):
                if _s.ends_with(words[i], "mm") and words[i + 1] == "x" and _s.ends_with(words[i + 2], "mm"):
                    cur.width_mm = _sys.dec(_s.slice(words[i], 0, len(words[i]) - 2))
                    cur.height_mm = _sys.dec(_s.slice(words[i + 2], 0, len(words[i + 2]) - 2))
                i += 1
            append(out, cur)
        elif cur != null:
            words := _sys.split_words(line)
            if len(words) > 0:
                md := _mode(words[0])
                if md != null:
                    if not _contains_mode(cur.modes, md):
                        append(cur.modes, md)
                    if _s.contains(line, "+"):
                        cur.modes = _move_first(cur.modes, md)      # mode préféré (« + ») en tête
                    if cur.resolution == null and _s.contains(line, "*"):
                        cur.resolution = md
    return out

func _move_first(modes, md):
    out := [md]
    for x in modes:
        if not (x[0] == md[0] and x[1] == md[1]):
            append(out, x)
    return out

func _from_xrandr():
    if _os.getenv("DISPLAY") == null or _proc.which("xrandr") == null:
        return []
    try:
        r := _proc.run("xrandr", ["--query"], null, 5.0)
        if r.code != 0:
            return []
        return parse_xrandr(r.stdout)
    catch e:
        return []

# Toutes les sorties vidéo connues (branchées ou non).
func outputs():
    found := _from_drm()
    if len(found) == 0 and _sys.root() == "":
        found = _from_xrandr()
    return found

# Écrans branchés.
func screens():
    return [s for s in outputs() if s.connected]

# Premier écran branché et allumé (sinon branché), ou null.
func primary():
    all := screens()
    for s in all:
        if s.enabled != false:
            return s
    if len(all) > 0:
        return all[0]
    return null

func available():
    return len(screens()) > 0

# Tampons d'image du noyau (/sys/class/graphics/fbN) : list de dict name, device, width, height, bits.
func framebuffers():
    out := []
    for entry in _sys.list("/sys/class/graphics"):
        if not _s.starts_with(entry, "fb"):
            continue
        base := "/sys/class/graphics/" + entry
        size := _sys.read(base + "/virtual_size")
        w := null
        h := null
        if size != null:
            parts := _s.split(size, ",")
            if len(parts) == 2:
                w = _sys.dec(parts[0])
                h = _sys.dec(parts[1])
        append(out, {"name": _sys.read(base + "/name"), "device": "/dev/" + entry, "width": w, "height": h, "bits": _sys.dec(_sys.read(base + "/bits_per_pixel"))})
    return out
