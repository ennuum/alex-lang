# ALEX STANDARD LIBRARY — logging.log_formatter
#
# Mise en forme des enregistrements :
#   Formatter(fmt, time_format)   gabarit : {time} {level} {level:8} (justifié) {name} {message} {pid} {thread}
#                                 {extra} (clé=valeur...) {exception} et tout champ extra par son nom {clé}
#   JsonFormatter                 une ligne JSON par enregistrement (collecte centralisée, ELK, Loki...)
#   KeyValueFormatter             logfmt : time=… level=… name=… msg="…" clé=valeur
#   ColorFormatter                comme Formatter, niveau coloré (terminal)
#
#   use logging.log_formatter as lf
#   f := lf.Formatter("{time} [{level:8}] {name}: {message}")
#   print(f.format(enregistrement))
#   j := lf.JsonFormatter()
#   lf.Formatter("{time} {message}", "%H:%M:%S")        # time_format : "iso" (défaut), "utc", "epoch",
#                                                        # ou un gabarit strftime (heure locale)
#
# Erreurs : LoggingError (gabarit invalide).

from core use len, type, to_int
from collections use append
use string as _s
use json as _json
use time as _time
use logging.log_level as _lv
use logging.logging_errors as _e

const DEFAULT := "{time} {level:8} {name}: {message}"

func _pad(s, n):
    out := s
    while len(out) < n:
        out += " "
    return out

func _fmt_time(t, time_format):
    if time_format == "iso":
        return _time.iso_from_timestamp(t, 0, "T", "milliseconds", true)
    if time_format == "utc":
        return _time.strftime("%Y-%m-%d %H:%M:%S", _time.gmtime(t))
    if time_format == "epoch":
        return str(t)
    return _time.strftime(time_format, _time.localtime(t))

func _extra_text(extra):
    parts := []
    for k in extra:
        append(parts, str(k) + "=" + _quote_if_needed(str(extra[k])))
    return _s.join(" ", parts)

func _quote_if_needed(v):
    if v == "" or _s.contains(v, " ") or _s.contains(v, "=") or _s.contains(v, "\""):
        return "\"" + _s.replace(_s.replace(v, "\\", "\\\\"), "\"", "\\\"") + "\""
    return v

func _exception_text(r):
    if not r.has_exception():
        return ""
    out := r.exc_type + " : " + str(r.exc_message)
    if type(r.exc_trace) == "list":
        for l in r.exc_trace:
            out += "\n    " + str(l)
    return out

class Formatter:
    func init(fmt=DEFAULT, time_format="iso"):
        if type(fmt) != "str":
            raise("TypeError", "Formatter : gabarit str attendu")
        self.fmt = fmt
        self.time_format = time_format

    func _field(r, key):
        width := 0
        k := key
        c := _s.find(key, ":")
        if c > 0:
            k = _s.substring(key, 0, c)
            width = to_int(_s.substring(key, c + 1, len(key)))
        v := null
        if k == "time":
            v = _fmt_time(r.time, self.time_format)
        elif k == "level":
            v = self.level_text(r)
        elif k == "levelno":
            v = str(r.level)
        elif k == "name":
            v = r.name
        elif k == "message":
            v = r.message()
        elif k == "pid":
            v = str(r.pid)
        elif k == "thread":
            v = str(r.thread)
        elif k == "extra":
            v = _extra_text(r.extra)
        elif k == "exception":
            v = _exception_text(r)
        elif k in r.extra:
            v = str(r.extra[k])
        else:
            return null
        if width > 0:
            v = _pad(v, width)
        return v

    func level_text(r):
        return r.level_name

    func format(r):
        text := self.fmt
        out := ""
        i := 0
        n := len(text)
        while i < n:
            if text[i] == '{':
                j := _s.find(_s.substring(text, i, n), "}")
                if j > 0:
                    v := self._field(r, _s.substring(text, i + 1, i + j))
                    if v != null:
                        out += v
                        i = i + j + 1
                        continue
            out += str(text[i])
            i += 1
        if r.has_exception() and not _s.contains(self.fmt, "{exception}"):
            out += "\n" + _exception_text(r)
        return out

class ColorFormatter extends Formatter:
    func init(fmt=DEFAULT, time_format="iso"):
        super.init(fmt, time_format)

    func level_text(r):
        return _lv.color(r.level) + r.level_name + _lv.RESET

class JsonFormatter:
    func init(time_format="iso", fields=null):
        self.time_format = time_format
        self.fields = fields

    func format(r):
        d := r.to_dict()
        d["time"] = _fmt_time(r.time, self.time_format)
        if self.fields != null:
            keep := {}
            for k in self.fields:
                if k in d:
                    keep[k] = d[k]
            d = keep
        return _json.stringify(d, null, false)

class KeyValueFormatter:
    func init(time_format="iso"):
        self.time_format = time_format

    func format(r):
        parts := ["time=" + _fmt_time(r.time, self.time_format), "level=" + _s.lower(r.level_name),
                  "name=" + _quote_if_needed(r.name), "msg=" + _quote_if_needed(r.message())]
        for k in r.extra:
            append(parts, str(k) + "=" + _quote_if_needed(str(r.extra[k])))
        if r.has_exception():
            append(parts, "error=" + _quote_if_needed(r.exc_type + ": " + str(r.exc_message)))
        return _s.join(" ", parts)

func formatter(fmt=DEFAULT, time_format="iso"):
    return Formatter(fmt, time_format)
