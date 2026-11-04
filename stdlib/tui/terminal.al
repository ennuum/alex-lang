# ALEX STANDARD LIBRARY — tui.terminal
#
# Le terminal en mode plein écran : écran alternatif (l'affichage d'avant revient à la sortie), saisie brute
# (touche par touche, sans écho), souris, collage, redimensionnement. Terminal() pilote le vrai terminal ;
# VirtualTerminal(largeur, hauteur) a la même interface sans terminal (tests, enregistrement) : on y injecte
# des événements et on lit l'écran obtenu.
#
# Interface commune
#   start() / stop()            entrer / sortir du mode plein écran (stop rétablit tout, même après une erreur)
#   size() -> [colonnes, lignes]
#   read(timeout) -> événement (voir tui.input) ou {"type": "resize", "width", "height"}, null après timeout
#   present(buffer)             affiche un tui.screen.Buffer (seules les cellules modifiées sont réécrites)
#   bell(), set_title(texte)
#
#   use tui.terminal as terminal
#   use tui.screen as screen
#   t := terminal.Terminal()
#   t.start()
#   try:
#       b := screen.Buffer(t.size()[0], t.size()[1])
#       b.text(0, 0, "Appuyer sur une touche")
#       t.present(b)
#       print(t.read())
#   finally:
#       t.stop()
#
# Erreurs : IoError (pas de terminal : entrée ou sortie redirigée).

from core use len, type
from collections use append, pop
use string as _s
use os as _os
use _native_fd as _f
use _native_net as _b
use _native_cli as _cli
use _native_signal as _sig
use tui.input as _in
use tui.screen as _screen
use tui.emulator as _emu
use tui.width as _tw

# Couleurs du terminal d'après l'environnement : "truecolor", "256", "16" ou "none".
func color_depth():
    if _os.getenv("NO_COLOR") != null:
        return "none"
    ct := _os.getenv("COLORTERM", "")
    if ct == "truecolor" or ct == "24bit":
        return "truecolor"
    term := _os.getenv("TERM", "")
    if term == "dumb" or term == "":
        if _os.platform() == "windows":
            return "truecolor"
        return "none"
    if _s.contains(term, "256") or _s.contains(term, "kitty") or _s.contains(term, "alacritty") or _s.contains(term, "wezterm"):
        return "256"
    return "16"

# Vrai si l'entrée et la sortie standard sont des terminaux.
func available():
    return _f.isatty(0) and _f.isatty(1)

func _write(text):
    _cli.write_out(text)
    _cli.flush()

class Terminal:
    # mouse : "drag" (clics, glisser, molette), "all" (aussi les survols), false (pas de souris).
    func init(mouse="drag", paste=true, alternate=true, depth=null):
        self.mouse = mouse
        self.paste = paste
        self.alternate = alternate
        self.depth = depth
        if depth == null:
            self.depth = color_depth()
        self.active = false
        self._decoder = _in.Decoder()
        self._queue = []
        self._raw_tail = ""
        self._last = null
        self._size = null
        self._signals = []

    func size():
        t := _os.terminal()
        w := t["columns"]
        h := t["rows"]
        if w == null:
            w = 80
        if h == null:
            h = 24
        return [w, h]

    func start():
        if self.active:
            return
        if not available():
            raise("IoError", "tui : un terminal est nécessaire (entrée et sortie standard)")
        _f.set_mode(0, true, false)
        seq := ""
        if self.alternate:
            seq += "\e[?1049h"
        seq += "\e[?25l\e[2J\e[H"
        if self.mouse == "all":
            seq += "\e[?1000h\e[?1003h\e[?1006h"
        elif self.mouse:
            seq += "\e[?1000h\e[?1002h\e[?1006h"
        if self.paste:
            seq += "\e[?2004h"
        _write(seq)
        self.active = true
        self._last = null
        self._size = self.size()
        # Un arrêt demandé (TERM, HUP) doit laisser le terminal propre : InterruptError, puis stop() dans finally.
        if _sig.supported() and _sig.is_main_thread():
            for name in ["TERM", "HUP"]:
                n := _sig.number(name)
                _sig.set_dispatcher(_on_signal)
                if _sig.intercept(n, true) == 0:
                    append(self._signals, n)
            w := _sig.number("WINCH")
            if _sig.intercept(w, false) == 0:
                append(self._signals, w)

    func stop():
        if not self.active:
            return
        seq := "\e[0m"
        if self.paste:
            seq += "\e[?2004l"
        if self.mouse:
            seq += "\e[?1006l\e[?1003l\e[?1002l\e[?1000l"
        seq += "\e[?25h"
        if self.alternate:
            seq += "\e[?1049l"
        _write(seq)
        _f.restore(0)
        for n in self._signals:
            _sig.reset(n)
        self._signals = []
        self.active = false

    func _check_resize():
        s := self.size()
        if self._size == null or s[0] != self._size[0] or s[1] != self._size[1]:
            self._size = s
            self._last = null
            append(self._queue, {"type": "resize", "width": s[0], "height": s[1]})

    # Prochain événement, ou null après timeout secondes (null : attendre sans limite).
    func read(timeout=null):
        started := _os.monotonic_time()
        while true:
            if len(self._queue) > 0:
                ev := self._queue[0]
                self._queue = [self._queue[i] for i in 1..len(self._queue)]
                return ev
            self._check_resize()
            if len(self._queue) > 0:
                continue
            slice := 0.05
            if self._decoder.waiting():
                slice = 0.03
            if timeout != null:
                left := timeout - (_os.monotonic_time() - started)
                if left <= 0:
                    return null
                if left < slice:
                    slice = left
            data := _f.read(0, 4096, slice)
            if data == null:
                if self._decoder.waiting():
                    for e in self._decoder.flush():
                        append(self._queue, e)
                continue
            if type(data) == "int":
                raise("IoError", "tui : lecture du terminal impossible (" + _f.strerror(data) + ")")
            if data == "":
                append(self._queue, {"type": "eof"})
                continue
            raw := self._raw_tail + data
            whole := _b.utf8_prefix(raw)
            self._raw_tail = _b.bslice(raw, whole, _b.blen(raw))
            for e in self._decoder.feed(_b.bslice(raw, 0, whole)):
                append(self._queue, e)

    func present(buffer):
        if not self.active:
            raise("IoError", "tui : terminal non démarré (start)")
        _write(_screen.render_diff(self._last, buffer, self.depth))
        self._last = _screen.copy(buffer)

    # Force un rendu complet au prochain present (après un affichage étranger).
    func invalidate():
        self._last = null

    func bell():
        _write("\x07")

    func set_title(text):
        _write("\e]0;" + str(text) + "\x07")

