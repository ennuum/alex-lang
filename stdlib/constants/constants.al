from string use lower
from collections use append

# ALEX STANDARD LIBRARY - constants
# Constantes mathématiques et physiques. Pure ALEX, aucune dépendance native.
#
#   use constants
#   print(constants.C, constants.PLANCK_HBAR)
#   v := constants.lookup("electron mass")   # [valeur, unité, incertitude relative, description]
#
# Sources : définition du SI (2019) pour les valeurs EXACTES ; CODATA 2018 (NIST) pour les valeurs mesurées.
# Les constantes dérivées (HBAR, R_GAS, SIGMA_SB, F_FARADAY, ...) sont CALCULÉES à partir des constantes exactes :
# elles restent donc exactes au sens de l'arithmétique flottante. Toutes les valeurs sont en unités SI.
# Le langage n'ayant pas de notation exponentielle, les littéraux sont écrits en décimal pur
# (générés mécaniquement : ne pas les éditer à la main).
#
# Convention : incertitude relative = 0.0 pour une valeur exacte.

# --- Constantes mathématiques ---
const PI := 3.14159265358979323846264338327950288
const TAU := 6.28318530717958647692528676655900577
const E := 2.71828182845904523536028747135266250
const PHI := 1.61803398874989484820458683436563812
const EULER_GAMMA := 0.57721566490153286060651209008240243
const SQRT2 := 1.41421356237309504880168872420969808
const SQRT3 := 1.73205080756887729352744634150587237
const LN2 := 0.69314718055994530941723212145817657
const LN10 := 2.30258509299404568401799145468436421
const CATALAN := 0.91596559417721901505460351493238411
const APERY := 1.20205690315959428539973816151144999
const FEIGENBAUM_DELTA := 4.66920160910299067185320382046620161

# --- Constantes physiques EXACTES (définition du SI) ---
const C := 299792458.0   # m/s : vitesse de la lumière dans le vide
const H := 0.000000000000000000000000000000000662607015   # J*s : constante de Planck
const E_CHARGE := 0.0000000000000000001602176634   # C : charge élémentaire
const K_B := 0.00000000000000000000001380649   # J/K : constante de Boltzmann
const N_A := 602214076000000000000000.0   # 1/mol : constante d'Avogadro
const G0 := 9.80665   # m/s^2 : accélération normale de la pesanteur
const ATM := 101325.0   # Pa : atmosphère normale
const BAR := 100000.0   # Pa : bar
const AU := 149597870700.0   # m : unité astronomique (IAU 2012)
const LIGHT_YEAR := 9460730472580800.0   # m : année-lumière (365,25 j x c)

# --- Constantes dérivées (calculées, exactes) ---
const HBAR := H / TAU                      # J*s : constante de Planck réduite
const R_GAS := N_A * K_B                   # J/(mol*K) : constante des gaz parfaits
const F_FARADAY := N_A * E_CHARGE          # C/mol : constante de Faraday
const SIGMA_SB := 2.0 * PI ** 5 * K_B ** 4 / (15.0 * H ** 3 * C ** 2)   # W/(m^2*K^4) : Stefan-Boltzmann
const WIEN_B := H * C / (K_B * 4.96511423174427630369)   # m*K : déplacement de Wien (4,9651... = racine de (x-5)e^x + 5)
const EV := E_CHARGE                       # J : électron-volt
const PARSEC := AU * 648000.0 / PI         # m : parsec
const GAUSS_K := 0.01720209895             # constante gravitationnelle gaussienne (rad/jour)

# --- Constantes physiques MESURÉES (CODATA 2018) ---
const G := 0.0000000000667430   # m^3/(kg*s^2) : constante gravitationnelle
const EPS0 := 0.0000000000088541878128   # F/m : permittivité du vide
const MU0 := 0.00000125663706212   # N/A^2 : perméabilité du vide
const M_E := 0.00000000000000000000000000000091093837015   # kg : masse de l'électron
const M_P := 0.00000000000000000000000000167262192369   # kg : masse du proton
const M_N := 0.00000000000000000000000000167492749804   # kg : masse du neutron
const AMU := 0.00000000000000000000000000166053906660   # kg : unité de masse atomique unifiée
const ALPHA := 0.0072973525693   # 1 : constante de structure fine
const RYDBERG := 10973731.568160   # 1/m : constante de Rydberg
const BOHR_RADIUS := 0.0000000000529177210903   # m : rayon de Bohr
const GM_SUN := 132712440000000000000.0   # m^3/s^2 : paramètre gravitationnel nominal du Soleil (IAU 2015)
const R_EARTH := 6378137.0   # m : rayon équatorial terrestre (WGS 84)

# Alias lisibles
const PLANCK_H := H
const PLANCK_HBAR := HBAR
const SPEED_OF_LIGHT := C
const BOLTZMANN := K_B
const AVOGADRO := N_A
const GAS_CONSTANT := R_GAS
const GRAVITATIONAL_CONSTANT := G
const ELEMENTARY_CHARGE := E_CHARGE
const STANDARD_GRAVITY := G0
const FINE_STRUCTURE := ALPHA

