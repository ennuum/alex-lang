# ALEX STANDARD LIBRARY — ui.dialog
#
# Dialogues pour les interfaces ui.view (fenêtre ou terminal) : une PILE de dialogues modaux gérée par un
# DialogManager — message, confirmation, saisie de texte avec validation, choix dans une liste, progression —
# avec des rappels pour le résultat. La vue de l'application ajoute manager.overlay() à son arbre (le dialogue du
# dessus est affiché, les autres attendent). Et les dialogues de fichiers natifs (ouvrir / enregistrer) avec un
# constructeur de filtres.
#
#   use ui.view as v
#   use ui.dialog as dlg
#   dm := dlg.DialogManager()
#   dm.confirm("Quitter", "Abandonner les modifications ?", (oui) => v.quit() if oui else null)
#   dm.prompt("Renommer", "Nouveau nom :", "rapport", (nom) => renommer(nom), (t) => null if t != "" else "nom vide")
#   dm.choose("Format", ["PDF", "HTML", "Texte"], (i) => exporter(i))
#   func vue():
#       return v.column([contenu(), dm.overlay()])       # overlay() vaut un espace vide sans dialogue
#   dlg.open_file(dlg.filters([["Images", "*.png;*.jpg"], ["Tous", "*.*"]]))   # dialogue natif (Windows)
#
# Erreurs : ArgumentError (choix vide), UiError (dialogue natif indisponible sur la plateforme).

from core use len, type
from collections use append
use string as _s
use ui.view as _v
use ui.file_dialog as _file_dialog

class Dialog:
    func init(kind, title, message=null, on_result=null):
        self.kind = kind
        self.title = title
        self.message = message
        self.on_result = on_result
        self.value = null
        self.error = null
        self.options = []
        self.selected = 0
        self.validate = null
        self.progress = 0.0
        self.closed = false
        self.result = null

class DialogManager:
    func init():
        self.stack = []
        self.history = []

    func size():
        return len(self.stack)

    func top():
        if len(self.stack) == 0:
            return null
        return self.stack[len(self.stack) - 1]

    func _push(d):
        append(self.stack, d)
        return d

    func close(d, result=null):
        if d.closed:
            return
        d.closed = true
        d.result = result
        self.stack = [x for x in self.stack if not (x.closed)]
        append(self.history, [d.kind, d.title, result])
        if d.on_result != null:
            f := d.on_result
            f(result)

    func alert(title, message, on_close=null):
        return self._push(Dialog("alert", title, message, (r) => on_close() if on_close != null else null))

    func confirm(title, message, on_result=null, yes="Oui", no="Non"):
        d := Dialog("confirm", title, message, on_result)
        d.options = [yes, no]
        return self._push(d)

    # validate(texte) -> null si correct, sinon le message d'erreur affiché.
    func prompt(title, message, default="", on_result=null, validate=null):
        d := Dialog("prompt", title, message, on_result)
        d.value = default
        d.validate = validate
        return self._push(d)

    func choose(title, options, on_result=null, selected=0):
        if len(options) == 0:
            raise("ArgumentError", "choose : au moins une option")
        d := Dialog("choose", title, null, on_result)
        d.options = options
        d.selected = selected
        return self._push(d)

    func progress(title, message=null):
        d := Dialog("progress", title, message, null)
        return self._push(d)

    func set_progress(d, value, message=null):
        d.progress = value
        if message != null:
            d.message = message
        if value >= 1.0:
            self.close(d, true)

    # Actions programmatiques (raccourcis, tests).
    func accept(d=null):
        x := d
        if x == null:
            x = self.top()
        if x == null:
            return false
        if x.kind == "prompt":
            if x.validate != null:
                f := x.validate
                err := f(x.value)
                if err != null:
                    x.error = err
                    return false
            self.close(x, x.value)
        elif x.kind == "confirm":
            self.close(x, true)
        elif x.kind == "choose":
            self.close(x, x.selected)
        else:
            self.close(x, true)
        return true

    func cancel(d=null):
        x := d
        if x == null:
            x = self.top()
        if x == null:
            return false
        if x.kind == "confirm":
            self.close(x, false)
        else:
            self.close(x, null)
        return true

    func set_value(text):
        x := self.top()
        if x != null:
            x.value = text
            x.error = null

    func select(i):
        x := self.top()
        if x != null:
            x.selected = i

    # Nœud ui.view du dialogue du dessus (spacer sans dialogue).
    func overlay():
        d := self.top()
        if d == null:
            return _v.spacer(0)
        if d.kind == "alert":
            return _v.alert(d.title, d.message, () => self.close(d, true))
        if d.kind == "confirm":
            return _v.confirm(d.title, d.message, () => self.close(d, true), () => self.close(d, false), d.options[0], d.options[1])
        if d.kind == "prompt":
            content := [_v.text(d.message, wrap=true), _v.field(d.value, (t) => self.set_value(t), (t) => self.accept(d))]
            if d.error != null:
                append(content, _v.text(d.error, style="error"))
            return _v.dialog(d.title, content, [["OK", () => self.accept(d)], ["Annuler", () => self.cancel(d)]], () => self.cancel(d))
        if d.kind == "choose":
            return _v.dialog(d.title, [_v.list_view(d.options, d.selected, (i) => self.select(i), (i) => self._choose_now(d, i))],
                             [["Choisir", () => self.accept(d)], ["Annuler", () => self.cancel(d)]], () => self.cancel(d))
        content := []
        if d.message != null:
            append(content, _v.text(d.message))
        append(content, _v.progress(d.progress))
        return _v.dialog(d.title, content, [], null)

    func _choose_now(d, i):
        d.selected = i
        self.accept(d)

# Filtre de dialogue natif à partir de [[libellé, "*.png;*.jpg"], ...].
func filters(pairs):
    out := ""
    for p in pairs:
        out += p[0] + " (" + p[1] + ")\0" + p[1] + "\0"
    return out

func open_file(filter="Tous les fichiers\0*.*\0"):
    return _file_dialog.open(filter)

func save_file(filter="Tous les fichiers\0*.*\0"):
    return _file_dialog.save(filter)
