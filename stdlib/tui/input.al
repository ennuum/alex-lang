# ALEX STANDARD LIBRARY — tui.input
#
# Décodage des octets reçus d'un terminal en événements : touches (avec Ctrl, Alt, Maj), souris (protocole
# SGR 1006 : boutons, glisser, molette), collage (« bracketed paste »), focus de la fenêtre.
# Décodeur pur (sans terminal) : feed(texte) rend les événements complets et garde une séquence
# inachevée pour la suite ; flush() termine une séquence en attente (Échap seul = touche « escape »).
#
# Événements (dict) :
#   {"type": "key", "key": nom, "text": caractère ou null, "ctrl", "alt", "shift"}
#       nom : le caractère lui-même (« a », « É », « 7 »), ou « enter », « tab », « backspace », « escape »,
#       « space », « up », « down », « left », « right », « home », « end », « insert », « delete »,
#       « page_up », « page_down », « f1 ».. « f12 », préfixé des modificateurs : « ctrl+c », « alt+x »,
#       « shift+tab », « ctrl+left », « ctrl+shift+up »
#   {"type": "mouse", "action": "down"|"up"|"drag"|"move"|"wheel", "button": "left"|"middle"|"right"|null,
#    "x", "y" (colonne et ligne à partir de 0), "dy" (molette : +1 vers le haut), "dx", "ctrl", "alt", "shift"}
#   {"type": "paste", "text": texte collé}
#   {"type": "focus", "focused": bool}

from core use len, type
from collections use append, contains_key
use string as _s

const ESC := "\e"

func key_event(name, text=null, ctrl=false, alt=false, shift=false):
    full := name
    if shift and (len(name) > 1 or text == null):
        full = "shift+" + full
    if alt:
        full = "alt+" + full
    if ctrl:
        full = "ctrl+" + full
    return {"type": "key", "key": full, "text": text, "ctrl": ctrl, "alt": alt, "shift": shift}

_CSI_KEYS := {"A": "up", "B": "down", "C": "right", "D": "left", "H": "home", "F": "end", "P": "f1", "Q": "f2", "R": "f3", "S": "f4", "Z": "tab"}
_TILDE_KEYS := {1: "home", 2: "insert", 3: "delete", 4: "end", 5: "page_up", 6: "page_down", 7: "home", 8: "end", 11: "f1", 12: "f2", 13: "f3", 14: "f4", 15: "f5", 17: "f6", 18: "f7", 19: "f8", 20: "f9", 21: "f10", 23: "f11", 24: "f12"}

func _num(text):
    if text == "":
        return null
    v := 0
    for c in text:
        d := _s.ord(c) - 48
        if d < 0 or d > 9:
            return null
        v = v * 10 + d
    return v

# Modificateurs xterm (paramètre 1 + somme : 1 Maj, 2 Alt, 4 Ctrl).
func _mods(m):
    if m == null or m < 2:
        return [false, false, false]
    b := m - 1
    return [b & 4 != 0, b & 2 != 0, b & 1 != 0]

# Événement d'un caractère seul (hors séquence).
func _char_event(c, alt):
    code := _s.ord(c)
    if code == 13 or code == 10:
        return key_event("enter", null, false, alt)
    if code == 9:
        return key_event("tab", null, false, alt)
    if code == 127 or code == 8:
        return key_event("backspace", null, false, alt)
    if code == 27:
        return key_event("escape", null, false, alt)
    if code == 0:
        return key_event("space", null, true, alt)
    if code < 27:
        return key_event(str(_s.chr(code + 96)), null, true, alt)
    if code < 32:
        return key_event(str(_s.chr(code + 64)), null, true, alt)
    if code == 32:
        if alt:
            return key_event("space", null, false, true)
        return {"type": "key", "key": "space", "text": " ", "ctrl": false, "alt": false, "shift": false}
    if alt:
        return key_event(str(c), null, false, true)
    return {"type": "key", "key": str(c), "text": str(c), "ctrl": false, "alt": false, "shift": false}

