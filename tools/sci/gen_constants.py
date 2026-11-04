# Génère stdlib/constants/constants.al : littéraux décimaux exacts (le langage n'a pas de notation exponentielle).
from decimal import Decimal, getcontext
getcontext().prec = 60
def lit(s):
    d = Decimal(s)
    t = format(d, 'f')
    if '.' not in t: t += '.0'
    return t

# (NOM, valeur, unité, incertitude relative (0 = exacte), description)
EXACT_SI = [  # définition SI 2019 : valeurs exactes
 ("C", "299792458", "m/s", "vitesse de la lumière dans le vide"),
 ("H", "6.62607015e-34", "J*s", "constante de Planck"),
 ("E_CHARGE", "1.602176634e-19", "C", "charge élémentaire"),
 ("K_B", "1.380649e-23", "J/K", "constante de Boltzmann"),
 ("N_A", "6.02214076e23", "1/mol", "constante d'Avogadro"),
 ("G0", "9.80665", "m/s^2", "accélération normale de la pesanteur"),
 ("ATM", "101325", "Pa", "atmosphère normale"),
 ("BAR", "100000", "Pa", "bar"),
 ("AU", "149597870700", "m", "unité astronomique (IAU 2012)"),
 ("LIGHT_YEAR", "9460730472580800", "m", "année-lumière (365,25 j x c)"),
]
MEASURED = [  # CODATA 2018
 ("G", "6.67430e-11", "m^3/(kg*s^2)", "2.2e-5", "constante gravitationnelle"),
 ("EPS0", "8.8541878128e-12", "F/m", "1.5e-10", "permittivité du vide"),
 ("MU0", "1.25663706212e-6", "N/A^2", "1.5e-10", "perméabilité du vide"),
 ("M_E", "9.1093837015e-31", "kg", "3.0e-10", "masse de l'électron"),
 ("M_P", "1.67262192369e-27", "kg", "3.1e-10", "masse du proton"),
 ("M_N", "1.67492749804e-27", "kg", "5.7e-10", "masse du neutron"),
 ("AMU", "1.66053906660e-27", "kg", "3.0e-10", "unité de masse atomique unifiée"),
 ("ALPHA", "7.2973525693e-3", "1", "1.5e-10", "constante de structure fine"),
 ("RYDBERG", "10973731.568160", "1/m", "1.9e-12", "constante de Rydberg"),
 ("BOHR_RADIUS", "5.29177210903e-11", "m", "1.5e-10", "rayon de Bohr"),
 ("GM_SUN", "1.3271244e20", "m^3/s^2", "0", "paramètre gravitationnel nominal du Soleil (IAU 2015)"),
 ("R_EARTH", "6378137", "m", "0", "rayon équatorial terrestre (WGS 84)"),
]
out = []
w = out.append
w('''from string use lower
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
''')
w("# --- Constantes mathématiques ---")
math_c = [
 ("PI","3.14159265358979323846264338327950288"),("TAU","6.28318530717958647692528676655900577"),
 ("E","2.71828182845904523536028747135266250"),("PHI","1.61803398874989484820458683436563812"),
 ("EULER_GAMMA","0.57721566490153286060651209008240243"),("SQRT2","1.41421356237309504880168872420969808"),
 ("SQRT3","1.73205080756887729352744634150587237"),("LN2","0.69314718055994530941723212145817657"),
 ("LN10","2.30258509299404568401799145468436421"),("CATALAN","0.91596559417721901505460351493238411"),
 ("APERY","1.20205690315959428539973816151144999"),("FEIGENBAUM_DELTA","4.66920160910299067185320382046620161"),
]
for n,v in math_c: w(f"const {n} := {lit(v)}")
w("")
w("# --- Constantes physiques EXACTES (définition du SI) ---")
for n,v,u,d in EXACT_SI: w(f"const {n} := {lit(v)}   # {u} : {d}")
w("")
w("# --- Constantes dérivées (calculées, exactes) ---")
w("const HBAR := H / TAU                      # J*s : constante de Planck réduite")
w("const R_GAS := N_A * K_B                   # J/(mol*K) : constante des gaz parfaits")
w("const F_FARADAY := N_A * E_CHARGE          # C/mol : constante de Faraday")
w("const SIGMA_SB := 2.0 * PI ** 5 * K_B ** 4 / (15.0 * H ** 3 * C ** 2)   # W/(m^2*K^4) : Stefan-Boltzmann")
w("const WIEN_B := H * C / (K_B * 4.96511423174427630369)   # m*K : déplacement de Wien (4,9651... = racine de (x-5)e^x + 5)")
w("const EV := E_CHARGE                       # J : électron-volt")
w("const PARSEC := AU * 648000.0 / PI         # m : parsec")
w("const GAUSS_K := 0.01720209895             # constante gravitationnelle gaussienne (rad/jour)")
w("")
w("# --- Constantes physiques MESURÉES (CODATA 2018) ---")
for n,v,u,r,d in MEASURED: w(f"const {n} := {lit(v)}   # {u} : {d}")
w("")
w("# Alias lisibles")
w("const PLANCK_H := H")
w("const PLANCK_HBAR := HBAR")
w("const SPEED_OF_LIGHT := C")
w("const BOLTZMANN := K_B")
w("const AVOGADRO := N_A")
w("const GAS_CONSTANT := R_GAS")
w("const GRAVITATIONAL_CONSTANT := G")
w("const ELEMENTARY_CHARGE := E_CHARGE")
w("const STANDARD_GRAVITY := G0")
w("const FINE_STRUCTURE := ALPHA")
w("")
w("# --- Table de recherche : nom -> [valeur, unité, incertitude relative, description] ---")
w("# Les unités sont écrites dans la syntaxe du module `units`.")
rows = []
for n,v,u,d in EXACT_SI: rows.append((n.lower().replace('_',' '),n,u,"0.0",d))
rows += [("hbar","HBAR","J*s","0.0","constante de Planck réduite"),
         ("gas constant","R_GAS","J/(mol*K)","0.0","constante des gaz parfaits"),
         ("faraday","F_FARADAY","C/mol","0.0","constante de Faraday"),
         ("stefan-boltzmann","SIGMA_SB","W/(m^2*K^4)","0.0","constante de Stefan-Boltzmann"),
         ("wien","WIEN_B","m*K","0.0","constante de déplacement de Wien"),
         ("parsec","PARSEC","m","0.0","parsec"),("ev","EV","J","0.0","électron-volt")]
