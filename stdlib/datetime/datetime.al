# ALEX STANDARD LIBRARY — datetime
# Dates, heures, instants, durées, périodes calendaires et fuseaux horaires. 100 % ALEX (s'appuie sur le module `time`).
#
#   use datetime
#   d := datetime.Date(2026, 10, 7)
#   d.plus_months(4).isoformat()                          # 2027-02-07
#   dt := datetime.DateTime(2026, 3, 29, 1, 30, 0, 0, datetime.get_timezone("Europe/Paris"))
#   dt.plus_exact(datetime.Duration(hours=1)).isoformat()   # 2026-03-29T03:30:00+02:00 (saut d'heure d'été)
#   dt.astimezone("Asia/Tokyo").format("%d %B %Y %H:%M %Z", "fr")
#   datetime.Duration(days=1, hours=2).format("long", "fr")    # 1 jour et 2 heures
#   datetime.period_between(datetime.Date(1990, 5, 17), d).to_string()   # P36Y4M20D
#
# TYPES
#   Duration  durée exacte (jours, secondes, microsecondes normalisés), fractions acceptées à la construction.
#   Period    durée calendaire (années, mois, jours) : « +1 mois » n'a pas de longueur fixe.
#   TimeZone  fuseau : décalage fixe ou règles d'heure d'été (UE, États-Unis, Australie, Nouvelle-Zélande).
#   Date      jour du calendrier grégorien proleptique (toute année entière, négatives et 0 comprises).
#   Time      heure du jour sans date ni fuseau (0:00:00 à 23:59:59.999999).
#   DateTime  date + heure, naïve (sans fuseau) ou avec fuseau ; `fold` lève l'ambiguïté d'une heure répétée.
#
# SANS LIMITE DE PLAGE
#   Toutes les valeurs sont des entiers exacts : une Date est un numéro de jour depuis 1970-01-01, un DateTime est
#   un numéro de jour + des microsecondes du jour. Aucune conversion en flottant, aucun débordement avant
#   ± 2,5 × 10^16 ans (la limite des int 64 bits en jours). Les règles d'heure d'été supposent |année| < 2,9 × 10^11.
#
# CONVENTIONS
#   - ALEX ne surcharge pas les opérateurs : plus / minus / diff / compare / equals / lt / le / gt / ge ; `==` compare
#     des identités d'objets. Les objets sont immuables par convention : chaque méthode renvoie un nouvel objet.
#   - ALEX n'accepte pas les arguments nommés sur un appel de MÉTHODE (d.replace(year=1)) : les paramètres optionnels
#     des méthodes sont positionnels (null = inchangé). Constructeurs et fonctions du module acceptent les noms
#     (Duration(hours=2), from_timestamp(ts, tz=...)).
#   - `str(objet)` n'appelle pas to_string() : écrire objet.to_string() (ou isoformat()).
#   - Naïf / aware : un DateTime sans fuseau est « naïf ». Comparer ou soustraire un naïf et un aware lève TypeError.
#     Là où une conversion est inévitable (timestamp, to_utc), un naïf est lu comme UTC.
#   - plus / minus : arithmétique « murale » (l'heure affichée avance de la durée, comme Python) ; plus_exact /
#     minus_exact : temps écoulé réel (traverse les changements d'heure). diff : durée réelle entre deux instants.
#   - Heures inexistantes (saut de printemps) : acceptées telles quelles, converties avec le décalage d'avant le saut
#     (fold = 0) ou d'après (fold = 1) ; `normalize()` renvoie l'heure réelle correspondante.
#   - Erreurs : raise("ValueError" | "TypeError" | "ZeroDivisionError", message en français).
#
# LIMITES ASSUMÉES
#   - Les règles de fuseau sont les règles ACTUELLES étendues à toutes les années (UE depuis 1996, États-Unis depuis
#     2007...) : pas d'historique tzdata. Une quarantaine de villes sont prédéfinies (voir timezone_names) ;
#     TimeZone(nom, décalage, économie, règle) en définit d'autres.
#   - Durées ISO 8601 sans années ni mois (non fixes) : utiliser Period.

use time
use string
from core use type, len, to_int, to_float
from collections use append, sort, keys, contains_key

const _US_SEC := 1000000
const _US_DAY := 86400000000

# ---------------------------------------------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------------------------------------------

func _chk_int(who, label, v):
    if type(v) != "int":
        raise("TypeError", "datetime." + who + " : " + label + " doit être un entier (obtenu '" + type(v) + "')")

func _chk_range(who, label, v, lo, hi):
    _chk_int(who, label, v)
    if v < lo or v > hi:
        raise("ValueError", "datetime." + who + " : " + label + " hors limites (" + str(lo) + ".." + str(hi) + ") : " + str(v))

func _trunc_div(a, b):
    q := (-a if a < 0 else a) // b
    return -q if a < 0 else q

# ---------------------------------------------------------------------------------------------------------------
# Duration
# ---------------------------------------------------------------------------------------------------------------

