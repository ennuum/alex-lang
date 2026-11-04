# =============================================================================
# ALEX - tests du module stdlib/units/units.al
# Analyse d'expressions d'unités, conversions (linéaires et affines), dimensions, grandeurs, erreurs.
#
# Lancer DEPUIS LA RACINE DU PROJET :  ./alex run tests/test_units.al
# Code de sortie 0 si tout passe, 1 sinon.
# =============================================================================
use units
use math

from core use len
from collections use append, clear

stats := [0, 0]
notes := []
failed_groups := []

func ok():
    stats[0] = stats[0] + 1

func fail(label, detail):
    stats[1] = stats[1] + 1
    append(notes, f"{label} : {detail}")

func abs_val(v):
    if v < 0:
        return 0 - v
    return v

func check(cond, label):
    if cond:
        ok()
    else:
        fail(label, "condition fausse")

func check_eq(actual, expected, label):
    if actual == expected:
        ok()
    else:
        fail(label, f"obtenu {actual}, attendu {expected}")

# Erreur relative (absolue si |attendu| < 1).
func check_close(actual, expected, tol, label):
    if actual == null:
        fail(label, f"obtenu null, attendu {expected}")
    else:
        scale := abs_val(expected)
        if scale < 1:
            scale = 1
        if abs_val(actual - expected) <= tol * scale:
            ok()
        else:
            fail(label, f"obtenu {actual}, attendu {expected}")

func check_list_close(actual, expected, tol, label):
    if len(actual) != len(expected):
        fail(label, f"longueurs {len(actual)} et {len(expected)}")
    else:
        i := 0
        while i < len(actual):
            check_close(actual[i], expected[i], tol, f"{label}[{i}]")
            i += 1

func run(name, fn):
    clear(notes)
    before := stats[1]
    fn()
    if stats[1] > before:
        append(failed_groups, name)
        print(f"  [ÉCHEC]  {name}")
        for n in notes:
            print(f"      {n}")
    else:
        print(f"  [OK]     {name}")

# Vrai si fn() (sans argument) lève une erreur.
func raises(fn):
    threw := false
    try:
        fn()
    catch e:
        threw = true
    return threw

func finish(title, groups):
    total := stats[0] + stats[1]
    print("")
    print(f"=== {title} ===")
    print(f"Groupes : {groups}, vérifications : {stats[0]} réussies, {stats[1]} en échec (sur {total})")
    if stats[1] > 0:
        print(f"Groupes en échec : {failed_groups}")
        raise("AssertionError", f"{stats[1]} vérification(s) en échec")
    print(f"TOUS LES TESTS {title} PASSENT")

