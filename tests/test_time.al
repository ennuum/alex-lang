# ALEX - tests du module time (ALEX pur). Lancer depuis la racine : ./alex run tests/test_time.al
# Les vecteurs de référence (tests/time_vectors.al) sont calculés par Python (datetime, zoneinfo) : voir tools/time/.
use time
use testing
use string
from core use len
from collections use append
use tests.time_vectors as tv
from testing use assert_eq, assert_true, assert_false, assert_raises, assert_near

func t_civil_vs_python():
    for r in tv.CIVIL:
        ymd := time.civil_from_days(r[0])
        assert_eq(ymd, (r[1], r[2], r[3]))
        assert_eq(time.days_from_civil(r[1], r[2], r[3]), r[0])
        assert_eq(time.weekday(r[1], r[2], r[3]), r[4])
        assert_eq(time.yearday(r[1], r[2], r[3]), r[5])
        assert_eq(time.iso_calendar(r[1], r[2], r[3]), (r[6], r[7], r[8]))
        assert_eq(time.to_ordinal(r[1], r[2], r[3]), r[9])
        assert_eq(time.iso_to_civil(r[6], r[7], r[8]), (r[1], r[2], r[3]))
        assert_eq(time.from_ordinal(r[9]), (r[1], r[2], r[3]))

testing.test("calendrier vs Python (414 dates)", t_civil_vs_python)

func t_unbounded_years():
    # toute année entière : allers-retours exacts très loin de 1970, an 0 et années négatives compris
    for y in [0, -1, -4712, 10000, 123456, -123456, 1000000000, -1000000000, 100000000000]:
        for m in [1, 2, 12]:
            n := time.days_from_civil(y, m, 1)
            assert_eq(time.civil_from_days(n), (y, m, 1))
    assert_true(time.is_leap(0))
    assert_true(time.is_leap(-4))
    assert_false(time.is_leap(-100))
    assert_true(time.is_leap(-400))
    assert_eq(time.days_in_month(0, 2), 29)
    assert_eq(time.days_from_civil(1970, 1, 1), 0)
    assert_eq(time.days_from_civil(0, 3, 1) - time.days_from_civil(0, 2, 28), 2)
    assert_eq(time.weekday(1, 1, 1), 0)

testing.test("années illimitées, an 0, négatives", t_unbounded_years)

func t_calendar_misc():
    assert_eq(time.weeks_in_year(2020), 53)
    assert_eq(time.weeks_in_year(2026), 53)
    assert_eq(time.weeks_in_year(2021), 52)
    assert_eq(time.nth_weekday(2026, 10, 3, 1), 1)
    assert_eq(time.nth_weekday(2026, 10, 6, -1), 25)
    assert_eq(time.nth_weekday(2026, 3, 6, -1), 29)
    assert_eq(time.nth_weekday(2026, 11, 3, 4), 26)
    assert_raises(() => time.nth_weekday(2026, 2, 0, 5), "ValueError")
    assert_eq(time.easter(2024), (3, 31))
    assert_eq(time.easter(2025), (4, 20))
    assert_eq(time.easter(2026), (4, 5))
    assert_eq(time.easter(2000), (4, 23))
    assert_eq(time.easter(1961), (4, 2))
    m := time.month_matrix(2026, 10, 0)
    assert_eq(m[0], [0, 0, 0, 1, 2, 3, 4])
    assert_eq(m[4], [26, 27, 28, 29, 30, 31, 0])
    assert_eq(time.month_matrix(2026, 2, 6)[0], [1, 2, 3, 4, 5, 6, 7])
    cal := time.month_calendar(2026, 10, 0, "en")
    assert_true(string_contains(cal, "October 2026"))
    assert_true(string_contains(cal, "26 27 28 29 30 31"))
    assert_raises(() => time.days_from_civil(2026, 2, 29), "ValueError")
    assert_raises(() => time.days_from_civil(2026, 13, 1), "ValueError")
    assert_raises(() => time.is_leap(2026.5), "TypeError")

func string_contains(s, sub):
    return string.contains(s, sub)

testing.test("calendrier : semaines, n-ième jour, Pâques, grille", t_calendar_misc)

