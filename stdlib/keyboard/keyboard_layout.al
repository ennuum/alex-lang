# ALEX STANDARD LIBRARY — keyboard.keyboard_layout
#
# Dispositions de clavier : quel caractère produit une touche PHYSIQUE (nom keyboard.key, position QWERTY du
# noyau) selon la disposition (azerty, qwerty, qwertz...) et les modificateurs (Maj, AltGr). Sert à traduire
# les événements bruts (evdev), qui ne donnent que la position, en texte.
#
#   use keyboard.keyboard_layout as kl
#   fr := kl.get("fr")                      # AZERTY français
#   print(fr.char("q"), fr.char("1", true), fr.char("2", false, true))   # a 1 ~
#   print(kl.detect())                      # disposition du système (XKB, localectl, LANG), ex. « fr »
#   print(kl.available())                   # [us, fr, de, be, ch, es, it, uk, dvorak]
#
# Les tables couvrent les touches de caractères (lettres, chiffres, ponctuation) ; les touches mortes (^, ¨)
# donnent le caractère lui-même (pas de composition).
#
# Erreurs : ArgumentError (disposition inconnue).

from core use type, len
from collections use append, contains_key, keys
use string as _s
use os as _os
use process as _proc

# Ordre des touches physiques décrites par les tables (rangées du clavier, positions QWERTY / evdev).
_KEYS := ["grave", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "minus", "equal",
          "q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "left_brace", "right_brace",
          "a", "s", "d", "f", "g", "h", "j", "k", "l", "semicolon", "apostrophe", "backslash",
          "less_greater", "z", "x", "c", "v", "b", "n", "m", "comma", "dot", "slash", "space"]

# Pour chaque disposition : trois chaînes de même longueur que _KEYS (normal, Maj, AltGr) ; « \u0000 » : rien.
func _table(normal, shifted, altgr):
    return [_chars(normal), _chars(shifted), _chars(altgr)]

func _chars(t):
    out := []
    for c in t:
        append(out, str(c))
    return out

_N := "\u0000"

_LAYOUTS := {
    "us": _table("`1234567890-=qwertyuiop[]asdfghjkl;'\\\\zxcvbnm,./ ",
                  "~!@#$%^&*()_+QWERTYUIOP{}ASDFGHJKL:\"||ZXCVBNM<>? ",
                  "\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000 "),
    "uk": _table("`1234567890-=qwertyuiop[]asdfghjkl;'#\\zxcvbnm,./ ",
                  "¬!\"£$%^&*()_+QWERTYUIOP{}ASDFGHJKL:@~|ZXCVBNM<>? ",
                  "¦\u0000\u0000\u0000€\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000é\u0000\u0000\u0000ú\u0000ó\u0000\u0000\u0000á\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000 "),
    "fr": _table("²&é\"'(-è_çà)=azertyuiop^$qsdfghjklmù*<wxcvbn,;:! ",
                  "\u00001234567890°+AZERTYUIOP¨£QSDFGHJKLM%µ>WXCVBN?./§ ",
                  "\u0000\u0000~#{[|`\\^@]}\u0000\u0000€\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000¤\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000 "),
    "be": _table("²&é\"'(§è!çà)-azertyuiop^$qsdfghjklmùµ<wxcvbn,;:= ",
                  "³1234567890°_AZERTYUIOP¨*QSDFGHJKLM%£>WXCVBN?./+ ",
                  "\u0000|@#\u0000\u0000^\u0000\u0000{}\u0000\u0000\u0000\u0000€\u0000\u0000\u0000\u0000\u0000\u0000\u0000[]\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000´`\\\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000~ "),
    "de": _table("^1234567890ß´qwertzuiopü+asdfghjklöä#<yxcvbnm,.- ",
                  "°!\"§$%&/()=?`QWERTZUIOPÜ*ASDFGHJKLÖÄ'>YXCVBNM;:_ ",
                  "\u0000\u0000²³\u0000\u0000\u0000{[]}\\\u0000@\u0000€\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000~\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000|\u0000\u0000\u0000\u0000\u0000\u0000µ\u0000\u0000\u0000 "),
    "ch": _table("§1234567890'^qwertzuiopè¨asdfghjkléà$<yxcvbnm,.- ",
                  "°+\"*ç%&/()=?`QWERTZUIOPü!ASDFGHJKLöä£>YXCVBNM;:_ ",
                  "\u0000¦@#°§¬|¢\u0000\u0000´~\u0000\u0000€\u0000\u0000\u0000\u0000\u0000\u0000\u0000[]\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000{}\\\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000 "),
    "es": _table("º1234567890'¡qwertyuiop`+asdfghjklñ´ç<zxcvbnm,.- ",
                  "ª!\"·$%&/()=?¿QWERTYUIOP^*ASDFGHJKLÑ¨Ç>ZXCVBNM;:_ ",
                  "\\|@#~€¬\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000€\u0000\u0000\u0000\u0000\u0000\u0000\u0000[]\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000{}\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000 "),
    "it": _table("\\1234567890'ìqwertyuiopè+asdfghjklòàù<zxcvbnm,.- ",
                  "|!\"£$%&/()=?^QWERTYUIOPé*ASDFGHJKLç°§>ZXCVBNM;:_ ",
                  "\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000€\u0000\u0000\u0000\u0000\u0000\u0000\u0000[]\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000@#\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000 "),
    "dvorak": _table("`1234567890[]',.pyfgcrl/=aoeuidhtns-\\\\;qjkxbmwvz ",
                  "~!@#$%^&*(){}\"<>PYFGCRL?+AOEUIDHTNS_||:QJKXBMWVZ ",
                  "\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000\u0000 ")}