func t_linear():
    check_close(units.convert(1, "km", "m"), 1000.0, 0.000000000000005, "1 km -> m")
    check_close(units.convert(1, "mi", "km"), 1.609344, 0.000000000000005, "1 mi -> km")
    check_close(units.convert(1, "ft", "in"), 12.0, 0.000000000000005, "1 ft -> in")
    check_close(units.convert(1, "yd", "ft"), 3.0, 0.000000000000005, "1 yd -> ft")
    check_close(units.convert(1, "nmi", "m"), 1852.0, 0.000000000000005, "1 nmi -> m")
    check_close(units.convert(1, "au", "m"), 149597870700.0, 0.000000000000005, "1 au -> m")
    check_close(units.convert(1, "ly", "m"), 9460730472580800.0, 0.000000000000005, "1 ly -> m")
    check_close(units.convert(1, "pc", "au"), 206264.80624709636, 0.000000000000005, "1 pc -> au")
    check_close(units.convert(1, "angstrom", "nm"), 0.1, 0.000000000000005, "1 angstrom -> nm")
    check_close(units.convert(5, "mg", "g"), 0.005, 0.000000000000005, "5 mg -> g")
    check_close(units.convert(1, "lb", "kg"), 0.45359237, 0.000000000000005, "1 lb -> kg")
    check_close(units.convert(1, "oz", "g"), 28.349523125, 0.000000000000005, "1 oz -> g")
    check_close(units.convert(1, "t", "kg"), 1000.0, 0.000000000000005, "1 t -> kg")
    check_close(units.convert(1, "u", "kg"), 0.0000000000000000000000000016605390666, 0.000000000000005, "1 u -> kg")
    check_close(units.convert(1, "h", "s"), 3600.0, 0.000000000000005, "1 h -> s")
    check_close(units.convert(1, "d", "h"), 24.0, 0.000000000000005, "1 d -> h")
    check_close(units.convert(1, "wk", "d"), 7.0, 0.000000000000005, "1 wk -> d")
    check_close(units.convert(1, "yr", "d"), 365.25, 0.000000000000005, "1 yr -> d")
    check_close(units.convert(90, "min", "h"), 1.5, 0.000000000000005, "90 min -> h")
    check_close(units.convert(1, "kHz", "Hz"), 1000.0, 0.000000000000005, "1 kHz -> Hz")
    check_close(units.convert(2, "GHz", "MHz"), 2000.0, 0.000000000000005, "2 GHz -> MHz")
    check_close(units.convert(60, "rpm", "Hz"), 1.0, 0.000000000000005, "60 rpm -> Hz")
    check_close(units.convert(1, "kN", "N"), 1000.0, 0.000000000000005, "1 kN -> N")
    check_close(units.convert(1, "lbf", "N"), 4.4482216152605, 0.000000000000005, "1 lbf -> N")
    check_close(units.convert(1, "kgf", "N"), 9.80665, 0.000000000000005, "1 kgf -> N")
    check_close(units.convert(1, "dyn", "N"), 0.00001, 0.000000000000005, "1 dyn -> N")
    check_close(units.convert(1, "atm", "Pa"), 101325.0, 0.000000000000005, "1 atm -> Pa")
    check_close(units.convert(1, "bar", "kPa"), 100.0, 0.000000000000005, "1 bar -> kPa")
    check_close(units.convert(1, "atm", "mmHg"), 759.9998917256113, 0.000000000000005, "1 atm -> mmHg")
    check_close(units.convert(1, "psi", "Pa"), 6894.757293168362, 0.000000000000005, "1 psi -> Pa")
    check_close(units.convert(1, "torr", "Pa"), 133.32236842105263, 0.000000000000005, "1 torr -> Pa")
    check_close(units.convert(1, "kJ", "J"), 1000.0, 0.000000000000005, "1 kJ -> J")
    check_close(units.convert(1, "kWh", "J"), 3600000.0, 0.000000000000005, "1 kWh -> J")
    check_close(units.convert(1, "cal", "J"), 4.184, 0.000000000000005, "1 cal -> J")
    check_close(units.convert(1, "eV", "J"), 0.0000000000000000001602176634, 0.000000000000005, "1 eV -> J")
    check_close(units.convert(1, "BTU", "J"), 1055.05585262, 0.000000000000005, "1 BTU -> J")
    check_close(units.convert(1, "hp", "W"), 745.6998715822702, 0.000000000000005, "1 hp -> W")
    check_close(units.convert(1, "kW", "W"), 1000.0, 0.000000000000005, "1 kW -> W")
    check_close(units.convert(1, "mA", "A"), 0.001, 0.000000000000005, "1 mA -> A")
    check_close(units.convert(1, "Ah", "C"), 3600.0, 0.000000000000005, "1 Ah -> C")
    check_close(units.convert(1, "kV", "V"), 1000.0, 0.000000000000005, "1 kV -> V")
    check_close(units.convert(1, "mF", "F"), 0.001, 0.000000000000005, "1 mF -> F")
    check_close(units.convert(1, "kohm", "ohm"), 1000.0, 0.000000000000005, "1 kohm -> ohm")
    check_close(units.convert(1, "mT", "T"), 0.001, 0.000000000000005, "1 mT -> T")
    check_close(units.convert(1, "L", "m^3"), 0.001, 0.000000000000005, "1 L -> m^3")
    check_close(units.convert(1, "mL", "cm^3"), 1.0, 0.000000000000005, "1 mL -> cm^3")
    check_close(units.convert(1, "gal", "L"), 3.785411784, 0.000000000000005, "1 gal -> L")
    check_close(units.convert(1, "qt", "gal"), 0.25, 0.000000000000005, "1 qt -> gal")
    check_close(units.convert(1, "cup", "floz"), 8.0, 0.000000000000005, "1 cup -> floz")
    check_close(units.convert(1, "tbsp", "tsp"), 3.0, 0.000000000000005, "1 tbsp -> tsp")
    check_close(units.convert(1, "ha", "m^2"), 10000.0, 0.000000000000005, "1 ha -> m^2")
    check_close(units.convert(1, "acre", "m^2"), 4046.8564224, 0.000000000000005, "1 acre -> m^2")
    check_close(units.convert(1, "km^2", "m^2"), 1000000.0, 0.000000000000005, "1 km^2 -> m^2")
    check_close(units.convert(1, "cm^3", "m^3"), 0.000001, 0.000000000000005, "1 cm^3 -> m^3")
    check_close(units.convert(180, "deg", "rad"), 3.141592653589793, 0.000000000000005, "180 deg -> rad")
    check_close(units.convert(1, "turn", "deg"), 360.0, 0.000000000000005, "1 turn -> deg")
    check_close(units.convert(1, "arcmin", "arcsec"), 60.0, 0.000000000000005, "1 arcmin -> arcsec")
    check_close(units.convert(200, "grad", "deg"), 180.0, 0.000000000000005, "200 grad -> deg")
    check_close(units.convert(100, "km/h", "m/s"), 27.77777777777778, 0.000000000000005, "100 km/h -> m/s")
    check_close(units.convert(1, "kn", "km/h"), 1.852, 0.000000000000005, "1 kn -> km/h")
    check_close(units.convert(1, "m/s^2", "km/h/s"), 3.6, 0.000000000000005, "1 m/s^2 -> km/h/s")
    check_close(units.convert(1, "g/cm^3", "kg/m^3"), 1000.0, 0.000000000000005, "1 g/cm^3 -> kg/m^3")
    check_close(units.convert(1, "kg*m/s^2", "N"), 1.0, 0.000000000000005, "1 kg*m/s^2 -> N")
    check_close(units.convert(1, "N*m", "J"), 1.0, 0.000000000000005, "1 N*m -> J")
    check_close(units.convert(1, "W*s", "J"), 1.0, 0.000000000000005, "1 W*s -> J")
    check_close(units.convert(1, "V*A", "W"), 1.0, 0.000000000000005, "1 V*A -> W")
    check_close(units.convert(1, "J/s", "W"), 1.0, 0.000000000000005, "1 J/s -> W")
    check_close(units.convert(1, "J/(mol*K)", "cal/(mol*K)"), 0.2390057361376673, 0.000000000000005, "1 J/(mol*K) -> cal/(mol*K)")
    check_close(units.convert(1, "kg m^2/s^2", "J"), 1.0, 0.000000000000005, "1 kg m^2/s^2 -> J")
    check_close(units.convert(1, "m*kg/s^2", "N"), 1.0, 0.000000000000005, "1 m*kg/s^2 -> N")
    check_close(units.convert(1, "1/s", "Hz"), 1.0, 0.000000000000005, "1 1/s -> Hz")
    check_close(units.convert(50, "%", "1"), 0.5, 0.000000000000005, "50 % -> 1")
    check_close(units.convert(3, "ppm", "1"), 0.000003, 0.000000000000005, "3 ppm -> 1")
    check_close(units.convert(1, "Wh", "kJ"), 3.6, 0.000000000000005, "1 Wh -> kJ")
    check_close(units.convert(1, "MPa", "bar"), 10.0, 0.000000000000005, "1 MPa -> bar")
    check_close(units.convert(1, "µm", "nm"), 1000.0, 0.000000000000005, "1 µm -> nm")
    check_close(units.convert(1, "µs", "ns"), 1000.0, 0.000000000000005, "1 µs -> ns")
    check_close(units.convert(1, "pm", "angstrom"), 0.01, 0.000000000000005, "1 pm -> angstrom")
    check_close(units.convert(1, "hPa", "Pa"), 100.0, 0.000000000000005, "1 hPa -> Pa")
    check_close(units.convert(1, "daN", "N"), 10.0, 0.000000000000005, "1 daN -> N")
    check_close(units.convert(1, "dm", "cm"), 10.0, 0.000000000000005, "1 dm -> cm")

