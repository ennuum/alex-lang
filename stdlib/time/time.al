# ALEX STANDARD LIBRARY — time
# Horloges, calendrier grégorien proleptique, formats (strftime / strptime / ISO 8601), durées et chronomètres.
# 100 % ALEX : aucune primitive C++ dédiée, seulement `os` pour l'horloge système (os.time, os.monotonic_time,
# os.sleep, os.system_time).
#
#   use time
#   time.time()                                   # secondes epoch (float)
#   t := time.gmtime(1791360000)                  # {"year": 2026, "month": 10, "day": 7, "hour": 8, ...}
#   time.strftime("%A %d %B %Y", t, "fr")         # mercredi 07 octobre 2026
#   time.timegm({"year": 2026, "month": 10, "day": 7})     # 1791331200
#   time.parse_duration("1h30m")                  # 5400
#   sw := time.Stopwatch(true); ...; sw.elapsed()
#
# SANS LIMITE DE PLAGE
#   Le calendrier est arithmétique (algorithmes en nombres entiers, O(1)) : toute année entière est acceptée,
#   négative et zéro comprises (numérotation astronomique : l'an 0 existe, -1 = 2 av. J.-C.). Les dates sont
#   manipulées en « jours depuis 1970-01-01 » (int 64 bits), donc jusqu'à ± 2,5 × 10^16 ans. Les secondes epoch
#   int vont jusqu'à ± 9,2 × 10^18 s (± 292 milliards d'années) ; les float perdent la précision de la
#   microseconde à plus de ± 140 ans de 1970 : d'où `split_timestamp`, `duration_parts` et les `*_parts`, qui
#   travaillent en entiers exacts (secondes, microsecondes).
#
# CONVENTIONS
#   - weekday : 0 = lundi ... 6 = dimanche (comme `os.system_time`). iso_weekday : 1 = lundi ... 7 = dimanche.
#   - « struct time » : dict {"year","month","day","hour","minute","second","microsecond","weekday","yearday",
#     "utc_offset","timezone","is_dst"} ; seules year (obligatoire) et les champs utiles sont lues en entrée.
#   - Les fonctions qui normalisent (timegm, mktime) acceptent des champs hors plage (mois 14, jour 0, seconde 90...).
#   - Langues pour les noms de mois / jours : "en" (défaut), "fr", "es", "de", "it", "pt", "nl" ; `register_locale`
#     en ajoute d'autres. Codes « fr_FR » / « fr-CA » acceptés (seules les deux premières lettres comptent).
#   - Erreurs : raise("ValueError" | "TypeError" | "TimeoutError", message en français).
#
# LIMITES ASSUMÉES
#   - `localtime` / `mktime` utilisent le décalage actuel du système (un seul décalage fixe : os.system_time) ;
#     pour les fuseaux avec heure d'été à toute date, voir le module `datetime` (TimeZone avec règles).
#   - strptime : pas de %U %W %V (consommés et ignorés) ; une seconde 60 (seconde intercalaire) est refusée.

use os
use string
from core use type, len, to_int, to_float
from collections use append, keys, contains_key

# ---------------------------------------------------------------------------------------------------------------
# Constantes
# ---------------------------------------------------------------------------------------------------------------

const MONDAY := 0
const TUESDAY := 1
const WEDNESDAY := 2
const THURSDAY := 3
const FRIDAY := 4
const SATURDAY := 5
const SUNDAY := 6

const SECONDS_PER_MINUTE := 60
const SECONDS_PER_HOUR := 3600
const SECONDS_PER_DAY := 86400
const SECONDS_PER_WEEK := 604800
const MICROS_PER_SECOND := 1000000
const MICROS_PER_DAY := 86400000000
# Numéro d'ordre de 1970-01-01 quand 0001-01-01 vaut 1 (comme date.toordinal de Python).
const UNIX_EPOCH_ORDINAL := 719163

const _FLOAT_LIMIT := 9000000000000000000.0
const _DIM := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

# Réglages et doublures pour les tests (voir set_clock, install_fake_clock, set_local_zone).
_state := {"wall": null, "mono": null, "sleep": null, "local": null, "locales": {}}

# ---------------------------------------------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------------------------------------------

func _fail(message):
    raise("ValueError", message)

func _need_int(fn, label, v):
    if type(v) != "int":
        raise("TypeError", "time." + fn + " : " + label + " doit être un entier (obtenu '" + type(v) + "')")

func _need_number(fn, label, v):
    t := type(v)
    if t != "int" and t != "float":
        raise("TypeError", "time." + fn + " : " + label + " doit être un nombre (obtenu '" + type(v) + "')")
    if t == "float" and (v != v or v >= _FLOAT_LIMIT or v <= -_FLOAT_LIMIT):
        raise("ValueError", "time." + fn + " : " + label + " hors limites ou non fini")

func _need_str(fn, label, v):
    if type(v) != "str":
        raise("TypeError", "time." + fn + " : " + label + " doit être une chaîne (obtenu '" + type(v) + "')")

# Plancher d'un nombre, en int (floor mathématique, y compris pour les négatifs).
func ifloor(x):
    if type(x) == "int":
        return x
    _need_number("ifloor", "x", x)
    i := to_int(x)
    if to_float(i) > x:
        i = i - 1
    return i

# Arrondi au plus proche (moitié vers +infini), en int.
func iround(x):
    if type(x) == "int":
        return x
    _need_number("iround", "x", x)
    return ifloor(x + 0.5)

func _chars(text):
    out := []
    for c in text:
        append(out, str(c))
    return out

func _join_range(chars, i, count):
    out := ""
    k := 0
    while k < count:
        out = out + chars[i + k]
        k = k + 1
    return out

func _is_digit(c):
    o := string.ord(c)
    return o >= 48 and o <= 57

func _is_space(c):
    return c == " " or c == "\t" or c == "\n" or c == "\r"

# Minuscules « pliées » : ASCII + lettres latines accentuées U+00C0..U+00DE (sauf ×) ; sert aux comparaisons.
func _fold(text):
    out := ""
    for c in text:
        s := str(c)
        o := string.ord(s)
        if o >= 65 and o <= 90:
            out = out + str(string.chr(o + 32))
        elif o >= 192 and o <= 222 and o != 215:
            out = out + str(string.chr(o + 32))
        else:
            out = out + s
    return out

func _pad(n, width):
    neg := n < 0
    s := str(-n if neg else n)
    if len(s) < width:
        s = string.repeat("0", width - len(s)) + s
    return "-" + s if neg else s

func _pad_space(n, width):
    s := str(n)
    if len(s) < width:
        s = string.repeat(" ", width - len(s)) + s
    return s

# Année : 4 chiffres minimum ; « -0044 » pour les années négatives, « 12345 » au-delà de 9999.
func _year_str(y):
    if y >= 0:
        return _pad(y, 4)
    return "-" + _pad(-y, 4)

# Année ISO 8601 étendue : « +12345 » au-delà de 9999, « -0044 » en dessous de 0.
func _year_iso(y):
    if y > 9999:
        return "+" + str(y)
    return _year_str(y)

# ---------------------------------------------------------------------------------------------------------------
# Horloges
# ---------------------------------------------------------------------------------------------------------------

# Remplace les horloges (tests déterministes) : wall() -> secondes epoch ; mono() -> secondes ;
# sleeper(s) pour dormir. null rétablit la valeur du système.
func set_clock(wall=null, mono=null, sleeper=null):
    _state["wall"] = wall
    _state["mono"] = mono
    _state["sleep"] = sleeper

func reset_clock():
    _state["wall"] = null
    _state["mono"] = null
    _state["sleep"] = null
    _state["local"] = null

# Horloge manuelle : `advance(s)` fait avancer le temps, `sleep` n'attend pas réellement.
class FakeClock:
    now := 0
    func init(start=0):
        self.now = start
    func advance(seconds):
        self.now = self.now + seconds
        return self.now
    func set(value):
        self.now = value
        return self.now

# Installe une FakeClock comme horloge murale, monotone et de sommeil ; renvoie l'horloge.
func install_fake_clock(start=0):
    fc := FakeClock(start)
    _state["wall"] = () => fc.now
    _state["mono"] = () => fc.now
    _state["sleep"] = s => fc.advance(s)
    return fc

# Fixe la zone « locale » vue par localtime / mktime (offset en secondes à l'est de UTC) ; null = système.
func set_local_zone(offset=null, name=null, is_dst=false):
    if offset == null:
        _state["local"] = null
        return null
    _need_int("set_local_zone", "offset", offset)
    label := name
    if label == null:
        label = _offset_name(offset)
    _state["local"] = {"offset": offset, "name": label, "dst": is_dst}
    return null

func _local_info():
    o := _state["local"]
    if o != null:
        return o
    st := os.system_time()
    return {"offset": st["utc_offset"], "name": st["timezone"], "dst": st["is_dst"]}

# Décalage actuel du système par rapport à UTC, en secondes (à l'est = positif).
func local_utc_offset():
    return _local_info()["offset"]

# Heure murale : secondes depuis 1970-01-01 UTC (float).
func time():
    w := _state["wall"]
    if w != null:
        return w()
    return os.time()

# Heure murale en nanosecondes (int ; précision réelle ≈ microseconde).
func time_ns():
    p := split_timestamp(time())
    return p[0] * 1000000000 + p[1] * 1000

# Horloge monotone (secondes) : ne recule jamais ; à utiliser pour mesurer une durée.
func monotonic():
    m := _state["mono"]
    if m != null:
        return m()
    return os.monotonic_time()

func monotonic_ns():
    p := split_timestamp(monotonic())
    return p[0] * 1000000000 + p[1] * 1000

# Chronométrage de précision (alias de monotonic).
func perf_counter():
    return monotonic()

# Suspend l'exécution `seconds` secondes (nombre >= 0).
func sleep(seconds):
    _need_number("sleep", "seconds", seconds)
    if seconds < 0:
        _fail("time.sleep : durée négative")
    s := _state["sleep"]
    if s != null:
        s(seconds)
        return null
    os.sleep(seconds)
    return null

