# ALEX STANDARD LIBRARY — tui
#
# Interfaces plein écran dans le terminal. La vue est décrite avec ui.view (les mêmes composants
# que gui.run dans une fenêtre) :
#
#   use ui.view as v
#   use tui
#   etat := {"n": 0}
#   func plus():
#       etat["n"] += 1
#   func vue():
#       return v.column([v.text("Valeur : " + str(etat["n"])), v.button("+1", plus)], padding=1)
#   tui.run(vue)
#
# Clavier : Tab / Maj+Tab, flèches, Entrée, Espace, Échap, F10 (menus), Ctrl+Q ou Ctrl+C pour quitter.
# Souris : clics, glisser, molette (désactivable : mouse=false). Le terminal retrouve son état à la sortie,
# même après une erreur ou un signal TERM / HUP.
#
# Modules de plus bas niveau : tui.terminal (écran alternatif, saisie brute, terminal virtuel),
# tui.screen (tampon de cellules et rendu différentiel), tui.input (décodage des touches et de la souris),
# tui.style (couleurs), tui.width (largeur du texte), tui.markup (balisage « [bold red]...[/] »),
# tui.inline (composants en ligne : menus, saisies, tableaux, barres de progression, spinners).
#
# Tests sans terminal : TestApp(vue, largeur, hauteur) pilote l'application sur un terminal virtuel
# (press, type, click, wheel, paste) et donne l'écran (lines, contains, find).

from core use len, type
use string as _s
use ui.view.runtime as _rt
use tui.surface as _sf
use tui.terminal as _term
use tui.screen as _screen

# Vrai si l'entrée et la sortie standard sont un terminal.
func available():
    return _term.available()

# Lance l'application ; revient quand elle se termine (ui.view.quit(), Ctrl+Q / Ctrl+C, fin de l'entrée).
# Renvoie la valeur donnée à app.stop(valeur), sinon null.
#   on_key(touche) : touches non utilisées par les composants (true : traitée)
#   on_tick(temps) : appelé toutes les tick secondes (horloges, animations, données qui changent)
#   theme : "dark", "light", "terminal" (couleurs du terminal) ou un dict de rôles
func run(view, title=null, theme="dark", on_key=null, on_tick=null, tick=null, mouse=true, quit_keys=null):
    if quit_keys == null:
        quit_keys = ["ctrl+q", "ctrl+c"]
    t := _term.Terminal("drag" if mouse else false)
    s := _sf.Surface(t, theme)
    app := _rt.App(view, s, on_key, on_tick, tick, quit_keys)
    if title != null:
        t.set_title(title)
    return app.run()

class TestApp:
    func init(view, width=80, height=24, theme="dark", on_key=null, emulate=false):
        self.term = _term.VirtualTerminal(width, height, emulate)
        self.surface = _sf.Surface(self.term, theme, true)
        self.app = _rt.App(view, self.surface, on_key, null, null, ["ctrl+q", "ctrl+c"])
        self.app.running = true
        _rt.set_current(self.app)
        self.app.render()

    # Touches par leur nom (« tab », « enter », « down », « ctrl+s », « a »...), puis nouvel affichage.
    func press(name, times=1):
        i := 0
        while i < times:
            self.term.key(name)
            i += 1
        return self.step()

    func type(text):
        self.term.type_text(text)
        return self.step()

    func paste(text):
        self.term.paste(text)
        return self.step()

    # Clic sur le texte affiché target (premier endroit de l'écran où il apparaît), ou en (target, y).
    func click(target, y=null, clicks=1):
        pos := self.where(target, y)
        k := 0
        while k < clicks:
            self.term.click(pos[0], pos[1])
            k += 1
        return self.step()

    func double_click(target, y=null):
        return self.click(target, y, 2)

    func drag(x0, y0, x1, y1):
        self.term.mouse("down", x0, y0)
        self.term.mouse("drag", x1, y1)
        self.term.mouse("up", x1, y1)
        return self.step()

    func move(target, y=null):
        pos := self.where(target, y)
        self.term.mouse("move", pos[0], pos[1])
        return self.step()

    func wheel(target, dy, y=null):
        pos := self.where(target, y)
        self.term.mouse("wheel", pos[0], pos[1], null, dy)
        return self.step()

    func resize(width, height):
        self.term.resize(width, height)
        return self.step()

    func where(target, y=null):
        if y != null:
            return [target, y]
        p := self.term.find(target)
        if p == null:
            raise("ArgumentError", "TestApp : « " + str(target) + " » n'est pas à l'écran")
        return p

    func step():
        _rt.set_current(self.app)
        return self.app.step()

    # Écran : lignes (sans espaces de fin), texte complet, présence d'un texte.
    func lines():
        return self.term.lines()

    func screen():
        return self.term.screen_text()

    func contains(text):
        return self.term.contains(text)

    func find(text):
        return self.term.find(text)

    func line(y):
        ls := self.term.lines()
        if y < len(ls):
            return ls[y]
        return ""

    # Composant qui a le focus (ui.view.node.Node), ou null.
    func focused():
        return self.app.focused()

    func running():
        return self.app.running

    func cursor():
        return self.surface.buf.cursor

    func style_at(x, y):
        return self.term.style_at(x, y)

    # L'écran en HTML coloré (captures, documentation).
    func html():
        th := self.surface.theme
        fg := th["text"] if th["text"] != null else "#d0d0d0"
        bg := th["bg"] if th["bg"] != null else "#101010"
        return _screen.to_html(self.surface.buf, fg, bg)
