# ALEX STANDARD LIBRARY — tui.emulator
#
# Petit émulateur de terminal : rejoue les séquences produites par tui.screen.render_diff (et les séquences
# courantes : déplacement du curseur, effacement, styles, caractères larges) sur une grille, pour vérifier un
# rendu sans vrai terminal. Ce n'est pas un émulateur complet (pas de défilement, de marges, ni d'onglets).

from core use len, type
from collections use append
use string as _s
use tui.width as _w

class Emulator:
    func init(width, height):
        self.resize(width, height)

    func resize(width, height):
        self.width = width
        self.height = height
        self.chars = [" " for i in 0..width * height]
        self.styles = ["" for i in 0..width * height]
        self.x = 0
        self.y = 0
        self.sgr = ""
        self.cursor_visible = true
        self.alternate = false

    func _clear():
        n := self.width * self.height
        self.chars = [" " for i in 0..n]
        self.styles = ["" for i in 0..n]

    # Défilement d'une ligne vers le haut (ligne du bas vidée).
    func _scroll():
        w := self.width
        n := w * self.height
        self.chars = [self.chars[i + w] if i + w < n else " " for i in 0..n]
        self.styles = [self.styles[i + w] if i + w < n else "" for i in 0..n]

    func _put(ch, cw):
        if self.x >= self.width:
            self.x = 0
            self.y += 1
        if self.y >= self.height:
            self._scroll()
            self.y = self.height - 1
        i := self.y * self.width + self.x
        self.chars[i] = ch
        self.styles[i] = self.sgr
        if cw == 2 and self.x + 1 < self.width:
            self.chars[i + 1] = ""
            self.styles[i + 1] = self.sgr
        self.x += cw

    func feed(data):
        i := 0
        n := len(data)
        while i < n:
            c := data[i]
            code := _s.ord(c)
            if code == 27 and i + 1 < n and data[i + 1] == '[':
                j := i + 2
                while j < n and (_s.ord(data[j]) < 64 or _s.ord(data[j]) > 126):
                    j += 1
                if j >= n:
                    break
                self._csi(_s.slice(data, i + 2, j), str(data[j]))
                i = j + 1
                continue
            if code == 27 and i + 1 < n and data[i + 1] == ']':
                j := i + 2
                while j < n and _s.ord(data[j]) != 7:
                    j += 1
                i = j + 1
                continue
            if code == 13:
                self.x = 0
            elif code == 10:
                self.y += 1
                if self.y >= self.height:
                    self._scroll()
                    self.y = self.height - 1
            elif code >= 32:
                cw := _w.char_width(c)
                if cw == 0:
                    if self.x > 0:
                        k := self.y * self.width + self.x - 1
                        self.chars[k] = self.chars[k] + str(c)
                else:
                    self._put(str(c), cw)
            i += 1

    func _csi(params, final):
        if final == "H":
            p := _s.split(params, ";")
            row := 1
            col := 1
            if len(p) >= 1 and p[0] != "":
                row = _int(p[0])
            if len(p) >= 2 and p[1] != "":
                col = _int(p[1])
            self.y = row - 1
            self.x = col - 1
        elif final == "A" or final == "B" or final == "C" or final == "D" or final == "G":
            n := 1
            if params != "":
                n = _int(params)
            if final == "A":
                self.y = _clamp(self.y - n, 0, self.height - 1)
            elif final == "B":
                self.y = _clamp(self.y + n, 0, self.height - 1)
            elif final == "C":
                self.x = _clamp(self.x + n, 0, self.width - 1)
            elif final == "D":
                self.x = _clamp(self.x - n, 0, self.width - 1)
            else:
                self.x = _clamp(n - 1, 0, self.width - 1)
        elif final == "J":
            if params == "2":
                self._clear()
        elif final == "K":
            k := self.y * self.width + self.x
            end := (self.y + 1) * self.width
            if params == "2":
                k = self.y * self.width
            while k < end:
                self.chars[k] = " "
                self.styles[k] = self.sgr
                k += 1
        elif final == "m":
            if params == "" or params == "0":
                self.sgr = ""
            elif _s.starts_with(params, "0;"):
                self.sgr = _s.slice(params, 2)
            else:
                self.sgr = params
        elif final == "h" or final == "l":
            if params == "?25":
                self.cursor_visible = final == "h"
            elif params == "?1049":
                self.alternate = final == "h"

    func row_text(y):
        out := []
        i := y * self.width
        end := i + self.width
        while i < end:
            if self.chars[i] != "":
                append(out, self.chars[i])
            i += 1
        return _s.join("", out)

    func lines():
        out := []
        y := 0
        while y < self.height:
            t := self.row_text(y)
            n := len(t)
            while n > 0 and t[n - 1] == ' ':
                n -= 1
            append(out, _s.slice(t, 0, n))
            y += 1
        return out

    func style_at(x, y):
        return self.styles[y * self.width + x]

func _int(t):
    v := 0
    for c in t:
        v = v * 10 + _s.ord(c) - 48
    return v

func _clamp(v, lo, hi):
    if v < lo:
        return lo
    if v > hi:
        return hi
    return v
