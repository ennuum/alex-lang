# ALEX STANDARD LIBRARY — camera.camera_controls
#
# Réglages de la caméra :
#   - MATÉRIELS par Video4Linux (outil v4l2-ctl) : liste des contrôles proposés par le pilote (luminosité,
#     contraste, saturation, exposition automatique / absolue, balance des blancs, mise au point, gain, zoom...)
#     avec type, bornes, pas, valeur par défaut et actuelle ; lecture et écriture (bornes vérifiées) ;
#     retour aux valeurs par défaut ; profil enregistrable.
#   - LOGICIELS appliqués aux images (quand la caméra ne propose pas le réglage) : luminosité, contraste,
#     gamma, saturation, balance des blancs par gains RGB — clairement distincts des réglages matériels.
#
#   use camera.camera_controls as cc
#   ctl := cc.CameraControls("/dev/video0")          # CameraUnavailable sans v4l2-ctl
#   for c in ctl.list():
#       print(c.describe())                          # « brightness (int) 0..255 pas 1 : 128 (défaut 128) »
#   ctl.set("brightness", 150)
#   ctl.reset_all()
#   sw := cc.SoftwareControls()
#   sw.brightness = 20 ; sw.gamma = 0.8
#   image2 := sw.apply(image)                        # VideoFrame rgb24
#   cs := cc.parse_list_ctrls(texte)                 # analyse d'une sortie « v4l2-ctl --list-ctrls »
#
# Erreurs : ControlError (contrôle inconnu, valeur hors limites, contrôle inactif), CameraUnavailable.

from core use len, type, to_int
from collections use append
use string as _s
use math as _math
use process as _proc
use hardware._sys as _sys
use camera.video_frame as _vf

class Control:
    func init(name, kind, minimum=null, maximum=null, step=null, default=null, value=null, flags=""):
        self.name = name
        self.kind = kind            # int | bool | menu | button | int64 | ...
        self.min = minimum
        self.max = maximum
        self.step = step
        self.default = default
        self.value = value
        self.flags = flags
        self.menu = {}

    func inactive():
        return _s.contains(self.flags, "inactive")

    func read_only():
        return _s.contains(self.flags, "read-only")

    func check(v):
        if self.read_only():
            raise("ControlError", "contrôle « " + self.name + " » en lecture seule")
        if self.kind == "bool":
            if v != 0 and v != 1:
                raise("ControlError", "contrôle « " + self.name + " » : 0 ou 1 attendu")
            return
        if self.min != null and v < self.min:
            raise("ControlError", "contrôle « " + self.name + " » : " + str(v) + " < minimum " + str(self.min))
        if self.max != null and v > self.max:
            raise("ControlError", "contrôle « " + self.name + " » : " + str(v) + " > maximum " + str(self.max))
        if self.step != null and self.step > 1 and self.min != null and (v - self.min) % self.step != 0:
            raise("ControlError", "contrôle « " + self.name + " » : pas de " + str(self.step))
        if self.kind == "menu" and len(self.menu) > 0 and not (v in self.menu):
            raise("ControlError", "contrôle « " + self.name + " » : entrée de menu " + str(v) + " inconnue")

    func describe():
        t := self.name + " (" + self.kind + ")"
        if self.min != null:
            t += " " + str(self.min) + ".." + str(self.max)
        if self.step != null:
            t += " pas " + str(self.step)
        t += " : " + str(self.value) + " (défaut " + str(self.default) + ")"
        if self.flags != "":
            t += " [" + self.flags + "]"
        return t

func _kv(text):
    out := {}
    for part in _s.split(text, " "):
        k := _s.find(part, "=")
        if k > 0:
            out[_s.substring(part, 0, k)] = _s.substring(part, k + 1, len(part))
    return out

func _int_or_null(d, key):
    if key in d:
        try:
            return to_int(d[key])
        catch e:
            return null
    return null

# Analyse « v4l2-ctl --list-ctrls-menus » (ou --list-ctrls) : liste de Control.
func parse_list_ctrls(text):
    out := []
    cur := null
    for line in _s.split(text, "\n"):
        t := _s.trim(line)
        if t == "" or not _s.contains(t, ":"):
            continue
        k := _s.find(t, ":")
        head := _s.trim(_s.substring(t, 0, k))
        body := _s.trim(_s.substring(t, k + 1, len(t)))
        if _s.contains(head, "(") and _s.contains(head, ")"):
            name := _s.trim(_s.split(head, " ")[0])
            kind := _s.substring(head, _s.find(head, "(") + 1, _s.find(head, ")"))
            d := _kv(body)
            fl := ""
            if "flags" in d:
                fl = d["flags"]
            cur = Control(name, kind, _int_or_null(d, "min"), _int_or_null(d, "max"), _int_or_null(d, "step"),
                          _int_or_null(d, "default"), _int_or_null(d, "value"), fl)
            if kind == "bool":
                cur.min = 0
                cur.max = 1
            append(out, cur)
        elif cur != null and cur.kind == "menu":
            ok := true
            for ch in head:
                if ch < '0' or ch > '9':
                    ok = false
            if ok and head != "":
                cur.menu[to_int(head)] = body
    return out