func t_gmtime_timegm():
    f := time.gmtime(1791360000)
    assert_eq(f["year"], 2026)
    assert_eq(f["month"], 10)
    assert_eq(f["day"], 7)
    assert_eq(f["hour"], 8)
    assert_eq(f["weekday"], 2)
    assert_eq(f["yearday"], 280)
    assert_eq(time.timegm(f), 1791360000)
    assert_eq(time.timegm({"year": 1969, "month": 12, "day": 31, "hour": 23, "minute": 59, "second": 59}), -1)
    g := time.gmtime(-0.25)
    assert_eq(g["second"], 59)
    assert_eq(g["microsecond"], 750000)
    assert_eq(g["year"], 1969)
    assert_near(time.timegm({"year": 2026, "month": 1, "day": 1, "microsecond": 500000}), 1767225600.5)
    # normalisation des champs hors plage
    assert_eq(time.timegm({"year": 2026, "month": 14, "day": 1}), time.timegm({"year": 2027, "month": 2, "day": 1}))
    assert_eq(time.timegm({"year": 2026, "month": 3, "day": 0}), time.timegm({"year": 2026, "month": 2, "day": 28}))
    assert_eq(time.timegm({"year": 2026, "month": 1, "day": 1, "second": 90}), time.timegm({"year": 2026, "month": 1, "day": 1}) + 90)
    assert_eq(time.timegm([2000, 1, 1, 0, 0, 0]), 946684800)
    # très grandes années
    big := time.timegm({"year": 100000, "month": 1, "day": 1})
    assert_eq(time.gmtime(big)["year"], 100000)
    assert_eq(time.split_timestamp(5), (5, 0))
    assert_eq(time.split_timestamp(1.5), (1, 500000))
    assert_eq(time.split_timestamp(-1.5), (-2, 500000))

testing.test("gmtime / timegm / normalisation", t_gmtime_timegm)

func t_local():
    time.set_local_zone(7200, "CEST", true)
    f := time.localtime(1791360000)
    assert_eq(f["hour"], 10)
    assert_eq(f["utc_offset"], 7200)
    assert_eq(f["timezone"], "CEST")
    assert_eq(time.mktime({"year": 2026, "month": 10, "day": 7, "hour": 10}), 1791360000)
    assert_eq(time.mktime({"year": 2026, "month": 10, "day": 7, "hour": 10, "utc_offset": 0}), 1791367200)
    assert_eq(time.local_utc_offset(), 7200)
    time.set_local_zone(null)

testing.test("zone locale simulée", t_local)

func t_strftime_vs_python():
    for r in tv.STRFTIME:
        f := time.gmtime(r[0])
        f["microsecond"] = r[1]
        assert_eq(time.strftime(tv.STRFTIME_FORMAT, f), r[2])

testing.test("strftime vs Python (120 dates, 29 directives)", t_strftime_vs_python)

func t_strftime_misc():
    f := time.gmtime(1791360000)
    assert_eq(time.strftime("%A %d %B %Y", f, "fr"), "mercredi 07 octobre 2026")
    assert_eq(time.strftime("%a %b %e", f, "de"), "Mi Okt  7")
    assert_eq(time.strftime("%-d/%-m/%y %-H:%M", f), "7/10/26 8:00")
    assert_eq(time.strftime("%c", f, "en"), "Wed Oct  7 08:00:00 2026")
    assert_eq(time.strftime("%x %X", f, "fr"), "07/10/2026 08:00:00")
    assert_eq(time.strftime("%s", f), "1791360000")
    assert_eq(time.strftime("%z|%:z|%Z", {"year": 2026, "utc_offset": -19800, "timezone": "IST"}), "-0530|-05:30|IST")
    assert_eq(time.strftime("%z", {"year": 2026}), "")
    assert_eq(time.strftime("%Y", {"year": -44}), "-0044")
    assert_eq(time.strftime("%Y", {"year": 12345}), "12345")
    assert_eq(time.strftime("100%%"), "100%")
    assert_eq(time.strftime("%I %p", {"year": 2026, "hour": 0}), "12 AM")
    assert_eq(time.strftime("%I %p", {"year": 2026, "hour": 13}), "01 PM")
    assert_eq(time.strftime("%L", {"year": 2026, "microsecond": 123456}), "123")
    assert_eq(time.asctime(f), "Wed Oct  7 08:00:00 2026")
    assert_raises(() => time.strftime("%q", f), "ValueError")
    assert_raises(() => time.strftime("abc%", f), "ValueError")
    assert_raises(() => time.strftime("%Y", f, "xx"), "ValueError")
    assert_raises(() => time.strftime(5, f), "TypeError")

testing.test("strftime : langues, drapeaux, cas limites", t_strftime_misc)