func t_temperature():
    check_close(units.convert(0.0, "degC", "K"), 273.15, 0.00000000000001, "0 degC -> K")
    check_close(units.convert(100.0, "degC", "degF"), 212.0, 0.00000000000001, "100 degC -> degF")
    check_close(units.convert(32.0, "degF", "degC"), 0.0, 0.00000000000001, "32 degF -> degC")
    check_close(units.convert(-40.0, "degC", "degF"), -40.0, 0.00000000000001, "-40 degC -> degF")
    check_close(units.convert(-40.0, "degF", "degC"), -40.0, 0.00000000000001, "-40 degF -> degC")
    check_close(units.convert(98.6, "degF", "K"), 310.15, 0.00000000000001, "98.6 degF -> K")
    check_close(units.convert(300.0, "K", "degF"), 80.33, 0.00000000000001, "300 K -> degF")
    check_close(units.convert(0.0, "K", "degC"), -273.15, 0.00000000000001, "0 K -> degC")
    check_close(units.convert(25.0, "degC", "K"), 298.15, 0.00000000000001, "25 degC -> K")
    check_close(units.convert(-459.67, "degF", "K"), 0.0, 0.00000000000001, "-459.67 degF -> K")
    check_close(units.convert(671.67, "degR", "K"), 373.15, 0.00000000000001, "671.67 degR -> K")
    check_close(units.convert(373.15, "K", "degR"), 671.67, 0.00000000000001, "373.15 K -> degR")
    check_close(units.convert(0.0, "degC", "degR"), 491.67, 0.00000000000001, "0 degC -> degR")
    check_close(units.convert(1.0, "°C", "°F"), 33.8, 0.00000000000001, "1 °C -> °F")
    check_close(units.convert(212.0, "°F", "°C"), 100.0, 0.00000000000001, "212 °F -> °C")
    check_eq(units.convert(100, "degC", "degF"), 212.0, "100 degC -> 212 degF exact")
    check_eq(units.convert(32, "degF", "degC"), 0.0, "32 degF -> 0 degC exact")
    check_close(units.convert(10, "K", "K"), 10.0, 0.000000000000001, "K -> K")
    check_close(units.convert(10, "mK", "K"), 0.01, 0.000000000000001, "mK -> K")

