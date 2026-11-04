# ALEX STANDARD LIBRARY — multimedia.playback.playlist
#
# Listes de lecture : entrées (chemin ou URL, titre, durée), entrée courante, suivant / précédent, modes de
# répétition (« none », « one », « all »), lecture aléatoire REPRODUCTIBLE (graine), ajout, retrait, déplacement ;
# lecture et écriture M3U / M3U8 étendu (#EXTINF) et PLS. Les chemins relatifs sont résolus par rapport au
# dossier de la liste.
#
#   use multimedia.playback.playlist as pl
#   p := pl.load("soiree.m3u")
#   p.set_repeat("all")
#   p.shuffle(42)
#   e := p.current()                      # Entry : path, title, duration
#   e2 := p.next()                        # null en fin de liste (repeat « none »)
#   pl.save(p, "copie.pls")
#
# Erreurs : CorruptDataError (PLS mal formé), LimitError (nombre d'entrées), FormatError, MediaError.

from core use len, type, to_int, to_float
from collections use append, keys
use string as _s
use io as _io
use os as _os
use multimedia.core.errors as merr
use multimedia.security.limits as lim

class Entry:
    func init(path, title=null, duration=null):
        self.path = path
        self.title = title
        self.duration = duration

    func label():
        if self.title != null and len(self.title) > 0:
            return self.title
        return _os.basename(self.path)

const REPEAT := ["none", "one", "all"]

class Playlist:
    func init(entries=null, limits=null):
        self.limits = lim.of(limits)
        self.entries = []
        self.order = []
        self.pos = 0
        self.repeat = "none"
        self.shuffled = false
        if entries != null:
            for e in entries:
                self.add(e)

    func _check():
        self.limits.check("max_playlist_items", len(self.entries))

    func add(entry, title=null, duration=null):
        e := entry
        if type_is_str(entry):
            e = Entry(entry, title, duration)
        append(self.entries, e)
        append(self.order, len(self.entries) - 1)
        self._check()
        return e

    func size():
        return len(self.entries)

    func is_empty():
        return len(self.entries) == 0

    func remove(index):
        if index < 0 or index >= len(self.entries):
            merr.fail(merr.FORMAT, "indice de liste hors limites : " + str(index))
        cur := self.current_index()
        self.entries = [self.entries[k] for k in 0..len(self.entries) if k != index]
        self.order = [(o - 1 if o > index else o) for o in self.order if o != index]
        if len(self.order) == 0:
            self.pos = 0
        elif cur == index:
            if self.pos >= len(self.order):
                self.pos = len(self.order) - 1
        else:
            self.select(cur - 1 if cur > index else cur)

    func move(src, dst):
        if src < 0 or src >= len(self.entries) or dst < 0 or dst >= len(self.entries):
            merr.fail(merr.FORMAT, "déplacement hors limites")
        cur := self.current()
        e := self.entries[src]
        rest := [self.entries[k] for k in 0..len(self.entries) if k != src]
        self.entries = [rest[k] for k in 0..dst] + [e] + [rest[k] for k in dst..len(rest)]
        self.order = [k for k in 0..len(self.entries)]
        self.shuffled = false
        if cur != null:
            for k in 0..len(self.entries):
                if self.entries[k] == cur:
                    self.pos = k

    func current_index():
        if len(self.order) == 0:
            return -1
        return self.order[self.pos]

    func current():
        i := self.current_index()
        if i < 0:
            return null
        return self.entries[i]

    func select(index):
        for k in 0..len(self.order):
            if self.order[k] == index:
                self.pos = k
                return self.entries[index]
        merr.fail(merr.FORMAT, "indice de liste hors limites : " + str(index))

    func set_repeat(mode):
        if not (mode in REPEAT):
            merr.fail(merr.FORMAT, "mode de répétition inconnu : " + str(mode) + " (none, one, all)")
        self.repeat = mode

    # Entrée suivante selon la répétition (null en fin de liste avec « none »). `user` : appui sur « suivant »
    # (avec repeat « one », l'utilisateur passe quand même au suivant).
    func next(user=false):
        if len(self.order) == 0:
            return null
        if self.repeat == "one" and not user:
            return self.current()
        if self.pos + 1 < len(self.order):
            self.pos += 1
            return self.current()
        if self.repeat == "all" or (self.repeat == "one" and user):
            self.pos = 0
            return self.current()
        return null

    func previous():
        if len(self.order) == 0:
            return null
        if self.pos > 0:
            self.pos -= 1
        elif self.repeat == "all":
            self.pos = len(self.order) - 1
        return self.current()

    func has_next():
        return self.repeat != "none" or self.pos + 1 < len(self.order)

    # Ordre aléatoire reproductible (Fisher-Yates, générateur congruentiel) ; l'entrée courante passe en tête.
    func shuffle(seed=1):
        cur := self.current_index()
        idx := [k for k in 0..len(self.entries)]
        state := seed & 0x7FFFFFFF
        k := len(idx) - 1
        while k > 0:
            state = (state * 1103515245 + 12345) & 0x7FFFFFFF
            j := state % (k + 1)
            tmp := idx[k]
            idx[k] = idx[j]
            idx[j] = tmp
            k -= 1
        if cur >= 0:
            idx = [cur] + [x for x in idx if x != cur]
        self.order = idx
        self.pos = 0
        self.shuffled = true

    func unshuffle():
        cur := self.current_index()
        self.order = [k for k in 0..len(self.entries)]
        self.pos = cur if cur >= 0 else 0
        self.shuffled = false

    func total_duration():
        s := 0.0
        for e in self.entries:
            if e.duration == null:
                return null
            s = s + e.duration
        return s

