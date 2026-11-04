# =============================================================================
# ALEX - tests du module stdlib/constants/constants.al
# Valeurs exactes (SI 2019), CODATA 2018, cohérence physique, table de recherche.
#
# Lancer DEPUIS LA RACINE DU PROJET :  ./alex run tests/test_constants.al
# Code de sortie 0 si tout passe, 1 sinon.
# =============================================================================
use constants
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


func t_exact():
    check_eq(constants.C, 299792458.0, "C")
    check_eq(constants.H, 0.000000000000000000000000000000000662607015, "H")
    check_eq(constants.E_CHARGE, 0.0000000000000000001602176634, "E_CHARGE")
    check_eq(constants.K_B, 0.00000000000000000000001380649, "K_B")
    check_eq(constants.N_A, 602214076000000000000000.0, "N_A")
    check_eq(constants.G0, 9.80665, "G0")
    check_eq(constants.ATM, 101325.0, "ATM")
    check_eq(constants.AU, 149597870700.0, "AU")
    check_eq(constants.LIGHT_YEAR, 9460730472580800.0, "LIGHT_YEAR")

func t_derived():
    check_close(constants.HBAR, 0.000000000000000000000000000000000105457181764616, 0.000000000001, "HBAR")
    check_close(constants.HBAR * constants.TAU, constants.H, 0.0000000000000005, "HBAR*TAU == H")
    check_close(constants.R_GAS, 8.31446261815324, 0.000000000000001, "R_GAS")
    check_close(constants.F_FARADAY, 96485.33212331001, 0.000000000000001, "F_FARADAY")
    check_close(constants.SIGMA_SB * 100000000.0, 5.670374419184429, 0.000000000000001, "SIGMA_SB")
    check_close(constants.WIEN_B * 1000.0, 2.897771955185172, 0.000000000000001, "WIEN_B")
    check_close(constants.PARSEC / 10000000000000000.0, 3.0856775814913673, 0.000000000000001, "PARSEC")
    check_eq(constants.EV, constants.E_CHARGE, "EV")

func t_math():
    check_eq(constants.PI, 3.141592653589793, "PI")
    check_eq(constants.TAU, 6.283185307179586, "TAU")
    check_close(constants.E, math.exp(1.0), 0.0000000000000005, "E")
    check_close(constants.PHI * constants.PHI, constants.PHI + 1.0, 0.0000000000000005, "PHI^2 = PHI + 1")
    check_close(constants.SQRT2 * constants.SQRT2, 2.0, 0.0000000000000005, "SQRT2^2")
    check_close(constants.SQRT3 * constants.SQRT3, 3.0, 0.0000000000000005, "SQRT3^2")
    check_close(math.exp(constants.LN2), 2.0, 0.0000000000000005, "exp(LN2)")
    check_close(math.exp(constants.LN10), 10.0, 0.000000000000001, "exp(LN10)")
    check_eq(constants.EULER_GAMMA, 0.5772156649015329, "EULER_GAMMA")
    check_eq(constants.CATALAN, 0.915965594177219, "CATALAN")
    check_eq(constants.APERY, 1.2020569031595942, "APERY")

# Cohérence interne des valeurs CODATA (relations physiques, tolérance 1e-9 : incertitudes ~1e-10).
func t_consistency():
    check_close(constants.MU0 * constants.EPS0 * constants.C * constants.C, 1.0, 0.000000001, "mu0 eps0 c^2 = 1")
    alpha := constants.E_CHARGE * constants.E_CHARGE / (4.0 * constants.PI * constants.EPS0 * constants.HBAR * constants.C)
    check_close(alpha, constants.ALPHA, 0.000000001, "alpha = e^2 / (4 pi eps0 hbar c)")
    bohr := constants.HBAR / (constants.M_E * constants.C * constants.ALPHA)
    check_close(bohr, constants.BOHR_RADIUS, 0.000000001, "a0 = hbar / (me c alpha)")
    rydberg := constants.ALPHA * constants.ALPHA * constants.M_E * constants.C / (2.0 * constants.H)
    check_close(rydberg, constants.RYDBERG, 0.000000001, "R_inf = alpha^2 me c / (2 h)")
    check_close(constants.M_P / constants.M_E, 1836.15267343, 0.0000000001, "mp/me")
    check_close(constants.AMU * constants.N_A * 1000.0, 1.00000000054, 0.000000001, "amu * N_A ~ 1 g/mol")
    check(constants.M_N > constants.M_P, "m_n > m_p")

func t_aliases():
    check_eq(constants.SPEED_OF_LIGHT, constants.C, "alias c")
    check_eq(constants.PLANCK_H, constants.H, "alias h")
    check_eq(constants.PLANCK_HBAR, constants.HBAR, "alias hbar")
    check_eq(constants.BOLTZMANN, constants.K_B, "alias k_B")
    check_eq(constants.AVOGADRO, constants.N_A, "alias N_A")
    check_eq(constants.GAS_CONSTANT, constants.R_GAS, "alias R")
    check_eq(constants.GRAVITATIONAL_CONSTANT, constants.G, "alias G")
    check_eq(constants.ELEMENTARY_CHARGE, constants.E_CHARGE, "alias e")
    check_eq(constants.STANDARD_GRAVITY, constants.G0, "alias g0")
    check_eq(constants.FINE_STRUCTURE, constants.ALPHA, "alias alpha")

func t_lookup():
    row := constants.lookup("Electron Mass")
    check(row != null, "lookup insensible à la casse")
    check_eq(row[0], constants.M_E, "lookup valeur")
    check_eq(row[1], "kg", "lookup unité")
    check(row[2] > 0.0, "lookup incertitude > 0")
    check_eq(constants.lookup("speed of light")[2], 0.0, "incertitude nulle (exacte)")
    check_eq(constants.value("c"), 299792458.0, "value('c')")
    check_eq(constants.value("PLANCK"), constants.H, "value('PLANCK')")
    check_eq(constants.lookup("inconnue"), null, "lookup inconnu -> null")
    check(len(constants.names()) >= 30, "names() fournit la table")

func bad_value():
    constants.value("zzz")

func t_errors():
    check(raises(bad_value), "value() d'un nom inconnu lève ValueError")

run("constantes exactes (SI)", t_exact)
run("constantes dérivées", t_derived)
run("constantes mathématiques", t_math)
run("cohérence CODATA", t_consistency)
run("alias", t_aliases)
run("table de recherche", t_lookup)
run("erreurs", t_errors)
finish("CONSTANTS", 7)