func _first(l, n):
    out := []
    k := 0
    while k < n:
        append(out, l[k])
        k = k + 1
    return out

func t_strptime():
    for r in tv.STRFTIME:
        head := string.join("|", _first(string.split(r[2], "|"), 16))
        f := time.strptime(head, "%Y|%C|%m|%d|%e|%H|%I|%M|%S|%f|%j|%a|%A|%b|%B|%p")
        g := time.gmtime(r[0])
        assert_eq(f["year"], g["year"])
        assert_eq(f["month"], g["month"])
        assert_eq(f["day"], g["day"])
        assert_eq(f["hour"], g["hour"])
        assert_eq(f["minute"], g["minute"])
        assert_eq(f["second"], g["second"])
        assert_eq(f["microsecond"], r[1])
        assert_eq(f["weekday"], g["weekday"])
    f := time.strptime("7 octobre 2026 14h05", "%d %B %Y %Hh%M", "fr")
    assert_eq(f["month"], 10)
    assert_eq(f["hour"], 14)
    assert_eq(time.strptime("Mer 7 Oct 2026", "%a %d %b %Y", "fr")["day"], 7)
    assert_eq(time.strptime("févr. 2026", "%b %Y", "fr")["month"], 2)
    assert_eq(time.strptime("FÉVRIER 2026", "%B %Y", "fr")["month"], 2)
    assert_eq(time.strptime("20261007", "%Y%m%d")["day"], 7)
    assert_eq(time.strptime("-0044-03-15", "%Y-%m-%d")["year"], -44)
    assert_eq(time.strptime("+123456-01-01", "%Y-%m-%d")["year"], 123456)
    assert_eq(time.strptime("12:30 PM", "%I:%M %p")["hour"], 12)
    assert_eq(time.strptime("12:30 AM", "%I:%M %p")["hour"], 0)
    assert_eq(time.strptime("11:30 pm", "%I:%M %p")["hour"], 23)
    assert_eq(time.strptime("69", "%y")["year"], 1969)
    assert_eq(time.strptime("68", "%y")["year"], 2068)
    assert_eq(time.strptime("2024 060", "%Y %j")["month"], 2)
    assert_eq(time.strptime("2024 060", "%Y %j")["day"], 29)
    z := time.strptime("2026-10-07 08:00:00 +0530", "%F %T %z")
    assert_eq(z["utc_offset"], 19800)
    assert_eq(time.strptime("2026-10-07 Z", "%F %z")["utc_offset"], 0)
    assert_eq(time.strptime("2026-10-07 08:00 CEST", "%F %R %Z")["timezone"], "CEST")
    s := time.strptime("1791360000", "%s")
    assert_eq(s["year"], 2026)
    assert_eq(s["hour"], 8)
    assert_eq(time.strptime("  2026-10-07   08:00 ", "%F %R")["hour"], 8)
    assert_eq(time.strptime("08:00:00.5", "%T.%f")["microsecond"], 500000)
    assert_eq(time.strptime("1.123456789", "%S.%f")["microsecond"], 123456)
    assert_raises(() => time.strptime("2026-02-30", "%F"), "ValueError")
    assert_raises(() => time.strptime("2026-13-01", "%F"), "ValueError")
    assert_raises(() => time.strptime("25:00", "%H:%M"), "ValueError")
    assert_raises(() => time.strptime("2026-10-07 x", "%F"), "ValueError")
    assert_raises(() => time.strptime("2026/10/07", "%F"), "ValueError")
    assert_raises(() => time.strptime("13:00 AM", "%I:%M %p"), "ValueError")

testing.test("strptime : aller-retour, langues, décalages", t_strptime)

func t_iso_vs_python():
    for r in tv.ISO:
        f := time.parse_iso(r[0])
        assert_eq(f["year"], r[1])
        assert_eq(f["month"], r[2])
        assert_eq(f["day"], r[3])
        assert_eq(f["hour"], r[4])
        assert_eq(f["minute"], r[5])
        assert_eq(f["second"], r[6])
        assert_eq(f["microsecond"], r[7])
        assert_eq(f["utc_offset"], r[8])

testing.test("ISO 8601 vs Python (27 formes)", t_iso_vs_python)