# Dort jusqu'à l'instant `timestamp` (secondes epoch) ; rend tout de suite s'il est passé. Renvoie le temps dormi.
func sleep_until(timestamp):
    _need_number("sleep_until", "timestamp", timestamp)
    d := timestamp - time()
    if d <= 0:
        return 0.0
    sleep(d)
    return d

# ---------------------------------------------------------------------------------------------------------------
# Calendrier grégorien proleptique (entiers, O(1), toute année)
# ---------------------------------------------------------------------------------------------------------------

func is_leap(year):
    _need_int("is_leap", "year", year)
    return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)

func days_in_month(year, month):
    _need_int("days_in_month", "year", year)
    _need_int("days_in_month", "month", month)
    if month < 1 or month > 12:
        _fail("time.days_in_month : mois hors limites (1..12) : " + str(month))
    if month == 2 and is_leap(year):
        return 29
    return _DIM[month - 1]

func days_in_year(year):
    return 366 if is_leap(year) else 365

# Jours depuis 1970-01-01 pour year-month-day, sans valider le jour (month doit être 1..12).
func _dfc(year, month, day):
    y := year - 1 if month <= 2 else year
    era := y // 400
    yoe := y - era * 400
    mp := (month + 9) % 12
    doy := (153 * mp + 2) // 5 + day - 1
    doe := yoe * 365 + yoe // 4 - yoe // 100 + doy
    return era * 146097 + doe - 719468

# Jours écoulés depuis 1970-01-01 (négatif avant) ; valide la date.
func days_from_civil(year, month, day):
    _need_int("days_from_civil", "year", year)
    _need_int("days_from_civil", "month", month)
    _need_int("days_from_civil", "day", day)
    if month < 1 or month > 12:
        _fail("time.days_from_civil : mois hors limites (1..12) : " + str(month))
    if day < 1 or day > days_in_month(year, month):
        _fail("time.days_from_civil : jour hors limites pour " + _year_str(year) + "-" + _pad(month, 2) + " : " + str(day))
    return _dfc(year, month, day)

