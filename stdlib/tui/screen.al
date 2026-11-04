# ALEX STANDARD LIBRARY — tui.screen
#
# Tampon d'écran : une grille de cellules (caractère + style SGR, voir tui.style) sur laquelle on dessine
# (texte, rectangles, cadres), puis render_diff() calcule les séquences ANSI qui font passer le terminal de
# l'image précédente à la nouvelle en ne réécrivant que les cellules modifiées.
#
# Coordonnées : x = colonne, y = ligne, à partir de 0. Un caractère large (CJK, émoji) occupe deux cellules :
# la seconde est une cellule de continuation (caractère ""). Une zone de découpe (push_clip / pop_clip) limite
# le dessin.
#
#   use tui.screen as screen
#   b := screen.Buffer(40, 10)
#   b.box(0, 0, 40, 10, "", "round", "Titre")
#   b.text(2, 2, "Bonjour", st.style("green", bold=true))
#   print(b.lines())

from core use len, type
from collections use append, pop
use string as _s
use tui.width as _w
use tui.style as _st

_BOXES := {"single": ["┌", "┐", "└", "┘", "─", "│"], "double": ["╔", "╗", "╚", "╝", "═", "║"], "round": ["╭", "╮", "╰", "╯", "─", "│"], "heavy": ["┏", "┓", "┗", "┛", "━", "┃"], "ascii": ["+", "+", "+", "+", "-", "|"]}

# Caractères d'un type de cadre : [haut-gauche, haut-droite, bas-gauche, bas-droite, horizontal, vertical].
func box_chars(kind):
    if type(kind) == "list":
        return kind
    if kind == null:
        kind = "single"
    if not _has_box(kind):
        raise("ArgumentError", "tui.screen : cadre inconnu '" + str(kind) + "' (single, double, round, heavy, ascii)")
    return _BOXES[kind]

func _has_box(kind):
    for k in ["single", "double", "round", "heavy", "ascii"]:
        if k == kind:
            return true
    return false

