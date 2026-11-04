# ALEX STANDARD LIBRARY — web.browser.console
#
# Console du navigateur simulé : log, info, warn, error, debug, trace, assert_, table, group / group_end,
# count / count_reset, time / time_log / time_end, avec substitutions « %s %d %i %f %o %O %j %c » et
# affichage des valeurs à la manière de JavaScript. Les messages sont conservés (messages, errors(),
# text()) et peuvent être recopiés sur la sortie standard (echo).
#
#   use web.browser.console as cs
#   c := cs.Console()
#   c.log("Bonjour %s, %d ans", "Ada", 36)       # Bonjour Ada, 36 ans
#   c.warn({"a": [1, null]})                      # {a: [1, null]}
#   c.group("Réseau"); c.info("GET /"); c.group_end()
#   c.count("clic"); c.count("clic")              # clic: 1, clic: 2
#   c.table([{"nom": "Ada", "âge": 36}])
#   c.messages[0].level, c.messages[0].text       # log Bonjour Ada, 36 ans
#   c.errors()                                    # messages de niveau error
#
# Erreurs : aucune (une console ne lève jamais).

from core use len, type, to_int, to_float
from collections use append, keys
use string as _s
use web.js.js_value as _jv
use web.js.js_types as _jt

class Message:
    func init(level, text, args, group_depth, time):
        self.level = level
        self.text = text
        self.args = args
        self.group_depth = group_depth
        self.time = time

    func __str__():
        return "[" + self.level + "] " + self.text

# Texte d'une valeur comme l'afficherait une console JavaScript (chaînes sans guillemets au premier niveau).
func display(v, top=true):
    if type(v) == "str":
        return v if top else _jt.quote(v, "'")
    if v == null:
        return "null"
    if _jt.is_undefined(v):
        return "undefined"
    if type(v) == "bool":
        return "true" if v else "false"
    if type(v) == "int" or type(v) == "float":
        return _jt.number(v)
    if type(v) == "list" or type(v) == "tuple":
        parts := []
        for x in v:
            append(parts, display(x, false))
        return "[" + _s.join(", ", parts) + "]"
    if type(v) == "dict":
        parts := []
        for k in keys(v):
            append(parts, _jt.property_key(k) + ": " + display(v[k], false))
        return "{" + _s.join(", ", parts) + "}"
    try:
        return str(v)
    catch e:
        return "[object]"

func _format(args):
    if len(args) == 0:
        return ""
    first := args[0]
    rest := []
    i := 1
    while i < len(args):
        append(rest, args[i])
        i += 1
    if type(first) != "str" or not _s.contains(first, "%"):
        parts := []
        for a in args:
            append(parts, display(a))
        return _s.join(" ", parts)
    out := []
    n := len(first)
    j := 0
    k := 0
    while j < n:
        c := first[j]
        if c == '%' and j + 1 < n:
            d := first[j + 1]
            if d == '%':
                append(out, "%")
                j += 2
                continue
            if d in ['s', 'd', 'i', 'f', 'o', 'O', 'j', 'c']:
                if d == 'c':
                    if k < len(rest):
                        k += 1
                    j += 2
                    continue
                if k < len(rest):
                    v := rest[k]
                    k += 1
                    if d == 's':
                        append(out, display(v))
                    elif d == 'd' or d == 'i':
                        try:
                            append(out, str(to_int(v)) if type(v) != "str" else str(to_int(to_float(v))))
                        catch e:
                            append(out, "NaN")
                    elif d == 'f':
                        try:
                            append(out, _jt.number(to_float(v)))
                        catch e2:
                            append(out, "NaN")
                    else:
                        append(out, display(v, false))
                else:
                    append(out, "%" + str(d))
                j += 2
                continue
        append(out, str(c))
        j += 1
    text := _s.join("", out)
    while k < len(rest):
        text = text + " " + display(rest[k])
        k += 1
    return text