# Durée exacte. Duration(days=1, hours=2, minutes=30, seconds=5, milliseconds=0, microseconds=0, weeks=0) ; les
# fractions sont arrondies à la microseconde (Duration(hours=1.5)). Champs normalisés : days (signé), 0 <= seconds < 86400,
# 0 <= microseconds < 1 000 000 : -1 s s'écrit days = -1, seconds = 86399, microseconds = 0.
class Duration:
    func init(days=0, hours=0, minutes=0, seconds=0, milliseconds=0, microseconds=0, weeks=0):
        acc := [0, 0]
        for item in [[1, days, "days"], [2, hours, "hours"], [3, minutes, "minutes"], [4, seconds, "seconds"],
                     [5, milliseconds, "milliseconds"], [6, microseconds, "microseconds"], [0, weeks, "weeks"]]:
            v := item[1]
            tv := type(v)
            if tv != "int" and tv != "float":
                raise("TypeError", "datetime.Duration : " + item[2] + " doit être un nombre (obtenu '" + tv + "')")
            whole := time.ifloor(v)
            frac := 0.0
            if tv == "float":
                frac = v - to_float(whole)
            time._accumulate(acc, item[0], whole, frac)
        n := time.normalize_duration(acc[0], 0, acc[1])
        self.days = n[0]
        self.seconds = n[1]
        self.microseconds = n[2]

    # Total en microsecondes, exact ; ValueError au-delà de ± 292 000 ans (limite int 64 bits).
    func total_microseconds():
        if self.days > 106751990 or self.days < -106751990:
            raise("ValueError", "datetime.Duration.total_microseconds : durée trop grande pour un int 64 bits")
        return (self.days * 86400 + self.seconds) * _US_SEC + self.microseconds
    func total_seconds():
        return time.parts_to_seconds(self.days, self.seconds, self.microseconds)
    func total_milliseconds():
        return self.total_seconds() * 1000.0
    func total_minutes():
        return self.total_seconds() / 60.0
    func total_hours():
        return self.total_seconds() / 3600.0
    func total_days():
        return to_float(self.days) + (to_float(self.seconds) + to_float(self.microseconds) / 1000000.0) / 86400.0
    func is_negative():
        return self.days < 0
    func is_zero():
        return self.days == 0 and self.seconds == 0 and self.microseconds == 0
    func negate():
        n := time.normalize_duration(-self.days, -self.seconds, -self.microseconds)
        return Duration(days=n[0], seconds=n[1], microseconds=n[2])
    func absolute():
        return self.negate() if self.days < 0 else self
    func plus(other):
        _need_duration("Duration.plus", other)
        n := time.normalize_duration(self.days + other.days, self.seconds + other.seconds,
                                     self.microseconds + other.microseconds)
        return Duration(days=n[0], seconds=n[1], microseconds=n[2])
    func minus(other):
        _need_duration("Duration.minus", other)
        n := time.normalize_duration(self.days - other.days, self.seconds - other.seconds,
                                     self.microseconds - other.microseconds)
        return Duration(days=n[0], seconds=n[1], microseconds=n[2])
    # Multiplie par un nombre (exact pour un int, arrondi à la microseconde pour un float).
    func times(k):
        tk := type(k)
        if tk != "int" and tk != "float":
            raise("TypeError", "datetime.Duration.times : un nombre est attendu (obtenu '" + tk + "')")
        return Duration(days=self.days * k, seconds=self.seconds * k, microseconds=self.microseconds * k)
    # Divise par un nombre non nul (résultat arrondi à la microseconde).
    func divided(k):
        tk := type(k)
        if tk != "int" and tk != "float":
            raise("TypeError", "datetime.Duration.divided : un nombre est attendu (obtenu '" + tk + "')")
        if k == 0:
            raise("ZeroDivisionError", "datetime.Duration.divided : division par zéro")
        return Duration(days=self.days / k, seconds=self.seconds / k, microseconds=self.microseconds / k)
    # Rapport de deux durées (float).
    func ratio(other):
        _need_duration("Duration.ratio", other)
        if other.is_zero():
            raise("ZeroDivisionError", "datetime.Duration.ratio : division par une durée nulle")
        return self.total_seconds() / other.total_seconds()
    # Nombre entier de fois que `other` tient dans cette durée (plancher).
    func floordiv(other):
        _need_duration("Duration.floordiv", other)
        if other.is_zero():
            raise("ZeroDivisionError", "datetime.Duration.floordiv : division par une durée nulle")
        return self.total_microseconds() // other.total_microseconds()
    func modulo(other):
        _need_duration("Duration.modulo", other)
        if other.is_zero():
            raise("ZeroDivisionError", "datetime.Duration.modulo : division par une durée nulle")
        return Duration(microseconds=self.total_microseconds() % other.total_microseconds())
    # -1, 0 ou 1.
    func compare(other):
        _need_duration("Duration.compare", other)
        return _cmp3([self.days, self.seconds, self.microseconds], [other.days, other.seconds, other.microseconds])
    func equals(other):
        return isinstance(other, Duration) and self.compare(other) == 0
    func lt(other):
        return self.compare(other) < 0
    func le(other):
        return self.compare(other) <= 0
    func gt(other):
        return self.compare(other) > 0
    func ge(other):
        return self.compare(other) >= 0
    # Composantes de la valeur absolue + signe : {"sign","days","hours","minutes","seconds","milliseconds","microseconds"}.
    func components():
        a := self.absolute()
        return {"sign": -1 if self.days < 0 else 1, "days": a.days, "hours": a.seconds // 3600,
                "minutes": (a.seconds % 3600) // 60, "seconds": a.seconds % 60,
                "milliseconds": a.microseconds // 1000, "microseconds": a.microseconds % 1000}
    # Styles : "compact" (1d 2h 3m 4.5s), "clock" (26:03:04.5), "iso" (P1DT2H3M4.5S), "long" (en / fr).
    func format(style="compact", locale="en"):
        return time.format_duration_parts(self.days, self.seconds, self.microseconds, style, locale)
    func iso():
        return self.format("iso", "en")
    func to_string():
        return self.format("compact", "en")
    func to_dict():
        return {"days": self.days, "seconds": self.seconds, "microseconds": self.microseconds}

func _need_duration(who, v):
    if not isinstance(v, Duration):
        raise("TypeError", "datetime." + who + " : une Duration est attendue (obtenu '" + type(v) + "')")

# Compare deux listes de nombres de même longueur : -1, 0, 1.
func _cmp3(a, b):
    k := 0
    while k < len(a):
        if a[k] < b[k]:
            return -1
        if a[k] > b[k]:
            return 1
        k = k + 1
    return 0

# Analyse une durée (« 1h30m », « PT90M », « 2 days, 1:30:00 », « 3 semaines »...) : voir time.parse_duration.
func parse_duration(text):
    p := time.duration_parts(text)
    return Duration(days=p[0], seconds=p[1], microseconds=p[2])

func duration_from_seconds(seconds):
    p := time.seconds_to_parts(seconds)
    return Duration(days=p[0], seconds=p[1], microseconds=p[2])

# Durée de a vers b (b - a) pour deux Date, Time ou DateTime du même type.
func duration_between(a, b):
    return b.diff(a)

# ---------------------------------------------------------------------------------------------------------------
# Period (durée calendaire)
# ---------------------------------------------------------------------------------------------------------------

# Période en années, mois et jours : Period(years=1, months=2, days=3). S'ajoute à une Date ou un DateTime (mois et
# années d'abord, avec le jour ramené en fin de mois si besoin, puis les jours).
class Period:
    func init(years=0, months=0, days=0):
        _chk_int("Period", "years", years)
        _chk_int("Period", "months", months)
        _chk_int("Period", "days", days)
        self.years = years
        self.months = months
        self.days = days
    func total_months():
        return self.years * 12 + self.months
    func is_zero():
        return self.years == 0 and self.months == 0 and self.days == 0
    func negate():
        return Period(years=-self.years, months=-self.months, days=-self.days)
    func plus(other):
        if not isinstance(other, Period):
            raise("TypeError", "datetime.Period.plus : une Period est attendue")
        return Period(years=self.years + other.years, months=self.months + other.months, days=self.days + other.days)
    func times(k):
        _chk_int("Period.times", "k", k)
        return Period(years=self.years * k, months=self.months * k, days=self.days * k)
    # Ajoute la période à une Date ou à un DateTime.
    func apply_to(value):
        if isinstance(value, Date) or isinstance(value, DateTime):
            return value.plus_months(self.total_months()).plus_days(self.days)
        raise("TypeError", "datetime.Period.apply_to : une Date ou un DateTime est attendu (obtenu '" + type(value) + "')")
    func equals(other):
        return isinstance(other, Period) and self.years == other.years and self.months == other.months and self.days == other.days
    # ISO 8601 : P1Y2M3D (P0D si nulle ; composantes négatives avec leur signe : P-1Y2M).
    func iso():
        out := ""
        if self.years != 0:
            out = out + str(self.years) + "Y"
        if self.months != 0:
            out = out + str(self.months) + "M"
        if self.days != 0:
            out = out + str(self.days) + "D"
        return "P0D" if out == "" else "P" + out
    func to_string():
        return self.iso()

# Période entre deux Date (comme java.time.Period.between) : années, mois, jours ; négative si end < start.
func period_between(start, end):
    if not isinstance(start, Date) or not isinstance(end, Date):
        raise("TypeError", "datetime.period_between : deux Date sont attendues")
    total := (end.year * 12 + end.month) - (start.year * 12 + start.month)
    days := end.day - start.day
    if total > 0 and days < 0:
        total = total - 1
        days = end.epoch_day - start.plus_months(total).epoch_day
    elif total < 0 and days > 0:
        total = total + 1
        days = days - end.days_in_month()
    years := _trunc_div(total, 12)
    months := total - years * 12
    return Period(years=years, months=months, days=days)

# Mois entiers de b à a (vers zéro) en comparant le jour du mois puis l'heure.
func _whole_months(ay, am, ad, aus, by, bm, bd, bus):
    total := (ay * 12 + am) - (by * 12 + bm)
    if total > 0 and (ad < bd or (ad == bd and aus < bus)):
        total = total - 1
    elif total < 0 and (ad > bd or (ad == bd and aus > bus)):
        total = total + 1
    return total

# ---------------------------------------------------------------------------------------------------------------
# TimeZone
# ---------------------------------------------------------------------------------------------------------------

# Règles d'heure d'été prédéfinies. Une règle = {"start": [mois, rang, jour, secondes, repère], "end": [...]} :
# le rang vaut 1.. (n-ième) ou -1 (dernier), le jour 0 = lundi ... 6 = dimanche, `secondes` est l'heure du changement,
# `repère` dit dans quelle heure elle est lue : "utc", "std" (heure d'hiver locale) ou "dst" (heure d'été locale).
const _RULES := {
    "eu": {"start": [3, -1, 6, 3600, "utc"], "end": [10, -1, 6, 3600, "utc"]},
    "us": {"start": [3, 2, 6, 7200, "std"], "end": [11, 1, 6, 7200, "dst"]},
    "au": {"start": [10, 1, 6, 7200, "std"], "end": [4, 1, 6, 10800, "dst"]},
    "nz": {"start": [9, -1, 6, 7200, "std"], "end": [4, 1, 6, 10800, "dst"]}
}

# Fuseau horaire. TimeZone(nom, décalage_standard_s, économie_s=0, règle=null, abbr_hiver=null, abbr_été=null) :
# décalage en secondes à l'est de UTC (|décalage| < 86400) ; règle = dict (voir _RULES) ou "eu" / "us" / "au" / "nz" ;
# sans règle, le fuseau est fixe. Exemple : TimeZone("Europe/Paris", 3600, 3600, "eu", "CET", "CEST").
class TimeZone:
    func init(name, std_offset=0, dst_save=0, rule=null, std_abbr=null, dst_abbr=null):
        if type(name) != "str" or len(name) == 0:
            raise("TypeError", "datetime.TimeZone : le nom doit être une chaîne non vide")
        _chk_int("TimeZone", "std_offset", std_offset)
        _chk_int("TimeZone", "dst_save", dst_save)
        if std_offset <= -86400 or std_offset >= 86400:
            raise("ValueError", "datetime.TimeZone : décalage hors limites (± 24 h exclu) : " + str(std_offset))
        if dst_save < 0 or dst_save >= 86400:
            raise("ValueError", "datetime.TimeZone : économie d'heure hors limites (0..86399) : " + str(dst_save))
        r := rule
        if type(r) == "str":
            if not contains_key(_RULES, r):
                raise("ValueError", "datetime.TimeZone : règle inconnue '" + r + "' (eu, us, au, nz)")
            r = _RULES[r]
        if r == null and dst_save != 0:
            raise("ValueError", "datetime.TimeZone : une économie d'heure demande une règle")
        if r != null:
            if dst_save == 0:
                raise("ValueError", "datetime.TimeZone : une règle demande une économie d'heure non nulle")
            _check_rule(r)
        self.name = name
        self.std_offset = std_offset
        self.dst_save = dst_save
        self.rule = r
        self.std_abbr = std_abbr
        self.dst_abbr = dst_abbr

    func has_dst():
        return self.rule != null
    # Instant (secondes epoch UTC) du changement d'heure `which` ("start" ou "end") de l'année.
    func transition(year, which):
        spec := self.rule[which]
        day := time.nth_weekday(year, spec[0], spec[2], spec[1])
        base := time._dfc(year, spec[0], day) * 86400 + spec[3]
        if spec[4] == "utc":
            return base
        if spec[4] == "std":
            return base - self.std_offset
        return base - (self.std_offset + self.dst_save)
    func is_dst_at_instant(instant):
        if self.rule == null:
            return false
        y := time.civil_from_days((instant + self.std_offset) // 86400)[0]
        s := self.transition(y, "start")
        e := self.transition(y, "end")
        if s < e:
            return instant >= s and instant < e
        return instant >= s or instant < e
    # Décalage (secondes à l'est de UTC) à l'instant donné (secondes epoch UTC, int).
    func offset_at_instant(instant):
        if self.rule != null and self.is_dst_at_instant(instant):
            return self.std_offset + self.dst_save
        return self.std_offset
    # Décalage pour une heure murale : jour (depuis 1970-01-01) et seconde du jour. Heure répétée (retour à
    # l'heure d'hiver) : fold 0 = première fois (été), 1 = seconde. Heure inexistante : fold 0 = décalage d'avant le saut.
    func offset_at_local(epoch_day, second_of_day, fold=0):
        if self.rule == null:
            return self.std_offset
        local := epoch_day * 86400 + second_of_day
        o_dst := self.std_offset + self.dst_save
        dst_ok := self.is_dst_at_instant(local - o_dst)
        std_ok := not self.is_dst_at_instant(local - self.std_offset)
        if dst_ok and std_ok:
            return self.std_offset if fold == 1 else o_dst
        if dst_ok:
            return o_dst
        if std_ok:
            return self.std_offset
        return o_dst if fold == 1 else self.std_offset
    func abbr(is_dst):
        if is_dst:
            return self.dst_abbr if self.dst_abbr != null else self.name
        return self.std_abbr if self.std_abbr != null else self.name
    func abbr_at_instant(instant):
        return self.abbr(self.is_dst_at_instant(instant))
    # Changements d'heure d'une année : liste de {"instant","before","after","to_dst"} triée.
    func transitions(year):
        if self.rule == null:
            return []
        s := self.transition(year, "start")
        e := self.transition(year, "end")
        o_dst := self.std_offset + self.dst_save
        a := {"instant": s, "before": self.std_offset, "after": o_dst, "to_dst": true}
        b := {"instant": e, "before": o_dst, "after": self.std_offset, "to_dst": false}
        return [a, b] if s < e else [b, a]
    func to_string():
        return self.name

func _check_rule(r):
    if type(r) != "dict" or not contains_key(r, "start") or not contains_key(r, "end"):
        raise("TypeError", "datetime.TimeZone : une règle est un dict {\"start\": [...], \"end\": [...]}")
    for which in ["start", "end"]:
        spec := r[which]
        if type(spec) != "list" or len(spec) != 5:
            raise("ValueError", "datetime.TimeZone : règle '" + which + "' : [mois, rang, jour, secondes, repère] attendu")
        _chk_range("TimeZone", "mois de la règle", spec[0], 1, 12)
        _chk_int("TimeZone", "rang de la règle", spec[1])
        if spec[1] == 0 or spec[1] < -5 or spec[1] > 5:
            raise("ValueError", "datetime.TimeZone : rang de la règle hors limites (±1..±5) : " + str(spec[1]))
        _chk_range("TimeZone", "jour de la règle", spec[2], 0, 6)
        _chk_int("TimeZone", "secondes de la règle", spec[3])
        if spec[4] != "utc" and spec[4] != "std" and spec[4] != "dst":
            raise("ValueError", "datetime.TimeZone : repère de règle inconnu '" + str(spec[4]) + "' (utc, std, dst)")

const UTC := TimeZone("UTC", 0)

# Table : [nom, décalage d'hiver (s), règle ou null, abréviation d'hiver, abréviation d'été].
func _zone_rows():
    return [
        ["Europe/London", 0, "eu", "GMT", "BST"], ["Europe/Dublin", 0, "eu", "GMT", "IST"], ["Europe/Lisbon", 0, "eu", "WET", "WEST"],
        ["Europe/Paris", 3600, "eu", "CET", "CEST"], ["Europe/Berlin", 3600, "eu", "CET", "CEST"], ["Europe/Madrid", 3600, "eu", "CET", "CEST"],
        ["Europe/Rome", 3600, "eu", "CET", "CEST"], ["Europe/Amsterdam", 3600, "eu", "CET", "CEST"], ["Europe/Brussels", 3600, "eu", "CET", "CEST"],
        ["Europe/Zurich", 3600, "eu", "CET", "CEST"], ["Europe/Vienna", 3600, "eu", "CET", "CEST"], ["Europe/Stockholm", 3600, "eu", "CET", "CEST"],
        ["Europe/Oslo", 3600, "eu", "CET", "CEST"], ["Europe/Copenhagen", 3600, "eu", "CET", "CEST"], ["Europe/Warsaw", 3600, "eu", "CET", "CEST"],
        ["Europe/Prague", 3600, "eu", "CET", "CEST"], ["Europe/Budapest", 3600, "eu", "CET", "CEST"],
        ["Europe/Athens", 7200, "eu", "EET", "EEST"], ["Europe/Helsinki", 7200, "eu", "EET", "EEST"], ["Europe/Kyiv", 7200, "eu", "EET", "EEST"],
        ["Europe/Bucharest", 7200, "eu", "EET", "EEST"], ["Europe/Moscow", 10800, null, "MSK", null], ["Europe/Istanbul", 10800, null, "+03", null],
        ["America/New_York", -18000, "us", "EST", "EDT"], ["America/Toronto", -18000, "us", "EST", "EDT"], ["America/Chicago", -21600, "us", "CST", "CDT"],
        ["America/Denver", -25200, "us", "MST", "MDT"], ["America/Phoenix", -25200, null, "MST", null], ["America/Los_Angeles", -28800, "us", "PST", "PDT"],
        ["America/Vancouver", -28800, "us", "PST", "PDT"], ["America/Anchorage", -32400, "us", "AKST", "AKDT"], ["Pacific/Honolulu", -36000, null, "HST", null],
        ["America/Mexico_City", -21600, null, "CST", null], ["America/Bogota", -18000, null, "-05", null], ["America/Lima", -18000, null, "-05", null],
        ["America/Sao_Paulo", -10800, null, "-03", null], ["America/Argentina/Buenos_Aires", -10800, null, "-03", null],
        ["Asia/Tokyo", 32400, null, "JST", null], ["Asia/Seoul", 32400, null, "KST", null], ["Asia/Shanghai", 28800, null, "CST", null],
        ["Asia/Hong_Kong", 28800, null, "HKT", null], ["Asia/Singapore", 28800, null, "+08", null], ["Asia/Taipei", 28800, null, "CST", null],
        ["Asia/Manila", 28800, null, "PST", null], ["Asia/Kolkata", 19800, null, "IST", null], ["Asia/Dubai", 14400, null, "+04", null],
        ["Asia/Karachi", 18000, null, "PKT", null], ["Asia/Dhaka", 21600, null, "+06", null], ["Asia/Bangkok", 25200, null, "+07", null],
        ["Asia/Jakarta", 25200, null, "WIB", null], ["Asia/Tehran", 12600, null, "+0330", null], ["Asia/Kathmandu", 20700, null, "+0545", null],
        ["Asia/Riyadh", 10800, null, "+03", null], ["Africa/Lagos", 3600, null, "WAT", null], ["Africa/Johannesburg", 7200, null, "SAST", null],
        ["Africa/Nairobi", 10800, null, "EAT", null], ["Africa/Accra", 0, null, "GMT", null],
        ["Australia/Sydney", 36000, "au", "AEST", "AEDT"], ["Australia/Melbourne", 36000, "au", "AEST", "AEDT"],
        ["Australia/Adelaide", 34200, "au", "ACST", "ACDT"], ["Australia/Brisbane", 36000, null, "AEST", null], ["Australia/Perth", 28800, null, "AWST", null],
        ["Pacific/Auckland", 43200, "nz", "NZST", "NZDT"]]

# Index (noms en minuscules, villes seules) ; construit une fois au chargement du module.
_zones := {"by_name": {}, "by_city": {}, "cache": {}}

func _install_zones():
    for row in _zone_rows():
        low := string.lower(row[0])
        _zones["by_name"][low] = row
        parts := string.split(low, "/")
        city := parts[len(parts) - 1]
        if contains_key(_zones["by_city"], city):
            append(_zones["by_city"][city], row[0])
        else:
            _zones["by_city"][city] = [row[0]]

_install_zones()

# Noms des fuseaux prédéfinis, triés.
func timezone_names():
    out := []
    for row in _zone_rows():
        append(out, row[0])
    sort(out)
    return out

func _zone_from_row(row):
    low := string.lower(row[0])
    cache := _zones["cache"]
    if contains_key(cache, low):
        return cache[low]
    save := 3600 if row[2] != null else 0
    z := TimeZone(row[0], row[1], save, row[2], row[3], row[4])
    cache[low] = z
    return z

# Décalage fixe : fixed_offset(7200) ou fixed_offset(Duration(hours=2)) ; nom par défaut « UTC+02:00 ».
func fixed_offset(offset, name=null):
    secs := offset
    if isinstance(offset, Duration):
        if offset.microseconds != 0 or offset.seconds % 1 != 0:
            raise("ValueError", "datetime.fixed_offset : le décalage doit être en secondes entières")
        secs = offset.days * 86400 + offset.seconds
    _chk_int("fixed_offset", "offset", secs)
    if secs == 0 and name == null:
        return UTC
    label := name
    if label == null:
        label = "UTC" + time.format_offset(secs, true)
    return TimeZone(label, secs)

# Fuseau du système : décalage ACTUEL fixe (voir time.local_utc_offset).
func local_timezone():
    secs := time.local_utc_offset()
    info := time._local_info()
    return TimeZone(info["name"] if info["name"] != "" else "UTC" + time.format_offset(secs, true), secs)

# « UTC+2 », « GMT-05:30 », « +0530 », « -3 » -> secondes ; null si le texte n'est pas un décalage.
func _parse_offset_text(text):
    s := string.lower(string.trim(text))
    if len(s) >= 3 and (string.starts_with(s, "utc") or string.starts_with(s, "gmt")):
        s = str(string.slice(s, 3, null))
    if len(s) < 2:
        return null
    sign := 1
    first := str(string.slice(s, 0, 1))
    if first == "-":
        sign = -1
    elif first != "+":
        return null
    body := str(string.slice(s, 1, null))
    pieces := []
    if string.contains(body, ":"):
        pieces = string.split(body, ":")
    else:
        n := len(body)
        if n == 1 or n == 2:
            pieces = [body]
        elif n == 4:
            pieces = [str(string.slice(body, 0, 2)), str(string.slice(body, 2, 4))]
        elif n == 6:
            pieces = [str(string.slice(body, 0, 2)), str(string.slice(body, 2, 4)), str(string.slice(body, 4, 6))]
        else:
            return null
    if len(pieces) > 3:
        return null
    nums := []
    for p in pieces:
        if len(p) < 1 or len(p) > 2:
            return null
        for c in p:
            if string.ord(str(c)) < 48 or string.ord(str(c)) > 57:
                return null
        append(nums, to_int(p))
    total := nums[0] * 3600
    if len(nums) > 1:
        total = total + nums[1] * 60
    if len(nums) > 2:
        total = total + nums[2]
    if nums[0] > 23 or (len(nums) > 1 and nums[1] > 59) or (len(nums) > 2 and nums[2] > 59):
        return null
    return sign * total

# Résout un fuseau : TimeZone (rendu tel quel), int (décalage en secondes), ou texte : « UTC », « Z », « +02:00 »,
# « UTC-5 », « Europe/Paris », « paris » (nom de ville sans ambiguïté). Insensible à la casse.
func get_timezone(spec):
    if isinstance(spec, TimeZone):
        return spec
    if type(spec) == "int":
        return fixed_offset(spec)
    if type(spec) != "str":
        raise("TypeError", "datetime.get_timezone : un TimeZone, un entier ou un nom est attendu (obtenu '" + type(spec) + "')")
    s := string.replace(string.lower(string.trim(spec)), " ", "_")
    if s == "utc" or s == "z" or s == "gmt" or s == "etc/utc" or s == "etc/gmt" or s == "utc0" or s == "zulu":
        return UTC
    off := _parse_offset_text(s)
    if off != null:
        return fixed_offset(off)
    if contains_key(_zones["by_name"], s):
        return _zone_from_row(_zones["by_name"][s])
    if contains_key(_zones["by_city"], s):
        names := _zones["by_city"][s]
        if len(names) == 1:
            return _zone_from_row(_zones["by_name"][string.lower(names[0])])
        raise("ValueError", "datetime.get_timezone : nom ambigu '" + spec + "' : " + string.join(", ", names))
    raise("ValueError", "datetime.get_timezone : fuseau inconnu '" + spec + "' (voir timezone_names ; ou « +02:00 », « UTC-5 »)")

func _tz_arg(tz):
    if isinstance(tz, TimeZone):
        return tz
    return get_timezone(tz)

# ---------------------------------------------------------------------------------------------------------------
# Date
# ---------------------------------------------------------------------------------------------------------------

# Jour du calendrier grégorien proleptique : Date(2026, 10, 7). Champs : year (tout entier), month, day, epoch_day
# (jours depuis 1970-01-01).
class Date:
    func init(year, month=1, day=1):
        _chk_int("Date", "year", year)
        _chk_int("Date", "month", month)
        _chk_int("Date", "day", day)
        if month < 1 or month > 12:
            raise("ValueError", "datetime.Date : mois hors limites (1..12) : " + str(month))
        if day < 1 or day > time.days_in_month(year, month):
            raise("ValueError", "datetime.Date : jour hors limites pour " + time._year_str(year) + "-" + time._pad(month, 2) + " : " + str(day))
        self.year = year
        self.month = month
        self.day = day
        self.epoch_day = time._dfc(year, month, day)

    func to_days():
        return self.epoch_day
    # 0001-01-01 = 1.
    func to_ordinal():
        return self.epoch_day + time.UNIX_EPOCH_ORDINAL
    # 0 = lundi ... 6 = dimanche.
    func weekday():
        return time.weekday_of_days(self.epoch_day)
    # 1 = lundi ... 7 = dimanche.
    func isoweekday():
        return time.weekday_of_days(self.epoch_day) + 1
    func yearday():
        return self.epoch_day - time._dfc(self.year, 1, 1) + 1
    # (année ISO, semaine ISO, jour ISO).
    func iso_calendar():
        return time.iso_calendar(self.year, self.month, self.day)
    func week():
        return time.iso_calendar(self.year, self.month, self.day)[1]
    func quarter():
        return (self.month - 1) // 3 + 1
    func is_leap_year():
        return time.is_leap(self.year)
    func days_in_month():
        return time.days_in_month(self.year, self.month)
    func days_in_year():
        return time.days_in_year(self.year)
    func is_weekend():
        return self.weekday() >= 5
    func plus_days(n):
        _chk_int("Date.plus_days", "n", n)
        return _date_from_days(self.epoch_day + n)
    func minus_days(n):
        _chk_int("Date.minus_days", "n", n)
        return _date_from_days(self.epoch_day - n)
    func plus_weeks(n):
        _chk_int("Date.plus_weeks", "n", n)
        return _date_from_days(self.epoch_day + 7 * n)
    # Ajoute n mois ; le jour est ramené à la fin du mois si besoin (31 janvier + 1 mois = 28 ou 29 février).
    func plus_months(n):
        _chk_int("Date.plus_months", "n", n)
        total := self.year * 12 + (self.month - 1) + n
        y := total // 12
        m := total % 12 + 1
        d := self.day
        dim := time.days_in_month(y, m)
        if d > dim:
            d = dim
        return Date(y, m, d)
    func plus_years(n):
        _chk_int("Date.plus_years", "n", n)
        return self.plus_months(12 * n)
    # Ajoute une Duration de jours entiers (ValueError si elle contient des heures : utiliser DateTime).
    func plus(duration):
        _need_duration("Date.plus", duration)
        if duration.seconds != 0 or duration.microseconds != 0:
            raise("ValueError", "datetime.Date.plus : la durée contient des heures ; utiliser un DateTime ou plus_days")
        return self.plus_days(duration.days)
    func minus(duration):
        return self.plus(duration.negate())
    # Durée self - other (en jours entiers).
    func diff(other):
        _need_date("Date.diff", other)
        return Duration(days=self.epoch_day - other.epoch_day)
    func days_until(other):
        _need_date("Date.days_until", other)
        return other.epoch_day - self.epoch_day
    func days_since(other):
        _need_date("Date.days_since", other)
        return self.epoch_day - other.epoch_day
    # Mois entiers de other à self (vers zéro, jour du mois comparé).
    func months_between(other):
        _need_date("Date.months_between", other)
        return _whole_months(self.year, self.month, self.day, 0, other.year, other.month, other.day, 0)
    func years_between(other):
        return _trunc_div(self.months_between(other), 12)
    func compare(other):
        _need_date("Date.compare", other)
        if self.epoch_day < other.epoch_day:
            return -1
        return 1 if self.epoch_day > other.epoch_day else 0
    func equals(other):
        return isinstance(other, Date) and self.epoch_day == other.epoch_day
    func lt(other):
        return self.compare(other) < 0
    func le(other):
        return self.compare(other) <= 0
    func gt(other):
        return self.compare(other) > 0
    func ge(other):
        return self.compare(other) >= 0
    # Entre a et b inclus.
    func is_between(a, b):
        return self.compare(a) >= 0 and self.compare(b) <= 0
    # Paramètres positionnels, null = inchangé.
    func replace(year=null, month=null, day=null):
        return Date(self.year if year == null else year, self.month if month == null else month,
                    self.day if day == null else day)
    func start_of_week(first_weekday=0):
        return self.plus_days(-((self.weekday() - first_weekday) % 7))
    func end_of_week(first_weekday=0):
        return self.start_of_week(first_weekday).plus_days(6)
    func start_of_month():
        return Date(self.year, self.month, 1)
    func end_of_month():
        return Date(self.year, self.month, time.days_in_month(self.year, self.month))
    func start_of_quarter():
        return Date(self.year, (self.month - 1) // 3 * 3 + 1, 1)
    func end_of_quarter():
        m := (self.month - 1) // 3 * 3 + 3
        return Date(self.year, m, time.days_in_month(self.year, m))
    func start_of_year():
        return Date(self.year, 1, 1)
    func end_of_year():
        return Date(self.year, 12, 31)
    # Prochain jour de semaine donné (0 = lundi), strictement après cette date.
    func next_weekday(weekday_):
        _chk_range("Date.next_weekday", "weekday", weekday_, 0, 6)
        return self.plus_days((weekday_ - self.weekday() - 1) % 7 + 1)
    func prev_weekday(weekday_):
        _chk_range("Date.prev_weekday", "weekday", weekday_, 0, 6)
        return self.plus_days(-((self.weekday() - weekday_ - 1) % 7 + 1))
    # n-ième `weekday` du mois de cette date (n = -1 : le dernier) : ex. le 3e jeudi.
    func nth_weekday(weekday_, n):
        return Date(self.year, self.month, time.nth_weekday(self.year, self.month, weekday_, n))
    # Jour ouvré : du lundi au vendredi, hors `holidays` (liste de Date).
    func is_business_day(holidays=null):
        if self.weekday() >= 5:
            return false
        return not _holiday_set(holidays).has(self.epoch_day)
    # Avance (ou recule si n < 0) de n jours ouvrés.
    func plus_business_days(n, holidays=null):
        _chk_int("Date.plus_business_days", "n", n)
        hs := _holiday_set(holidays)
        step := -1 if n < 0 else 1
        left := -n if n < 0 else n
        d := self.epoch_day
        while left > 0:
            d = d + step
            if time.weekday_of_days(d) < 5 and not hs.has(d):
                left = left - 1
        return _date_from_days(d)
    # Nombre de jours ouvrés dans [self, other[ (négatif si other < self).
    func business_days_until(other, holidays=null):
        _need_date("Date.business_days_until", other)
        hs := _holiday_set(holidays)
        a := self.epoch_day
        b := other.epoch_day
        sign := 1
        if b < a:
            sign = -1
            t := a
            a = b
            b = t
        count := 0
        d := a
        while d < b:
            if time.weekday_of_days(d) < 5 and not hs.has(d):
                count = count + 1
            d = d + 1
        return sign * count
    # DateTime à l'heure donnée (positionnel : heure, minute, seconde, microseconde, fuseau).
    func at(hour=0, minute=0, second=0, microsecond=0, tz=null):
        return DateTime(self.year, self.month, self.day, hour, minute, second, microsecond, tz)
    func start_of_day(tz=null):
        return DateTime(self.year, self.month, self.day, 0, 0, 0, 0, tz)
    func isoformat():
        return time._year_iso(self.year) + "-" + time._pad(self.month, 2) + "-" + time._pad(self.day, 2)
    func to_string():
        return self.isoformat()
    func fields():
        return {"year": self.year, "month": self.month, "day": self.day, "hour": 0, "minute": 0, "second": 0,
                "microsecond": 0, "weekday": self.weekday(), "yearday": self.yearday(), "utc_offset": null,
                "timezone": null, "is_dst": false}
    func format(fmt, locale="en"):
        return time.strftime(fmt, self.fields(), locale)
    func to_dict():
        return {"year": self.year, "month": self.month, "day": self.day}

func _need_date(who, v):
    if not isinstance(v, Date):
        raise("TypeError", "datetime." + who + " : une Date est attendue (obtenu '" + type(v) + "')")

# Ensemble de jours (epoch_day) des Date d'une liste ; has(n) -> bool.
class _DaySet:
    func init(holidays):
        self.items = {}
        if holidays != null:
            for h in holidays:
                _need_date("holidays", h)
                self.items[str(h.epoch_day)] = true
    func has(epoch_day):
        return contains_key(self.items, str(epoch_day))

func _holiday_set(holidays):
    return _DaySet(holidays)

func _date_from_days(days):
    ymd := time.civil_from_days(days)
    return Date(ymd[0], ymd[1], ymd[2])

# Date du jour dans le fuseau tz (fuseau du système si null).
func today(tz=null):
    return now(tz).to_date()

func date_from_days(days):
    _chk_int("date_from_days", "days", days)
    return _date_from_days(days)

func date_from_ordinal(ordinal):
    _chk_int("date_from_ordinal", "ordinal", ordinal)
    return _date_from_days(ordinal - time.UNIX_EPOCH_ORDINAL)

# Date de la semaine ISO : année ISO, semaine 1..53, jour 1..7 (1 = lundi).
func date_from_iso_week(iso_year, week, iso_day=1):
    ymd := time.iso_to_civil(iso_year, week, iso_day)
    return Date(ymd[0], ymd[1], ymd[2])

# « 2026-10-07 », « 20261007 », « 2026-W41-3 », « 2026-280 », « +12345-01-01 » (pas d'heure).
func date_from_iso(text):
    f := time.parse_iso(text)
    if f["has_time"]:
        raise("ValueError", "datetime.date_from_iso : une date sans heure est attendue : '" + text + "'")
    return Date(f["year"], f["month"], f["day"])

func parse_date(text, fmt, locale="en"):
    f := time.strptime(text, fmt, locale)
    return Date(f["year"], f["month"], f["day"])

func date_from_timestamp(ts, tz=null):
    return from_timestamp(ts, tz).to_date()

# Dates de start à end (incluse si inclusive) par pas de step_days (négatif pour descendre).
func date_range(start, end, step_days=1, inclusive=true):
    _need_date("date_range", start)
    _need_date("date_range", end)
    _chk_int("date_range", "step_days", step_days)
    if step_days == 0:
        raise("ValueError", "datetime.date_range : step_days ne peut pas valoir 0")
    out := []
    d := start.epoch_day
    e := end.epoch_day
    while (d < e or (inclusive and d == e)) if step_days > 0 else (d > e or (inclusive and d == e)):
        append(out, _date_from_days(d))
        d = d + step_days
    return out

# Dimanche de Pâques de l'année (Date).
func easter_date(year):
    md := time.easter(year)
    return Date(year, md[0], md[1])

# Jours fériés légaux en France métropolitaine : liste de [Date, nom].
func holidays_fr(year):
    e := easter_date(year)
    return [[Date(year, 1, 1), "Jour de l'an"], [e.plus_days(1), "Lundi de Pâques"], [Date(year, 5, 1), "Fête du Travail"],
            [Date(year, 5, 8), "Victoire 1945"], [e.plus_days(39), "Ascension"], [e.plus_days(50), "Lundi de Pentecôte"],
            [Date(year, 7, 14), "Fête nationale"], [Date(year, 8, 15), "Assomption"], [Date(year, 11, 1), "Toussaint"],
            [Date(year, 11, 11), "Armistice 1918"], [Date(year, 12, 25), "Noël"]]

func holiday_dates_fr(year):
    out := []
    for pair in holidays_fr(year):
        append(out, pair[0])
    return out

# Âge en années entières à la date `on` (aujourd'hui si null).
func age(birth, on=null):
    _need_date("age", birth)
    ref := today() if on == null else on
    _need_date("age", ref)
    return ref.years_between(birth)

# ---------------------------------------------------------------------------------------------------------------
# Time (heure du jour)
# ---------------------------------------------------------------------------------------------------------------

# Heure du jour sans date ni fuseau : Time(14, 30, 5, 250000). Champs : hour, minute, second, microsecond, day_us
# (microsecondes depuis minuit).
class Time:
    func init(hour=0, minute=0, second=0, microsecond=0):
        _chk_range("Time", "hour", hour, 0, 23)
        _chk_range("Time", "minute", minute, 0, 59)
        _chk_range("Time", "second", second, 0, 59)
        _chk_range("Time", "microsecond", microsecond, 0, 999999)
        self.hour = hour
        self.minute = minute
        self.second = second
        self.microsecond = microsecond
        self.day_us = ((hour * 60 + minute) * 60 + second) * _US_SEC + microsecond

    func to_micros():
        return self.day_us
    func to_seconds():
        return to_float(self.day_us) / 1000000.0
    func is_midnight():
        return self.day_us == 0
    # Ajoute une Duration en repartant à 0 h après 24 h (heure murale).
    func plus(duration):
        _need_duration("Time.plus", duration)
        total := self.day_us + duration.seconds * _US_SEC + duration.microseconds
        return _time_from_micros(total % _US_DAY)
    func minus(duration):
        return self.plus(duration.negate())
    # Renvoie (Time, jours de report) : la Time après l'ajout et le nombre de jours franchis (négatif en arrière).
    func plus_with_carry(duration):
        _need_duration("Time.plus_with_carry", duration)
        total := self.day_us + duration.seconds * _US_SEC + duration.microseconds
        return (_time_from_micros(total % _US_DAY), duration.days + total // _US_DAY)
    func plus_hours(n):
        return self.plus(Duration(hours=n))
    func plus_minutes(n):
        return self.plus(Duration(minutes=n))
    func plus_seconds(n):
        return self.plus(Duration(seconds=n))
    # Durée self - other (peut être négative).
    func diff(other):
        _need_time("Time.diff", other)
        return Duration(microseconds=self.day_us - other.day_us)
    func compare(other):
        _need_time("Time.compare", other)
        if self.day_us < other.day_us:
            return -1
        return 1 if self.day_us > other.day_us else 0
    func equals(other):
        return isinstance(other, Time) and self.day_us == other.day_us
    func lt(other):
        return self.compare(other) < 0
    func le(other):
        return self.compare(other) <= 0
    func gt(other):
        return self.compare(other) > 0
    func ge(other):
        return self.compare(other) >= 0
    func replace(hour=null, minute=null, second=null, microsecond=null):
        return Time(self.hour if hour == null else hour, self.minute if minute == null else minute,
                    self.second if second == null else second, self.microsecond if microsecond == null else microsecond)
    # Arrondit vers le bas : "hour", "minute", "second", "millisecond".
    func truncate(unit):
        if unit == "hour":
            return Time(self.hour)
        if unit == "minute":
            return Time(self.hour, self.minute)
        if unit == "second":
            return Time(self.hour, self.minute, self.second)
        if unit == "millisecond":
            return Time(self.hour, self.minute, self.second, self.microsecond // 1000 * 1000)
        raise("ValueError", "datetime.Time.truncate : unité inconnue '" + str(unit) + "' (hour, minute, second, millisecond)")
    # timespec : "auto", "hours", "minutes", "seconds", "milliseconds", "microseconds".
    func isoformat(timespec="auto"):
        return time.iso_time_string(self.hour, self.minute, self.second, self.microsecond, timespec)
    func to_string():
        return self.isoformat("auto")
    func fields():
        return {"year": 1970, "month": 1, "day": 1, "hour": self.hour, "minute": self.minute, "second": self.second,
                "microsecond": self.microsecond, "weekday": 3, "yearday": 1, "utc_offset": null, "timezone": null,
                "is_dst": false}
    func format(fmt, locale="en"):
        return time.strftime(fmt, self.fields(), locale)
    # DateTime combinant `date` et cette heure (fuseau facultatif).
    func at(date, tz=null):
        _need_date("Time.at", date)
        return DateTime(date.year, date.month, date.day, self.hour, self.minute, self.second, self.microsecond, tz)
    func to_dict():
        return {"hour": self.hour, "minute": self.minute, "second": self.second, "microsecond": self.microsecond}

func _need_time(who, v):
    if not isinstance(v, Time):
        raise("TypeError", "datetime." + who + " : une Time est attendue (obtenu '" + type(v) + "')")

func _time_from_micros(us):
    sod := us // _US_SEC
    return Time(sod // 3600, (sod % 3600) // 60, sod % 60, us % _US_SEC)

# Time depuis des microsecondes écoulées depuis minuit (0 <= n < 86 400 000 000).
func time_from_micros(micros):
    _chk_range("time_from_micros", "micros", micros, 0, _US_DAY - 1)
    return _time_from_micros(micros)

# Time depuis des secondes depuis minuit (int ou float).
func time_from_seconds(seconds):
    p := time.split_timestamp(seconds)
    if p[0] < 0 or p[0] > 86399:
        raise("ValueError", "datetime.time_from_seconds : hors d'une journée (0..86399.999999) : " + str(seconds))
    return _time_from_micros(p[0] * _US_SEC + p[1])

# « 14:30 », « 14:30:05.25 », « T143005 ». Pas de fuseau : utiliser DateTime.
func time_from_iso(text):
    f := time.parse_iso_time(text)
    if f["utc_offset"] != null:
        raise("ValueError", "datetime.time_from_iso : pas de fuseau pour une Time ; utiliser from_iso d'un DateTime : '" + text + "'")
    return Time(f["hour"], f["minute"], f["second"], f["microsecond"])

func parse_time(text, fmt, locale="en"):
    f := time.strptime(text, fmt, locale)
    return Time(f["hour"], f["minute"], f["second"], f["microsecond"])

func midnight():
    return Time(0)

func noon():
    return Time(12)

# ---------------------------------------------------------------------------------------------------------------
# DateTime
# ---------------------------------------------------------------------------------------------------------------

# Date + heure, avec ou sans fuseau : DateTime(2026, 10, 7, 14, 30, 5, 250000, tz, fold). tz = TimeZone, nom
# (« Europe/Paris », « +02:00 ») ou décalage en secondes ; null = naïf. Champs : year, month, day, hour, minute,
# second, microsecond, tz, fold, epoch_day (jour mural depuis 1970-01-01), day_us (microsecondes murales du jour).
class DateTime:
    func init(year, month=1, day=1, hour=0, minute=0, second=0, microsecond=0, tz=null, fold=0):
        _chk_int("DateTime", "year", year)
        _chk_range("DateTime", "month", month, 1, 12)
        _chk_int("DateTime", "day", day)
        if day < 1 or day > time.days_in_month(year, month):
            raise("ValueError", "datetime.DateTime : jour hors limites pour " + time._year_str(year) + "-" + time._pad(month, 2) + " : " + str(day))
        _chk_range("DateTime", "hour", hour, 0, 23)
        _chk_range("DateTime", "minute", minute, 0, 59)
        _chk_range("DateTime", "second", second, 0, 59)
        _chk_range("DateTime", "microsecond", microsecond, 0, 999999)
        _chk_range("DateTime", "fold", fold, 0, 1)
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.second = second
        self.microsecond = microsecond
        self.tz = null if tz == null else _tz_arg(tz)
        self.fold = fold
        self.epoch_day = time._dfc(year, month, day)
        self.day_us = ((hour * 60 + minute) * 60 + second) * _US_SEC + microsecond

    # --- fuseau ---------------------------------------------------------------------------------------------
    func is_aware():
        return self.tz != null
    func is_naive():
        return self.tz == null
    # Décalage en secondes à l'est de UTC, ou null si naïf.
    func utc_offset():
        if self.tz == null:
            return null
        return self.tz.offset_at_local(self.epoch_day, self.day_us // _US_SEC, self.fold)
    func is_dst():
        if self.tz == null or self.tz.rule == null:
            return false
        return self.utc_offset() != self.tz.std_offset
    # Abréviation (CET, CEST, EST...) ou nom du fuseau ; null si naïf.
    func tzname():
        if self.tz == null:
            return null
        return self.tz.abbr(self.is_dst())
    # Même heure murale dans un autre fuseau (remplace le fuseau, ne convertit pas) ; null = naïf.
    func with_tz(tz):
        return DateTime(self.year, self.month, self.day, self.hour, self.minute, self.second, self.microsecond,
                        tz, self.fold)
    func to_naive():
        return self.with_tz(null)
    # Convertit vers un autre fuseau (même instant). Un DateTime naïf est refusé : utiliser with_tz.
    func astimezone(tz):
        if self.tz == null:
            raise("ValueError", "datetime.DateTime.astimezone : datetime naïf ; fixer d'abord un fuseau avec with_tz")
        p := _utc_of(self)
        return _from_utc(p[0], p[1], _tz_arg(tz))
    # En UTC (un naïf est lu comme UTC).
    func to_utc():
        if self.tz == null:
            return self.with_tz(UTC)
        return self.astimezone(UTC)
    func to_local():
        return self.astimezone(local_timezone())
    # Heure réelle correspondant à une heure inexistante (saut de printemps) ; inchangé sinon.
    func normalize():
        if self.tz == null:
            return self
        return self.astimezone(self.tz)

    # --- accesseurs -----------------------------------------------------------------------------------------
    func to_date():
        return Date(self.year, self.month, self.day)
    func to_time():
        return Time(self.hour, self.minute, self.second, self.microsecond)
    func weekday():
        return time.weekday_of_days(self.epoch_day)
    func isoweekday():
        return time.weekday_of_days(self.epoch_day) + 1
    func yearday():
        return self.epoch_day - time._dfc(self.year, 1, 1) + 1
    func iso_calendar():
        return time.iso_calendar(self.year, self.month, self.day)
    func week():
        return time.iso_calendar(self.year, self.month, self.day)[1]
    func quarter():
        return (self.month - 1) // 3 + 1
    func is_leap_year():
        return time.is_leap(self.year)
    func is_weekend():
        return self.weekday() >= 5

    # --- timestamps -----------------------------------------------------------------------------------------
    # (secondes epoch entières, microsecondes) exacts ; un naïf est lu comme UTC.
    func timestamp_parts():
        p := _utc_of(self)
        return (p[0] * 86400 + p[1] // _US_SEC, p[1] % _US_SEC)
    func timestamp():
        p := _utc_of(self)
        return to_float(p[0]) * 86400.0 + to_float(p[1]) / 1000000.0
    func timestamp_ms():
        q := self.timestamp_parts()
        return q[0] * 1000 + q[1] // 1000

    # --- arithmétique ---------------------------------------------------------------------------------------
    # Heure murale + durée (le fuseau est conservé ; l'heure obtenue peut ne pas exister, voir normalize).
    func plus(duration):
        _need_duration("DateTime.plus", duration)
        us := self.day_us + duration.seconds * _US_SEC + duration.microseconds
        return _make(self.epoch_day + duration.days + us // _US_DAY, us % _US_DAY, self.tz, 0)
    func minus(duration):
        _need_duration("DateTime.minus", duration)
        return self.plus(duration.negate())
    # Temps réellement écoulé : traverse les changements d'heure (naïf : identique à plus).
    func plus_exact(duration):
        _need_duration("DateTime.plus_exact", duration)
        if self.tz == null:
            return self.plus(duration)
        p := _utc_of(self)
        us := p[1] + duration.seconds * _US_SEC + duration.microseconds
        return _from_utc(p[0] + duration.days + us // _US_DAY, us % _US_DAY, self.tz)
    func minus_exact(duration):
        _need_duration("DateTime.minus_exact", duration)
        return self.plus_exact(duration.negate())
    func plus_days(n):
        return self.plus(Duration(days=n))
    func plus_weeks(n):
        return self.plus(Duration(weeks=n))
    func plus_hours(n):
        return self.plus(Duration(hours=n))
    func plus_minutes(n):
        return self.plus(Duration(minutes=n))
    func plus_seconds(n):
        return self.plus(Duration(seconds=n))
    func plus_millis(n):
        return self.plus(Duration(milliseconds=n))
    func plus_micros(n):
        return self.plus(Duration(microseconds=n))
    # Ajoute n mois (jour ramené en fin de mois si besoin), même heure murale.
    func plus_months(n):
        _chk_int("DateTime.plus_months", "n", n)
        total := self.year * 12 + (self.month - 1) + n
        y := total // 12
        m := total % 12 + 1
        d := self.day
        dim := time.days_in_month(y, m)
        if d > dim:
            d = dim
        return DateTime(y, m, d, self.hour, self.minute, self.second, self.microsecond, self.tz, self.fold)
    func plus_years(n):
        _chk_int("DateTime.plus_years", "n", n)
        return self.plus_months(12 * n)
    # Durée réelle self - other (deux aware : différence d'instants ; deux naïfs : différence murale).
    func diff(other):
        _need_datetime("DateTime.diff", other)
        _same_awareness("DateTime.diff", self, other)
        a := _utc_of(self)
        b := _utc_of(other)
        return Duration(days=a[0] - b[0], microseconds=a[1] - b[1])
    func until(other):
        return other.diff(self)
    func days_between(other):
        _need_datetime("DateTime.days_between", other)
        return _trunc_div(self.diff(other).total_microseconds(), _US_DAY)
    # Mois entiers de other à self (vers zéro) en comparant jour du mois puis heure (dans le fuseau de chacun).
    func months_between(other):
        _need_datetime("DateTime.months_between", other)
        return _whole_months(self.year, self.month, self.day, self.day_us, other.year, other.month, other.day, other.day_us)
    func years_between(other):
        return _trunc_div(self.months_between(other), 12)

    # --- comparaison ----------------------------------------------------------------------------------------
    # -1, 0, 1 ; deux aware : par instant ; deux naïfs : par heure murale ; mélange : TypeError.
    func compare(other):
        _need_datetime("DateTime.compare", other)
        _same_awareness("DateTime.compare", self, other)
        a := _utc_of(self)
        b := _utc_of(other)
        return _cmp3(a, b)
    func equals(other):
        return isinstance(other, DateTime) and (self.tz == null) == (other.tz == null) and self.compare(other) == 0
    func lt(other):
        return self.compare(other) < 0
    func le(other):
        return self.compare(other) <= 0
    func gt(other):
        return self.compare(other) > 0
    func ge(other):
        return self.compare(other) >= 0
    func is_before(other):
        return self.compare(other) < 0
    func is_after(other):
        return self.compare(other) > 0
    func is_between(a, b):
        return self.compare(a) >= 0 and self.compare(b) <= 0

    # --- remplacement, troncature ---------------------------------------------------------------------------
    # Paramètres positionnels, null = inchangé : (year, month, day, hour, minute, second, microsecond, tz, fold).
    func replace(year=null, month=null, day=null, hour=null, minute=null, second=null, microsecond=null, tz=null, fold=null):
        return DateTime(self.year if year == null else year, self.month if month == null else month,
                        self.day if day == null else day, self.hour if hour == null else hour,
                        self.minute if minute == null else minute, self.second if second == null else second,
                        self.microsecond if microsecond == null else microsecond, self.tz if tz == null else tz,
                        self.fold if fold == null else fold)
    # Arrondit vers le bas : "microsecond", "millisecond", "second", "minute", "hour", "day", "week" (lundi),
    # "month", "quarter", "year".
    func truncate(unit):
        us := self.day_us
        if unit == "microsecond":
            return self
        if unit == "millisecond":
            return _make(self.epoch_day, us - us % 1000, self.tz, self.fold)
        if unit == "second":
            return _make(self.epoch_day, us - us % _US_SEC, self.tz, self.fold)
        if unit == "minute":
            return _make(self.epoch_day, us - us % 60000000, self.tz, self.fold)
        if unit == "hour":
            return _make(self.epoch_day, us - us % 3600000000, self.tz, self.fold)
        if unit == "day":
            return _make(self.epoch_day, 0, self.tz, 0)
        if unit == "week":
            return _make(self.epoch_day - self.weekday(), 0, self.tz, 0)
        if unit == "month":
            return DateTime(self.year, self.month, 1, 0, 0, 0, 0, self.tz)
        if unit == "quarter":
            return DateTime(self.year, (self.month - 1) // 3 * 3 + 1, 1, 0, 0, 0, 0, self.tz)
        if unit == "year":
            return DateTime(self.year, 1, 1, 0, 0, 0, 0, self.tz)
        raise("ValueError", "datetime.DateTime.truncate : unité inconnue '" + str(unit) + "' (microsecond, millisecond, second, minute, hour, day, week, month, quarter, year)")
    # Arrondit vers le haut (inchangé si déjà sur la borne).
    func ceil(unit):
        t := self.truncate(unit)
        if t.compare(self) == 0 and t.fold == self.fold:
            return self
        if unit == "millisecond":
            return t.plus_micros(1000)
        if unit == "second":
            return t.plus_seconds(1)
        if unit == "minute":
            return t.plus_minutes(1)
        if unit == "hour":
            return t.plus_hours(1)
        if unit == "day":
            return t.plus_days(1)
        if unit == "week":
            return t.plus_days(7)
        if unit == "month":
            return t.plus_months(1)
        if unit == "quarter":
            return t.plus_months(3)
        if unit == "year":
            return t.plus_years(1)
        return self
    func start_of_day():
        return self.truncate("day")
    func end_of_day():
        return _make(self.epoch_day, _US_DAY - 1, self.tz, 0)

    # --- formats --------------------------------------------------------------------------------------------
    # Champs pour time.strftime : inclut utc_offset, timezone (abréviation) et is_dst.
    func fields():
        return {"year": self.year, "month": self.month, "day": self.day, "hour": self.hour, "minute": self.minute,
                "second": self.second, "microsecond": self.microsecond, "weekday": self.weekday(),
                "yearday": self.yearday(), "utc_offset": self.utc_offset(), "timezone": self.tzname(),
                "is_dst": self.is_dst()}
    # sep : séparateur date/heure ; timespec : "auto", "hours", "minutes", "seconds", "milliseconds", "microseconds" ;
    # z = true écrit « Z » pour UTC. Positionnel : isoformat("T", "auto", false).
    func isoformat(sep="T", timespec="auto", z=false):
        return time.iso_from_fields(self.fields(), self.utc_offset(), sep, timespec, z)
    # « 2026-10-07 14:30:05+02:00 ».
    func to_string():
        return self.isoformat(" ", "auto", false)
    func format(fmt, locale="en"):
        return time.strftime(fmt, self.fields(), locale)
    # « Wed, 07 Oct 2026 14:30:05 +0200 » (RFC 2822 / e-mail).
    func rfc2822():
        off := self.utc_offset()
        return time.strftime("%a, %d %b %Y %H:%M:%S ", self.fields(), "en") + time.format_offset(0 if off == null else off, false)
    # « Wed, 07 Oct 2026 12:30:05 GMT » (en-tête HTTP, toujours en UTC).
    func http_date():
        return self.to_utc().format("%a, %d %b %Y %H:%M:%S GMT", "en")
    func ctime():
        return time.asctime(self.fields())
    # Durée relative à `other` (maintenant si null) : « il y a 3 heures », « in 2 days » ; locale "en" ou "fr".
    func humanize(other=null, locale="en"):
        ref := other
        if ref == null:
            ref = now() if self.tz != null else from_timestamp(time.time(), local_timezone()).to_naive()
        return time.humanize(self.diff(ref).total_seconds(), locale)
    func to_dict():
        return {"year": self.year, "month": self.month, "day": self.day, "hour": self.hour, "minute": self.minute,
                "second": self.second, "microsecond": self.microsecond, "utc_offset": self.utc_offset()}

func _need_datetime(who, v):
    if not isinstance(v, DateTime):
        raise("TypeError", "datetime." + who + " : un DateTime est attendu (obtenu '" + type(v) + "')")

func _same_awareness(who, a, b):
    if (a.tz == null) != (b.tz == null):
        raise("TypeError", "datetime." + who + " : impossible de mélanger un datetime naïf et un datetime avec fuseau")

# (jours, microsecondes) UTC de l'instant ; un naïf est lu comme UTC.
func _utc_of(dt):
    if dt.tz == null:
        return [dt.epoch_day, dt.day_us]
    off := dt.tz.offset_at_local(dt.epoch_day, dt.day_us // _US_SEC, dt.fold)
    total := dt.day_us - off * _US_SEC
    return [dt.epoch_day + total // _US_DAY, total % _US_DAY]

# DateTime mural (jour, microsecondes du jour) dans tz.
func _make(epoch_day, day_us, tz, fold):
    ymd := time.civil_from_days(epoch_day)
    sod := day_us // _US_SEC
    return DateTime(ymd[0], ymd[1], ymd[2], sod // 3600, (sod % 3600) // 60, sod % 60, day_us % _US_SEC, tz, fold)

# DateTime vu dans tz (UTC si null) pour l'instant (jour UTC, microsecondes UTC du jour).
func _from_utc(udays, uus, tz):
    zone := UTC if tz == null else tz
    off := zone.std_offset
    if zone.rule != null:
        off = zone.offset_at_instant(udays * 86400 + uus // _US_SEC)
    total := uus + off * _US_SEC
    ldays := udays + total // _US_DAY
    lus := total % _US_DAY
    fold := 0
    if zone.rule != null and zone.offset_at_local(ldays, lus // _US_SEC, 0) != off:
        fold = 1
    return _make(ldays, lus, zone, fold)

# Maintenant dans le fuseau tz ; fuseau du système (décalage actuel) si null. Toujours « aware ».
func now(tz=null):
    zone := local_timezone() if tz == null else _tz_arg(tz)
    return from_timestamp(time.time(), zone)

func now_utc():
    return from_timestamp(time.time(), UTC)

# Instant d'un timestamp (secondes epoch, int ou float) dans le fuseau tz (UTC par défaut) ; aware.
func from_timestamp(ts, tz=null):
    p := time.split_timestamp(ts)
    return from_timestamp_parts(p[0], p[1], tz)

# Comme from_timestamp avec des secondes entières et des microsecondes exactes (aucune perte).
func from_timestamp_parts(seconds, microseconds=0, tz=null):
    _chk_int("from_timestamp_parts", "seconds", seconds)
    _chk_range("from_timestamp_parts", "microseconds", microseconds, 0, 999999)
    zone := UTC if tz == null else _tz_arg(tz)
    return _from_utc(seconds // 86400, (seconds % 86400) * _US_SEC + microseconds, zone)

# Combine une Date et une Time (fuseau facultatif).
func combine(date, tod, tz=null):
    _need_date("combine", date)
    _need_time("combine", tod)
    return DateTime(date.year, date.month, date.day, tod.hour, tod.minute, tod.second, tod.microsecond, tz)

func _from_fields(f, tz):
    zone := null
    if f["utc_offset"] != null:
        zone = fixed_offset(f["utc_offset"])
    dt := DateTime(f["year"], f["month"], f["day"], f["hour"], f["minute"], f["second"], f["microsecond"], zone)
    if tz == null:
        return dt
    target := _tz_arg(tz)
    if zone == null:
        return dt.with_tz(target)
    return dt.astimezone(target)

# ISO 8601 : « 2026-10-07T14:30:05+02:00 », « 2026-10-07 », « 20261007T143005Z »... Sans décalage dans le texte :
# naïf (ou fuseau `tz` si donné) ; avec décalage : décalage fixe (converti vers `tz` si donné).
func from_iso(text, tz=null):
    return _from_fields(time.parse_iso(text), tz)

# Analyse selon un format strptime (voir time.strptime pour les directives).
func parse(text, fmt, locale="en", tz=null):
    return _from_fields(time.strptime(text, fmt, locale), tz)

func earliest(values):
    best := null
    for v in values:
        if best == null or v.compare(best) < 0:
            best = v
    return best

func latest(values):
    best := null
    for v in values:
        if best == null or v.compare(best) > 0:
            best = v
    return best

# DateTime de start vers end (heure murale), step = Duration non nulle (négative pour descendre) ; end inclus si inclusive.
func datetime_range(start, end, step, inclusive=false):
    _need_datetime("datetime_range", start)
    _need_datetime("datetime_range", end)
    _need_duration("datetime_range", step)
    if step.is_zero():
        raise("ValueError", "datetime.datetime_range : le pas ne peut pas être nul")
    out := []
    cur := start
    forward := not step.is_negative()
    while true:
        c := cur.compare(end)
        if forward and (c > 0 or (c == 0 and not inclusive)):
            break
        if not forward and (c < 0 or (c == 0 and not inclusive)):
            break
        append(out, cur)
        cur = cur.plus(step)
    return out