class Decoder:
    func init():
        self._pending = ""
        self._paste = null

    # Ajoute des caractères reçus ; renvoie la liste des événements complets.
    func feed(data):
        self._pending = self._pending + data
        out := []
        while self._pending != "":
            if self._paste != null:
                k := _s.find(self._pending, ESC + "[201~")
                if k < 0:
                    self._paste = self._paste + self._pending
                    self._pending = ""
                    break
                append(out, {"type": "paste", "text": self._paste + _s.slice(self._pending, 0, k)})
                self._paste = null
                self._pending = _s.slice(self._pending, k + 6)
                continue
            r := self._one(self._pending)
            if r == null:
                break                       # séquence incomplète : attendre la suite
            n := r[0]
            ev := r[1]
            self._pending = _s.slice(self._pending, n)
            if ev != null:
                append(out, ev)
        return out

    # Vrai si une séquence inachevée attend (typiquement un Échap seul).
    func waiting():
        return self._pending != "" or self._paste != null

    # Termine ce qui attend : un Échap seul devient la touche « escape ».
    func flush():
        out := []
        p := self._pending
        self._pending = ""
        if self._paste != null:
            append(out, {"type": "paste", "text": self._paste + p})
            self._paste = null
            return out
        i := 0
        while i < len(p):
            append(out, _char_event(p[i], false))
            i += 1
        return out

    # [longueur consommée, événement ou null] ; null si incomplet.
    func _one(t):
        c := t[0]
        if _s.ord(c) != 27:
            return [1, _char_event(c, false)]
        if len(t) == 1:
            return null
        c1 := t[1]
        if c1 == '[':
            return self._csi(t)
        if c1 == 'O':
            if len(t) < 3:
                return null
            k := str(t[2])
            if contains_key(_CSI_KEYS, k):
                return [3, key_event(_CSI_KEYS[k])]
            return [3, null]
        if _s.ord(c1) == 27:
            return [1, key_event("escape")]
        # Alt + caractère.
        return [2, _char_event(c1, true)]

    func _csi(t):
        # ESC [ paramètres (0x30-0x3F) intermédiaires (0x20-0x2F) final (0x40-0x7E)
        i := 2
        n := len(t)
        while i < n:
            code := _s.ord(t[i])
            if code >= 64 and code <= 126:
                break
            if code < 32 or code > 63:
                return [i, null]            # séquence invalide : ignorée
            i += 1
        if i >= n:
            if n > 64:
                return [n, null]
            return null
        final := str(t[i])
        params := _s.slice(t, 2, i)
        total := i + 1
        if _s.starts_with(params, "<") and (final == "M" or final == "m"):
            return [total, _mouse(_s.slice(params, 1), final == "M")]
        if final == "~":
            parts := _s.split(params, ";")
            num := _num(parts[0])
            if num == 200:
                self._paste = ""
                return [total, null]
            if num == 201:
                return [total, null]
            mods := [false, false, false]
            if len(parts) > 1:
                mods = _mods(_num(parts[1]))
            if num != null and contains_key(_TILDE_KEYS, num):
                return [total, key_event(_TILDE_KEYS[num], null, mods[0], mods[1], mods[2])]
            return [total, null]
        if final == "I" and params == "":
            return [total, {"type": "focus", "focused": true}]
        if final == "O" and params == "":
            return [total, {"type": "focus", "focused": false}]
        if final == "Z":
            return [total, key_event("tab", null, false, false, true)]
        if contains_key(_CSI_KEYS, final):
            parts := _s.split(params, ";")
            mods := [false, false, false]
            if len(parts) > 1:
                mods = _mods(_num(parts[1]))
            return [total, key_event(_CSI_KEYS[final], null, mods[0], mods[1], mods[2])]
        return [total, null]

func _mouse(params, pressed):
    parts := _s.split(params, ";")
    if len(parts) != 3:
        return null
    b := _num(parts[0])
    x := _num(parts[1])
    y := _num(parts[2])
    if b == null or x == null or y == null:
        return null
    ev := {"type": "mouse", "action": "down", "button": null, "x": x - 1, "y": y - 1, "dx": 0, "dy": 0, "shift": b & 4 != 0, "alt": b & 8 != 0, "ctrl": b & 16 != 0}
    base := b & 3
    names := ["left", "middle", "right", null]
    if b & 64 != 0:
        ev["action"] = "wheel"
        if base == 0:
            ev["dy"] = 1
        elif base == 1:
            ev["dy"] = -1
        elif base == 2:
            ev["dx"] = -1
        else:
            ev["dx"] = 1
        return ev
    if b & 32 != 0:
        ev["button"] = names[base]
        if base == 3:
            ev["action"] = "move"
        else:
            ev["action"] = "drag"
        return ev
    ev["button"] = names[base]
    if not pressed:
        ev["action"] = "up"
    return ev

# Décode d'un coup un texte complet (tests) : feed puis flush.
func decode(data):
    d := Decoder()
    out := d.feed(data)
    for e in d.flush():
        append(out, e)
    return out