class Console:
    # echo : recopier sur la sortie standard ; clock : fonction sans argument -> ms (performance.now).
    func init(echo=false, clock=null):
        self.echo = echo
        self.clock = clock
        self.messages = []
        self.depth = 0
        self.counters = {}
        self.timers = {}

    func _now():
        if self.clock != null:
            return self.clock()
        return 0.0

    func _emit(level, args):
        text := _format(args)
        m := Message(level, text, args, self.depth, self._now())
        append(self.messages, m)
        if self.echo:
            print(_s.repeat("  ", self.depth) + ("" if level == "log" else "[" + level + "] ") + text)
        return m

    func log(a=null, b=null, c=null, d=null, e=null):
        return self._emit("log", _args(a, b, c, d, e))

    func info(a=null, b=null, c=null, d=null, e=null):
        return self._emit("info", _args(a, b, c, d, e))

    func warn(a=null, b=null, c=null, d=null, e=null):
        return self._emit("warn", _args(a, b, c, d, e))

    func error(a=null, b=null, c=null, d=null, e=null):
        return self._emit("error", _args(a, b, c, d, e))

    func debug(a=null, b=null, c=null, d=null, e=null):
        return self._emit("debug", _args(a, b, c, d, e))

    func trace(a=null, b=null, c=null):
        return self._emit("trace", ["Trace:"] + _args(a, b, c, null, null))

    # Message d'erreur seulement si la condition est fausse.
    func assert_(condition, a=null, b=null, c=null):
        if not condition:
            args := _args(a, b, c, null, null)
            if len(args) == 0:
                return self._emit("error", ["Assertion failed"])
            if type(args[0]) == "str":
                args[0] = "Assertion failed: " + args[0]
                return self._emit("error", args)
            return self._emit("error", ["Assertion failed:"] + args)
        return null

    func group(label=null):
        if label != null:
            self._emit("group", [label])
        self.depth += 1

    func group_collapsed(label=null):
        self.group(label)

    func group_end():
        if self.depth > 0:
            self.depth -= 1

    func count(label="default"):
        n := (self.counters[label] if label in self.counters else 0) + 1
        self.counters[label] = n
        return self._emit("count", [label + ": " + str(n)])

    func count_reset(label="default"):
        self.counters[label] = 0

    func time(label="default"):
        self.timers[label] = self._now()

    func time_log(label="default"):
        if not (label in self.timers):
            return self._emit("warn", ["Timer '" + label + "' does not exist"])
        return self._emit("log", [label + ": " + _jt.number(self._now() - self.timers[label]) + " ms"])

    func time_end(label="default"):
        m := self.time_log(label)
        if label in self.timers:
            out := {}
            for k in keys(self.timers):
                if k != label:
                    out[k] = self.timers[k]
            self.timers = out
        return m

    # Tableau texte d'une liste de dicts (ou de listes).
    func table(rows, columns=null):
        cols := []
        if columns != null:
            cols = columns
        else:
            for r in rows:
                if type(r) == "dict":
                    for k in keys(r):
                        if not (k in cols):
                            append(cols, k)
        lines := []
        header := ["(index)"] + cols
        if columns == null and len(cols) == 0:
            header = ["(index)", "Values"]
        data := []
        i := 0
        for r in rows:
            line := [str(i)]
            if type(r) == "dict":
                for c in cols:
                    append(line, display(r[c], false) if c in r else "")
            else:
                append(line, display(r, false))
            append(data, line)
            i += 1
        widths := []
        for h in header:
            append(widths, len(h))
        for line in data:
            j := 0
            for cell in line:
                if j < len(widths) and len(cell) > widths[j]:
                    widths[j] = len(cell)
                j += 1
        append(lines, _row(header, widths))
        for line in data:
            append(lines, _row(line, widths))
        return self._emit("table", [_s.join("\n", lines)])

    func clear():
        self.messages = []
        self.depth = 0

    func errors():
        return self.by_level("error")

    func warnings():
        return self.by_level("warn")

    func by_level(level):
        out := []
        for m in self.messages:
            if m.level == level:
                append(out, m)
        return out

    # Tout le texte de la console (une ligne par message).
    func text():
        lines := []
        for m in self.messages:
            append(lines, _s.repeat("  ", m.group_depth) + m.text)
        return _s.join("\n", lines)

func _row(cells, widths):
    parts := []
    j := 0
    while j < len(widths):
        c := cells[j] if j < len(cells) else ""
        append(parts, c + _s.repeat(" ", widths[j] - len(c)))
        j += 1
    return "│ " + _s.join(" │ ", parts) + " │"

func _args(a, b, c, d, e):
    out := []
    for x in [a, b, c, d, e]:
        append(out, x)
    while len(out) > 0 and out[len(out) - 1] == null:
        out = out[0:len(out) - 1]
    return out