func t_iso_misc():
    assert_eq(time.parse_iso("+12345-01-01")["year"], 12345)
    assert_eq(time.parse_iso("-0044-03-15")["year"], -44)
    assert_eq(time.parse_iso("2026-10-07")["has_time"], false)
    assert_eq(time.parse_iso("2026-10-07T01")["has_time"], true)
    for bad in ["", "2026", "2026-1-1", "2026-10-07T", "2026-10-07T25:00", "2026-02-30", "2026-W54-1", "2026-10-07X",
                "2026-10-07T08:00+25:00", "2026-10-07T08:00Z junk", "20261", "abcd-10-07"]:
        assert_raises(() => time.parse_iso(bad), "ValueError")
    assert_eq(time.parse_iso_time("T08:30:15.5")["microsecond"], 500000)
    assert_eq(time.parse_iso_time("0830+01:00")["utc_offset"], 3600)
    assert_eq(time.iso_from_timestamp(1791360000), "2026-10-07T08:00:00+00:00")
    assert_eq(time.iso_from_timestamp(1791360000, 7200, "T", "auto", false), "2026-10-07T10:00:00+02:00")
    assert_eq(time.iso_from_timestamp(1791360000, 0, "T", "auto", true), "2026-10-07T08:00:00Z")
    assert_eq(time.iso_from_timestamp(1791360000.25, 0, " ", "milliseconds"), "2026-10-07 08:00:00.250+00:00")
    assert_eq(time.iso_from_timestamp(1791360000, 0, "T", "minutes"), "2026-10-07T08:00+00:00")
    assert_eq(time.parse_iso_timestamp("2026-10-07T10:00:00+02:00"), 1791360000)
    assert_eq(time.parse_iso_timestamp("2026-10-07T08:00:00Z"), 1791360000)
    assert_eq(time.parse_iso_timestamp("2026-10-07T08:00:00", 3600), 1791356400)
    assert_near(time.parse_iso_timestamp("2026-10-07T08:00:00.5Z"), 1791360000.5)
    assert_eq(time.format_offset(-19800), "-05:30")
    assert_eq(time.format_offset(3661, false), "+010101")

testing.test("ISO 8601 : formes étendues, erreurs, conversions", t_iso_misc)

func t_duration_text():
    assert_eq(time.parse_duration("1h30m"), 5400)
    assert_eq(time.parse_duration("90s"), 90)
    assert_eq(time.parse_duration("1.5h"), 5400)
    assert_eq(time.parse_duration("2d 3h"), 183600)
    assert_eq(time.parse_duration("1 hour 30 minutes"), 5400)
    assert_eq(time.parse_duration("3 semaines et 2 jours"), 3 * 604800 + 2 * 86400)
    assert_eq(time.parse_duration("-1h"), -3600)
    assert_eq(time.parse_duration("PT90M"), 5400)
    assert_eq(time.parse_duration("P1DT2H3M4S"), 93784)
    assert_eq(time.parse_duration("P2W"), 1209600)
    assert_near(time.parse_duration("PT0.5S"), 0.5)
    assert_near(time.parse_duration("250ms"), 0.25)
    assert_near(time.parse_duration("1h 0,5s"), 3600.5)
    assert_eq(time.parse_duration("1:30:00"), 5400)
    assert_near(time.parse_duration("1:02:03.5"), 3723.5)
    assert_eq(time.parse_duration("2 days, 1:30:00"), 2 * 86400 + 5400)
    assert_eq(time.parse_duration("45"), 45)
    assert_eq(time.duration_parts("-1s"), (-1, 86399, 0))
    assert_eq(time.duration_parts("100000000d"), (100000000, 0, 0))
    for bad in ["", "abc", "1x", "P1Y", "P1M", "1h 2", "PT", "1:75:00", "1h30"]:
        assert_raises(() => time.parse_duration(bad), "ValueError")

testing.test("parse_duration : unités, ISO, horloge", t_duration_text)

