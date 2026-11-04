# Démonstration des modules time et datetime (ALEX pur).   ./alex run examples/time_demo.al
use time
use datetime
from datetime use Date, DateTime, Duration

# --- time : champs, formats, langues
f := time.gmtime(1791360000)
print(time.strftime("%A %d %B %Y, %H:%M", f, "fr"))
print(time.parse_duration("1h30m") / 60, "minutes")
print(time.humanize(-7200, "fr"))

# --- dates sans limite d'année
print(Date(-44, 3, 15).isoformat(), Date(-44, 3, 15).weekday())
print(Date(1000000000, 1, 1).plus_years(5).isoformat())

# --- arithmétique et périodes
d := Date(2026, 10, 7)
print(d.plus_months(4).isoformat(), d.end_of_month().isoformat(), d.iso_calendar())
print(datetime.period_between(Date(1990, 5, 17), d).to_string())
print(d.plus_business_days(10, datetime.holiday_dates_fr(2026)).isoformat())

# --- fuseaux et heure d'été
paris := datetime.get_timezone("Europe/Paris")
dt := DateTime(2026, 3, 29, 1, 30, 0, 0, paris)
print(dt.plus(Duration(hours=1)).isoformat(), "(heure murale)")
print(dt.plus_exact(Duration(hours=1)).isoformat(), "(temps écoulé)")
print(dt.astimezone("Asia/Tokyo").format("%d %B %Y %H:%M %Z", "fr"))
print(dt.astimezone("America/New_York").rfc2822())

# --- chronomètre
sw := time.Stopwatch(true)
time.sleep(0.05)
print("écoulé :", sw.elapsed() >= 0.05)