_NAMES := {"us": "anglais (États-Unis) QWERTY", "uk": "anglais (Royaume-Uni) QWERTY", "fr": "français AZERTY",
           "be": "belge AZERTY", "de": "allemand QWERTZ", "ch": "suisse QWERTZ", "es": "espagnol QWERTY",
           "it": "italien QWERTY", "dvorak": "Dvorak (anglais)"}

class KeyboardLayout:
    func init(code):
        if not contains_key(_LAYOUTS, code):
            raise("ArgumentError", "keyboard_layout : disposition inconnue '" + str(code) + "' (" + str(available()) + ")")
        self.code = code
        self.name = _NAMES[code]
        t := _LAYOUTS[code]
        self._normal = t[0]
        self._shift = t[1]
        self._altgr = t[2]
        if len(self._normal) != len(_KEYS) or len(self._shift) != len(_KEYS) or len(self._altgr) != len(_KEYS):
            raise("ValueError", "keyboard_layout : table '" + code + "' invalide (" + str([len(x) for x in t]) + " au lieu de " + str(len(_KEYS)) + ")")

    func _index(key):
        i := 0
        while i < len(_KEYS):
            if _KEYS[i] == key:
                return i
            i += 1
        return -1

    # Caractère produit par la touche physique key (nom keyboard.key), ou "" si aucun.
    func char(key, shift=false, altgr=false, caps_lock=false):
        i := self._index(key)
        if i < 0:
            return ""
        c := self._normal[i]
        if altgr:
            c = self._altgr[i]
        elif shift:
            c = self._shift[i]
        if caps_lock and not altgr and len(c) == 1 and c >= "a" and c <= "z":
            c = _s.upper(c)
        if c == _N:
            return ""
        return c

    # Touche physique (et modificateurs) qui produit le caractère c : (touche, shift, altgr), ou null.
    func key_for(c):
        i := 0
        while i < len(_KEYS):
            if self._normal[i] == c:
                return (_KEYS[i], false, false)
            if self._shift[i] == c:
                return (_KEYS[i], true, false)
            if self._altgr[i] == c:
                return (_KEYS[i], false, true)
            i += 1
        return null

    # Texte produit par une suite de KeyEvent bruts (evdev) : gère Maj, AltGr, verrouillage majuscules,
    # retour arrière, entrée.
    func type_text(events):
        out := []
        shift := false
        altgr := false
        caps := false
        for e in events:
            k := e.key
            if k == "left_shift" or k == "right_shift":
                shift = e.pressed()
                continue
            if k == "right_alt":
                altgr = e.pressed()
                continue
            if not e.pressed():
                continue
            if k == "caps_lock":
                caps = not caps
            elif k == "backspace":
                if len(out) > 0:
                    out = [out[j] for j in 0..(len(out) - 1)]
            elif k == "enter":
                append(out, "\n")
            elif k == "tab":
                append(out, "\t")
            else:
                c := self.char(k, shift, altgr, caps)
                if c != "":
                    append(out, c)
        return _s.join("", out)

func get(code):
    return KeyboardLayout(code)

func available():
    return [k for k in keys(_LAYOUTS)]

# Disposition du système, si elle est connue et décrite ici (sinon « us »).
func detect():
    cand := null
    e := _os.getenv("XKB_DEFAULT_LAYOUT")
    if e != null and e != "":
        cand = e
    if cand == null and _proc.which("setxkbmap") != null and _os.getenv("DISPLAY") != null:
        try:
            r := _proc.run("setxkbmap", ["-query"], null, 2)
            for line in _s.split(r.stdout, "\n"):
                if _s.starts_with(line, "layout:"):
                    cand = _s.trim(_s.substring(line, 7, len(line)))
        catch err:
            cand = null
    if cand == null and _proc.which("localectl") != null:
        try:
            r := _proc.run("localectl", ["status"], null, 2)
            for line in _s.split(r.stdout, "\n"):
                l := _s.trim(line)
                if _s.starts_with(l, "X11 Layout:"):
                    cand = _s.trim(_s.substring(l, 11, len(l)))
        catch err:
            cand = null
    if cand == null:
        lang := _os.getenv("LANG", "")
        if len(lang) >= 5:
            region := _s.lower(_s.substring(lang, 3, 5))
            m := {"fr": "fr", "be": "be", "de": "de", "at": "de", "ch": "ch", "es": "es", "it": "it", "gb": "uk", "us": "us"}
            if contains_key(m, region):
                cand = m[region]
    if cand != null:
        first := _s.split(cand, ",")[0]
        if contains_key(_LAYOUTS, first):
            return first
        if first == "gb":
            return "uk"
    return "us"
