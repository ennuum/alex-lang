# ALEX STANDARD LIBRARY — system.time
#
# Le module `time` (docs/TIME_DATETIME.md) sous le nom system.time : horloges (time, monotonic, perf_counter), pauses
# (sleep, sleep_until), calendrier, formatage et analyse (strftime, strptime, ISO 8601), durées, mesure
# (Stopwatch, Deadline, measure, benchmark). Les dates complètes sont dans `datetime`. `time` reste disponible.

use time as _t


const MONDAY := _t.MONDAY
const TUESDAY := _t.TUESDAY
const WEDNESDAY := _t.WEDNESDAY
const THURSDAY := _t.THURSDAY
const FRIDAY := _t.FRIDAY
const SATURDAY := _t.SATURDAY
const SUNDAY := _t.SUNDAY
const SECONDS_PER_MINUTE := _t.SECONDS_PER_MINUTE
const SECONDS_PER_HOUR := _t.SECONDS_PER_HOUR
const SECONDS_PER_DAY := _t.SECONDS_PER_DAY
const SECONDS_PER_WEEK := _t.SECONDS_PER_WEEK
const MICROS_PER_SECOND := _t.MICROS_PER_SECOND
const MICROS_PER_DAY := _t.MICROS_PER_DAY
const UNIX_EPOCH_ORDINAL := _t.UNIX_EPOCH_ORDINAL

set_clock := _t.set_clock
reset_clock := _t.reset_clock
install_fake_clock := _t.install_fake_clock
set_local_zone := _t.set_local_zone
local_utc_offset := _t.local_utc_offset
time := _t.time
time_ns := _t.time_ns
monotonic := _t.monotonic
monotonic_ns := _t.monotonic_ns
perf_counter := _t.perf_counter
sleep := _t.sleep
sleep_until := _t.sleep_until
is_leap := _t.is_leap
days_in_month := _t.days_in_month
days_in_year := _t.days_in_year
days_from_civil := _t.days_from_civil
civil_from_days := _t.civil_from_days
weekday_of_days := _t.weekday_of_days
weekday := _t.weekday
iso_weekday := _t.iso_weekday
yearday := _t.yearday
to_ordinal := _t.to_ordinal
from_ordinal := _t.from_ordinal
weeks_in_year := _t.weeks_in_year
iso_calendar := _t.iso_calendar
iso_to_civil := _t.iso_to_civil
nth_weekday := _t.nth_weekday
easter := _t.easter
month_matrix := _t.month_matrix
month_calendar := _t.month_calendar
split_timestamp := _t.split_timestamp
gmtime := _t.gmtime
localtime := _t.localtime
fields_at_offset := _t.fields_at_offset
timegm := _t.timegm
mktime := _t.mktime
register_locale := _t.register_locale
locales := _t.locales
month_name := _t.month_name
day_name := _t.day_name
format_offset := _t.format_offset
strftime := _t.strftime
asctime := _t.asctime
ctime := _t.ctime
strptime := _t.strptime
parse_iso := _t.parse_iso
parse_iso_time := _t.parse_iso_time
iso_from_fields := _t.iso_from_fields
iso_time_string := _t.iso_time_string
iso_from_timestamp := _t.iso_from_timestamp
parse_iso_timestamp := _t.parse_iso_timestamp
normalize_duration := _t.normalize_duration
seconds_to_parts := _t.seconds_to_parts
parts_to_seconds := _t.parts_to_seconds
duration_parts := _t.duration_parts
parse_duration := _t.parse_duration
format_duration_parts := _t.format_duration_parts
format_duration := _t.format_duration
humanize := _t.humanize
measure := _t.measure
timeit := _t.timeit
benchmark := _t.benchmark
every := _t.every

func Stopwatch(autostart=false):
    return _t.Stopwatch(autostart)

func Deadline(seconds=null):
    return _t.Deadline(seconds)

func FakeClock(start=0):
    return _t.FakeClock(start)