func t_duration_format():
    assert_eq(time.format_duration(5430.5), "1h 30m 30.5s")
    assert_eq(time.format_duration(0), "0s")
    assert_eq(time.format_duration(-90), "-1m 30s")
    assert_eq(time.format_duration(93784.25, "clock"), "26:03:04.25")
    assert_eq(time.format_duration(93784, "iso"), "P1DT2H3M4S")
    assert_eq(time.format_duration(0, "iso"), "PT0S")
    assert_eq(time.format_duration(93784.25, "long"), "1 day, 2 hours, 3 minutes and 4.25 seconds")
    assert_eq(time.format_duration(93784.25, "long", "fr"), "1 jour, 2 heures, 3 minutes et 4,25 secondes")
    assert_eq(time.format_duration(3600, "long"), "1 hour")
    assert_eq(time.format_duration(1, "long", "fr"), "1 seconde")
    assert_eq(time.format_duration(0, "long", "fr"), "0 seconde")
    assert_eq(time.format_duration(1.5, "long", "fr"), "1,5 seconde")
    assert_eq(time.format_duration(172800, "long"), "2 days")
    assert_raises(() => time.format_duration(1, "zzz"), "ValueError")
    assert_eq(time.humanize(2), "just now")
    assert_eq(time.humanize(-30), "30 seconds ago")
    assert_eq(time.humanize(60), "in a minute")
    assert_eq(time.humanize(-600), "10 minutes ago")
    assert_eq(time.humanize(7200), "in 2 hours")
    assert_eq(time.humanize(-86400 * 3, "fr"), "il y a 3 jours")
    assert_eq(time.humanize(86400 * 400, "fr"), "dans un an")
    assert_eq(time.humanize(86400 * 800), "in 2 years")

testing.test("format_duration et humanize", t_duration_format)

func t_clock():
    fc := time.install_fake_clock(1000.0)
    assert_eq(time.time(), 1000.0)
    time.sleep(2.5)
    assert_eq(time.time(), 1002.5)
    assert_eq(time.monotonic(), 1002.5)
    sw := time.Stopwatch(true)
    fc.advance(3)
    assert_eq(sw.lap(), 3)
    fc.advance(4)
    assert_eq(sw.lap(), 4)
    assert_eq(sw.elapsed(), 7)
    assert_eq(sw.stop(), 7)
    fc.advance(100)
    assert_eq(sw.elapsed(), 7)
    sw.start()
    fc.advance(1)
    assert_eq(sw.elapsed(), 8)
    sw.reset()
    assert_eq(sw.elapsed(), 0.0)
    d := time.Deadline(10)
    assert_false(d.expired())
    fc.advance(4)
    assert_eq(d.remaining(), 6.0)
    d.extend(5)
    fc.advance(10)
    assert_false(d.expired())
    fc.advance(1)
    assert_true(d.expired())
    assert_eq(d.remaining(), 0.0)
    assert_raises(() => d.check("trop tard"), "TimeoutError", "trop tard")
    assert_true(time.Deadline(null).remaining() == null)
    d2 := time.Deadline(3)
    d2.wait()
    assert_true(d2.expired())
    m := time.measure(() => time.sleep(2))
    assert_eq(m[1], 2)
    calls := []
    n := time.every(5, i => _note(calls, i), 3)
    assert_eq(n, 3)
    assert_eq(len(calls), 3)
    t0 := time.time()
    assert_eq(time.sleep_until(t0 + 7), 7)
    assert_eq(time.sleep_until(t0), 0.0)
    b := time.benchmark(() => time.sleep(1), 4, 1)
    assert_eq(b["runs"], 4)
    assert_eq(b["mean"], 1)
    assert_eq(time.timeit(() => time.sleep(2), 5), 2)
    assert_raises(() => time.sleep(-1), "ValueError")
    time.reset_clock()

func _note(l, i):
    append(l, i)

testing.test("horloge simulée, Stopwatch, Deadline, every", t_clock)

func t_locales():
    time.register_locale("xx", {"months": ["a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8", "a9", "a10", "a11", "a12"], "months_abbr": ["b1", "b2", "b3", "b4", "b5", "b6", "b7", "b8", "b9", "b10", "b11", "b12"], "days": ["d1", "d2", "d3", "d4", "d5", "d6", "d7"], "days_abbr": ["e1", "e2", "e3", "e4", "e5", "e6", "e7"]})
    assert_eq(time.strftime("%B %A", {"year": 2026, "month": 10, "day": 7}, "xx"), "a10 d3")
    assert_eq(time.month_name(3, "fr"), "mars")
    assert_eq(time.month_name(2, "es", true), "feb")
    assert_eq(time.day_name(6, "de"), "Sonntag")
    assert_eq(time.day_name(0, "pt", true), "seg")
    assert_eq(time.month_name(12, "nl"), "december")
    assert_eq(time.month_name(1, "fr_FR"), "janvier")
    assert_raises(() => time.register_locale("yy", {"months": []}), "ValueError")

testing.test("langues : prédéfinies et personnalisées", t_locales)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) time en échec")
print("TIME: OK")