class CameraControls:
    func init(device="/dev/video0", runner=null):
        self.device = device
        self.runner = runner
        if runner == null and _sys.find_tool(["v4l2-ctl"]) == null:
            raise("CameraUnavailable", "v4l2-ctl absent (paquet v4l-utils) : réglages matériels indisponibles")
        self._cache = null

    func _run(args):
        if self.runner != null:
            f := self.runner
            return f(args)
        r := _proc.run("v4l2-ctl", ["-d", self.device] + args, null, 10.0)
        if r.code != 0:
            raise("ControlError", "v4l2-ctl : " + _s.trim(r.stderr))
        return r.stdout

    func list(refresh=false):
        if self._cache == null or refresh:
            self._cache = parse_list_ctrls(self._run(["--list-ctrls-menus"]))
        return self._cache

    func names():
        return [c.name for c in self.list()]

    func control(name):
        for c in self.list():
            if c.name == name:
                return c
        raise("ControlError", "contrôle inconnu : « " + name + " » (" + _s.join(", ", self.names()) + ")")

    func get(name):
        out := self._run(["--get-ctrl=" + name])
        k := _s.find(out, ":")
        return to_int(_s.trim(_s.substring(out, k + 1, len(out))))

    func set(name, value):
        c := self.control(name)
        if c.inactive():
            raise("ControlError", "contrôle « " + name + " » inactif (dépend d'un autre réglage, ex. exposition automatique)")
        c.check(value)
        self._run(["--set-ctrl=" + name + "=" + str(value)])
        c.value = value
        return value

    func reset_all():
        n := 0
        for c in self.list():
            if c.default != null and not c.read_only() and not c.inactive() and c.kind != "button":
                if c.value != c.default:
                    self.set(c.name, c.default)
                    n += 1
        return n

    func profile():
        return {c.name: c.value for c in self.list() if c.value != null}

    func apply_profile(p):
        for k in p:
            self.set(k, p[k])

class SoftwareControls:
    func init():
        self.brightness = 0          # -255..255 (ajout)
        self.contrast = 1.0          # facteur autour de 128
        self.gamma = 1.0
        self.saturation = 1.0
        self.gains = [1.0, 1.0, 1.0]

    func is_identity():
        return self.brightness == 0 and self.contrast == 1.0 and self.gamma == 1.0 and self.saturation == 1.0 and self.gains == [1.0, 1.0, 1.0]

    func _lut(channel):
        lut := []
        i := 0
        while i < 256:
            v := i * self.gains[channel]
            v = (v - 128) * self.contrast + 128 + self.brightness
            if v < 0:
                v = 0.0
            if v > 255:
                v = 255.0
            if self.gamma != 1.0:
                v = 255.0 * _math.pow(v / 255.0, 1.0 / self.gamma)
            append(lut, _math.floor(v + 0.5))
            i += 1
        return lut

    # Image rgb24 corrigée (les autres formats sont d'abord convertis en RGB).
    func apply(frame):
        f := frame
        if f.pixel_format != "rgb24":
            f = f.to_rgb()
        if self.is_identity():
            return f
        luts := [self._lut(0), self._lut(1), self._lut(2)]
        d := f.data
        out := []
        i := 0
        n := len(d)
        while i + 2 < n:
            r := luts[0][d[i]]
            g := luts[1][d[i + 1]]
            b := luts[2][d[i + 2]]
            if self.saturation != 1.0:
                y := 0.299 * r + 0.587 * g + 0.114 * b
                r = _clamp(y + (r - y) * self.saturation)
                g = _clamp(y + (g - y) * self.saturation)
                b = _clamp(y + (b - y) * self.saturation)
            append(out, r)
            append(out, g)
            append(out, b)
            i += 3
        return _vf.VideoFrame(f.width, f.height, "rgb24", out, f.index, f.timestamp)

    # Balance des blancs automatique « monde gris » à partir d'une image.
    func auto_white_balance(frame):
        f := frame
        if f.pixel_format != "rgb24":
            f = f.to_rgb()
        s := [0.0, 0.0, 0.0]
        i := 0
        d := f.data
        while i + 2 < len(d):
            s[0] += d[i]
            s[1] += d[i + 1]
            s[2] += d[i + 2]
            i += 3
        m := (s[0] + s[1] + s[2]) / 3
        self.gains = [m / s[0] if s[0] > 0 else 1.0, m / s[1] if s[1] > 0 else 1.0, m / s[2] if s[2] > 0 else 1.0]
        return self.gains

func _clamp(v):
    if v < 0:
        return 0
    if v > 255:
        return 255
    return _math.floor(v + 0.5)