class Buffer:
    func init(width, height, sgr=""):
        if type(width) != "int" or type(height) != "int" or width < 0 or height < 0:
            raise("ArgumentError", "tui.screen.Buffer : largeur et hauteur entières >= 0 attendues")
        self.width = width
        self.height = height
        self.chars = [" " for i in 0..width * height]
        self.styles = [sgr for i in 0..width * height]
        self.cursor = null             # [x, y] où placer le curseur visible, ou null (caché)
        self._clips = []
        self._clip = [0, 0, width, height]

    func resize(width, height, sgr=""):
        self.init(width, height, sgr)

    func clear(sgr=""):
        n := self.width * self.height
        self.chars = [" " for i in 0..n]
        self.styles = [sgr for i in 0..n]
        self.cursor = null

    # ---------------------------------------------------------------- découpe
    # Restreint le dessin au rectangle (intersection avec la découpe courante).
    func push_clip(x, y, w, h):
        append(self._clips, self._clip)
        c := self._clip
        x0 := _max(x, c[0])
        y0 := _max(y, c[1])
        x1 := _min(x + w, c[0] + c[2])
        y1 := _min(y + h, c[1] + c[3])
        self._clip = [x0, y0, _max(0, x1 - x0), _max(0, y1 - y0)]

    func pop_clip():
        if len(self._clips) > 0:
            self._clip = pop(self._clips)

    func _visible(x, y):
        c := self._clip
        return x >= c[0] and y >= c[1] and x < c[0] + c[2] and y < c[1] + c[3]

    # ---------------------------------------------------------------- cellules
    func get(x, y):
        if x < 0 or y < 0 or x >= self.width or y >= self.height:
            return null
        i := y * self.width + x
        return [self.chars[i], self.styles[i]]

    func _put(x, y, ch, sgr):
        w := self.width
        i := y * w + x
        # Écraser une moitié de caractère large : nettoyer l'autre moitié.
        if self.chars[i] == "" and x > 0:
            self.chars[i - 1] = " "
        if x + 1 < w and self.chars[i + 1] == "" and self.chars[i] != "":
            self.chars[i + 1] = " "
        self.chars[i] = ch
        self.styles[i] = sgr

    # Écrit un caractère (ou une grappe de largeur cw) en (x, y).
    func set(x, y, ch, sgr="", cw=1):
        if not self._visible(x, y):
            return
        if cw == 2:
            if not self._visible(x + 1, y):
                self._put(x, y, " ", sgr)
                return
            self._put(x, y, ch, sgr)
            if x + 2 < self.width and self.chars[y * self.width + x + 2] == "":
                self.chars[y * self.width + x + 2] = " "
            self.chars[y * self.width + x + 1] = ""
            self.styles[y * self.width + x + 1] = sgr
            return
        self._put(x, y, ch, sgr)

    # Écrit text à partir de (x, y) sur une ligne (sans retour à la ligne), au plus max_width colonnes.
    # Renvoie le nombre de colonnes écrites.
    func text(x, y, text, sgr="", max_width=null):
        if y < self._clip[1] or y >= self._clip[1] + self._clip[3]:
            return 0
        col := x
        limit := null
        if max_width != null:
            limit = x + max_width
        for cl in _w.clusters(text):
            cw := cl[1]
            if limit != null and col + cw > limit:
                break
            if col >= self._clip[0] + self._clip[2]:
                break
            if col + cw > self._clip[0]:
                self.set(col, y, cl[0], sgr, cw)
            col += cw
        return col - x

    # Remplit un rectangle avec ch (espace par défaut) dans le style sgr.
    func fill(x, y, w, h, sgr="", ch=" "):
        x0 := _max(x, self._clip[0])
        y0 := _max(y, self._clip[1])
        x1 := _min(x + w, self._clip[0] + self._clip[2])
        y1 := _min(y + h, self._clip[1] + self._clip[3])
        yy := y0
        while yy < y1:
            xx := x0
            while xx < x1:
                self._put(xx, yy, ch, sgr)
                xx += 1
            yy += 1

    # Change le style d'un rectangle sans toucher aux caractères (surlignage d'une sélection).
    func restyle(x, y, w, h, sgr):
        x0 := _max(x, self._clip[0])
        y0 := _max(y, self._clip[1])
        x1 := _min(x + w, self._clip[0] + self._clip[2])
        y1 := _min(y + h, self._clip[1] + self._clip[3])
        yy := y0
        while yy < y1:
            xx := x0
            while xx < x1:
                self.styles[yy * self.width + xx] = sgr
                xx += 1
            yy += 1

    func hline(x, y, w, sgr="", ch="─"):
        i := 0
        while i < w:
            self.set(x + i, y, ch, sgr)
            i += 1

    func vline(x, y, h, sgr="", ch="│"):
        i := 0
        while i < h:
            self.set(x, y + i, ch, sgr)
            i += 1

    # Cadre (kind : "single", "double", "round", "heavy", "ascii" ou liste de 6 caractères) avec un titre
    # facultatif dans la bordure du haut (title_style : style du titre, sinon celui du cadre).
    func box(x, y, w, h, sgr="", kind="single", title=null, title_style=null, fill=null):
        if w < 2 or h < 2:
            return
        c := box_chars(kind)
        if fill != null:
            self.fill(x + 1, y + 1, w - 2, h - 2, fill)
        self.set(x, y, c[0], sgr)
        self.set(x + w - 1, y, c[1], sgr)
        self.set(x, y + h - 1, c[2], sgr)
        self.set(x + w - 1, y + h - 1, c[3], sgr)
        self.hline(x + 1, y, w - 2, sgr, c[4])
        self.hline(x + 1, y + h - 1, w - 2, sgr, c[4])
        self.vline(x, y + 1, h - 2, sgr, c[5])
        self.vline(x + w - 1, y + 1, h - 2, sgr, c[5])
        if title != null and title != "" and w > 4:
            ts := title_style
            if ts == null:
                ts = sgr
            self.text(x + 2, y, " " + _w.truncate(title, w - 6) + " ", ts)

    # Copie un autre tampon en (x, y).
    func blit(other, x, y):
        yy := 0
        while yy < other.height:
            xx := 0
            while xx < other.width:
                i := yy * other.width + xx
                ch := other.chars[i]
                if ch != "" and self._visible(x + xx, y + yy):
                    cw := 1
                    if xx + 1 < other.width and other.chars[i + 1] == "":
                        cw = 2
                    self.set(x + xx, y + yy, ch, other.styles[i], cw)
                xx += 1
            yy += 1

    # ---------------------------------------------------------------- lecture (tests)
    # Texte d'une ligne (sans les styles, espaces de fin compris).
    func row_text(y):
        out := []
        i := y * self.width
        end := i + self.width
        while i < end:
            if self.chars[i] != "":
                append(out, self.chars[i])
            i += 1
        return _s.join("", out)

    # Toutes les lignes ; trim=true retire les espaces de fin.
    func lines(trim=true):
        out := []
        y := 0
        while y < self.height:
            t := self.row_text(y)
            if trim:
                t = _rtrim(t)
            append(out, t)
            y += 1
        return out

    # Le texte des lignes joint par « \n » (instantané lisible).
    func dump():
        return _s.join("\n", self.lines())

    # Style de la cellule (x, y).
    func style_at(x, y):
        c := self.get(x, y)
        if c == null:
            return null
        return c[1]

    # Le tampon en texte avec ses styles (séquences ANSI) : pour l'afficher hors du mode plein écran.
    func to_ansi():
        out := []
        y := 0
        while y < self.height:
            cur := ""
            i := y * self.width
            end := i + self.width
            while i < end:
                if self.chars[i] != "":
                    if self.styles[i] != cur:
                        cur = self.styles[i]
                        append(out, _st.ansi(cur))
                    append(out, self.chars[i])
                i += 1
            if cur != "":
                append(out, _st.RESET)
            if y + 1 < self.height:
                append(out, "\n")
            y += 1
        return _s.join("", out)

