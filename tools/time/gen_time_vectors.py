#!/usr/bin/env python3
"""Génère tests/time_vectors.al : vecteurs de référence du module `time` calculés par Python (datetime, calendar).
Usage : python3 tools/time/gen_time_vectors.py > tests/time_vectors.al   (graine fixe : sortie reproductible)
Le fichier généré ne doit jamais être édité à la main."""
import datetime as dt
import random

rnd = random.Random(20261007)
EPOCH = dt.date(1970, 1, 1)

def rand_date():
    y = rnd.choice([rnd.randint(1, 9999), rnd.randint(1900, 2100), rnd.randint(1970, 2040)])
    m = rnd.randint(1, 12)
    import calendar
    d = rnd.randint(1, calendar.monthrange(y, m)[1])
    return dt.date(y, m, d)

edge = [dt.date(1, 1, 1), dt.date(9999, 12, 31), dt.date(1970, 1, 1), dt.date(2000, 2, 29), dt.date(1900, 2, 28),
        dt.date(2100, 3, 1), dt.date(2024, 12, 30), dt.date(2021, 1, 3), dt.date(2020, 12, 31), dt.date(2015, 12, 31),
        dt.date(2016, 1, 1), dt.date(1582, 10, 15), dt.date(400, 2, 29), dt.date(100, 3, 1)]
dates = edge + [rand_date() for _ in range(400)]

print("# GÉNÉRÉ par tools/time/gen_time_vectors.py (Python datetime) - ne pas éditer à la main.")
print("# CIVIL : [jours depuis 1970-01-01, année, mois, jour, weekday(0=lundi), yearday, année ISO, semaine ISO, jour ISO, ordinal]")
print("const CIVIL := [")
rows = []
for d in dates:
    days = (d - EPOCH).days
    iso = d.isocalendar()
    rows.append("    [%d, %d, %d, %d, %d, %d, %d, %d, %d, %d]" % (days, d.year, d.month, d.day, d.weekday(),
                d.timetuple().tm_yday, iso[0], iso[1], iso[2], d.toordinal()))
print(",\n".join(rows))
print("]")

# strftime : instants (années 1000..9999 : le formatage des années < 1000 dépend de la plate-forme)
FMT = "%Y|%y|%m|%d|%e|%H|%I|%M|%S|%f|%j|%a|%A|%b|%B|%p|%u|%w|%U|%W|%V|%G|%g|%C|%%|%F|%T|%D|%R"
print("const STRFTIME_FORMAT := \"%s\"" % FMT)
print("# STRFTIME : [timestamp UTC entier, microsecondes, texte attendu]")
print("const STRFTIME := [")
rows = []
for _ in range(120):
    y = rnd.choice([rnd.randint(1000, 9999), rnd.randint(1970, 2100)])
    d = dt.datetime(y, rnd.randint(1, 12), 1, rnd.randint(0, 23), rnd.randint(0, 59), rnd.randint(0, 59),
                    rnd.randint(0, 999999))
    import calendar
    d = d.replace(day=rnd.randint(1, calendar.monthrange(y, d.month)[1]))
    ts = int((d.replace(microsecond=0) - dt.datetime(1970, 1, 1)).total_seconds())
    text = d.strftime(FMT.replace("%e", "%e"))
    rows.append("    [%d, %d, \"%s\"]" % (ts, d.microsecond, text))
print(",\n".join(rows))
print("]")

# ISO 8601 : textes valides compris par fromisoformat (Python 3.11+) -> champs
print("# ISO : [texte, année, mois, jour, heure, minute, seconde, microseconde, décalage en secondes ou null]")
print("const ISO := [")
rows = []
samples = ["2026-10-07", "20261007", "2026-10-07T08:30:15", "2026-10-07 08:30:15", "20261007T083015", "2026-10-07T08:30",
           "2026-10-07T08", "2026-10-07T08:30:15.25", "2026-10-07T08:30:15.123456", "2026-10-07T08:30:15,5",
           "2026-10-07T08:30:15Z", "2026-10-07T08:30:15+02:00", "2026-10-07T08:30:15-05:30", "2026-10-07T08:30:15+0200",
           "20261007T083015+0530", "2026-W41-3", "2026W413", "2026-W41", "2020-W53-7", "2026-280", "2026280",
           "2024-366", "0001-01-01T00:00:00", "9999-12-31T23:59:59.999999+00:00", "2026-10-07T08:30:15.5-03",
           "2021-W01-1", "2020-12-31T23:59:59-12:00"]
for s in samples:
    import re
    m = re.fullmatch(r"(\d{4})-?(\d{3})", s)
    if m:  # date ordinale (AAAA-DDD) : non comprise par fromisoformat
        base = dt.date(int(m.group(1)), 1, 1) + dt.timedelta(days=int(m.group(2)) - 1)
        d = dt.datetime(base.year, base.month, base.day)
    else:
        d = dt.datetime.fromisoformat(s)
    off = d.utcoffset()
    off_s = "null" if off is None else str(int(off.total_seconds()))
    rows.append("    [\"%s\", %d, %d, %d, %d, %d, %d, %d, %s]" % (s, d.year, d.month, d.day, d.hour, d.minute, d.second,
                d.microsecond, off_s))
print(",\n".join(rows))
print("]")

# Fuseaux : instants (dont beaucoup autour des changements d'heure) -> décalage, abréviation et heure murale (zoneinfo)
from zoneinfo import ZoneInfo
ZONES = ["Europe/Paris", "Europe/London", "America/New_York", "America/Los_Angeles", "Australia/Sydney",
         "Pacific/Auckland", "America/Chicago", "Europe/Athens", "Australia/Adelaide", "America/Denver"]
print("# TZ : [fuseau, timestamp UTC, décalage (s), abréviation, heure murale AAAA-MM-JJTHH:MM:SS]")
print("const TZ := [")
rows = []
def tzrow(z, ts):
    d = dt.datetime.fromtimestamp(ts, ZoneInfo(z))
    return '    ["%s", %d, %d, "%s", "%s"]' % (z, ts, int(d.utcoffset().total_seconds()), d.tzname(), d.strftime("%Y-%m-%dT%H:%M:%S"))
for _ in range(250):
    rows.append(tzrow(rnd.choice(ZONES), rnd.randint(1175000000, 2200000000)))
for z in ZONES:
    for y in (2009, 2016, 2024, 2031):
        for mo in (3, 4, 9, 10, 11):
            for dd in (25, 28, 31):
                try:
                    base = dt.datetime(y, mo, dd, 0, tzinfo=dt.timezone.utc)
                except ValueError:
                    continue
                for h in (0, 6, 12, 18):
                    rows.append(tzrow(z, int(base.timestamp()) + h * 3600))
print(",\n".join(rows))
print("]")
