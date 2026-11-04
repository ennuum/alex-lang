# =============================================================================
# ALEX - tests d'intégration de la bibliothèque scientifique (Phase 1)
# constants <-> units <-> math <-> complex <-> random
#
# Lancer DEPUIS LA RACINE DU PROJET :  ./alex run tests/test_science_integration.al
# =============================================================================
use constants
use units
use math
use complex
use random
from core use len
from collections use append, clear

stats := [0, 0]
notes := []

func check(cond, label):
    if cond:
        stats[0] = stats[0] + 1
    else:
        stats[1] = stats[1] + 1
        append(notes, label)

func rel(a, b):
    d := a - b
    if d < 0:
        d = 0 - d
    s := b
    if s < 0:
        s = 0 - s
    if s < 1:
        s = 1
    return d / s

# Toute unité déclarée dans la table des constantes est une unité valide pour `units`.
func t_constants_units():
    bad := []
    for name in constants.names():
        row := constants.lookup(name)
        if not units.is_unit(row[1]):
            append(bad, f"{name} -> {row[1]}")
    check(len(bad) == 0, f"unités de constants invalides pour units : {bad}")

# Les dimensions déclarées ont un sens physique.
func t_dimensions():
    check(units.dimension_name(constants.lookup("speed of light")[1]) == "velocity", "c : vitesse")
    check(units.dimension_name(constants.lookup("planck constant")[1]) == "angular momentum", "h : moment cinétique")
    check(units.dimension_name(constants.lookup("electron mass")[1]) == "mass", "m_e : masse")
    check(units.dimension_name(constants.lookup("elementary charge")[1]) == "electric charge", "e : charge")
    check(units.dimension_name(constants.lookup("boltzmann")[1]) == "J/K" or units.compatible(constants.lookup("boltzmann")[1], "J/K"), "k_B : J/K")
    check(units.compatible(constants.lookup("gas constant")[1], "J/(mol*K)"), "R")
    check(units.compatible(constants.lookup("vacuum permittivity")[1], "F/m"), "eps0")
    check(units.compatible(constants.lookup("stefan-boltzmann")[1], "W/(m^2*K^4)"), "sigma")
    check(units.compatible(constants.lookup("gravitational constant")[1], "N*m^2/kg^2"), "G")

# Cohérence entre constants et le registre d'unités (mêmes définitions).
func t_cross_values():
    check(rel(units.convert(1, "eV", "J"), constants.EV) < 0.000000000000001, "eV")
    check(rel(units.convert(1, "atm", "Pa"), constants.ATM) < 0.000000000000001, "atm")
    check(rel(units.convert(1, "au", "m"), constants.AU) < 0.000000000000001, "au")
    check(rel(units.convert(1, "ly", "m"), constants.LIGHT_YEAR) < 0.000000000000001, "année-lumière")
    check(rel(units.convert(1, "pc", "m"), constants.PARSEC) < 0.000000000000001, "parsec")
    check(rel(units.convert(1, "u", "kg"), constants.AMU) < 0.00000000001, "unité de masse atomique")
    check(rel(units.convert(1, "bar", "Pa"), constants.BAR) < 0.000000000000001, "bar")

# Calcul physique complet : énergie d'un photon de 500 nm, en J puis en eV.
func t_photon():
    lam := units.quantity(500, "nm")
    energy := constants.H * constants.C / units.q_to(lam, "m")
    ev := units.convert(energy, "J", "eV")
    check(rel(ev, 2.4796839) < 0.0000001, f"photon 500 nm = {ev} eV")
    # Température de couleur de Wien
    t_sun := constants.WIEN_B / units.q_to(lam, "m")
    check(rel(t_sun, 5795.5439) < 0.000001, f"Wien 500 nm = {t_sun} K")

# Fréquence de résonance d'un circuit LC avec grandeurs et complexes.
func t_circuit():
    l_h := units.q_to(units.quantity(10, "mH"), "H")
    c_f := units.q_to(units.quantity(100, "nF"), "F")
    w0 := 1.0 / math.sqrt(l_h * c_f)
    f0 := units.convert(w0 / constants.TAU, "Hz", "kHz")
    check(rel(f0, 5.032921210448704) < 0.000000000001, f"f0 LC = {f0} kHz")
    # À la résonance, l'impédance série d'un RLC est purement résistive.
    z := complex.new(50.0, w0 * l_h - 1.0 / (w0 * c_f))
    check(math.abs(complex.im(z)) < 0.000000001, "impédance purement résistive à la résonance")
    check(rel(complex.abs(z), 50.0) < 0.000000000001, "|Z| = R")

# Monte-Carlo reproductible + constantes : le résultat est identique d'une exécution à l'autre.
func t_reproducible():
    a := random.new(2026)
    b := random.new(2026)
    ra := random.estimate_pi(2000, a)
    rb := random.estimate_pi(2000, b)
    check(ra[0] == rb[0], "estimate_pi reproductible")
    check(math.abs(ra[0] - constants.PI) < 5.0 * ra[1] + 0.000001, f"pi estimé {ra[0]}")

# Racines de l'unité (complex) tirées au hasard (random) : toutes de module 1.
func t_random_complex():
    g := random.new(8)
    roots := complex.roots_of_unity(12)
    ok := true
    i := 0
    while i < 100:
        z := random.choice(roots, g)
        if rel(complex.abs(z), 1.0) > 0.000000000000005:
            ok = false
        i += 1
    check(ok, "|racine de l'unité| = 1")

func run(name, fn):
    clear(notes)
    before := stats[1]
    fn()
    if stats[1] > before:
        print(f"  [ÉCHEC]  {name}")
        for n in notes:
            print(f"      {n}")
    else:
        print(f"  [OK]     {name}")

run("unités de constants valides pour units", t_constants_units)
run("sens physique des dimensions", t_dimensions)
run("valeurs concordantes constants/units", t_cross_values)
run("photon (h c / lambda)", t_photon)
run("circuit LC/RLC (units + complex + math)", t_circuit)
run("Monte-Carlo reproductible", t_reproducible)
run("random + complex", t_random_complex)
print("")
print(f"=== INTÉGRATION SCIENTIFIQUE ===")
print(f"Vérifications : {stats[0]} réussies, {stats[1]} en échec (sur {stats[0] + stats[1]})")
if stats[1] > 0:
    raise("AssertionError", "intégration scientifique : échecs")
print("TOUS LES TESTS D'INTEGRATION PASSENT")