# Inverse : (year, month, day) pour un nombre de jours depuis 1970-01-01.
func civil_from_days(days):
    _need_int("civil_from_days", "days", days)
    z := days + 719468
    era := z // 146097
    doe := z - era * 146097
    yoe := (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
    y := yoe + era * 400
    doy := doe - (365 * yoe + yoe // 4 - yoe // 100)
    mp := (5 * doy + 2) // 153
    d := doy - (153 * mp + 2) // 5 + 1
    m := mp + 3 if mp < 10 else mp - 9
    if m <= 2:
        y = y + 1
    return (y, m, d)

# Jour de la semaine (0 = lundi) pour un nombre de jours depuis 1970-01-01 (jeudi).
func weekday_of_days(days):
    return (days + 3) % 7

func weekday(year, month, day):
    return weekday_of_days(days_from_civil(year, month, day))

func iso_weekday(year, month, day):
    return weekday(year, month, day) + 1

# Rang du jour dans l'année (1..366).
func yearday(year, month, day):
    return days_from_civil(year, month, day) - _dfc(year, 1, 1) + 1

# Numéro d'ordre : 0001-01-01 = 1 (calendrier grégorien proleptique).
func to_ordinal(year, month, day):
    return days_from_civil(year, month, day) + UNIX_EPOCH_ORDINAL

func from_ordinal(ordinal):
    _need_int("from_ordinal", "ordinal", ordinal)
    return civil_from_days(ordinal - UNIX_EPOCH_ORDINAL)

func _p(y):
    return (y + y // 4 - y // 100 + y // 400) % 7

# Nombre de semaines ISO (52 ou 53) de l'année ISO `year`.
func weeks_in_year(year):
    _need_int("weeks_in_year", "year", year)
    if _p(year) == 4 or _p(year - 1) == 3:
        return 53
    return 52

# (année ISO, semaine ISO 1..53, jour ISO 1..7) d'une date.
func iso_calendar(year, month, day):
    days := days_from_civil(year, month, day)
    wd := weekday_of_days(days)
    doy := days - _dfc(year, 1, 1) + 1
    week := (doy - (wd + 1) + 10) // 7
    iso_year := year
    if week < 1:
        iso_year = year - 1
        week = weeks_in_year(iso_year)
    elif week > weeks_in_year(year):
        iso_year = year + 1
        week = 1
    return (iso_year, week, wd + 1)

# Date (year, month, day) d'une année ISO, d'une semaine et d'un jour ISO (1 = lundi ... 7 = dimanche).
func iso_to_civil(iso_year, week, iso_day=1):
    _need_int("iso_to_civil", "iso_year", iso_year)
    _need_int("iso_to_civil", "week", week)
    _need_int("iso_to_civil", "iso_day", iso_day)
    if week < 1 or week > weeks_in_year(iso_year):
        _fail("time.iso_to_civil : semaine ISO hors limites pour " + str(iso_year) + " : " + str(week))
    if iso_day < 1 or iso_day > 7:
        _fail("time.iso_to_civil : jour ISO hors limites (1..7) : " + str(iso_day))
    jan4 := _dfc(iso_year, 1, 4)
    monday := jan4 - weekday_of_days(jan4)
    return civil_from_days(monday + (week - 1) * 7 + (iso_day - 1))

# Jour du mois du n-ième `weekday` (0 = lundi) du mois : n >= 1 depuis le début, n = -1 le dernier, -2 l'avant-dernier.
func nth_weekday(year, month, weekday_, n):
    dim := days_in_month(year, month)
    _need_int("nth_weekday", "weekday", weekday_)
    _need_int("nth_weekday", "n", n)
    if weekday_ < 0 or weekday_ > 6:
        _fail("time.nth_weekday : jour de semaine hors limites (0..6) : " + str(weekday_))
    if n == 0:
        _fail("time.nth_weekday : n ne peut pas valoir 0")
    day := 0
    if n > 0:
        first := weekday_of_days(_dfc(year, month, 1))
        day = 1 + (weekday_ - first) % 7 + (n - 1) * 7
    else:
        last := weekday_of_days(_dfc(year, month, dim))
        day = dim - (last - weekday_) % 7 + (n + 1) * 7
    if day < 1 or day > dim:
        _fail("time.nth_weekday : ce jour n'existe pas dans " + _year_str(year) + "-" + _pad(month, 2))
    return day

# Dimanche de Pâques (calendrier grégorien, algorithme de Meeus/Jones/Butcher) : (month, day).
# Valable pour toute année ; avant 1583 c'est la date proleptique grégorienne, pas celle de l'époque.
func easter(year):
    _need_int("easter", "year", year)
    a := year % 19
    b := year // 100
    c := year % 100
    d := b // 4
    e := b % 4
    f := (b + 8) // 25
    g := (b - f + 1) // 3
    h := (19 * a + b - d - g + 15) % 30
    i := c // 4
    k := c % 4
    l := (32 + 2 * e + 2 * i - h - k) % 7
    m := (a + 11 * h + 22 * l) // 451
    t := h + l - 7 * m + 114
    return (t // 31, t % 31 + 1)

# Grille d'un mois : liste de semaines (7 entiers, 0 = case vide). first_weekday : 0 = lundi ... 6 = dimanche.
func month_matrix(year, month, first_weekday=0):
    dim := days_in_month(year, month)
    _need_int("month_matrix", "first_weekday", first_weekday)
    if first_weekday < 0 or first_weekday > 6:
        _fail("time.month_matrix : first_weekday hors limites (0..6)")
    start := (weekday_of_days(_dfc(year, month, 1)) - first_weekday) % 7
    weeks := []
    week := []
    k := 0
    while k < start:
        append(week, 0)
        k = k + 1
    day := 1
    while day <= dim:
        append(week, day)
        if len(week) == 7:
            append(weeks, week)
            week = []
        day = day + 1
    if len(week) > 0:
        while len(week) < 7:
            append(week, 0)
        append(weeks, week)
    return weeks

# Calendrier du mois en texte (comme la commande `cal`).
func month_calendar(year, month, first_weekday=0, locale="en"):
    loc := _locale(locale)
    title := loc["months"][month - 1] + " " + _year_str(year)
    out := ""
    width := 20
    pad := (width - len(title)) // 2
    if pad > 0:
        out = string.repeat(" ", pad)
    out = out + title + "\n"
    heads := []
    k := 0
    while k < 7:
        name := loc["days_abbr"][(first_weekday + k) % 7]
        name = _fold_cut(name, 2)
        append(heads, name)
        k = k + 1
    out = out + string.join(" ", heads) + "\n"
    for week in month_matrix(year, month, first_weekday):
        cells := []
        for d in week:
            append(cells, "  " if d == 0 else _pad_space(d, 2))
        out = out + string.join(" ", cells) + "\n"
    return out

# Les `n` premiers caractères de `text`, complétés à droite par des espaces jusqu'à n.
func _fold_cut(text, n):
    out := ""
    k := 0
    for c in text:
        if k < n:
            out = out + str(c)
        k = k + 1
    while len(out) < n:
        out = out + " "
    return out

# ---------------------------------------------------------------------------------------------------------------
# Timestamps ↔ champs
# ---------------------------------------------------------------------------------------------------------------

# Découpe un timestamp (int ou float) en (secondes entières, microsecondes 0..999999), exactement pour un int.
func split_timestamp(ts):
    if type(ts) == "int":
        return (ts, 0)
    _need_number("split_timestamp", "ts", ts)
    whole := ifloor(ts)
    us := iround((ts - to_float(whole)) * 1000000.0)
    if us >= 1000000:
        whole = whole + 1
        us = us - 1000000
    return (whole, us)

func _fields_from_days(days, sod, micro):
    ymd := civil_from_days(days)
    return {"year": ymd[0], "month": ymd[1], "day": ymd[2], "hour": sod // 3600, "minute": (sod % 3600) // 60,
            "second": sod % 60, "microsecond": micro, "weekday": weekday_of_days(days),
            "yearday": days - _dfc(ymd[0], 1, 1) + 1, "utc_offset": 0, "timezone": "UTC", "is_dst": false}

# Champs d'un instant exprimé en secondes entières + microsecondes, vu avec un décalage donné.
func _fields_at(whole, micro, offset, name, dst):
    local := whole + offset
    r := _fields_from_days(local // 86400, local % 86400, micro)
    r["utc_offset"] = offset
    r["timezone"] = name
    r["is_dst"] = dst
    return r

# Champs UTC d'un timestamp (maintenant si null).
func gmtime(ts=null):
    if ts == null:
        ts = time()
    p := split_timestamp(ts)
    return _fields_at(p[0], p[1], 0, "UTC", false)

# Champs dans la zone locale du système (décalage actuel, voir « limites assumées »).
func localtime(ts=null):
    if ts == null:
        ts = time()
    p := split_timestamp(ts)
    info := _local_info()
    return _fields_at(p[0], p[1], info["offset"], info["name"], info["dst"])

# Champs vus avec un décalage fixe `offset` (secondes à l'est de UTC).
func fields_at_offset(ts, offset, name=null):
    _need_int("fields_at_offset", "offset", offset)
    p := split_timestamp(ts)
    label := name
    if label == null:
        label = _offset_name(offset)
    return _fields_at(p[0], p[1], offset, label, false)

func _get(d, key, fallback):
    if contains_key(d, key):
        v := d[key]
        if v != null:
            return v
    return fallback

# Champs normalisés d'un dict (ou d'un timestamp : UTC) avec weekday / yearday calculés.
func _complete(t):
    if t == null:
        return localtime()
    ty := type(t)
    if ty == "int" or ty == "float":
        return gmtime(t)
    if ty != "dict":
        raise("TypeError", "time : un dict de champs ou un timestamp est attendu (obtenu '" + ty + "')")
    if not contains_key(t, "year"):
        _fail("time : le champ 'year' est obligatoire")
    year := t["year"]
    month := _get(t, "month", 1)
    day := _get(t, "day", 1)
    _need_int("champs", "year", year)
    _need_int("champs", "month", month)
    _need_int("champs", "day", day)
    if month < 1 or month > 12:
        _fail("time : mois hors limites (1..12) : " + str(month))
    if day < 1 or day > days_in_month(year, month):
        _fail("time : jour hors limites : " + str(day))
    days := _dfc(year, month, day)
    return {"year": year, "month": month, "day": day, "hour": _get(t, "hour", 0), "minute": _get(t, "minute", 0),
            "second": _get(t, "second", 0), "microsecond": _get(t, "microsecond", 0),
            "weekday": weekday_of_days(days), "yearday": days - _dfc(year, 1, 1) + 1,
            "utc_offset": _get(t, "utc_offset", null), "timezone": _get(t, "timezone", null),
            "is_dst": _get(t, "is_dst", false)}

# Jours depuis 1970-01-01 de champs éventuellement hors plage (mois 0 ou 14, jour 0 ou 400...).
func _days_normalized(year, month, day):
    m0 := month - 1
    return _dfc(year + m0 // 12, m0 % 12 + 1, 1) + day - 1

# (secondes entières, microsecondes) UTC de champs, en ignorant utc_offset (les champs sont lus comme UTC).
func _parts_from_fields(t):
    if type(t) == "list" or type(t) == "tuple":
        t = _fields_from_sequence(t)
    if type(t) != "dict":
        raise("TypeError", "time.timegm : un dict de champs est attendu (obtenu '" + type(t) + "')")
    if not contains_key(t, "year"):
        _fail("time.timegm : le champ 'year' est obligatoire")
    year := t["year"]
    month := _get(t, "month", 1)
    day := _get(t, "day", 1)
    hour := _get(t, "hour", 0)
    minute := _get(t, "minute", 0)
    second := _get(t, "second", 0)
    micro := _get(t, "microsecond", 0)
    for pair in [["year", year], ["month", month], ["day", day], ["hour", hour], ["minute", minute], ["second", second],
                 ["microsecond", micro]]:
        _need_int("timegm", pair[0], pair[1])
    days := _days_normalized(year, month, day)
    secs := hour * 3600 + minute * 60 + second + micro // 1000000
    return (days * 86400 + secs, micro % 1000000)

func _fields_from_sequence(seq):
    names := ["year", "month", "day", "hour", "minute", "second", "microsecond"]
    d := {}
    k := 0
    while k < len(seq) and k < 7:
        d[names[k]] = seq[k]
        k = k + 1
    return d

# Timestamp UTC de champs (inverse de gmtime) : int si microsecond vaut 0, sinon float. Accepte aussi une liste
# [year, month, day, hour, minute, second, microsecond]. Champs hors plage normalisés ; utc_offset ignoré.
func timegm(t):
    p := _parts_from_fields(t)
    if p[1] == 0:
        return p[0]
    return to_float(p[0]) + to_float(p[1]) / 1000000.0

# Timestamp de champs locaux : utilise t["utc_offset"] s'il est présent, sinon le décalage actuel du système.
func mktime(t):
    p := _parts_from_fields(t)
    off := null
    if type(t) == "dict":
        off = _get(t, "utc_offset", null)
    if off == null:
        off = local_utc_offset()
    whole := p[0] - off
    if p[1] == 0:
        return whole
    return to_float(whole) + to_float(p[1]) / 1000000.0

# ---------------------------------------------------------------------------------------------------------------
# Langues (noms de mois et de jours)
# ---------------------------------------------------------------------------------------------------------------

func _loc(months, months_abbr, days, days_abbr, am, pm, fmt_c, fmt_x, fmt_X):
    return {"months": months, "months_abbr": months_abbr, "days": days, "days_abbr": days_abbr, "am": am, "pm": pm,
            "fmt_c": fmt_c, "fmt_x": fmt_x, "fmt_X": fmt_X}

func _install_locales():
    L := _state["locales"]
    L["en"] = _loc(["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"], ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"], ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"], ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], "AM", "PM", "%a %b %e %H:%M:%S %Y", "%m/%d/%y", "%H:%M:%S")
    L["fr"] = _loc(["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"], ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."], ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"], ["lun.", "mar.", "mer.", "jeu.", "ven.", "sam.", "dim."], "AM", "PM", "%A %d %B %Y %H:%M:%S", "%d/%m/%Y", "%H:%M:%S")
    L["es"] = _loc(["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"], ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"], ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"], ["lun", "mar", "mié", "jue", "vie", "sáb", "dom"], "AM", "PM", "%A, %d de %B de %Y %H:%M:%S", "%d/%m/%Y", "%H:%M:%S")
    L["de"] = _loc(["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"], ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"], ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"], ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"], "AM", "PM", "%A, %d. %B %Y %H:%M:%S", "%d.%m.%Y", "%H:%M:%S")
    L["it"] = _loc(["gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno", "luglio", "agosto", "settembre", "ottobre", "novembre", "dicembre"], ["gen", "feb", "mar", "apr", "mag", "giu", "lug", "ago", "set", "ott", "nov", "dic"], ["lunedì", "martedì", "mercoledì", "giovedì", "venerdì", "sabato", "domenica"], ["lun", "mar", "mer", "gio", "ven", "sab", "dom"], "AM", "PM", "%A %d %B %Y %H:%M:%S", "%d/%m/%Y", "%H:%M:%S")
    L["pt"] = _loc(["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"], ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"], ["segunda-feira", "terça-feira", "quarta-feira", "quinta-feira", "sexta-feira", "sábado", "domingo"], ["seg", "ter", "qua", "qui", "sex", "sáb", "dom"], "AM", "PM", "%A, %d de %B de %Y %H:%M:%S", "%d/%m/%Y", "%H:%M:%S")
    L["nl"] = _loc(["januari", "februari", "maart", "april", "mei", "juni", "juli", "augustus", "september", "oktober", "november", "december"], ["jan", "feb", "mrt", "apr", "mei", "jun", "jul", "aug", "sep", "okt", "nov", "dec"], ["maandag", "dinsdag", "woensdag", "donderdag", "vrijdag", "zaterdag", "zondag"], ["ma", "di", "wo", "do", "vr", "za", "zo"], "AM", "PM", "%A %d %B %Y %H:%M:%S", "%d-%m-%Y", "%H:%M:%S")

_install_locales()

func _locale(code):
    if type(code) != "str" or len(code) < 2:
        raise("TypeError", "time : le code de langue doit être une chaîne (ex. \"fr\")")
    key := ""
    k := 0
    for c in code:
        s := str(c)
        if s == "_" or s == "-" or s == ".":
            break
        key = key + s
    key = _fold(key)
    L := _state["locales"]
    if contains_key(L, key):
        return L[key]
    _fail("time : langue inconnue '" + code + "' (disponibles : " + string.join(", ", keys(L)) + ")")

# Ajoute ou remplace une langue. data = {"months": 12 noms, "months_abbr": 12, "days": 7 noms (lundi en premier),
# "days_abbr": 7} ; facultatifs : "am", "pm", "fmt_c", "fmt_x", "fmt_X" (formats pour %c %x %X).
func register_locale(code, data):
    _need_str("register_locale", "code", code)
    if type(data) != "dict":
        raise("TypeError", "time.register_locale : data doit être un dict")
    sizes := {"months": 12, "months_abbr": 12, "days": 7, "days_abbr": 7}
    for name in keys(sizes):
        if not contains_key(data, name) or type(data[name]) != "list" or len(data[name]) != sizes[name]:
            _fail("time.register_locale : '" + name + "' doit être une liste de " + str(sizes[name]) + " noms")
    _state["locales"][_fold(code)] = _loc(data["months"], data["months_abbr"], data["days"], data["days_abbr"],
        _get(data, "am", "AM"), _get(data, "pm", "PM"), _get(data, "fmt_c", "%a %b %e %H:%M:%S %Y"),
        _get(data, "fmt_x", "%Y-%m-%d"), _get(data, "fmt_X", "%H:%M:%S"))
    return null

func locales():
    return keys(_state["locales"])

# Nom du mois (1..12) ; abbr = true pour la forme courte.
func month_name(month, locale="en", abbr=false):
    _need_int("month_name", "month", month)
    if month < 1 or month > 12:
        _fail("time.month_name : mois hors limites (1..12) : " + str(month))
    loc := _locale(locale)
    return loc["months_abbr" if abbr else "months"][month - 1]

# Nom du jour (0 = lundi ... 6 = dimanche).
func day_name(weekday_, locale="en", abbr=false):
    _need_int("day_name", "weekday", weekday_)
    if weekday_ < 0 or weekday_ > 6:
        _fail("time.day_name : jour de semaine hors limites (0..6) : " + str(weekday_))
    loc := _locale(locale)
    return loc["days_abbr" if abbr else "days"][weekday_]

# ---------------------------------------------------------------------------------------------------------------
# Décalages horaires (texte)
# ---------------------------------------------------------------------------------------------------------------

# « +02:00 » (colon = true) ou « +0200 » ; les secondes ne sont ajoutées que si elles sont non nulles.
func format_offset(offset, colon=true):
    _need_int("format_offset", "offset", offset)
    sign := "-" if offset < 0 else "+"
    a := -offset if offset < 0 else offset
    sep := ":" if colon else ""
    out := sign + _pad(a // 3600, 2) + sep + _pad((a % 3600) // 60, 2)
    if a % 60 != 0:
        out = out + sep + _pad(a % 60, 2)
    return out

func _offset_name(offset):
    if offset == 0:
        return "UTC"
    return "UTC" + format_offset(offset, true)

# ---------------------------------------------------------------------------------------------------------------
# strftime
# ---------------------------------------------------------------------------------------------------------------

# Remplace les directives composées (%F %T %D %R %r %c %x %X) par leurs directives simples.
func _expand_composites(fmt, loc):
    chars := _chars(fmt)
    n := len(chars)
    out := ""
    i := 0
    while i < n:
        c := chars[i]
        if c == "%" and i + 1 < n:
            d := chars[i + 1]
            if d == "F":
                out = out + "%Y-%m-%d"
            elif d == "T":
                out = out + "%H:%M:%S"
            elif d == "D":
                out = out + "%m/%d/%y"
            elif d == "R":
                out = out + "%H:%M"
            elif d == "r":
                out = out + "%I:%M:%S %p"
            elif d == "c":
                out = out + loc["fmt_c"]
            elif d == "x":
                out = out + loc["fmt_x"]
            elif d == "X":
                out = out + loc["fmt_X"]
            else:
                out = out + c + d
            i = i + 2
        else:
            out = out + c
            i = i + 1
    return out

func _strip_zeros(s):
    k := 0
    n := len(s)
    chars := _chars(s)
    while k < n - 1 and (chars[k] == "0" or chars[k] == " "):
        k = k + 1
    out := ""
    while k < n:
        out = out + chars[k]
        k = k + 1
    return out

func _hour12(h):
    r := h % 12
    return 12 if r == 0 else r

func _directive(d, flag, f, loc):
    year := f["year"]
    out := ""
    numeric := true
    if d == "Y":
        out = _year_str(year)
    elif d == "y":
        out = _pad(year % 100, 2)
    elif d == "C":
        out = _pad(year // 100, 2)
    elif d == "m":
        out = _pad(f["month"], 2)
    elif d == "d":
        out = _pad(f["day"], 2)
    elif d == "e":
        out = _pad_space(f["day"], 2)
    elif d == "H":
        out = _pad(f["hour"], 2)
    elif d == "I":
        out = _pad(_hour12(f["hour"]), 2)
    elif d == "M":
        out = _pad(f["minute"], 2)
    elif d == "S":
        out = _pad(f["second"], 2)
    elif d == "f":
        out = _pad(f["microsecond"], 6)
    elif d == "L":
        out = _pad(f["microsecond"] // 1000, 3)
    elif d == "j":
        out = _pad(f["yearday"], 3)
    elif d == "u":
        out = str(f["weekday"] + 1)
    elif d == "w":
        out = str((f["weekday"] + 1) % 7)
    elif d == "U":
        out = _pad((f["yearday"] - 1 + 7 - (f["weekday"] + 1) % 7) // 7, 2)
    elif d == "W":
        out = _pad((f["yearday"] - 1 + 7 - f["weekday"]) // 7, 2)
    elif d == "V":
        out = _pad(iso_calendar(year, f["month"], f["day"])[1], 2)
    elif d == "G":
        out = _year_str(iso_calendar(year, f["month"], f["day"])[0])
    elif d == "g":
        out = _pad(iso_calendar(year, f["month"], f["day"])[0] % 100, 2)
    elif d == "p":
        out = loc["pm"] if f["hour"] >= 12 else loc["am"]
        numeric = false
    elif d == "A":
        out = loc["days"][f["weekday"]]
        numeric = false
    elif d == "a":
        out = loc["days_abbr"][f["weekday"]]
        numeric = false
    elif d == "B":
        out = loc["months"][f["month"] - 1]
        numeric = false
    elif d == "b" or d == "h":
        out = loc["months_abbr"][f["month"] - 1]
        numeric = false
    elif d == "z":
        numeric = false
        off := f["utc_offset"]
        if off == null:
            out = ""
        else:
            out = format_offset(off, flag == ":")
    elif d == "Z":
        numeric = false
        out = f["timezone"] if f["timezone"] != null else ""
    elif d == "s":
        off2 := f["utc_offset"]
        out = str(timegm(f) - (0 if off2 == null else off2))
    elif d == "n":
        out = "\n"
        numeric = false
    elif d == "t":
        out = "\t"
        numeric = false
    elif d == "%":
        out = "%"
        numeric = false
    else:
        _fail("time.strftime : directive inconnue '%" + d + "'")
    if flag == "-" and numeric:
        out = _strip_zeros(out)
    return out

# Formate des champs (dict de gmtime / localtime / datetime) ou un timestamp (lu comme UTC ; maintenant en zone
# locale si null). Directives : %Y %y %C %m %d %e %H %I %M %S %f (µs) %L (ms) %j %u %w %U %W %V %G %g %p %A %a %B %b
# %h %z (+0200) %:z (+02:00) %Z %s %n %t %% et les composées %F %T %D %R %r %c %x %X. Drapeau « - » : sans zéros
# initiaux (%-d, %-m, %-H...).
func strftime(fmt, t=null, locale="en"):
    _need_str("strftime", "fmt", fmt)
    loc := _locale(locale)
    f := _complete(t)
    chars := _chars(_expand_composites(fmt, loc))
    n := len(chars)
    out := ""
    i := 0
    while i < n:
        c := chars[i]
        if c != "%":
            out = out + c
            i = i + 1
            continue
        i = i + 1
        if i >= n:
            _fail("time.strftime : '%' isolé en fin de format")
        flag := ""
        if chars[i] == "-" or chars[i] == ":":
            flag = chars[i]
            i = i + 1
            if i >= n:
                _fail("time.strftime : directive incomplète en fin de format")
        out = out + _directive(chars[i], flag, f, loc)
        i = i + 1
    return out

# « Wed Oct  7 08:00:00 2026 » (format C asctime, noms anglais).
func asctime(t=null):
    return strftime("%a %b %e %H:%M:%S %Y", t, "en")

func ctime(ts=null):
    return asctime(localtime(ts))

# ---------------------------------------------------------------------------------------------------------------
# strptime
# ---------------------------------------------------------------------------------------------------------------

func _parse_fail(text, fmt, pos, why):
    _fail("time.strptime : '" + text + "' ne correspond pas au format '" + fmt + "' (position " + str(pos) + " : " + why + ")")

# Lit entre min_n et max_n chiffres (max_n = 0 : sans limite) ; renvoie [valeur, nouvel indice] ou null.
func _read_digits(chars, i, min_n, max_n):
    n := len(chars)
    j := i
    v := 0
    count := 0
    while j < n and _is_digit(chars[j]) and (max_n == 0 or count < max_n):
        v = v * 10 + (string.ord(chars[j]) - 48)
        j = j + 1
        count = count + 1
    if count < min_n:
        return null
    return [v, j]

# Fraction de seconde : 1 à 9 chiffres -> microsecondes (tronquées).
func _read_fraction(chars, i):
    n := len(chars)
    j := i
    digits := ""
    while j < n and _is_digit(chars[j]) and len(digits) < 9:
        digits = digits + chars[j]
        j = j + 1
    if len(digits) == 0:
        return null
    while len(digits) < 6:
        digits = digits + "0"
    micro := 0
    k := 0
    while k < 6:
        micro = micro * 10 + (string.ord(str(digits[k])) - 48)
        k = k + 1
    return [micro, j]

# Cherche le plus long nom (liste) qui commence à l'indice i, sans tenir compte de la casse ; [rang, indice] ou null.
func _match_name(chars, i, names):
    best := -1
    bestlen := 0
    k := 0
    n := len(chars)
    while k < len(names):
        nm := names[k]
        ln := len(nm)
        if ln > bestlen and i + ln <= n:
            if _fold(_join_range(chars, i, ln)) == _fold(nm):
                best = k
                bestlen = ln
        k = k + 1
    if best < 0:
        return null
    return [best, i + bestlen]

func _without_dot(names):
    out := []
    for nm in names:
        chars := _chars(str(nm))
        cnt := len(chars)
        if cnt > 1 and chars[cnt - 1] == ".":
            append(out, _join_range(chars, 0, cnt - 1))
        else:
            append(out, str(nm))
    return out

func _concat(a, b):
    out := []
    for x in a:
        append(out, x)
    for x in b:
        append(out, x)
    return out

# Décalage lu à l'indice i : Z, ±HH, ±HH:MM, ±HHMM, ±HH:MM:SS ; [secondes, indice] ou null.
func _read_offset(chars, i):
    n := len(chars)
    if i >= n:
        return null
    c := chars[i]
    if c == "Z" or c == "z":
        return [0, i + 1]
    if c != "+" and c != "-":
        return null
    sign := -1 if c == "-" else 1
    r := _read_digits(chars, i + 1, 2, 2)
    if r == null:
        return null
    hh := r[0]
    j := r[1]
    mm := 0
    ss := 0
    if j < n and chars[j] == ":":
        r2 := _read_digits(chars, j + 1, 2, 2)
        if r2 == null:
            return null
        mm = r2[0]
        j = r2[1]
        if j < n and chars[j] == ":":
            r3 := _read_digits(chars, j + 1, 2, 2)
            if r3 != null:
                ss = r3[0]
                j = r3[1]
    else:
        r2b := _read_digits(chars, j, 2, 2)
        if r2b != null:
            mm = r2b[0]
            j = r2b[1]
            r3b := _read_digits(chars, j, 2, 2)
            if r3b != null:
                ss = r3b[0]
                j = r3b[1]
    if hh > 23 or mm > 59 or ss > 59:
        return null
    return [sign * (hh * 3600 + mm * 60 + ss), j]

# Analyse `text` selon `fmt` (mêmes directives que strftime, plus la lecture souple des espaces) et renvoie des
# champs {"year",...,"weekday","yearday","utc_offset" (null si absent),"timezone" (null si absent)}.
# Valeurs par défaut : 1970-01-01 00:00:00. %y : 69..99 -> 19xx, 00..68 -> 20xx. %Y accepte un signe et un nombre
# quelconque de chiffres ; sans signe, 1 à 4 chiffres (« %Y%m%d » reste donc lisible).
func strptime(text, fmt, locale="en"):
    _need_str("strptime", "text", text)
    _need_str("strptime", "fmt", fmt)
    loc := _locale(locale)
    fchars := _chars(_expand_composites(fmt, loc))
    chars := _chars(text)
    fn := len(fchars)
    n := len(chars)
    month_names := _concat(_concat(loc["months"], loc["months_abbr"]), _without_dot(loc["months_abbr"]))
    day_names := _concat(_concat(loc["days"], loc["days_abbr"]), _without_dot(loc["days_abbr"]))
    year := null
    month := null
    day := null
    hour := 0
    minute := 0
    second := 0
    micro := 0
    hour12 := null
    pm := null
    yday := null
    epoch := null
    offset := null
    zone := null
    i := 0
    while i < n and _is_space(chars[i]):
        i = i + 1
    k := 0
    while k < fn:
        fc := fchars[k]
        if _is_space(fc):
            while i < n and _is_space(chars[i]):
                i = i + 1
            k = k + 1
            continue
        if fc != "%":
            if i >= n or chars[i] != fc:
                _parse_fail(text, fmt, i, "'" + fc + "' attendu")
            i = i + 1
            k = k + 1
            continue
        k = k + 1
        if k >= fn:
            _fail("time.strptime : '%' isolé en fin de format")
        d := fchars[k]
        if d == "-" or d == ":":
            k = k + 1
            if k >= fn:
                _fail("time.strptime : directive incomplète en fin de format")
            if d == ":" and fchars[k] != "z":
                _fail("time.strptime : '%:' n'est valide que devant z")
            d = fchars[k]
        k = k + 1
        if d == "Y":
            sign := 1
            r := null
            if i < n and (chars[i] == "+" or chars[i] == "-"):
                if chars[i] == "-":
                    sign = -1
                r = _read_digits(chars, i + 1, 1, 0)
            else:
                r = _read_digits(chars, i, 1, 4)
            if r == null:
                _parse_fail(text, fmt, i, "année attendue")
            year = sign * r[0]
            i = r[1]
        elif d == "y":
            r := _read_digits(chars, i, 1, 2)
            if r == null:
                _parse_fail(text, fmt, i, "année sur 2 chiffres attendue")
            year = 1900 + r[0] if r[0] >= 69 else 2000 + r[0]
            i = r[1]
        elif d == "C":
            r := _read_digits(chars, i, 1, 2)
            if r == null:
                _parse_fail(text, fmt, i, "siècle attendu")
            i = r[1]
        elif d == "m" or d == "d" or d == "e" or d == "H" or d == "I" or d == "M" or d == "S":
            if d == "e":
                while i < n and chars[i] == " ":
                    i = i + 1
            r := _read_digits(chars, i, 1, 2)
            if r == null:
                _parse_fail(text, fmt, i, "nombre attendu pour %" + d)
            i = r[1]
            if d == "m":
                month = r[0]
            elif d == "d" or d == "e":
                day = r[0]
            elif d == "H":
                hour = r[0]
            elif d == "I":
                hour12 = r[0]
            elif d == "M":
                minute = r[0]
            else:
                second = r[0]
        elif d == "j":
            r := _read_digits(chars, i, 1, 3)
            if r == null:
                _parse_fail(text, fmt, i, "jour de l'année attendu")
            yday = r[0]
            i = r[1]
        elif d == "f":
            r := _read_fraction(chars, i)
            if r == null:
                _parse_fail(text, fmt, i, "fraction de seconde attendue")
            micro = r[0]
            i = r[1]
        elif d == "L":
            r := _read_digits(chars, i, 1, 3)
            if r == null:
                _parse_fail(text, fmt, i, "millisecondes attendues")
            ms := r[0]
            width := r[1] - i
            while width < 3:
                ms = ms * 10
                width = width + 1
            micro = ms * 1000
            i = r[1]
        elif d == "u" or d == "w" or d == "U" or d == "W" or d == "V" or d == "g":
            r := _read_digits(chars, i, 1, 2)
            if r == null:
                _parse_fail(text, fmt, i, "nombre attendu pour %" + d)
            i = r[1]
        elif d == "G":
            sign2 := 1
            if i < n and (chars[i] == "+" or chars[i] == "-"):
                if chars[i] == "-":
                    sign2 = -1
                i = i + 1
            r := _read_digits(chars, i, 1, 0)
            if r == null:
                _parse_fail(text, fmt, i, "année ISO attendue")
            i = r[1]
        elif d == "p":
            m := _match_name(chars, i, [loc["am"], loc["pm"]])
            if m == null:
                _parse_fail(text, fmt, i, "AM/PM attendu")
            pm = m[0] == 1
            i = m[1]
        elif d == "A" or d == "a":
            m := _match_name(chars, i, day_names)
            if m == null:
                _parse_fail(text, fmt, i, "nom de jour attendu")
            i = m[1]
        elif d == "B" or d == "b" or d == "h":
            m := _match_name(chars, i, month_names)
            if m == null:
                _parse_fail(text, fmt, i, "nom de mois attendu")
            month = m[0] % 12 + 1
            i = m[1]
        elif d == "z":
            r := _read_offset(chars, i)
            if r == null:
                _parse_fail(text, fmt, i, "décalage attendu (Z, +02:00, +0200)")
            offset = r[0]
            i = r[1]
        elif d == "Z":
            j := i
            while j < n and not _is_space(chars[j]):
                j = j + 1
            if j == i:
                _parse_fail(text, fmt, i, "nom de fuseau attendu")
            zone = _join_range(chars, i, j - i)
            i = j
        elif d == "s":
            sign3 := 1
            if i < n and (chars[i] == "-" or chars[i] == "+"):
                if chars[i] == "-":
                    sign3 = -1
                i = i + 1
            r := _read_digits(chars, i, 1, 0)
            if r == null:
                _parse_fail(text, fmt, i, "timestamp attendu")
            epoch = sign3 * r[0]
            i = r[1]
        elif d == "n" or d == "t":
            while i < n and _is_space(chars[i]):
                i = i + 1
        elif d == "%":
            if i >= n or chars[i] != "%":
                _parse_fail(text, fmt, i, "'%' attendu")
            i = i + 1
        else:
            _fail("time.strptime : directive inconnue '%" + d + "'")
    while i < n and _is_space(chars[i]):
        i = i + 1
    if i < n:
        _parse_fail(text, fmt, i, "données restantes")
    if epoch != null:
        r := gmtime(epoch)
        if offset != null:
            r = fields_at_offset(epoch, offset)
        return r
    if hour12 != null:
        if hour12 < 1 or hour12 > 12:
            _fail("time.strptime : heure sur 12 hors limites (1..12) : " + str(hour12))
        hour = hour12 % 12 + (12 if pm == true else 0)
    elif pm != null:
        if pm == true and hour < 12:
            hour = hour + 12
    if year == null:
        year = 1970
    if yday != null and month == null and day == null:
        if yday < 1 or yday > days_in_year(year):
            _fail("time.strptime : jour de l'année hors limites : " + str(yday))
        ymd := civil_from_days(_dfc(year, 1, 1) + yday - 1)
        month = ymd[1]
        day = ymd[2]
    if month == null:
        month = 1
    if day == null:
        day = 1
    if month < 1 or month > 12:
        _fail("time.strptime : mois hors limites (1..12) : " + str(month))
    if day < 1 or day > days_in_month(year, month):
        _fail("time.strptime : jour hors limites : " + str(day))
    if hour > 23 or minute > 59 or second > 59:
        _fail("time.strptime : heure hors limites : " + _pad(hour, 2) + ":" + _pad(minute, 2) + ":" + _pad(second, 2))
    days := _dfc(year, month, day)
    return {"year": year, "month": month, "day": day, "hour": hour, "minute": minute, "second": second,
            "microsecond": micro, "weekday": weekday_of_days(days), "yearday": days - _dfc(year, 1, 1) + 1,
            "utc_offset": offset, "timezone": zone, "is_dst": false}

# ---------------------------------------------------------------------------------------------------------------
# ISO 8601
# ---------------------------------------------------------------------------------------------------------------

# Date à l'indice i : AAAA-MM-JJ, AAAAMMJJ, AAAA-DDD, AAAADDD, AAAA-Www-D, AAAAWwwD (année signée : forme étendue
# seulement). Renvoie [year, month, day, nouvel indice] ou null.
func _iso_date(chars, i):
    n := len(chars)
    sign := 1
    signed := false
    j := i
    if j < n and (chars[j] == "+" or chars[j] == "-"):
        signed = true
        if chars[j] == "-":
            sign = -1
        j = j + 1
    ry := null
    if signed:
        ry = _read_digits(chars, j, 4, 0)
    else:
        ry = _read_digits(chars, j, 4, 4)
    if ry == null:
        return null
    year := sign * ry[0]
    j = ry[1]
    if j < n and chars[j] == "-":
        j = j + 1
        if j < n and chars[j] == "W":
            rw := _read_digits(chars, j + 1, 2, 2)
            if rw == null:
                return null
            j = rw[1]
            wd := 1
            if j < n and chars[j] == "-":
                rd := _read_digits(chars, j + 1, 1, 1)
                if rd == null:
                    return null
                wd = rd[0]
                j = rd[1]
            if rw[0] < 1 or rw[0] > weeks_in_year(year) or wd < 1 or wd > 7:
                return null
            ymd := iso_to_civil(year, rw[0], wd)
            return [ymd[0], ymd[1], ymd[2], j]
        jstart := j
        rm := _read_digits(chars, j, 2, 3)
        if rm == null:
            return null
        j = rm[1]
        if j - jstart == 3:
            # AAAA-DDD : jour de l'année
            if rm[0] < 1 or rm[0] > days_in_year(year):
                return null
            ymd2 := civil_from_days(_dfc(year, 1, 1) + rm[0] - 1)
            return [ymd2[0], ymd2[1], ymd2[2], j]
        # AAAA-MM-JJ
        if j >= n or chars[j] != "-":
            return null
        rdd := _read_digits(chars, j + 1, 2, 2)
        if rdd == null:
            return null
        if rm[0] < 1 or rm[0] > 12 or rdd[0] < 1 or rdd[0] > days_in_month(year, rm[0]):
            return null
        return [year, rm[0], rdd[0], rdd[1]]
    if signed:
        return null
    if j < n and chars[j] == "W":
        rw2 := _read_digits(chars, j + 1, 2, 2)
        if rw2 == null:
            return null
        j = rw2[1]
        wd2 := 1
        rd2 := _read_digits(chars, j, 1, 1)
        if rd2 != null:
            wd2 = rd2[0]
            j = rd2[1]
        if rw2[0] < 1 or rw2[0] > weeks_in_year(year) or wd2 < 1 or wd2 > 7:
            return null
        ymd3 := iso_to_civil(year, rw2[0], wd2)
        return [ymd3[0], ymd3[1], ymd3[2], j]
    rc := _read_digits(chars, j, 3, 4)
    if rc == null:
        return null
    if rc[1] - j == 4:
        mm := rc[0] // 100
        dd := rc[0] % 100
        if mm < 1 or mm > 12 or dd < 1 or dd > days_in_month(year, mm):
            return null
        return [year, mm, dd, rc[1]]
    if rc[0] < 1 or rc[0] > days_in_year(year):
        return null
    ymd4 := civil_from_days(_dfc(year, 1, 1) + rc[0] - 1)
    return [ymd4[0], ymd4[1], ymd4[2], rc[1]]

# Heure à l'indice i : HH, HH:MM, HH:MM:SS[.f], HHMM, HHMMSS[.f] ; [h, m, s, µs, indice] ou null.
func _iso_time(chars, i):
    n := len(chars)
    rh := _read_digits(chars, i, 2, 2)
    if rh == null:
        return null
    hh := rh[0]
    j := rh[1]
    mm := 0
    ss := 0
    micro := 0
    extended := j < n and chars[j] == ":"
    if extended:
        rm := _read_digits(chars, j + 1, 2, 2)
        if rm == null:
            return null
        mm = rm[0]
        j = rm[1]
        if j < n and chars[j] == ":":
            rs := _read_digits(chars, j + 1, 2, 2)
            if rs == null:
                return null
            ss = rs[0]
            j = rs[1]
            if j < n and (chars[j] == "." or chars[j] == ","):
                rf := _read_fraction(chars, j + 1)
                if rf == null:
                    return null
                micro = rf[0]
                j = rf[1]
    else:
        rm2 := _read_digits(chars, j, 2, 2)
        if rm2 != null:
            mm = rm2[0]
            j = rm2[1]
            rs2 := _read_digits(chars, j, 2, 2)
            if rs2 != null:
                ss = rs2[0]
                j = rs2[1]
                if j < n and (chars[j] == "." or chars[j] == ","):
                    rf2 := _read_fraction(chars, j + 1)
                    if rf2 == null:
                        return null
                    micro = rf2[0]
                    j = rf2[1]
    if hh > 23 or mm > 59 or ss > 59:
        return null
    return [hh, mm, ss, micro, j]

# Analyse une date-heure ISO 8601 : « 2026-10-07 », « 2026-10-07T08:30:15.25+02:00 », « 20261007T083015Z »,
# « 2026-W41-3 », « 2026-280 », « +12345-01-01 ». Renvoie des champs avec "utc_offset" (null si absent) et
# "has_time" (bool).
func parse_iso(text):
    _need_str("parse_iso", "text", text)
    chars := _chars(text)
    n := len(chars)
    dt := _iso_date(chars, 0)
    if dt == null:
        _fail("time.parse_iso : date ISO 8601 invalide : '" + text + "'")
    i := dt[3]
    hh := 0
    mi := 0
    ss := 0
    micro := 0
    has_time := false
    offset := null
    if i < n:
        c := chars[i]
        if c != "T" and c != "t" and c != " ":
            _fail("time.parse_iso : caractère inattendu après la date : '" + text + "'")
        tm := _iso_time(chars, i + 1)
        if tm == null:
            _fail("time.parse_iso : heure ISO 8601 invalide : '" + text + "'")
        hh = tm[0]
        mi = tm[1]
        ss = tm[2]
        micro = tm[3]
        i = tm[4]
        has_time = true
        if i < n:
            while i < n and chars[i] == " ":
                i = i + 1
            ro := _read_offset(chars, i)
            if ro == null:
                _fail("time.parse_iso : décalage invalide : '" + text + "'")
            offset = ro[0]
            i = ro[1]
            if i < n:
                _fail("time.parse_iso : données restantes : '" + text + "'")
    days := _dfc(dt[0], dt[1], dt[2])
    return {"year": dt[0], "month": dt[1], "day": dt[2], "hour": hh, "minute": mi, "second": ss, "microsecond": micro,
            "weekday": weekday_of_days(days), "yearday": days - _dfc(dt[0], 1, 1) + 1, "utc_offset": offset,
            "timezone": null, "is_dst": false, "has_time": has_time}

# Analyse une heure ISO 8601 seule (« 08:30 », « 083015.5 », « T08:30:15 ») : champs hour/minute/second/microsecond.
func parse_iso_time(text):
    _need_str("parse_iso_time", "text", text)
    chars := _chars(text)
    i := 0
    if len(chars) > 0 and (chars[0] == "T" or chars[0] == "t"):
        i = 1
    tm := _iso_time(chars, i)
    if tm == null:
        _fail("time.parse_iso_time : heure ISO 8601 invalide : '" + text + "'")
    j := tm[4]
    offset := null
    if j < len(chars):
        ro := _read_offset(chars, j)
        if ro == null or ro[1] != len(chars):
            _fail("time.parse_iso_time : données restantes : '" + text + "'")
        offset = ro[0]
    return {"hour": tm[0], "minute": tm[1], "second": tm[2], "microsecond": tm[3], "utc_offset": offset}

# Formate des champs en ISO 8601. sep : séparateur date/heure ; timespec : "auto" (fraction seulement si µs != 0),
# "hours", "minutes", "seconds", "milliseconds", "microseconds" ; offset : secondes (null : pas de décalage) ;
# z = true écrit « Z » pour un décalage nul.
func iso_from_fields(f, offset=null, sep="T", timespec="auto", z=false):
    out := _year_iso(f["year"]) + "-" + _pad(f["month"], 2) + "-" + _pad(f["day"], 2) + sep
    out = out + iso_time_string(f["hour"], f["minute"], f["second"], f["microsecond"], timespec)
    if offset != null:
        if offset == 0 and z:
            out = out + "Z"
        else:
            out = out + format_offset(offset, true)
    return out

func iso_time_string(hour, minute, second, microsecond, timespec="auto"):
    if timespec == "hours":
        return _pad(hour, 2)
    if timespec == "minutes":
        return _pad(hour, 2) + ":" + _pad(minute, 2)
    base := _pad(hour, 2) + ":" + _pad(minute, 2) + ":" + _pad(second, 2)
    if timespec == "seconds":
        return base
    if timespec == "milliseconds":
        return base + "." + _pad(microsecond // 1000, 3)
    if timespec == "microseconds":
        return base + "." + _pad(microsecond, 6)
    if timespec == "auto":
        if microsecond == 0:
            return base
        return base + "." + _pad(microsecond, 6)
    _fail("time : timespec inconnu '" + str(timespec) + "' (auto, hours, minutes, seconds, milliseconds, microseconds)")

# Timestamp -> texte ISO 8601 avec le décalage donné (UTC par défaut, écrit « Z » si z).
func iso_from_timestamp(ts, offset=0, sep="T", timespec="auto", z=false):
    f := fields_at_offset(ts, offset)
    return iso_from_fields(f, offset, sep, timespec, z)

# Texte ISO 8601 -> timestamp (int si pas de fraction, sinon float). default_offset sert si le texte n'a pas de
# décalage (0 = UTC).
func parse_iso_timestamp(text, default_offset=0):
    f := parse_iso(text)
    off := f["utc_offset"]
    if off == null:
        off = default_offset
    p := _parts_from_fields(f)
    whole := p[0] - off
    if p[1] == 0:
        return whole
    return to_float(whole) + to_float(p[1]) / 1000000.0

# ---------------------------------------------------------------------------------------------------------------
# Durées
# ---------------------------------------------------------------------------------------------------------------

# Normalise (jours, secondes, microsecondes) : 0 <= secondes < 86400, 0 <= microsecondes < 1 000 000.
func normalize_duration(days, seconds, micro):
    s := seconds + micro // 1000000
    m := micro % 1000000
    d := days + s // 86400
    return (d, s % 86400, m)

# Nombre de secondes (int ou float, éventuellement négatif) -> (jours, secondes, microsecondes) normalisés.
func seconds_to_parts(seconds):
    _need_number("seconds_to_parts", "seconds", seconds)
    p := split_timestamp(seconds)
    return normalize_duration(0, p[0], p[1])

# Total en secondes (float) de (jours, secondes, microsecondes).
func parts_to_seconds(days, seconds, micro):
    return to_float(days) * 86400.0 + to_float(seconds) + to_float(micro) / 1000000.0

func _unit_table():
    return [["weeks", "week", "w", "semaines", "semaine", "sem"], ["days", "day", "d", "jours", "jour", "j"],
            ["hours", "hour", "hrs", "hr", "h", "heures", "heure"], ["minutes", "minute", "mins", "min", "m"],
            ["seconds", "second", "secs", "sec", "s", "secondes", "seconde"],
            ["milliseconds", "millisecond", "ms", "millisecondes", "milliseconde"],
            ["microseconds", "microsecond", "us", "µs", "microsecondes", "microseconde"], ["nanoseconds", "nanosecond", "ns", "nanosecondes", "nanoseconde"]]

# Rang de l'unité nommée (0 semaine, 1 jour, 2 heure, 3 minute, 4 seconde, 5 ms, 6 µs, 7 ns) ou -1.
func _unit_rank(word):
    w := _fold(word)
    table := _unit_table()
    r := 0
    while r < len(table):
        for name in table[r]:
            if name == w:
                return r
        r = r + 1
    return -1

# Ajoute `count` unités de rang `rank` aux accumulateurs [jours, microsecondes] ; frac = partie fractionnaire (float).
func _accumulate(acc, rank, whole, frac):
    if rank == 0:
        acc[0] = acc[0] + whole * 7
        acc[1] = acc[1] + iround(frac * 604800000000.0)
    elif rank == 1:
        acc[0] = acc[0] + whole
        acc[1] = acc[1] + iround(frac * 86400000000.0)
    elif rank == 2:
        acc[1] = acc[1] + whole * 3600000000 + iround(frac * 3600000000.0)
    elif rank == 3:
        acc[1] = acc[1] + whole * 60000000 + iround(frac * 60000000.0)
    elif rank == 4:
        acc[1] = acc[1] + whole * 1000000 + iround(frac * 1000000.0)
    elif rank == 5:
        acc[1] = acc[1] + whole * 1000 + iround(frac * 1000.0)
    elif rank == 6:
        acc[1] = acc[1] + whole + iround(frac)
    else:
        acc[1] = acc[1] + iround((to_float(whole) + frac) / 1000.0)

# Nombre à l'indice i : entiers et décimaux (« . » ou « , ») ; [partie entière, fraction float, indice] ou null.
func _read_number(chars, i):
    n := len(chars)
    r := _read_digits(chars, i, 1, 0)
    if r == null:
        return null
    whole := r[0]
    j := r[1]
    frac := 0.0
    if j < n and (chars[j] == "." or chars[j] == ","):
        k := j + 1
        scale := 0.1
        got := false
        while k < n and _is_digit(chars[k]):
            frac = frac + scale * to_float(string.ord(chars[k]) - 48)
            scale = scale / 10.0
            got = true
            k = k + 1
        if got:
            j = k
    return [whole, frac, j]

# Analyse une durée en (jours, secondes, microsecondes) exacts. Formes : « 1h30m », « 2d 3h », « 1.5h »,
# « 250ms », « 1 hour 30 minutes », « 3 semaines et 2 jours », ISO 8601 « P1DT2H3M4.5S » / « PT90M »
# (sans années ni mois : durées non fixes), horloge « 1:30:00 » / « 1:02:03.5 » / « 2 days, 1:30:00 », nombre seul
# = secondes. Signe « - » ou « + » en tête accepté.
func duration_parts(text):
    _need_str("parse_duration", "text", text)
    chars := _chars(text)
    n := len(chars)
    i := 0
    while i < n and _is_space(chars[i]):
        i = i + 1
    sign := 1
    if i < n and (chars[i] == "-" or chars[i] == "+"):
        if chars[i] == "-":
            sign = -1
        i = i + 1
        while i < n and _is_space(chars[i]):
            i = i + 1
    if i >= n:
        _fail("time.parse_duration : durée vide : '" + text + "'")
    acc := [0, 0]
    if chars[i] == "P" or chars[i] == "p":
        i = _parse_iso_duration(chars, i + 1, acc, text)
    else:
        i = _parse_free_duration(chars, i, acc, text)
    while i < n and _is_space(chars[i]):
        i = i + 1
    if i < n:
        _fail("time.parse_duration : données restantes : '" + text + "'")
    days := acc[0] * sign
    us := acc[1] * sign
    p := normalize_duration(days, 0, us)
    return p

func _parse_iso_duration(chars, start, acc, text):
    n := len(chars)
    i := start
    in_time := false
    seen := false
    while i < n:
        c := chars[i]
        if c == "T" or c == "t":
            if in_time:
                _fail("time.parse_duration : 'T' en double : '" + text + "'")
            in_time = true
            i = i + 1
            continue
        num := _read_number(chars, i)
        if num == null or num[2] >= n:
            _fail("time.parse_duration : durée ISO 8601 invalide : '" + text + "'")
        u := _fold(chars[num[2]])
        rank := -1
        if u == "w" and not in_time:
            rank = 0
        elif u == "d" and not in_time:
            rank = 1
        elif u == "h" and in_time:
            rank = 2
        elif u == "m" and in_time:
            rank = 3
        elif u == "s" and in_time:
            rank = 4
        elif (u == "y" or u == "m") and not in_time:
            _fail("time.parse_duration : années et mois ne sont pas des durées fixes : '" + text + "'")
        else:
            _fail("time.parse_duration : unité ISO 8601 invalide '" + chars[num[2]] + "' : '" + text + "'")
        _accumulate(acc, rank, num[0], num[1])
        seen = true
        i = num[2] + 1
    if not seen:
        _fail("time.parse_duration : durée ISO 8601 vide : '" + text + "'")
    return i

func _parse_free_duration(chars, start, acc, text):
    n := len(chars)
    i := start
    # forme horloge : [N jours,] H:MM[:SS[.f]] (tout le texte)
    clock := _try_clock(chars, i, acc)
    if clock != null:
        return clock
    seen := false
    while i < n:
        while i < n and (_is_space(chars[i]) or chars[i] == ","):
            i = i + 1
        if i >= n:
            break
        word_start := i
        # mots de liaison
        if _fold(chars[i]) == "e" and i + 1 < n and _fold(chars[i + 1]) == "t" and (i + 2 >= n or _is_space(chars[i + 2])):
            i = i + 2
            continue
        if _fold(chars[i]) == "a" and i + 2 < n and _fold(chars[i + 1]) == "n" and _fold(chars[i + 2]) == "d" and (i + 3 >= n or _is_space(chars[i + 3])):
            i = i + 3
            continue
        num := _read_number(chars, i)
        if num == null:
            _fail("time.parse_duration : nombre attendu à la position " + str(i) + " : '" + text + "'")
        i = num[2]
        while i < n and _is_space(chars[i]):
            i = i + 1
        j := i
        while j < n and not _is_digit(chars[j]) and not _is_space(chars[j]) and chars[j] != "," and chars[j] != "-" and chars[j] != "+":
            j = j + 1
        if j == i:
            # nombre seul : secondes, accepté uniquement s'il est la durée entière
            if seen or j < n:
                _fail("time.parse_duration : unité manquante à la position " + str(i) + " : '" + text + "'")
            _accumulate(acc, 4, num[0], num[1])
            seen = true
            i = j
            continue
        rank := _unit_rank(_join_range(chars, i, j - i))
        if rank < 0:
            _fail("time.parse_duration : unité inconnue '" + _join_range(chars, i, j - i) + "' : '" + text + "'")
        _accumulate(acc, rank, num[0], num[1])
        seen = true
        i = j
    if not seen:
        _fail("time.parse_duration : durée vide : '" + text + "'")
    return i

# [N day(s)|jour(s)[,]] H:MM[:SS[.f]] : renvoie l'indice de fin ou null si ce n'est pas une horloge.
func _try_clock(chars, start, acc):
    n := len(chars)
    i := start
    days := 0
    r0 := _read_digits(chars, i, 1, 0)
    if r0 == null:
        return null
    j := r0[1]
    # préfixe « N days, » ?
    k := j
    while k < n and _is_space(chars[k]):
        k = k + 1
    w := k
    while w < n and not _is_digit(chars[w]) and not _is_space(chars[w]) and chars[w] != ",":
        w = w + 1
    if w > k and _unit_rank(_join_range(chars, k, w - k)) == 1:
        days = r0[0]
        i = w
        while i < n and (_is_space(chars[i]) or chars[i] == ","):
            i = i + 1
        r0 = _read_digits(chars, i, 1, 0)
        if r0 == null:
            return null
        j = r0[1]
    if j >= n or chars[j] != ":":
        return null
    hh := r0[0]
    r1 := _read_digits(chars, j + 1, 1, 2)
    if r1 == null:
        return null
    mm := r1[0]
    j = r1[1]
    ss := 0
    micro := 0
    if j < n and chars[j] == ":":
        r2 := _read_digits(chars, j + 1, 1, 2)
        if r2 == null:
            return null
        ss = r2[0]
        j = r2[1]
        if j < n and (chars[j] == "." or chars[j] == ","):
            rf := _read_fraction(chars, j + 1)
            if rf == null:
                return null
            micro = rf[0]
            j = rf[1]
    if mm > 59 or ss > 59:
        _fail("time.parse_duration : minutes ou secondes hors limites (0..59)")
    acc[0] = acc[0] + days
    acc[1] = acc[1] + hh * 3600000000 + mm * 60000000 + ss * 1000000 + micro
    return j

# Durée en secondes : int si elle est entière, sinon float.
func parse_duration(text):
    p := duration_parts(text)
    if p[2] == 0:
        return p[0] * 86400 + p[1]
    return parts_to_seconds(p[0], p[1], p[2])

func _neg_parts(days, secs, micro):
    return normalize_duration(-days, -secs, -micro)

# Fraction « .5 » (au plus 6 chiffres, zéros finaux retirés) à partir de microsecondes non nulles.
func _frac_str(micro):
    s := _pad(micro, 6)
    k := len(s)
    chars := _chars(s)
    while k > 1 and chars[k - 1] == "0":
        k = k - 1
    return _join_range(chars, 0, k)

# Formate (jours, secondes, microsecondes) : style "compact" (« 1d 2h 3m 4.5s »), "clock" (« 26:03:04.5 »),
# "iso" (« P1DT2H3M4.5S »), "long" (« 1 day, 2 hours, 3 minutes and 4.5 seconds » ; locale "en" ou "fr").
func format_duration_parts(days, seconds, micro, style="compact", locale="en"):
    neg := days < 0
    d := days
    s := seconds
    m := micro
    if neg:
        p := _neg_parts(days, seconds, micro)
        d = p[0]
        s = p[1]
        m = p[2]
    sign := "-" if neg else ""
    h := s // 3600
    mi := (s % 3600) // 60
    sec := s % 60
    if style == "compact":
        parts := []
        if d != 0:
            append(parts, str(d) + "d")
        if h != 0:
            append(parts, str(h) + "h")
        if mi != 0:
            append(parts, str(mi) + "m")
        if sec != 0 or m != 0:
            append(parts, str(sec) + ("." + _frac_str(m) if m != 0 else "") + "s")
        if len(parts) == 0:
            return "0s"
        return sign + string.join(" ", parts)
    if style == "clock":
        out := sign + str(d * 24 + h) + ":" + _pad(mi, 2) + ":" + _pad(sec, 2)
        if m != 0:
            out = out + "." + _frac_str(m)
        return out
    if style == "iso":
        date_part := ""
        if d != 0:
            date_part = str(d) + "D"
        time_part := ""
        if h != 0:
            time_part = time_part + str(h) + "H"
        if mi != 0:
            time_part = time_part + str(mi) + "M"
        if sec != 0 or m != 0:
            time_part = time_part + str(sec) + ("." + _frac_str(m) if m != 0 else "") + "S"
        if date_part == "" and time_part == "":
            return "PT0S"
        return sign + "P" + date_part + ("T" + time_part if time_part != "" else "")
    if style == "long":
        return sign + _long_duration(d, h, mi, sec, m, locale)
    _fail("time.format_duration : style inconnu '" + str(style) + "' (compact, clock, iso, long)")

func _unit_word(locale_key, unit, plural):
    if locale_key == "fr":
        words := {"d": ["jour", "jours"], "h": ["heure", "heures"], "m": ["minute", "minutes"], "s": ["seconde", "secondes"]}
        return words[unit][1 if plural else 0]
    words2 := {"d": ["day", "days"], "h": ["hour", "hours"], "m": ["minute", "minutes"], "s": ["second", "seconds"]}
    return words2[unit][1 if plural else 0]

func _lang_key(locale):
    k := _fold(string.slice(locale, 0, 2))
    if k != "en" and k != "fr":
        _fail("time : le style « long » et humanize ne gèrent que \"en\" et \"fr\" (obtenu '" + locale + "')")
    return k

func _long_duration(d, h, mi, sec, micro, locale):
    key := _lang_key(locale)
    items := []
    if d != 0:
        append(items, str(d) + " " + _unit_word(key, "d", d != 1 and (key == "en" or d >= 2)))
    if h != 0:
        append(items, str(h) + " " + _unit_word(key, "h", h != 1 and (key == "en" or h >= 2)))
    if mi != 0:
        append(items, str(mi) + " " + _unit_word(key, "m", mi != 1 and (key == "en" or mi >= 2)))
    if sec != 0 or micro != 0:
        num := str(sec)
        plural := sec != 1
        if micro != 0:
            frac := _frac_str(micro)
            num = num + ("," if key == "fr" else ".") + frac
            plural = true if key == "en" else sec >= 2
        elif key == "fr":
            plural = sec >= 2
        append(items, num + " " + _unit_word(key, "s", plural))
    if len(items) == 0:
        return "0 " + _unit_word(key, "s", key == "en")
    if len(items) == 1:
        return items[0]
    last := items[len(items) - 1]
    head := []
    k := 0
    while k < len(items) - 1:
        append(head, items[k])
        k = k + 1
    return string.join(", ", head) + (" et " if key == "fr" else " and ") + last

# Formate un nombre de secondes (int ou float, éventuellement négatif).
func format_duration(seconds, style="compact", locale="en"):
    p := seconds_to_parts(seconds)
    return format_duration_parts(p[0], p[1], p[2], style, locale)

# Durée relative lisible : humanize(-90) -> « 2 minutes ago » ; humanize(3600) -> « in an hour » ;
# locale "en" ou "fr". Négatif = passé, positif = futur. Seuils proches de moment.js.
func humanize(seconds, locale="en"):
    _need_number("humanize", "seconds", seconds)
    key := _lang_key(locale)
    a := seconds
    past := false
    if seconds < 0:
        a = -seconds
        past = true
    text := ""
    if a < 5:
        return "just now" if key == "en" else "à l'instant"
    if a < 45:
        n := iround(a)
        text = str(n) + (" seconds" if key == "en" else " secondes")
    elif a < 90:
        text = "a minute" if key == "en" else "une minute"
    elif a < 2700:
        text = str(iround(a / 60.0)) + (" minutes")
    elif a < 5400:
        text = "an hour" if key == "en" else "une heure"
    elif a < 79200:
        text = str(iround(a / 3600.0)) + (" hours" if key == "en" else " heures")
    elif a < 129600:
        text = "a day" if key == "en" else "un jour"
    elif a < 2246400:
        text = str(iround(a / 86400.0)) + (" days" if key == "en" else " jours")
    elif a < 3888000:
        text = "a month" if key == "en" else "un mois"
    elif a < 27648000:
        text = str(iround(a / 2592000.0)) + (" months" if key == "en" else " mois")
    elif a < 47347200:
        text = "a year" if key == "en" else "un an"
    else:
        text = str(iround(a / 31557600.0)) + (" years" if key == "en" else " ans")
    if key == "en":
        return text + " ago" if past else "in " + text
    return "il y a " + text if past else "dans " + text

# ---------------------------------------------------------------------------------------------------------------
# Chronomètre, échéance, mesures
# ---------------------------------------------------------------------------------------------------------------

# Chronomètre sur l'horloge monotone : start / stop / reset / lap / elapsed. Les tours (lap) sont dans `laps`.
class Stopwatch:
    running := false
    func init(autostart=false):
        self.running = false
        self.started = 0.0
        self.accumulated = 0.0
        self.last_lap = 0.0
        self.laps = []
        if autostart:
            self.start()
    func start():
        if not self.running:
            self.started = monotonic()
            self.running = true
        return self
    # Arrête le chronomètre et renvoie la durée totale accumulée (secondes).
    func stop():
        if self.running:
            self.accumulated = self.accumulated + (monotonic() - self.started)
            self.running = false
        return self.accumulated
    func elapsed():
        if self.running:
            return self.accumulated + (monotonic() - self.started)
        return self.accumulated
    func reset():
        self.running = false
        self.started = 0.0
        self.accumulated = 0.0
        self.last_lap = 0.0
        self.laps = []
        return self
    func restart():
        self.reset()
        self.start()
        return self
    # Enregistre un tour et renvoie sa durée (depuis le tour précédent ou le début).
    func lap():
        total := self.elapsed()
        d := total - self.last_lap
        self.last_lap = total
        append(self.laps, d)
        return d

# Échéance sur l'horloge monotone : Deadline(secondes) ; Deadline(null) n'expire jamais.
class Deadline:
    func init(seconds=null):
        if seconds != null:
            _need_number("Deadline", "seconds", seconds)
            if seconds < 0:
                _fail("time.Deadline : durée négative")
        self.end = null if seconds == null else monotonic() + seconds
    # Secondes restantes (>= 0), ou null si l'échéance est infinie.
    func remaining():
        if self.end == null:
            return null
        r := self.end - monotonic()
        return r if r > 0 else 0.0
    func expired():
        return self.end != null and monotonic() >= self.end
    func extend(seconds):
        _need_number("Deadline.extend", "seconds", seconds)
        if self.end != null:
            self.end = self.end + seconds
        return self
    # Dort jusqu'à l'échéance (erreur si elle est infinie). Renvoie le temps dormi.
    func wait():
        if self.end == null:
            _fail("time.Deadline.wait : échéance infinie")
        r := self.remaining()
        if r > 0:
            sleep(r)
        return r
    # Lève TimeoutError si l'échéance est dépassée.
    func check(message=null):
        if self.expired():
            raise("TimeoutError", message if message != null else "délai dépassé")
        return null

# Appelle fn() et renvoie (résultat, secondes écoulées).
func measure(fn):
    start := monotonic()
    r := fn()
    return (r, monotonic() - start)

# Durée moyenne (secondes) d'un appel de fn() sur `number` appels.
func timeit(fn, number=1):
    _need_int("timeit", "number", number)
    if number < 1:
        _fail("time.timeit : number doit être >= 1")
    start := monotonic()
    k := 0
    while k < number:
        fn()
        k = k + 1
    return (monotonic() - start) / to_float(number)

# Mesure fn() sur `runs` essais (après `warmup` essais ignorés) : {"runs","min","max","mean","total"} en secondes.
func benchmark(fn, runs=5, warmup=0):
    _need_int("benchmark", "runs", runs)
    _need_int("benchmark", "warmup", warmup)
    if runs < 1 or warmup < 0:
        _fail("time.benchmark : runs >= 1 et warmup >= 0 attendus")
    k := 0
    while k < warmup:
        fn()
        k = k + 1
    total := 0.0
    lo := null
    hi := null
    k = 0
    while k < runs:
        s := monotonic()
        fn()
        d := monotonic() - s
        total = total + d
        if lo == null or d < lo:
            lo = d
        if hi == null or d > hi:
            hi = d
        k = k + 1
    return {"runs": runs, "min": lo, "max": hi, "mean": total / to_float(runs), "total": total}

# Appelle fn(i) toutes les `interval` secondes (sans dérive : les échéances sont fixées depuis le départ), `count`
# fois (null = jusqu'à ce que fn renvoie false). Renvoie le nombre d'appels.
func every(interval, fn, count=null):
    _need_number("every", "interval", interval)
    if interval < 0:
        _fail("time.every : intervalle négatif")
    start := monotonic()
    i := 0
    while count == null or i < count:
        r := fn(i)
        i = i + 1
        if r == false:
            break
        if count != null and i >= count:
            break
        wait := start + to_float(i) * interval - monotonic()
        if wait > 0:
            sleep(wait)
    return i