func t_dimensions():
    check_eq(units.dimension("N"), [1, 1, -2, 0, 0, 0, 0], "dimension N")
    check_eq(units.dimension("kg*m/s^2"), [1, 1, -2, 0, 0, 0, 0], "dimension kg*m/s^2")
    check_eq(units.dimension("J/(mol*K)"), [2, 1, -2, 0, -1, -1, 0], "dimension J/(mol*K)")
    check_eq(units.dimension("1/s"), [0, 0, -1, 0, 0, 0, 0], "dimension 1/s")
    check_eq(units.dimension("rad"), [0, 0, 0, 0, 0, 0, 0], "rad sans dimension")
    check_eq(units.dimension(""), [0, 0, 0, 0, 0, 0, 0], "chaîne vide = sans dimension")
    check_eq(units.dimension_name("N"), "force", "nom : force")
    check_eq(units.dimension_name("W/A"), "voltage", "nom : tension")
    check_eq(units.dimension_name("kg*m^2/s^2"), "energy", "nom : énergie")
    check_eq(units.dimension_name("m/s"), "velocity", "nom : vitesse")
    check_eq(units.dimension_name("Pa"), "pressure", "nom : pression")
    check_eq(units.dimension_name("m"), "length", "nom : longueur")
    check_eq(units.dimension_name("K"), "temperature", "nom : température")
    check_eq(units.dimension_name("m^3/s"), "m^3/s", "dimension sans nom -> écriture en unités de base")
    check_eq(units.dimension_name("kg*m/(s*K)"), "kg*m/(s*K)", "écriture avec dénominateur composé")
    check(units.compatible("N*m", "J"), "N*m ~ J")
    check(units.compatible("km/h", "m/s"), "km/h ~ m/s")
    check(not units.compatible("m", "s"), "m !~ s")
    check(not units.compatible("N", "J"), "N !~ J")
    check(units.is_unit("m/s"), "is_unit valide")
    check(not units.is_unit("m//s"), "is_unit : // invalide")
    check(not units.is_unit("(m"), "is_unit : parenthèse")
    check(not units.is_unit("zorglub"), "is_unit : inconnue")
    check(units.is_unit("mm^2"), "mm^2")
    check(units.is_unit("m^-2"), "m^-2")
    check(units.is_unit("µs"), "µs")
    check(not units.is_unit("degC*m"), "unité à décalage non combinable")
    check(not units.is_unit("degC^2"), "unité à décalage non élevable")