# --- Table de recherche : nom -> [valeur, unité, incertitude relative, description] ---
# Les unités sont écrites dans la syntaxe du module `units`.
const _TABLE := {
    "c": [C, "m/s", 0.0, "vitesse de la lumière dans le vide"],
    "h": [H, "J*s", 0.0, "constante de Planck"],
    "e charge": [E_CHARGE, "C", 0.0, "charge élémentaire"],
    "k b": [K_B, "J/K", 0.0, "constante de Boltzmann"],
    "n a": [N_A, "1/mol", 0.0, "constante d'Avogadro"],
    "g0": [G0, "m/s^2", 0.0, "accélération normale de la pesanteur"],
    "atm": [ATM, "Pa", 0.0, "atmosphère normale"],
    "bar": [BAR, "Pa", 0.0, "bar"],
    "au": [AU, "m", 0.0, "unité astronomique (IAU 2012)"],
    "light year": [LIGHT_YEAR, "m", 0.0, "année-lumière (365,25 j x c)"],
    "hbar": [HBAR, "J*s", 0.0, "constante de Planck réduite"],
    "gas constant": [R_GAS, "J/(mol*K)", 0.0, "constante des gaz parfaits"],
    "faraday": [F_FARADAY, "C/mol", 0.0, "constante de Faraday"],
    "stefan-boltzmann": [SIGMA_SB, "W/(m^2*K^4)", 0.0, "constante de Stefan-Boltzmann"],
    "wien": [WIEN_B, "m*K", 0.0, "constante de déplacement de Wien"],
    "parsec": [PARSEC, "m", 0.0, "parsec"],
    "ev": [EV, "J", 0.0, "électron-volt"],
    "g": [G, "m^3/(kg*s^2)", 0.000022, "constante gravitationnelle"],
    "eps0": [EPS0, "F/m", 0.00000000015, "permittivité du vide"],
    "mu0": [MU0, "N/A^2", 0.00000000015, "perméabilité du vide"],
    "m e": [M_E, "kg", 0.00000000030, "masse de l'électron"],
    "m p": [M_P, "kg", 0.00000000031, "masse du proton"],
    "m n": [M_N, "kg", 0.00000000057, "masse du neutron"],
    "amu": [AMU, "kg", 0.00000000030, "unité de masse atomique unifiée"],
    "alpha": [ALPHA, "1", 0.00000000015, "constante de structure fine"],
    "rydberg": [RYDBERG, "1/m", 0.0000000000019, "constante de Rydberg"],
    "bohr radius": [BOHR_RADIUS, "m", 0.00000000015, "rayon de Bohr"],
    "gm sun": [GM_SUN, "m^3/s^2", 0.0, "paramètre gravitationnel nominal du Soleil (IAU 2015)"],
    "r earth": [R_EARTH, "m", 0.0, "rayon équatorial terrestre (WGS 84)"],
    "planck": [H, "J*s", 0.0, "constante de Planck"],
    "planck constant": [H, "J*s", 0.0, "constante de Planck"],
    "reduced planck constant": [HBAR, "J*s", 0.0, "constante de Planck réduite"],
    "speed of light": [C, "m/s", 0.0, "vitesse de la lumière dans le vide"],
    "boltzmann": [K_B, "J/K", 0.0, "constante de Boltzmann"],
    "boltzmann constant": [K_B, "J/K", 0.0, "constante de Boltzmann"],
    "avogadro": [N_A, "1/mol", 0.0, "constante d'Avogadro"],
    "avogadro constant": [N_A, "1/mol", 0.0, "constante d'Avogadro"],
    "electron mass": [M_E, "kg", 0.00000000030, "masse de l'électron"],
    "proton mass": [M_P, "kg", 0.00000000031, "masse du proton"],
    "neutron mass": [M_N, "kg", 0.00000000057, "masse du neutron"],
    "fine structure": [ALPHA, "1", 0.00000000015, "constante de structure fine"],
    "fine structure constant": [ALPHA, "1", 0.00000000015, "constante de structure fine"],
    "elementary charge": [E_CHARGE, "C", 0.0, "charge élémentaire"],
    "standard gravity": [G0, "m/s^2", 0.0, "accélération normale de la pesanteur"],
    "gravitational constant": [G, "m^3/(kg*s^2)", 0.000022, "constante gravitationnelle"],
    "vacuum permittivity": [EPS0, "F/m", 0.00000000015, "permittivité du vide"],
    "vacuum permeability": [MU0, "N/A^2", 0.00000000015, "perméabilité du vide"],
    "atomic mass unit": [AMU, "kg", 0.00000000030, "unité de masse atomique unifiée"],
    "rydberg constant": [RYDBERG, "1/m", 0.0000000000019, "constante de Rydberg"],
    "electron volt": [EV, "J", 0.0, "électron-volt"],
    "faraday constant": [F_FARADAY, "C/mol", 0.0, "constante de Faraday"]
}

# Cherche une constante par son nom (insensible à la casse). Renvoie [valeur, unité, incertitude relative,
# description], ou null si le nom est inconnu.
func lookup(name):
    key := lower(name)
    try:
        return _TABLE[key]
    catch e:
        return null

# Valeur seule d'une constante ; lève ValueError si le nom est inconnu.
func value(name):
    row := lookup(name)
    if row == null:
        raise("ValueError", "constante inconnue : " + name)
    return row[0]

# Liste des noms disponibles (ordre non garanti).
func names():
    out := []
    for k in _TABLE:
        append(out, k)
    return out


