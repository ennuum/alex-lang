# Modules `time` et `datetime` (ALEX pur)

Deux modules écrits **100 % en ALEX** (`stdlib/time/time.al`, `stdlib/datetime/datetime.al`) ; seul `os` fournit l'horloge
système (`os.time`, `os.monotonic_time`, `os.sleep`, `os.system_time`). Tests : `make test-time test-datetime`
(inclus dans `make test-stdlib-pure`). Démo : `examples/time_demo.al`.

## Sans limite

- **Années** : tout entier, négatif et zéro compris (l'an 0 existe). Calendrier grégorien proleptique en arithmétique
  entière O(1) ; une date est un numéro de jour depuis 1970-01-01, donc jusqu'à ± 2,5 × 10^16 ans.
- **Exactitude** : `Date`, `DateTime`, `Duration` ne passent jamais par un flottant (jours + microsecondes entières).
  `split_timestamp`, `duration_parts`, `timestamp_parts`, `from_timestamp_parts` restent exacts à la microseconde ;
  un `float` seul n'est exact que dans ± 140 ans autour de 1970.
- **Formats** : années `-0044`, `+12345` (ISO 8601 étendu), `%Y` accepte un signe et un nombre quelconque de chiffres.
- **Langues** : en, fr, es, de, it, pt, nl, plus `time.register_locale(code, données)` pour toute autre langue.
- **Fuseaux** : une soixantaine de villes, règles personnalisées (`TimeZone(nom, décalage, économie, règle)`), décalages fixes.

## Vérification

Les calculs sont comparés à Python (`datetime`, `zoneinfo`) par `tools/time/gen_time_vectors.py` → `tests/time_vectors.al` :
414 dates (jour, semaine ISO, ordinal), 120 `strftime` à 29 directives, 27 formes ISO 8601, 2 600 instants dans 10 fuseaux.
En plus, un balayage de 30 200 instants (dont beaucoup autour des changements d'heure) : 0 écart de décalage,
d'abréviation et d'heure murale. Le générateur est reproductible (graine fixe) ; ne pas éditer `time_vectors.al` à la main.

## `time`

| Domaine | Fonctions |
|---|---|
| Horloges | `time monotonic perf_counter time_ns monotonic_ns sleep sleep_until localtime gmtime local_utc_offset` |
| Calendrier | `is_leap days_in_month days_in_year days_from_civil civil_from_days weekday iso_weekday yearday to_ordinal from_ordinal weeks_in_year iso_calendar iso_to_civil nth_weekday easter month_matrix month_calendar` |
| Conversions | `timegm mktime split_timestamp fields_at_offset` (champs hors plage normalisés : mois 14, jour 0, seconde 90) |
| Formats | `strftime strptime asctime ctime parse_iso parse_iso_time iso_from_fields iso_from_timestamp parse_iso_timestamp format_offset` |
| Langues | `month_name day_name register_locale locales` |
| Durées | `parse_duration duration_parts seconds_to_parts format_duration humanize` |
| Outils | `Stopwatch Deadline measure timeit benchmark every` |
| Tests | `set_clock reset_clock install_fake_clock set_local_zone` |

**strftime** : `%Y %y %C %m %d %e %H %I %M %S %f %L %j %u %w %U %W %V %G %g %p %A %a %B %b %h %z %:z %Z %s %n %t %%`
et les composées `%F %T %D %R %r %c %x %X` ; drapeau `-` (`%-d`) sans zéros initiaux. **strptime** : mêmes directives,
espaces souples, noms insensibles à la casse et aux accents (`FÉVRIER`), `%y` 69..99 → 19xx.

**Durées texte** : `1h30m`, `2d 3h`, `1.5h`, `250ms`, `3 semaines et 2 jours`, `PT90M`, `P1DT2H`, `1:30:00`, `2 days, 1:30:00`.
Styles de `format_duration` : `compact` (`1h 30m`), `clock` (`26:03:04.5`), `iso` (`P1DT2H`), `long` (`en`/`fr`).

**Horloge simulée** (tests déterministes, sans attente réelle) :

```alex
fc := time.install_fake_clock(1791360000)
time.sleep(60)            # n'attend pas : fc.now avance de 60
sw := time.Stopwatch(true); fc.advance(5); print(sw.elapsed())   # 5
time.reset_clock()
```

## `datetime`

| Type | Rôle |
|---|---|
| `Duration` | durée exacte (`Duration(days=1, hours=2.5)`), `plus minus times divided ratio floordiv modulo compare format iso` |
| `Period` | durée calendaire (années, mois, jours) ; `period_between(a, b)` ; `apply_to(date)` |
| `TimeZone` | fixe ou à règles d'heure d'été (`eu`, `us`, `au`, `nz`) ; `get_timezone("Europe/Paris" \| "+02:00" \| "UTC-5" \| "paris")` |
| `Date` | jour ; mois/années avec jour ramené en fin de mois ; débuts/fins de semaine, mois, trimestre, année ; jours ouvrés |
| `Time` | heure du jour sans fuseau |
| `DateTime` | naïf ou avec fuseau ; `astimezone with_tz to_utc normalize plus plus_exact diff truncate ceil replace isoformat format rfc2822 http_date humanize` |

Fonctions : `now today now_utc from_timestamp from_timestamp_parts from_iso parse combine date_from_iso date_from_days
date_from_ordinal date_from_iso_week parse_date time_from_iso parse_time date_range datetime_range earliest latest age
easter_date holidays_fr holiday_dates_fr timezone_names fixed_offset local_timezone parse_duration duration_between`.

### À savoir

- **Pas de surcharge d'opérateurs** : `plus / minus / diff / compare / equals / lt / le / gt / ge` ; `==` compare des identités.
- **Pas d'arguments nommés sur un appel de méthode** : `d.replace(null, 2, 28)` (null = inchangé) ; constructeurs et fonctions
  du module acceptent les noms (`Duration(hours=2)`, `from_timestamp(ts, tz="Asia/Tokyo")`).
- **`str(objet)`** n'appelle pas `to_string()` : écrire `objet.isoformat()` ou `objet.to_string()`.
- **Naïf / avec fuseau** : les mélanger dans `compare`/`diff` lève `TypeError`. `timestamp`, `to_utc` lisent un naïf comme UTC ;
  `astimezone` refuse un naïf (utiliser `with_tz`). `now()` et `from_timestamp()` renvoient toujours des objets avec fuseau.
- **`plus` / `plus_exact`** : `plus` avance l'heure affichée (comme Python) ; `plus_exact` compte le temps réellement écoulé et
  traverse les changements d'heure. Exemple (Paris, 29 mars 2026) : `01:30 + 1 h` → `02:30+01:00` (heure inexistante,
  `normalize()` donne `03:30+02:00`) contre `03:30+02:00` avec `plus_exact`.
- **Heure répétée** (retour d'octobre) : `fold = 0` première occurrence, `fold = 1` seconde ; `astimezone` renseigne `fold`.
- **`Date.plus(duration)`** refuse une durée contenant des heures (Python l'ignore silencieusement).

### Limites assumées

- Les règles de fuseau sont les règles **actuelles** étendues à toutes les années (UE depuis 1996, États-Unis depuis 2007…) :
  pas d'historique tzdata, et pas de villes à règles particulières (Le Caire, Casablanca, Santiago, Jérusalem…). Pour un
  autre fuseau : `TimeZone(nom, décalage, économie, règle)`. Règles valables pour |année| < 2,9 × 10^11 (décalages fixes : illimité).
- `time.localtime` / `datetime.local_timezone` utilisent le décalage **actuel** du système (un seul décalage fixe).
- `strptime` consomme sans les exploiter `%U %W %V %G %g %u %w` ; la seconde 60 (intercalaire) est refusée.
- `humanize` et le style `long` : `en` et `fr` seulement.