func _on_signal(num):
    raise("InterruptError", "signal " + str(_sig.name(num)) + " reçu")

# ---------------------------------------------------------------- terminal virtuel
class VirtualTerminal:
    # emulate=true : les séquences produites par present() sont rejouées par un émulateur ANSI (tui.emulator),
    # et screen_text() lit l'écran émulé (vérifie le rendu différentiel de bout en bout).
    func init(width=80, height=24, emulate=false, depth="truecolor"):
        self.width = width
        self.height = height
        self.depth = depth
        self.active = false
        self.events = []
        self.frames = 0
        self.last = null
        self.output = []          # séquences ANSI émises (emulate=true)
        self.emulator = null
        if emulate:
            self.emulator = _emu.Emulator(width, height)
        self._prev = null
        self.bells = 0
        self.title = null

    func size():
        return [self.width, self.height]

    func start():
        self.active = true

    func stop():
        self.active = false

    # Événement suivant ; null quand la file est vide (sans attendre).
    func read(timeout=null):
        if len(self.events) == 0:
            return null
        ev := self.events[0]
        self.events = [self.events[i] for i in 1..len(self.events)]
        return ev

    func pending():
        return len(self.events)

    func present(buffer):
        self.frames += 1
        if self.emulator != null:
            out := _screen.render_diff(self._prev, buffer, self.depth)
            append(self.output, out)
            self.emulator.feed(out)
            self._prev = _screen.copy(buffer)
        self.last = _screen.copy(buffer)

    func invalidate():
        self._prev = null

    func bell():
        self.bells += 1

    func set_title(text):
        self.title = text

    # ---- injection ----
    # Touche par son nom (« enter », « ctrl+c », « up », « a ») ; un nom d'un caractère est aussi du texte.
    func key(name):
        ev := {"type": "key", "key": name, "text": null, "ctrl": _s.starts_with(name, "ctrl+"), "alt": _s.contains(name, "alt+"), "shift": _s.contains(name, "shift+")}
        if len(name) == 1:
            ev["text"] = name
        if name == "space":
            ev["text"] = " "
        append(self.events, ev)

    # Chaque caractère du texte comme une touche.
    func type_text(text):
        for c in text:
            if c == ' ':
                self.key("space")
            else:
                self.key(str(c))

    func mouse(action, x, y, button="left", dy=0):
        b := button
        if action == "wheel" or action == "move":
            b = null
        append(self.events, {"type": "mouse", "action": action, "button": b, "x": x, "y": y, "dx": 0, "dy": dy, "ctrl": false, "alt": false, "shift": false})

    func click(x, y, button="left"):
        self.mouse("down", x, y, button)
        self.mouse("up", x, y, button)

    func paste(text):
        append(self.events, {"type": "paste", "text": text})

    # Octets bruts, décodés comme ceux d'un vrai terminal.
    func feed(data):
        for e in _in.decode(data):
            append(self.events, e)

    func resize(width, height):
        self.width = width
        self.height = height
        if self.emulator != null:
            self.emulator.resize(width, height)
            self._prev = null
        append(self.events, {"type": "resize", "width": width, "height": height})

    func push(ev):
        append(self.events, ev)

    # ---- lecture ----
    # Lignes de l'écran affiché (émulé si emulate=true), espaces de fin retirés.
    func lines():
        if self.emulator != null:
            return self.emulator.lines()
        if self.last == null:
            return []
        return self.last.lines()

    func screen_text():
        return _s.join("\n", self.lines())

    # Vrai si le texte apparaît à l'écran.
    func contains(text):
        for line in self.lines():
            if _s.contains(line, text):
                return true
        return false

    # Coordonnées [x, y] de la première occurrence du texte à l'écran, ou null.
    func find(text):
        y := 0
        for line in self.lines():
            k := _s.find(line, text)
            if k >= 0:
                return [_wof(_s.slice(line, 0, k)), y]
            y += 1
        return null

    func style_at(x, y):
        if self.last == null:
            return null
        return self.last.style_at(x, y)

func _wof(t):
    return _tw.of(t)