func t_syntax():
    # priorité gauche-droite, parenthèses, espaces, puissances négatives
    check_close(units.convert(1, "m/s/s", "m/s^2"), 1.0, 0.000000000000001, "m/s/s")
    check_close(units.convert(1, "m^2/s", "m*m/s"), 1.0, 0.000000000000001, "m^2/s")
    check_close(units.convert(1, "kg/(m*s^2)", "Pa"), 1.0, 0.000000000000001, "kg/(m*s^2)")
    check_close(units.convert(1, "kg m^-1 s^-2", "Pa"), 1.0, 0.000000000000001, "puissances négatives")
    check_close(units.convert(1, "  km  /  h ", "m/s") * 3.6, 1.0, 0.000000000000001, "espaces")
    check_close(units.convert(1, "N·m", "J"), 1.0, 0.000000000000001, "point médian")
    check_close(units.convert(1, "(km)", "m"), 1000.0, 0.000000000000001, "parenthèses")
    check_close(units.convert(3, "2*m", "m"), 6.0, 0.000000000000001, "facteur numérique")
    check_close(units.convert(1, "dam", "m"), 10.0, 0.000000000000001, "préfixe da")
    check_close(units.convert(1, "min", "s"), 60.0, 0.000000000000001, "min est une minute (pas milli-inch)")
    check_close(units.convert(1, "mmol", "mol"), 0.001, 0.000000000000001, "mmol")
    check_close(units.convert(1, "Pa", "N/m^2"), 1.0, 0.000000000000001, "Pa = N/m^2")
    check_close(units.convert(1, "T", "kg/(A*s^2)"), 1.0, 0.000000000000001, "tesla")

func t_convert_all():
    out := units.convert_all([0, 50, 100], "degC", "degF")
    check_list_close(out, [32.0, 122.0, 212.0], 0.00000000000001, "convert_all")
    check_eq(units.convert_all([], "m", "km"), [], "convert_all vide")

func t_quantities():
    d := units.quantity(5, "km")
    t := units.quantity(30, "min")
    v := units.q_div(d, t)
    check_close(units.q_to(v, "km/h"), 10.0, 0.000000000000001, "5 km / 30 min = 10 km/h")
    check_close(units.q_to(v, "m/s"), 2.7777777777777777, 0.000000000000001, "... en m/s")
    check_eq(units.dimension_name(v[1]), "velocity", "dimension du quotient")
    check_eq(units.q_str(v, "km/h"), "10.0 km/h", "q_str")
    s := units.q_add(units.quantity(1, "m"), units.quantity(50, "cm"))
    check_close(units.q_to(s, "cm"), 150.0, 0.000000000000001, "1 m + 50 cm")
    check_eq(units.q_str(s), "1.5 m", "q_str unité d'origine")
    diff := units.q_sub(units.quantity(1, "h"), units.quantity(15, "min"))
    check_close(units.q_to(diff, "min"), 45.0, 0.000000000000001, "1 h - 15 min")
    f := units.q_mul(units.quantity(2, "kg"), units.quantity(9.80665, "m/s^2"))
    check_close(units.q_to(f, "N"), 19.6133, 0.000000000000001, "m a = F")
    check_close(units.q_to(f, "lbf"), 4.409245243697551, 0.000000000000005, "F en lbf")
    e := units.q_mul(f, units.quantity(3, "m"))
    check_close(units.q_to(e, "J"), 58.8399, 0.000000000000001, "travail W = F d")
    check_eq(units.dimension_name(e[1]), "energy", "dimension du travail")
    ratio := units.q_div(units.quantity(1, "km"), units.quantity(500, "m"))
    check_close(ratio[0], 2.0, 0.000000000000001, "rapport sans dimension")
    check_eq(ratio[1], [0, 0, 0, 0, 0, 0, 0], "dimensions du rapport")
    sq := units.q_pow(units.quantity(3, "m"), 2)
    check_close(units.q_to(sq, "m^2"), 9.0, 0.000000000000001, "q_pow")
    check_close(units.q_to(units.q_scale(units.quantity(2, "kg"), 3), "kg"), 6.0, 0.000000000000001, "q_scale")
    check_close(units.q_to(units.q_neg(units.quantity(2, "kg")), "g"), -2000.0, 0.000000000000001, "q_neg")
    inch_ := units.q_in(units.quantity(1, "m"), "cm")
    check_eq(units.q_str(inch_), "100.0 cm", "q_in")
    check_eq(units.q_cmp(units.quantity(1, "km"), units.quantity(999, "m")), 1, "q_cmp >")
    check_eq(units.q_cmp(units.quantity(1, "km"), units.quantity(1000, "m")), 0, "q_cmp =")
    check_eq(units.q_cmp(units.quantity(1, "m"), units.quantity(1, "km")), -1, "q_cmp <")
    check(units.q_is_close(units.quantity(1, "km"), units.quantity(1000.0000001, "m")), "q_is_close")
    temp := units.quantity(25, "degC")
    check_close(units.q_to(temp, "K"), 298.15, 0.000000000000001, "grandeur en degC -> K")
    check_close(units.q_to(temp, "degF"), 77.0, 0.00000000000001, "grandeur en degC -> degF")
    check_eq(units.quantity(1, "m")[1], [1, 0, 0, 0, 0, 0, 0], "dimensions d'une grandeur")

