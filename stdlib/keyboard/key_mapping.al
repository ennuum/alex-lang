# ALEX STANDARD LIBRARY — keyboard.key_mapping
#
# Correspondances clavier : liaisons raccourci -> ACTION (nommée), par CONTEXTE (global, éditeur, menu... avec
# héritage), SÉQUENCES de touches (« ctrl+k ctrl+c », comme Emacs / VS Code) avec délai, REMAPPAGE de touches
# physiques (caps_lock -> escape), détection des conflits, et sauvegarde JSON. handle(KeyEvent) rend l'action.
#
#   use keyboard.key_mapping as km
#   m := km.KeyMap()
#   m.bind("ctrl+s", "fichier.enregistrer")
#   m.bind("ctrl+k ctrl+c", "edition.commenter")              # séquence
#   m.bind("escape", "menu.fermer", "menu")                   # seulement dans le contexte « menu »
#   m.context("menu", "global")                               # menu hérite de global
#   m.remap("caps_lock", "escape")
#   m.on_action((action, ev) => executer(action))
#   for ev in evenements:                                      # keyboard.key_event.KeyEvent
#       m.handle(ev)                                           # « fichier.enregistrer », null, ou « … » (séquence entamée)
#   print(m.conflicts(), m.bindings_for("edition.commenter"), m.describe())
#   km.from_dict(m.to_dict())
#
# Erreurs : ShortcutError (raccourci mal formé), MappingError (contexte inconnu, boucle d'héritage ou de remappage).

from core use len, type
from collections use append
use string as _s
use os as _os
use keyboard.key_event as _ke
use keyboard.key as _key

const PENDING := "…"

func _norm_combo(text):
    try:
        r := _ke.parse_shortcut(text)
        return _ke.format_shortcut(r[0], r[1])
    catch e:
        raise("ShortcutError", e.message)

func normalize_sequence(seq):
    parts := [p for p in _s.split(_s.trim(seq), " ") if p != ""]
    if len(parts) == 0:
        raise("ShortcutError", "séquence vide")
    return _s.join(" ", [_norm_combo(p) for p in parts])

