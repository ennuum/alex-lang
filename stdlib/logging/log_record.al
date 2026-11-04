# ALEX STANDARD LIBRARY — logging.log_record
#
# LogRecord : UN événement de journal — qui (logger), quoi (message et arguments), quand (instant), où
# (processus, fil), avec quel contexte (champs extra, structurés) et, s'il y a lieu, quelle exception
# (type, message, trace de pile).
#
#   use logging.log_record as lr
#   r := lr.LogRecord("app.db", 30, "requête lente : {} ms", [812], {"table": "clients"})
#   print(r.message())               # « requête lente : 812 ms »
#   print(r.level_name, r.extra["table"], r.iso_time())
#   r2 := lr.from_exception("app", 40, "échec", e)    # e : exception attrapée par catch
#   print(r2.exc_type, r2.exc_trace)
#
# Substitution du message : « {} » prend les arguments dans l'ordre, « {0} » par position, « {clé} » dans extra.
# Erreurs : aucune (une substitution impossible laisse le motif tel quel).

from core use len, type, to_int
from collections use append
use string as _s
use os as _os
use time as _time
use concurrency.thread as _ct
use logging.log_level as _lv

_clock := [null]

# Horloge des enregistrements (fn() -> secondes epoch) ; null : horloge système. Pour des tests reproductibles.
func set_clock(fn):
    _clock[0] = fn

func now():
    if _clock[0] != null:
        return _clock[0]()
    return _os.time()

class LogRecord:
    func init(name, level, msg, args=null, extra=null, time=null):
        self.name = name
        self.level = _lv.parse(level)
        self.level_name = _lv.name_of(self.level)
        self.msg = msg
        self.args = args
        if self.args == null:
            self.args = []
        self.extra = extra
        if self.extra == null:
            self.extra = {}
        self.time = time
        if self.time == null:
            self.time = now()
        self.pid = _os.pid()
        self.thread = _ct.current_id()
        self.exc_type = null
        self.exc_message = null
        self.exc_trace = null
        self._cached = null

    # Message avec les arguments substitués (calculé une fois).
    func message():
        if self._cached == null:
            self._cached = render(str(self.msg), self.args, self.extra)
        return self._cached

    func has_exception():
        return self.exc_type != null

    func iso_time():
        return _time.iso_from_timestamp(self.time, 0, "T", "milliseconds", true)

    func to_dict():
        d := {"time": self.time, "level": self.level_name, "name": self.name, "message": self.message(),
              "pid": self.pid, "thread": self.thread}
        for k in self.extra:
            d[k] = self.extra[k]
        if self.exc_type != null:
            d["exception"] = {"type": self.exc_type, "message": self.exc_message, "trace": self.exc_trace}
        return d

    func __str__():
        return self.level_name + " " + self.name + ": " + self.message()

func _value_text(v):
    return str(v)

# Remplace {} / {n} / {clé} dans text.
func render(text, args, extra):
    if _s.find(text, "{") < 0:
        return text
    out := ""
    i := 0
    k := 0
    n := len(text)
    while i < n:
        c := text[i]
        if c == '{':
            j := i + 1
            while j < n and text[j] != '}' and text[j] != '{':
                j += 1
            if j < n and text[j] == '}':
                key := _s.substring(text, i + 1, j)
                if key == "":
                    if k < len(args):
                        out += _value_text(args[k])
                        k += 1
                    else:
                        out += "{}"
                    i = j + 1
                    continue
                if _is_int(key):
                    idx := to_int(key)
                    if idx < len(args):
                        out += _value_text(args[idx])
                        i = j + 1
                        continue
                elif key in extra:
                    out += _value_text(extra[key])
                    i = j + 1
                    continue
        out += str(c)
        i += 1
    return out

func _is_int(s):
    if s == "":
        return false
    for c in s:
        if c < '0' or c > '9':
            return false
    return true

func from_exception(name, level, msg, e, extra=null):
    r := LogRecord(name, level, msg, null, extra)
    r.exc_type = e.type
    r.exc_message = e.message
    try:
        r.exc_trace = e.trace
    catch x:
        r.exc_trace = null
    return r
