# ALEX STANDARD LIBRARY — web.http.date_header
#
# Dates HTTP (RFC 9110 §5.6.7) des en-têtes Date, Last-Modified, Expires, If-Modified-Since, Retry-After... :
# toujours en UTC (« GMT »), au format IMF-fixdate. À la lecture, les deux formats obsolètes sont acceptés comme
# l'exige la RFC : RFC 850 (année sur deux chiffres) et asctime de C.
#
#   use web.http.date_header as dh
#   dh.format(784111777)                          # Sun, 06 Nov 1994 08:49:37 GMT
#   dh.parse("Sun, 06 Nov 1994 08:49:37 GMT")     # 784111777
#   dh.parse("Sunday, 06-Nov-94 08:49:37 GMT")    # 784111777
#   dh.parse("Sun Nov  6 08:49:37 1994")          # 784111777
#   dh.parse("hier")                              # null (date invalide : ignorée, RFC 9110 §5.6.7)
#   dh.now()                                      # date courante, prête pour l'en-tête Date
#   dh.retry_after_seconds("120")                 # 120 ; une date HTTP donne le délai restant
#
# Les horodatages sont des entiers de secondes depuis 1970-01-01 UTC (les fractions sont tronquées).

from core use len, type, to_int
from collections use append
use string as _s
use time as _time

const DAYS := ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
const LONG_DAYS := ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

func _pad2(n):
    if n < 10:
        return "0" + str(n)
    return str(n)

func _pad4(n):
    s := str(n)
    while len(s) < 4:
        s = "0" + s
    return s

func _floor_div(a, b):
    q := a // b
    if (a % b != 0) and ((a < 0) != (b < 0)) and q * b > a:
        q -= 1
    return q

# Horodatage (secondes UTC, int ou float) -> « Sun, 06 Nov 1994 08:49:37 GMT ».
func format(timestamp):
    t := to_int(timestamp)
    days := _floor_div(t, 86400)
    secs := t - days * 86400
    ymd := _time.civil_from_days(days)
    wd := _time.weekday_of_days(days)
    return DAYS[wd] + ", " + _pad2(ymd[2]) + " " + MONTHS[ymd[1] - 1] + " " + _pad4(ymd[0]) + " " + _pad2(secs // 3600) + ":" + _pad2((secs % 3600) // 60) + ":" + _pad2(secs % 60) + " GMT"

# Date courante au format HTTP.
# Date courante au format HTTP ; recalculée au plus une fois par seconde (une réponse sur deux en a besoin).
_now_cache := [-1, ""]

func now():
    t := to_int(_time.time())
    if t != _now_cache[0]:
        _now_cache[1] = format(t)
        _now_cache[0] = t
    return _now_cache[1]

func timestamp_now():
    return to_int(_time.time())

func _month_index(name):
    i := 0
    while i < 12:
        if MONTHS[i] == name:
            return i + 1
        i += 1
    return 0

func _int(text):
    if len(text) == 0:
        return -1
    n := 0
    for c in text:
        if c < '0' or c > '9':
            return -1
        n = n * 10 + (_s.ord(c) - 48)
    return n

func _time_of_day(text):
    parts := _s.split(text, ":")
    if len(parts) != 3 or len(parts[0]) != 2 or len(parts[1]) != 2 or len(parts[2]) != 2:
        return -1
    h := _int(parts[0])
    m := _int(parts[1])
    s := _int(parts[2])
    if h < 0 or h > 23 or m < 0 or m > 59 or s < 0 or s > 60:
        return -1
    if s == 60:
        s = 59
    return h * 3600 + m * 60 + s

func _build(year, month, day, tod):
    if month < 1 or month > 12 or day < 1 or tod < 0 or year < 0:
        return null
    if day > _time.days_in_month(year, month):
        return null
    return _time.days_from_civil(year, month, day) * 86400 + tod

func _words(text):
    out := []
    for w in _s.split(text, " "):
        if w != "":
            append(out, w)
    return out

# Date HTTP (trois formats) -> horodatage int, ou null si la valeur n'est pas une date HTTP valide.
func parse(text):
    if type(text) != "str":
        return null
    w := _words(_s.trim(text))
    # IMF-fixdate : Sun, 06 Nov 1994 08:49:37 GMT
    if len(w) == 6 and _s.ends_with(w[0], ",") and w[5] == "GMT":
        return _build(_int(w[3]), _month_index(w[2]), _int(w[1]), _time_of_day(w[4]))
    # RFC 850 : Sunday, 06-Nov-94 08:49:37 GMT
    if len(w) == 4 and _s.ends_with(w[0], ",") and w[3] == "GMT":
        d := _s.split(w[1], "-")
        if len(d) != 3:
            return null
        y := _int(d[2])
        if y < 0:
            return null
        if len(d[2]) == 2:
            # RFC 9110 : une année à deux chiffres qui paraît à plus de 50 ans dans le futur est dans le passé
            current := _time.civil_from_days(_floor_div(timestamp_now(), 86400))[0]
            y = (current // 100) * 100 + y
            if y > current + 50:
                y -= 100
        return _build(y, _month_index(d[1]), _int(d[0]), _time_of_day(w[2]))
    # asctime : Sun Nov  6 08:49:37 1994
    if len(w) == 5:
        return _build(_int(w[4]), _month_index(w[1]), _int(w[2]), _time_of_day(w[3]))
    return null

func is_valid(text):
    return parse(text) != null

# Retry-After (RFC 9110 §10.2.3) : secondes à attendre (int >= 0) depuis un nombre ou une date ; null si invalide.
func retry_after_seconds(value, now_ts=null):
    if value == null:
        return null
    v := _s.trim(str(value))
    n := _int(v)
    if n >= 0:
        return n
    ts := parse(v)
    if ts == null:
        return null
    current := now_ts if now_ts != null else timestamp_now()
    if ts <= current:
        return 0
    return ts - current

# Vrai si la ressource (Last-Modified = last_modified, horodatage) n'a pas changé depuis la date
# If-Modified-Since (texte) : la réponse peut être 304.
func not_modified_since(last_modified, if_modified_since):
    since := parse(if_modified_since)
    if since == null or last_modified == null:
        return false
    return to_int(last_modified) <= since

# Vrai si la date d'expiration (texte Expires) est passée ; une date invalide vaut « déjà expiré ».
func is_expired(expires, now_ts=null):
    ts := parse(expires)
    if ts == null:
        return true
    current := now_ts if now_ts != null else timestamp_now()
    return ts <= current