class KeyMap:
    func init(sequence_timeout=1.5):
        self.contexts = {"global": null}    # contexte -> parent
        self.bindings = {}                   # contexte -> {séquence: action}
        self.bindings["global"] = {}
        self.remaps = {}
        self.active = "global"
        self.timeout = sequence_timeout
        self.pending = []
        self.pending_time = 0.0
        self.listeners = []
        self.clock = null

    func context(name, parent="global"):
        if parent != null and not (parent in self.contexts):
            raise("MappingError", "contexte parent inconnu : " + parent)
        self.contexts[name] = parent
        if not (name in self.bindings):
            self.bindings[name] = {}
        self._chain(name)
        return self

    func _chain(name):
        out := []
        cur := name
        while cur != null:
            if cur in out:
                raise("MappingError", "boucle d'héritage de contextes : " + _s.join(" -> ", out + [cur]))
            append(out, cur)
            cur = self.contexts[cur]
        return out

    func set_context(name):
        if not (name in self.contexts):
            raise("MappingError", "contexte inconnu : " + name)
        self.active = name
        self.pending = []
        return self

    func bind(sequence, action, ctx="global"):
        if not (ctx in self.contexts):
            self.context(ctx)
        self.bindings[ctx][normalize_sequence(sequence)] = action
        return self

    func unbind(sequence, ctx="global"):
        k := normalize_sequence(sequence)
        if ctx in self.bindings and k in self.bindings[ctx]:
            del self.bindings[ctx][k]
            return true
        return false

    func remap(src, dst):
        a := _key.normalize(src)
        b := _key.normalize(dst)
        if b == a:
            raise("MappingError", "remappage d'une touche vers elle-même : " + a)
        seen := [a, b]
        cur := b
        while cur in self.remaps:
            cur = self.remaps[cur]
            if cur == a or cur in seen:
                raise("MappingError", "boucle de remappage : " + _s.join(" -> ", seen + [cur]))
            append(seen, cur)
        self.remaps[a] = b
        return self

    func apply_remap(ev):
        if ev.key in self.remaps:
            return _ke.KeyEvent(self.remaps[ev.key], ev.action, ev.mods, ev.text, ev.code, ev.source, ev.time)
        return ev

    func on_action(fn):
        append(self.listeners, fn)
        return self

    func _now():
        if self.clock != null:
            c := self.clock
            return c()
        return _os.monotonic_time()

    func lookup(sequence):
        k := normalize_sequence(sequence)
        for ctx in self._chain(self.active):
            if k in self.bindings[ctx]:
                return self.bindings[ctx][k]
        return null

    func _is_prefix(seq):
        for ctx in self._chain(self.active):
            for k in self.bindings[ctx]:
                if _s.starts_with(k, seq + " "):
                    return true
        return false

    # Action déclenchée par l'événement, PENDING si une séquence est entamée, ou null.
    func handle(ev):
        if ev == null or ev.action == "release":
            return null
        if _key.is_modifier(ev.key):
            return null
        e := self.apply_remap(ev)
        now := self._now()
        if len(self.pending) > 0 and now - self.pending_time > self.timeout:
            self.pending = []
        combo := _ke.format_shortcut(e.key, e.mods & 15)
        seq := _s.join(" ", self.pending + [combo])
        act := null
        for ctx in self._chain(self.active):
            if seq in self.bindings[ctx]:
                act = self.bindings[ctx][seq]
                break
        if act != null:
            self.pending = []
            for l in self.listeners:
                l(act, e)
            return act
        if self._is_prefix(seq):
            self.pending = self.pending + [combo]
            self.pending_time = now
            return PENDING
        if len(self.pending) > 0:
            self.pending = []
            return self.handle(ev)
        return null

    func bindings_for(action):
        out := []
        for ctx in self.bindings:
            for k in self.bindings[ctx]:
                if self.bindings[ctx][k] == action:
                    append(out, [ctx, k])
        return out

    # Conflits : même séquence liée à des actions différentes dans un contexte et ses ancêtres, ou séquence qui
    # en masque une autre (préfixe).
    func conflicts():
        out := []
        for ctx in self.bindings:
            chain := self._chain(ctx)
            for k in self.bindings[ctx]:
                for anc in chain[1:]:
                    if k in self.bindings[anc] and not (self.bindings[anc][k] == self.bindings[ctx][k]):
                        append(out, {"kind": "masquage", "sequence": k, "context": ctx, "hides": anc})
                for k2 in self.bindings[ctx]:
                    if k2 != k and _s.starts_with(k2, k + " "):
                        append(out, {"kind": "préfixe", "sequence": k, "context": ctx, "blocks": k2})
        return out

    func describe():
        lines := []
        for ctx in self.bindings:
            for k in self.bindings[ctx]:
                append(lines, _pad(ctx, 10) + _pad(k, 22) + self.bindings[ctx][k])
        for r in self.remaps:
            append(lines, "remap     " + r + " -> " + self.remaps[r])
        return _s.join("\n", lines)

    func to_dict():
        return {"contexts": self.contexts, "bindings": self.bindings, "remaps": self.remaps, "timeout": self.timeout}

func _pad(s, n):
    out := s
    while len(out) < n:
        out += " "
    return out + " "

func from_dict(d):
    m := KeyMap(d["timeout"])
    pending := [k for k in d["contexts"] if k != "global"]
    guard := 0
    while len(pending) > 0 and guard < 100:
        rest := []
        for c in pending:
            p := d["contexts"][c]
            if p == null or p in m.contexts:
                m.contexts[c] = p
                m.bindings[c] = {}
            else:
                append(rest, c)
        pending = rest
        guard += 1
    for ctx in d["bindings"]:
        for k in d["bindings"][ctx]:
            m.bind(k, d["bindings"][ctx][k], ctx)
    for r in d["remaps"]:
        m.remap(r, d["remaps"][r])
    return m
