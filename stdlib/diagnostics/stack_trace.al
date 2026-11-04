# ALEX STANDARD LIBRARY — diagnostics.stack_trace
#
# Piles d'appels : celle du point courant (current), celle d'une erreur rattrapée (from_error), sous forme de
# cadres StackFrame (fonction, fichier, ligne) avec le texte source de chaque ligne, et un rendu lisible.
#
#   use diagnostics.stack_trace as st
#   func f():
#       print(st.current().format())       # pile au point d'appel (appel le plus récent en dernier)
#   print(st.caller())                     # nom de la fonction qui a appelé la fonction courante
#   try:
#       traiter()
#   catch e:
#       t := st.from_error(e)
#       print(t.top().function, t.top().line)
#       print(st.format_error(e))          # « ValueError : ... » + pile + lignes de source
#
# La pile est lue par une erreur levée puis rattrapée (e.trace, maintenue par la VM) : elle donne les appels
# ALEX (pas les fonctions natives). Erreurs : aucune (une information indisponible vaut null).

from core use len, type, to_int
from collections use append
use string as _s
use io as _io
use os as _os

class StackFrame:
    func init(function, file, line):
        self.function = function
        self.file = file
        self.line = line

    # Ligne de source (sans les espaces de tête), null si le fichier est illisible.
    func source():
        return source_line(self.file, self.line)

    func location():
        return self.file + ":" + str(self.line)

    func to_dict():
        return {"function": self.function, "file": self.file, "line": self.line}

    func __str__():
        return self.location() + " dans " + self.function

_SOURCES := {}

func source_line(file, line):
    if file == null or line == null or line < 1:
        return null
    lines := null
    if file in _SOURCES:
        lines = _SOURCES[file]
    else:
        try:
            lines = _s.split(_io.read_file(file), "\n")
        catch e:
            lines = []
        _SOURCES[file] = lines
    if line > len(lines):
        return null
    return _s.trim(lines[line - 1])

# « fichier:ligne dans fonction » -> StackFrame.
func parse_entry(text):
    t := _s.trim(text)
    k := _s.find(t, " dans ")
    fn := "?"
    loc := t
    if k >= 0:
        fn = _s.trim(_s.substring(t, k + 6, len(t)))
        loc = _s.trim(_s.substring(t, 0, k))
        if _s.ends_with(loc, ","):
            loc = _s.substring(loc, 0, len(loc) - 1)
    if _s.starts_with(loc, "à "):
        loc = _s.substring(loc, 2, len(loc))
    if _s.starts_with(loc, "at "):
        loc = _s.substring(loc, 3, len(loc))
    file := loc
    line := 0
    i := len(loc) - 1
    while i >= 0 and loc[i] != ':':
        i -= 1
    if i > 0:
        num := _s.substring(loc, i + 1, len(loc))
        ok := len(num) > 0
        for c in num:
            if c < '0' or c > '9':
                ok = false
        if ok:
            file = _s.substring(loc, 0, i)
            line = to_int(num)
    return StackFrame(fn, file, line)

class StackTrace:
    func init(frames, error_type=null, message=null):
        self.frames = frames         # le plus récent en dernier
        self.error_type = error_type
        self.message = message

    func depth():
        return len(self.frames)

    func top():
        if len(self.frames) == 0:
            return null
        return self.frames[len(self.frames) - 1]

    func bottom():
        if len(self.frames) == 0:
            return null
        return self.frames[0]

    func functions():
        return [f.function for f in self.frames]

    # Cadres dont le fichier contient fragment (p. ex. ne garder que son projet).
    func filter(fragment):
        return StackTrace([f for f in self.frames if _s.contains(f.file, fragment)], self.error_type, self.message)

    func without_stdlib():
        return StackTrace([f for f in self.frames if not _s.contains(f.file, "/stdlib/")], self.error_type, self.message)

    func format(with_source=true, most_recent_first=false):
        lines := []
        if self.error_type != null:
            append(lines, self.error_type + " : " + str(self.message))
        fr := self.frames
        if most_recent_first:
            fr = [self.frames[len(self.frames) - 1 - i] for i in 0..len(self.frames)]
        append(lines, "Pile d'appels (" + _order_label(most_recent_first) + ") :")
        for f in fr:
            append(lines, "  " + str(f))
            if with_source:
                src := f.source()
                if src != null and src != "":
                    append(lines, "      " + src)
        return _s.join("\n", lines)

    func to_list():
        return [f.to_dict() for f in self.frames]

    func __str__():
        return self.format(false)

func _order_label(recent_first):
    if recent_first:
        return "appel le plus récent en premier"
    return "appel le plus récent en dernier"

func from_trace_list(entries, error_type=null, message=null):
    return StackTrace([parse_entry(x) for x in entries], error_type, message)

func from_error(e):
    tr := []
    try:
        tr = e.trace
    catch x:
        tr = []
    return from_trace_list(tr, e.type, e.message)

# Pile au point d'appel ; skip : nombre de cadres supplémentaires à ignorer en tête (côté récent).
func current(skip=0):
    entries := []
    try:
        raise("StackProbe", "")
    catch e:
        entries = e.trace
    t := from_trace_list(entries)
    # retire le cadre de current() lui-même
    n := len(t.frames) - 1 - skip
    if n < 0:
        n = 0
    t.frames = t.frames[:n]
    return t

# Nom de la fonction appelante de celle qui appelle caller().
func caller():
    t := current(2)
    f := t.top()
    if f == null:
        return null
    return f.function

func depth():
    return current(1).depth()

func format_error(e, with_source=true):
    return from_error(e).format(with_source)

func print_current():
    print(current(1).format())