for n,v,u,r,d in MEASURED: rows.append((n.lower().replace('_',' '),n,u,lit(r) if r!="0" else "0.0",d))
# noms usuels
alias = {"c":"C","h":"H","planck":"H","planck constant":"H","reduced planck constant":"HBAR","speed of light":"C",
         "boltzmann":"K_B","boltzmann constant":"K_B","avogadro":"N_A","avogadro constant":"N_A","electron mass":"M_E",
         "proton mass":"M_P","neutron mass":"M_N","fine structure":"ALPHA","fine structure constant":"ALPHA",
         "elementary charge":"E_CHARGE","standard gravity":"G0","gravitational constant":"G","vacuum permittivity":"EPS0",
         "vacuum permeability":"MU0","atomic mass unit":"AMU","rydberg constant":"RYDBERG","bohr radius":"BOHR_RADIUS",
         "electron volt":"EV","gas constant":"R_GAS","faraday constant":"F_FARADAY"}
w("const _TABLE := {")
seen=set()
lines=[]
for n,sym,u,r,d in rows:
    if n in seen: continue
    seen.add(n)
    lines.append(f'    "{n}": [{sym}, "{u}", {r}, "{d}"]')
for a,sym in alias.items():
    if a in seen: continue
    # retrouve la ligne
    for n,s2,u,r,d in rows:
        if s2==sym:
            lines.append(f'    "{a}": [{sym}, "{u}", {r}, "{d}"]'); seen.add(a); break
w(",\n".join(lines))
w("}")
w('''
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

''')
import os
os.makedirs(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "stdlib", "constants"), exist_ok=True)
open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "stdlib", "constants", "constants.al"),"w",encoding="utf8").write("\n".join(out)+"\n")
print("ok", len(out))
