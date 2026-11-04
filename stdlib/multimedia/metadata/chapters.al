# ALEX STANDARD LIBRARY — multimedia.metadata.chapters
#
# Chapitres d'un média : début, fin (déduite du chapitre suivant ou de la durée), titre. Lecture et écriture du
# format texte courant « 00:00 Introduction » (une ligne par chapitre, comme dans les descriptions de vidéos) et
# du format OGM (« CHAPTER01=00:00:00.000 » / « CHAPTER01NAME=... »), recherche du chapitre courant, contrôle.
#
#   use multimedia.metadata.chapters as ch
#   c := ch.parse("00:00 Intro\n01:30 Couplet\n04:10 Fin", 300.0)
#   print(c.at(95.0).title)                    # Couplet
#   print(c.next_start(95.0))                  # 250.0
#   print(ch.format_simple(c))
#
# Erreurs : CorruptDataError (ligne illisible), FormatError.

from core use len
from collections use append, keys
use algorithm.sort as _sort
use string as _s
use multimedia.core.errors as merr
use multimedia.core.timestamp as ts

class Chapter:
    func init(start, title, end=null):
        self.start = start
        self.end = end
        self.title = title

    func describe():
        e := "?" if self.end == null else ts.format_clock(self.end)
        return ts.format_clock(self.start) + " – " + e + " " + self.title

class ChapterList:
    func init(duration=null):
        self.items = []
        self.duration = duration

    func add(start, title, end=null):
        append(self.items, Chapter(start, title, end))
        self.items = _sort.sorted(self.items, (c) => c.start)
        self._fill_ends()
        return self

    func _fill_ends():
        for i in 0..len(self.items):
            c := self.items[i]
            if i + 1 < len(self.items):
                nxt := self.items[i + 1].start
                if c.end == null or c.end > nxt:
                    c.end = nxt
            elif c.end == null and self.duration != null:
                c.end = self.duration

    func count():
        return len(self.items)

    func at(t):
        for c in self.items:
            e := c.end
            if t >= c.start and (e == null or t < e):
                return c
        return null

    func index_at(t):
        for i in 0..len(self.items):
            c := self.items[i]
            if t >= c.start and (c.end == null or t < c.end):
                return i
        return -1

    func next_start(t):
        for c in self.items:
            if c.start > t:
                return c.start
        return null

    func previous_start(t, grace=2.0):
        i := self.index_at(t)
        if i < 0:
            return 0.0
        if t - self.items[i].start > grace or i == 0:
            return self.items[i].start
        return self.items[i - 1].start

    func problems():
        out := []
        for i in 0..len(self.items):
            c := self.items[i]
            if c.end != null and c.end <= c.start:
                append(out, "chapitre " + str(i + 1) + " : durée nulle ou négative")
            if self.duration != null and c.start >= self.duration:
                append(out, "chapitre " + str(i + 1) + " : commence après la fin du média")
            if len(_s.trim(c.title)) == 0:
                append(out, "chapitre " + str(i + 1) + " : sans titre")
        return out

func _lines(text):
    return _s.split(_s.replace(_s.replace(text, "\r\n", "\n"), "\r", "\n"), "\n")

# « 00:00 Titre », « 1:02:03 Titre », « 00:01:30.500 - Titre » : une ligne par chapitre.
func parse(text, duration=null):
    out := ChapterList(duration)
    n := 0
    for raw in _lines(text):
        n += 1
        line := _s.trim(raw)
        if len(line) == 0:
            continue
        if _s.starts_with(line, "CHAPTER"):
            return parse_ogm(text, duration)
        sp := _s.find(line, " ")
        clock := line if sp < 0 else _s.substring(line, 0, sp)
        title := "" if sp < 0 else _s.trim(_s.substring(line, sp + 1, len(line)))
        if _s.starts_with(title, "- ") or _s.starts_with(title, "– "):
            title = _s.trim(_s.substring(title, 2, len(title)))
        t := 0.0
        try:
            t = ts.parse_clock(clock)
        catch e:
            merr.corrupt("chapitres", "ligne " + str(n) + " : instant illisible « " + clock + " »")
        out.add(t, title)
    return out

func parse_ogm(text, duration=null):
    starts := {}
    names := {}
    for raw in _lines(text):
        line := _s.trim(raw)
        eq := _s.find(line, "=")
        if eq < 0 or not _s.starts_with(line, "CHAPTER"):
            continue
        key := _s.substring(line, 0, eq)
        value := _s.substring(line, eq + 1, len(line))
        if _s.ends_with(key, "NAME"):
            names[_s.substring(key, 7, len(key) - 4)] = value
        else:
            try:
                starts[_s.substring(key, 7, len(key))] = ts.parse_clock(value)
            catch e:
                merr.corrupt("chapitres OGM", "instant illisible « " + value + " »")
    out := ChapterList(duration)
    for k in keys(starts):
        out.add(starts[k], names[k] if k in names else "")
    return out

func format_simple(chs):
    out := []
    long := chs.duration != null and chs.duration >= 3600
    for c in chs.items:
        clock := ts.format_clock(c.start)
        clock = _s.substring(clock, 0, 8)
        if not long and _s.starts_with(clock, "00:"):
            clock = _s.substring(clock, 3, len(clock))
        append(out, clock + " " + c.title)
    return _s.join("\n", out)

func format_ogm(chs):
    out := []
    for i in 0..len(chs.items):
        num := str(i + 1)
        if i + 1 < 10:
            num = "0" + num
        append(out, "CHAPTER" + num + "=" + ts.format_clock(chs.items[i].start))
        append(out, "CHAPTER" + num + "NAME=" + chs.items[i].title)
    return _s.join("\n", out)