func _rtrim(t):
    n := len(t)
    while n > 0 and t[n - 1] == ' ':
        n -= 1
    return _s.slice(t, 0, n)

func _min(a, b):
    if a < b:
        return a
    return b

func _max(a, b):
    if a > b:
        return a
    return b

# ---------------------------------------------------------------- rendu différentiel
func move_to(x, y):
    return "\e[" + str(y + 1) + ";" + str(x + 1) + "H"

# Séquences ANSI qui transforment l'image prev (Buffer ou null : écran inconnu) en cur. depth : couleurs du
# terminal ("truecolor", "256", "16", "none"). Le curseur est ensuite placé en cur.cursor (ou caché).
func render_diff(prev, cur, depth="truecolor"):
    out := []
    full := prev == null or prev.width != cur.width or prev.height != cur.height
    if full:
        append(out, "\e[0m\e[2J")
    w := cur.width
    active := null
    y := 0
    while y < cur.height:
        row := y * w
        first := -1
        last := -1
        x := 0
        while x < w:
            i := row + x
            if full or cur.chars[i] != prev.chars[i] or cur.styles[i] != prev.styles[i]:
                if first < 0:
                    first = x
                last = x
            x += 1
        if first >= 0:
            if first > 0 and cur.chars[row + first] == "":
                first -= 1
            if last + 1 < w and cur.chars[row + last + 1] == "":
                last += 1
            append(out, move_to(first, y))
            x = first
            while x <= last:
                i := row + x
                ch := cur.chars[i]
                if ch != "":
                    sg := cur.styles[i]
                    if sg != active:
                        active = sg
                        append(out, _st.ansi(_st.downgrade(sg, depth)))
                    append(out, ch)
                x += 1
        y += 1
    if active != null and active != "":
        append(out, _st.RESET)
    if cur.cursor != null:
        append(out, move_to(cur.cursor[0], cur.cursor[1]) + "\e[?25h")
    else:
        append(out, "\e[?25l")
    return _s.join("", out)

# Copie indépendante d'un tampon (image précédente du rendu différentiel).
func copy(buf):
    b := Buffer(0, 0)
    b.width = buf.width
    b.height = buf.height
    b.chars = [c for c in buf.chars]
    b.styles = [s for s in buf.styles]
    b.cursor = buf.cursor
    b._clip = [0, 0, buf.width, buf.height]
    return b

func _esc_html(t):
    return _s.replace(_s.replace(_s.replace(t, "&", "&amp;"), "<", "&lt;"), ">", "&gt;")

# Le tampon en HTML (<pre> coloré) : captures d'écran, documentation. fg et bg : couleurs par défaut.
func to_html(buf, fg="#d0d0d0", bg="#101010", font="DejaVu Sans Mono, Menlo, Consolas, monospace"):
    out := ["<pre style=\"margin:0;padding:8px;line-height:1.25;font-family:" + font + ";font-size:14px;color:" + fg + ";background:" + bg + "\">"]
    y := 0
    while y < buf.height:
        x := 0
        run_style := null
        run := []
        while x < buf.width:
            i := y * buf.width + x
            ch := buf.chars[i]
            if ch != "":
                sg := buf.styles[i]
                if buf.cursor != null and buf.cursor[0] == x and buf.cursor[1] == y:
                    sg = sg + ";7" if sg != "" else "7"
                if sg != run_style:
                    if len(run) > 0:
                        append(out, _span(run_style, _s.join("", run), fg, bg))
                    run = []
                    run_style = sg
                append(run, ch)
            x += 1
        if len(run) > 0:
            append(out, _span(run_style, _s.join("", run), fg, bg))
        append(out, "\n")
        y += 1
    append(out, "</pre>")
    return _s.join("", out)

func _span(sgr, text, dfg, dbg):
    a := _st.decode(sgr)
    f := a["fg"] if a["fg"] != null else dfg
    b := a["bg"] if a["bg"] != null else dbg
    if a["reverse"]:
        t := f
        f = b
        b = t
    css := "color:" + f + ";background:" + b
    if a["bold"]:
        css += ";font-weight:bold"
    if a["dim"]:
        css += ";opacity:0.55"
    if a["italic"]:
        css += ";font-style:italic"
    if a["underline"]:
        css += ";text-decoration:underline"
    return "<span style=\"" + css + "\">" + _esc_html(text) + "</span>"