func type_is_str(x):
    return type(x) == "str"

func _resolve(base, p):
    if base == null or _s.contains(p, "://") or _os.is_absolute(p):
        return p
    return _os.join(base, p)

func _lines(text):
    t := text
    if _s.starts_with(t, "﻿"):
        t = _s.substring(t, 1, len(t))
    return _s.split(_s.replace(_s.replace(t, "\r\n", "\n"), "\r", "\n"), "\n")

func parse_m3u(text, base=null, limits=null):
    l := lim.of(limits)
    l.check("max_text_bytes", _s.byte_len(text))
    p := Playlist(null, l)
    title := null
    duration := null
    for raw in _lines(text):
        line := _s.trim(raw)
        if len(line) == 0:
            continue
        if _s.starts_with(line, "#EXTINF:"):
            body := _s.substring(line, 8, len(line))
            comma := _s.find(body, ",")
            d := body if comma < 0 else _s.substring(body, 0, comma)
            sp := _s.find(d, " ")
            if sp >= 0:
                d = _s.substring(d, 0, sp)
            duration = null
            try:
                v := to_float(_s.trim(d))
                if v >= 0:
                    duration = v
            catch e:
                duration = null
            title = null if comma < 0 else _s.trim(_s.substring(body, comma + 1, len(body)))
            continue
        if _s.starts_with(line, "#"):
            continue
        p.add(Entry(_resolve(base, line), title, duration))
        title = null
        duration = null
    return p

func parse_pls(text, base=null, limits=null):
    l := lim.of(limits)
    l.check("max_text_bytes", _s.byte_len(text))
    lines := _lines(text)
    seen := false
    files := {}
    titles := {}
    lengths := {}
    for raw in lines:
        line := _s.trim(raw)
        if len(line) == 0 or _s.starts_with(line, ";"):
            continue
        if _s.lower(line) == "[playlist]":
            seen = true
            continue
        eq := _s.find(line, "=")
        if eq < 0:
            continue
        key := _s.lower(_s.trim(_s.substring(line, 0, eq)))
        value := _s.trim(_s.substring(line, eq + 1, len(line)))
        for pre in ["file", "title", "length"]:
            if _s.starts_with(key, pre) and len(key) > len(pre):
                num := _s.substring(key, len(pre), len(key))
                n := 0
                try:
                    n = to_int(num)
                catch e:
                    merr.corrupt("PLS", "numéro d'entrée illisible « " + key + " »")
                if pre == "file":
                    files[n] = value
                elif pre == "title":
                    titles[n] = value
                else:
                    try:
                        v := to_float(value)
                        lengths[n] = v if v >= 0 else null
                    catch e:
                        lengths[n] = null
    if not seen:
        merr.corrupt("PLS", "section [playlist] absente")
    p := Playlist(null, l)
    nums := _sorted_ints(keys(files))
    for n in nums:
        p.add(Entry(_resolve(base, files[n]), titles[n] if n in titles else null, lengths[n] if n in lengths else null))
    return p

func _sorted_ints(xs):
    out := [x for x in xs]
    for i in 0..len(out):
        for j in 0..len(out) - 1 - i:
            if out[j] > out[j + 1]:
                tmp := out[j]
                out[j] = out[j + 1]
                out[j + 1] = tmp
    return out

func format_m3u(p):
    out := ["#EXTM3U"]
    for e in p.entries:
        if e.title != null or e.duration != null:
            d := -1 if e.duration == null else to_int(e.duration + 0.5)
            append(out, "#EXTINF:" + str(d) + "," + (e.title if e.title != null else ""))
        append(out, e.path)
    return _s.join("\n", out) + "\n"

func format_pls(p):
    out := ["[playlist]"]
    i := 1
    for e in p.entries:
        append(out, "File" + str(i) + "=" + e.path)
        if e.title != null:
            append(out, "Title" + str(i) + "=" + e.title)
        append(out, "Length" + str(i) + "=" + str(-1 if e.duration == null else to_int(e.duration + 0.5)))
        i += 1
    append(out, "NumberOfEntries=" + str(len(p.entries)))
    append(out, "Version=2")
    return _s.join("\n", out) + "\n"

func load(path, limits=null):
    if not _os.isfile(path):
        merr.fail(merr.MEDIA, "liste introuvable : " + str(path))
    text := _io.read_file(path)
    base := _os.dirname(path)
    low := _s.lower(path)
    if _s.ends_with(low, ".pls") or _s.starts_with(_s.lower(_s.trim(text)), "[playlist]"):
        return parse_pls(text, base, limits)
    return parse_m3u(text, base, limits)

func save(p, path):
    if _s.ends_with(_s.lower(path), ".pls"):
        _io.write_file(path, format_pls(p))
    else:
        _io.write_file(path, format_m3u(p))