func e_incompat():
    units.convert(1, "m", "s")
func e_unknown():
    units.convert(1, "furlongs", "m")
func e_add():
    units.q_add(units.quantity(1, "m"), units.quantity(1, "s"))
func e_affine_add():
    units.q_add(units.quantity(1, "degC"), units.quantity(1, "degC"))
func e_affine_mul():
    units.q_mul(units.quantity(1, "degF"), units.quantity(2, "m"))
func e_to():
    units.q_to(units.quantity(1, "m"), "kg")
func e_parse_type():
    units.parse(5)
func e_syntax():
    units.parse("m/")
func e_exp():
    units.parse("m^x")
func e_zero():
    units.q_div(units.quantity(1, "m"), units.quantity(0, "s"))
func e_cmp():
    units.q_cmp(units.quantity(1, "m"), units.quantity(1, "s"))
func e_pow_float():
    units.q_pow(units.quantity(1, "m"), 1.5)

func t_errors():
    check(raises(e_incompat), "convert m -> s")
    check(raises(e_unknown), "unité inconnue")
    check(raises(e_add), "q_add incompatibles")
    check(raises(e_affine_add), "q_add sur degC")
    check(raises(e_affine_mul), "q_mul sur degF")
    check(raises(e_to), "q_to incompatible")
    check(raises(e_parse_type), "parse(5)")
    check(raises(e_syntax), "syntaxe 'm/'")
    check(raises(e_exp), "exposant non entier")
    check(raises(e_zero), "q_div par zéro")
    check(raises(e_cmp), "q_cmp incompatibles")
    check(raises(e_pow_float), "q_pow exposant flottant")

func t_registry():
    names := units.list_units()
    check(len(names) >= 90, "registre fourni")
    ok := true
    for n in names:
        if not units.is_unit(n):
            ok = false
            print("  unité du registre invalide :", n)
    check(ok, "toutes les unités du registre se parsent")
    # chaque unité préfixable accepte 'k' : kHz, kPa... (sans exiger de vérifier chaque combinaison)
    check(units.is_unit("kHz") and units.is_unit("kPa") and units.is_unit("GJ") and units.is_unit("ms"), "préfixes courants")
    check(not units.is_unit("kmi"), "'kmi' : mi n'est pas préfixable")
    check(not units.is_unit("kft"), "'kft' : ft n'est pas préfixable")

run("conversions linéaires", t_linear)
run("températures (affines)", t_temperature)
run("dimensions et noms", t_dimensions)
run("syntaxe des expressions", t_syntax)
run("convert_all", t_convert_all)
run("grandeurs (valeur + unité)", t_quantities)
run("registre", t_registry)
run("erreurs", t_errors)
finish("UNITS", 8)
