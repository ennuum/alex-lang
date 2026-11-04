use math
use string
from core use len, is_int, is_str, to_int, to_float
from collections use append

# ALEX STANDARD LIBRARY - units
# Conversion et vérification des unités (analyse dimensionnelle). Pure ALEX, aucune dépendance native.
#
#   use units
#   units.convert(100, "km/h", "m/s")          # 27.777...
#   units.convert(100, "degC", "degF")         # 212.0
#   units.convert(1, "J/(mol*K)", "cal/(mol*K)")
#   units.compatible("N*m", "J")               # true
#   units.dimension_name("kg*m/s^2")           # "force"
#   d := units.quantity(5, "km")
#   t := units.quantity(30, "min")
#   v := units.q_div(d, t)                     # grandeur de dimension « velocity »
#   print(units.q_str(v, "km/h"))              # 10.0 km/h
#
# SYNTAXE DES UNITÉS
#   noms      : m, kg, s, N, Pa, J, W, V, mol, eV, mi, ft, lb, gal, ...  (units.list_units())
#   préfixes  : SI de y (10^-24) à Y (10^24) sur les unités préfixables (km, mg, µs, GHz, kWh, mL, ...)
#   produit   : « * », « · » ou une espace ;   quotient : « / » ;   puissance entière : « ^ » (m^2, s^-1)
#   groupes   : parenthèses, ex. J/(mol*K) ; « 1/s » est valide ; « * » et « / » se lisent de gauche à droite.
#   températures : degC (°C), degF (°F), degR, K. Les unités à décalage ne se combinent pas avec d'autres.
#
# MODÈLE
#   Chaque unité = facteur vers l'unité SI cohérente + vecteur de 7 dimensions (L, M, T, I, Θ, N, J). Deux unités
#   sont convertibles si et seulement si leurs vecteurs sont égaux. Les facteurs sont exacts en décimal ; une
#   conversion ajoute au plus quelques erreurs d'arrondi flottant (~1e-15 relatif).
#   L'angle (rad, deg...) est traité comme sans dimension, comme dans le SI.
#
# LIMITES (documentées) : exposants entiers uniquement ; pas de mélange d'unités à décalage dans une expression.

# --- Registre des unités : nom -> [facteur vers l'unité SI cohérente, dimensions, décalage (K), préfixable] ---
# Dimensions : [longueur, masse, temps, courant, température, quantité de matière, intensité lumineuse].
# Unités à décalage (°C, °F) : 5e élément = [valeur de l'unité à 0 °C, numérateur, dénominateur] : K = (x - zéro) * num / den + 273,15.
# Facteurs EXACTS en décimal (générés mécaniquement à partir des définitions légales : ne pas éditer à la main).
const _UNITS := {
    "1": [1.0, [0, 0, 0, 0, 0, 0, 0], 0.0, false],
    "%": [0.01, [0, 0, 0, 0, 0, 0, 0], 0.0, false],
    "ppm": [0.000001, [0, 0, 0, 0, 0, 0, 0], 0.0, false],
    "ppb": [0.000000001, [0, 0, 0, 0, 0, 0, 0], 0.0, false],
    "rad": [1.0, [0, 0, 0, 0, 0, 0, 0], 0.0, true],
    "sr": [1.0, [0, 0, 0, 0, 0, 0, 0], 0.0, false],
    "deg": [0.01745329251994329576923691, [0, 0, 0, 0, 0, 0, 0], 0.0, false],
    "°": [0.01745329251994329576923691, [0, 0, 0, 0, 0, 0, 0], 0.0, false],
    "grad": [0.01570796326794896619231322, [0, 0, 0, 0, 0, 0, 0], 0.0, false],
    "turn": [6.283185307179586476925287, [0, 0, 0, 0, 0, 0, 0], 0.0, false],
    "arcmin": [0.0002908882086657215961539485, [0, 0, 0, 0, 0, 0, 0], 0.0, false],
    "arcsec": [0.000004848136811095359935899141, [0, 0, 0, 0, 0, 0, 0], 0.0, false],
    "m": [1.0, [1, 0, 0, 0, 0, 0, 0], 0.0, true],
    "in": [0.0254, [1, 0, 0, 0, 0, 0, 0], 0.0, false],
    "ft": [0.3048, [1, 0, 0, 0, 0, 0, 0], 0.0, false],
    "yd": [0.9144, [1, 0, 0, 0, 0, 0, 0], 0.0, false],
    "mi": [1609.344, [1, 0, 0, 0, 0, 0, 0], 0.0, false],
    "nmi": [1852.0, [1, 0, 0, 0, 0, 0, 0], 0.0, false],
    "angstrom": [0.0000000001, [1, 0, 0, 0, 0, 0, 0], 0.0, false],
    "Å": [0.0000000001, [1, 0, 0, 0, 0, 0, 0], 0.0, false],
    "au": [149597870700.0, [1, 0, 0, 0, 0, 0, 0], 0.0, false],
    "ly": [9460730472580800.0, [1, 0, 0, 0, 0, 0, 0], 0.0, false],
    "pc": [30856775814913672.78913938, [1, 0, 0, 0, 0, 0, 0], 0.0, true],
    "thou": [0.0000254, [1, 0, 0, 0, 0, 0, 0], 0.0, false],
    "mil": [0.0000254, [1, 0, 0, 0, 0, 0, 0], 0.0, false],
    "kg": [1.0, [0, 1, 0, 0, 0, 0, 0], 0.0, false],
    "g": [0.001, [0, 1, 0, 0, 0, 0, 0], 0.0, true],
    "t": [1000.0, [0, 1, 0, 0, 0, 0, 0], 0.0, false],
    "lb": [0.45359237, [0, 1, 0, 0, 0, 0, 0], 0.0, false],
    "oz": [0.028349523125, [0, 1, 0, 0, 0, 0, 0], 0.0, false],
    "st": [6.35029318, [0, 1, 0, 0, 0, 0, 0], 0.0, false],
    "u": [0.0000000000000000000000000016605390666, [0, 1, 0, 0, 0, 0, 0], 0.0, false],
    "Da": [0.0000000000000000000000000016605390666, [0, 1, 0, 0, 0, 0, 0], 0.0, false],
    "ct": [0.0002, [0, 1, 0, 0, 0, 0, 0], 0.0, false],
    "s": [1.0, [0, 0, 1, 0, 0, 0, 0], 0.0, true],
    "min": [60.0, [0, 0, 1, 0, 0, 0, 0], 0.0, false],
    "h": [3600.0, [0, 0, 1, 0, 0, 0, 0], 0.0, false],
    "d": [86400.0, [0, 0, 1, 0, 0, 0, 0], 0.0, false],
    "wk": [604800.0, [0, 0, 1, 0, 0, 0, 0], 0.0, false],
    "yr": [31557600.0, [0, 0, 1, 0, 0, 0, 0], 0.0, false],
    "A": [1.0, [0, 0, 0, 1, 0, 0, 0], 0.0, true],
    "K": [1.0, [0, 0, 0, 0, 1, 0, 0], 0.0, true],
    "degC": [1.0, [0, 0, 0, 0, 1, 0, 0], 273.15, false, [0.0, 1.0, 1.0]],
    "°C": [1.0, [0, 0, 0, 0, 1, 0, 0], 273.15, false, [0.0, 1.0, 1.0]],
    "degF": [0.5555555555555555555555556, [0, 0, 0, 0, 1, 0, 0], 255.3722222222222222222222, false, [32.0, 5.0, 9.0]],
    "°F": [0.5555555555555555555555556, [0, 0, 0, 0, 1, 0, 0], 255.3722222222222222222222, false, [32.0, 5.0, 9.0]],
    "degR": [0.5555555555555555555555556, [0, 0, 0, 0, 1, 0, 0], 0.0, false],
    "mol": [1.0, [0, 0, 0, 0, 0, 1, 0], 0.0, true],
    "cd": [1.0, [0, 0, 0, 0, 0, 0, 1], 0.0, true],
    "lm": [1.0, [0, 0, 0, 0, 0, 0, 1], 0.0, true],
    "lx": [1.0, [-2, 0, 0, 0, 0, 0, 1], 0.0, true],
    "Hz": [1.0, [0, 0, -1, 0, 0, 0, 0], 0.0, true],
    "rpm": [0.01666666666666666666666667, [0, 0, -1, 0, 0, 0, 0], 0.0, false],
    "Bq": [1.0, [0, 0, -1, 0, 0, 0, 0], 0.0, true],
    "N": [1.0, [1, 1, -2, 0, 0, 0, 0], 0.0, true],
    "lbf": [4.4482216152605, [1, 1, -2, 0, 0, 0, 0], 0.0, false],
    "kgf": [9.80665, [1, 1, -2, 0, 0, 0, 0], 0.0, false],
    "dyn": [0.00001, [1, 1, -2, 0, 0, 0, 0], 0.0, false],
    "Pa": [1.0, [-1, 1, -2, 0, 0, 0, 0], 0.0, true],
    "bar": [100000.0, [-1, 1, -2, 0, 0, 0, 0], 0.0, true],
    "atm": [101325.0, [-1, 1, -2, 0, 0, 0, 0], 0.0, false],
    "mmHg": [133.322387415, [-1, 1, -2, 0, 0, 0, 0], 0.0, false],
    "torr": [133.3223684210526315789474, [-1, 1, -2, 0, 0, 0, 0], 0.0, false],
    "psi": [6894.757293168361336722673, [-1, 1, -2, 0, 0, 0, 0], 0.0, false],
    "J": [1.0, [2, 1, -2, 0, 0, 0, 0], 0.0, true],
    "eV": [0.0000000000000000001602176634, [2, 1, -2, 0, 0, 0, 0], 0.0, true],
    "cal": [4.184, [2, 1, -2, 0, 0, 0, 0], 0.0, true],
    "erg": [0.0000001, [2, 1, -2, 0, 0, 0, 0], 0.0, false],
    "Wh": [3600.0, [2, 1, -2, 0, 0, 0, 0], 0.0, true],
    "BTU": [1055.05585262, [2, 1, -2, 0, 0, 0, 0], 0.0, false],
    "W": [1.0, [2, 1, -3, 0, 0, 0, 0], 0.0, true],
    "hp": [745.69987158227022, [2, 1, -3, 0, 0, 0, 0], 0.0, false],
    "C": [1.0, [0, 0, 1, 1, 0, 0, 0], 0.0, true],
    "Ah": [3600.0, [0, 0, 1, 1, 0, 0, 0], 0.0, true],
    "V": [1.0, [2, 1, -3, -1, 0, 0, 0], 0.0, true],
    "F": [1.0, [-2, -1, 4, 2, 0, 0, 0], 0.0, true],
    "ohm": [1.0, [2, 1, -3, -2, 0, 0, 0], 0.0, true],
    "Ω": [1.0, [2, 1, -3, -2, 0, 0, 0], 0.0, true],
    "S": [1.0, [-2, -1, 3, 2, 0, 0, 0], 0.0, true],
    "Wb": [1.0, [2, 1, -2, -1, 0, 0, 0], 0.0, true],
    "T": [1.0, [0, 1, -2, -1, 0, 0, 0], 0.0, true],
    "H": [1.0, [2, 1, -2, -2, 0, 0, 0], 0.0, true],
    "Gy": [1.0, [2, 0, -2, 0, 0, 0, 0], 0.0, true],
    "Sv": [1.0, [2, 0, -2, 0, 0, 0, 0], 0.0, true],
    "ha": [10000.0, [2, 0, 0, 0, 0, 0, 0], 0.0, false],
    "acre": [4046.8564224, [2, 0, 0, 0, 0, 0, 0], 0.0, false],
    "L": [0.001, [3, 0, 0, 0, 0, 0, 0], 0.0, true],
    "l": [0.001, [3, 0, 0, 0, 0, 0, 0], 0.0, true],
    "gal": [0.003785411784, [3, 0, 0, 0, 0, 0, 0], 0.0, false],
    "qt": [0.000946352946, [3, 0, 0, 0, 0, 0, 0], 0.0, false],
    "pt": [0.000473176473, [3, 0, 0, 0, 0, 0, 0], 0.0, false],
    "cup": [0.0002365882365, [3, 0, 0, 0, 0, 0, 0], 0.0, false],
    "floz": [0.0000295735295625, [3, 0, 0, 0, 0, 0, 0], 0.0, false],
    "tbsp": [0.00001478676478125, [3, 0, 0, 0, 0, 0, 0], 0.0, false],
    "tsp": [0.00000492892159375, [3, 0, 0, 0, 0, 0, 0], 0.0, false],
    "kn": [0.5144444444444444444444444, [1, 0, -1, 0, 0, 0, 0], 0.0, false]
}

# Préfixes SI, du plus long au plus court (« da » avant « d »).
const _PREFIXES := [
    ["da", 10.0],
    ["Y", 1000000000000000000000000.0],
    ["Z", 1000000000000000000000.0],
    ["E", 1000000000000000000.0],
    ["P", 1000000000000000.0],
    ["T", 1000000000000.0],
    ["G", 1000000000.0],
    ["M", 1000000.0],
    ["k", 1000.0],
    ["h", 100.0],
    ["d", 0.1],
    ["c", 0.01],
    ["m", 0.001],
    ["µ", 0.000001],
    ["u", 0.000001],
    ["n", 0.000000001],
    ["p", 0.000000000001],
    ["f", 0.000000000000001],
    ["a", 0.000000000000000001],
    ["z", 0.000000000000000000001],
    ["y", 0.000000000000000000000001]
]

# Noms usuels des dimensions : clé = dimensions séparées par des virgules.
const _DIM_NAMES := {
    "0,0,0,0,0,0,0": "dimensionless",
    "1,0,0,0,0,0,0": "length",
    "0,1,0,0,0,0,0": "mass",
    "0,0,1,0,0,0,0": "time",
    "0,0,0,1,0,0,0": "current",
    "0,0,0,0,1,0,0": "temperature",
    "0,0,0,0,0,1,0": "amount of substance",
    "0,0,0,0,0,0,1": "luminous intensity",
    "2,0,0,0,0,0,0": "area",
    "3,0,0,0,0,0,0": "volume",
    "0,0,-1,0,0,0,0": "frequency",
    "1,0,-1,0,0,0,0": "velocity",
    "1,0,-2,0,0,0,0": "acceleration",
    "1,1,-2,0,0,0,0": "force",
    "-1,1,-2,0,0,0,0": "pressure",
    "2,1,-2,0,0,0,0": "energy",
    "2,1,-3,0,0,0,0": "power",
    "0,0,1,1,0,0,0": "electric charge",
    "2,1,-3,-1,0,0,0": "voltage",
    "-2,-1,4,2,0,0,0": "capacitance",
    "2,1,-3,-2,0,0,0": "resistance",
    "-2,-1,3,2,0,0,0": "conductance",
    "2,1,-2,-1,0,0,0": "magnetic flux",
    "0,1,-2,-1,0,0,0": "magnetic flux density",
    "2,1,-2,-2,0,0,0": "inductance",
    "1,1,-1,0,0,0,0": "momentum",
    "-3,1,0,0,0,0,0": "density",
    "2,0,-2,0,0,0,0": "absorbed dose",
    "-2,0,0,0,0,0,1": "illuminance",
    "2,1,-1,0,0,0,0": "angular momentum",
    "-1,1,-1,0,0,0,0": "dynamic viscosity",
    "-3,0,0,0,0,1,0": "molar concentration",
    "2,1,-2,0,-1,0,0": "entropy",
    "1,1,-3,-1,0,0,0": "electric field",
    "0,0,0,0,0,0,0": "dimensionless"
}


# ============================================================================
# Analyse d'une expression d'unité
# ============================================================================

func _zeros():
    return [0, 0, 0, 0, 0, 0, 0]

func _copy_dims(d):
    return [d[0], d[1], d[2], d[3], d[4], d[5], d[6]]

func _dims_combine(a, b, k):
    out := []
    i := 0
    while i < 7:
        append(out, a[i] + k * b[i])
        i += 1
    return out

func _copy_aff(a):
    if a == null:
        return null
    return [a[0], a[1], a[2]]

func _same_dims(a, b):
    i := 0
    while i < 7:
        if a[i] != b[i]:
            return false
        i += 1
    return true

func _dims_key(d):
    return f"{d[0]},{d[1]},{d[2]},{d[3]},{d[4]},{d[5]},{d[6]}"

# Texte d'une puissance : "m", "m^2".
func _power_text(sym, n):
    if n == 1:
        return sym
    return f"{sym}^{n}"

# Écrit les dimensions avec les symboles SI de base : "kg*m/s^2", "1/s", "1".
func _dims_text(d):
    # Ordre d'écriture usuel : kg, m, s, A, K, mol, cd (la masse d'abord : « kg*m/s^2 »).
    syms := ["m", "kg", "s", "A", "K", "mol", "cd"]
    order := [1, 0, 2, 3, 4, 5, 6]
    num := []
    den := []
    for i in order:
        if d[i] > 0:
            append(num, _power_text(syms[i], d[i]))
        if d[i] < 0:
            append(den, _power_text(syms[i], 0 - d[i]))
    top := "1"
    if len(num) > 0:
        top = string.join("*", num)
    if len(den) == 0:
        return top
    if len(den) == 1:
        return top + "/" + den[0]
    return top + "/(" + string.join("*", den) + ")"

# Cherche une unité par son nom (exact, puis préfixe SI + unité préfixable).
# Renvoie [facteur, dimensions, décalage, données affines ou null] ou null.
func _find(name):
    found := null
    try:
        found = _UNITS[name]
    catch e:
        found = null
    if found != null:
        aff := null
        if len(found) > 4:
            aff = [found[4][0], found[4][1], found[4][2]]
        return [found[0], _copy_dims(found[1]), found[2], aff]
    for p in _PREFIXES:
        plen := len(p[0])
        if len(name) > plen and string.starts_with(name, p[0]):
            rest := string.substring(name, plen, len(name))
            base := null
            try:
                base = _UNITS[rest]
            catch e2:
                base = null
            if base != null and base[3]:
                return [p[1] * base[0], _copy_dims(base[1]), 0.0, null]
    return null

# Découpe en jetons : ["n", nom] | ["d", nombre] | ["o", opérateur].
func _tokenize(text):
    toks := []
    chars := []
    for ch in text:
        append(chars, str(ch))
    n := len(chars)
    i := 0
    while i < n:
        c := chars[i]
        if c == " ":
            i += 1
        elif c == "*" or c == "/" or c == "^" or c == "(" or c == ")" or c == "-":
            append(toks, ["o", c])
            i += 1
        elif c == "·" or c == "×":
            append(toks, ["o", "*"])
            i += 1
        elif string.contains("0123456789.", c):
            j := i
            buf := ""
            while j < n and string.contains("0123456789.", chars[j]):
                buf = buf + chars[j]
                j += 1
            append(toks, ["d", to_float(buf)])
            i = j
        else:
            j := i
            buf := ""
            while j < n and not string.contains(" */^()-·×0123456789.", chars[j]):
                buf = buf + chars[j]
                j += 1
            append(toks, ["n", buf])
            i = j
    return toks

func _peek(st):
    if st[1] >= len(st[0]):
        return null
    return st[0][st[1]]

func _is_op(t, c):
    return t != null and t[0] == "o" and t[1] == c

# Lit une expression jusqu'à ')' ou la fin. Renvoie [facteur, dimensions, décalage, données affines ou null].
# Produit et quotient se lisent de gauche à droite ; la juxtaposition vaut « * ».
func _expr(st):
    scale := 1.0
    dims := _zeros()
    op := 1
    count := 0
    offset := 0.0
    affdata := null
    affine := false
    while true:
        t := _peek(st)
        if t == null:
            raise("ValueError", "unité : expression incomplète")
        fs := 1.0
        fd := _zeros()
        fo := 0.0
        fa := null
        if _is_op(t, "("):
            st[1] += 1
            sub := _expr(st)
            if not _is_op(_peek(st), ")"):
                raise("ValueError", "unité : parenthèse fermante manquante")
            st[1] += 1
            fs = sub[0]
            fd = sub[1]
            fo = sub[2]
            fa = sub[3]
        elif t[0] == "d":
            fs = t[1]
            st[1] += 1
        elif t[0] == "n":
            u := _find(t[1])
            if u == null:
                raise("ValueError", "unité inconnue : " + t[1])
            fs = u[0]
            fd = u[1]
            fo = u[2]
            fa = u[3]
            st[1] += 1
        else:
            raise("ValueError", "unité : symbole inattendu '" + t[1] + "'")
        if _is_op(_peek(st), "^"):
            st[1] += 1
            neg := false
            et := _peek(st)
            if _is_op(et, "-"):
                neg = true
                st[1] += 1
                et = _peek(st)
            if et == null or et[0] != "d" or et[1] != math.floor(et[1]):
                raise("ValueError", "unité : exposant entier attendu après '^'")
            p := to_int(et[1])
            st[1] += 1
            if neg:
                p = 0 - p
            if fo != 0.0:
                raise("ValueError", "unité : une unité à décalage (°C, °F) ne peut pas être élevée à une puissance")
            fs = fs ** p
            fd = _dims_combine(_zeros(), fd, p)
        if fo != 0.0:
            affine = true
            offset = fo
            affdata = fa
        count += 1
        if op == 1:
            scale = scale * fs
            dims = _dims_combine(dims, fd, 1)
        else:
            scale = scale / fs
            dims = _dims_combine(dims, fd, -1)
        nt := _peek(st)
        if nt == null or _is_op(nt, ")"):
            break
        if _is_op(nt, "*"):
            op = 1
            st[1] += 1
        elif _is_op(nt, "/"):
            op = -1
            st[1] += 1
        else:
            op = 1
    if affine and count > 1:
        raise("ValueError", "unité : une unité à décalage (°C, °F) ne peut pas figurer dans une expression composée")
    return [scale, dims, offset, affdata]

_CACHE := {}

# Analyse une unité (« km/h », « kg*m^2/s^2 », « J/(mol*K) », « °C », « 1/s ») et renvoie
# [facteur vers l'unité SI, dimensions (liste de 7 entiers), décalage en kelvin, données affines ou null].
# Le résultat est mémoïsé. Lève ValueError pour une unité inconnue ou mal formée.
func parse(unit):
    if not is_str(unit):
        raise("TypeError", "units.parse : chaîne attendue")
    hit := null
    try:
        hit = _CACHE[unit]
    catch e:
        hit = null
    if hit != null:
        return [hit[0], _copy_dims(hit[1]), hit[2], _copy_aff(hit[3])]
    toks := _tokenize(unit)
    result := null
    if len(toks) == 0:
        result = [1.0, _zeros(), 0.0, null]
    else:
        st := [toks, 0]
        result = _expr(st)
        if st[1] < len(toks):
            raise("ValueError", "unité : parenthèse fermante inattendue dans '" + unit + "'")
    _CACHE[unit] = result
    return [result[0], _copy_dims(result[1]), result[2], _copy_aff(result[3])]

# Vrai si la chaîne est une unité valide.
func is_unit(unit):
    ok := true
    try:
        parse(unit)
    catch e:
        ok = false
    return ok

# Dimensions (7 entiers) d'une unité.
func dimension(unit):
    return parse(unit)[1]

# Nom usuel de la dimension d'une unité (« force », « energy »...) ou, à défaut, son écriture en unités de
# base (« kg*m^2/s^2 »). Accepte une unité (chaîne) ou une liste de 7 entiers.
func dimension_name(unit_or_dims):
    d := unit_or_dims
    if is_str(unit_or_dims):
        d = parse(unit_or_dims)[1]
    named := null
    try:
        named = _DIM_NAMES[_dims_key(d)]
    catch e:
        named = null
    if named != null:
        return named
    return _dims_text(d)

# Vrai si les deux unités ont la même dimension (donc sont convertibles).
func compatible(a, b):
    return _same_dims(parse(a)[1], parse(b)[1])

# ============================================================================
# Conversion
# ============================================================================

# Valeur -> unité SI cohérente, et retour. Les unités à décalage passent par le kelvin :
# K = (x - zéro) * num / den + 273,15 (ordre des opérations choisi pour que 32 °F -> 0 °C soit exact).
func _to_si(x, p):
    if p[3] == null:
        return (x * p[0])
    return ((x - p[3][0]) * p[3][1]) / p[3][2] + 273.15

func _from_si(v, p):
    if p[3] == null:
        return v / p[0]
    return ((v - 273.15) * p[3][2]) / p[3][1] + p[3][0]

# Convertit une valeur d'une unité à une autre : convert(100, "degC", "degF") -> 212.0.
# Lève ValueError si les dimensions diffèrent.
func convert(value, from_unit, to_unit):
    a := parse(from_unit)
    b := parse(to_unit)
    if not _same_dims(a[1], b[1]):
        raise("ValueError", f"conversion impossible : '{from_unit}' ({dimension_name(a[1])}) vers '{to_unit}' ({dimension_name(b[1])})")
    return _from_si(_to_si(value, a), b)

# Convertit chaque élément d'une liste.
func convert_all(values, from_unit, to_unit):
    a := parse(from_unit)
    b := parse(to_unit)
    if not _same_dims(a[1], b[1]):
        raise("ValueError", f"conversion impossible : '{from_unit}' vers '{to_unit}'")
    out := []
    for v in values:
        append(out, _from_si(_to_si(v, a), b))
    return out

# Liste des noms d'unités du registre (sans les unités préfixées).
func list_units():
    out := []
    for k in _UNITS:
        append(out, k)
    return out

# ============================================================================
# Grandeurs (valeur + unité) : [valeur SI, dimensions, unité d'affichage]
# ============================================================================
# Une grandeur mémorise sa valeur dans l'unité SI cohérente, ses dimensions et l'unité dans laquelle elle
# s'affiche. Les opérations vérifient la compatibilité des dimensions. Les unités à décalage (°C, °F)
# servent à CRÉER et CONVERTIR une température ; l'arithmétique sur ces grandeurs est refusée (ambiguë) :
# passez par le kelvin (q_to(t, "K")).

func quantity(value, unit):
    p := parse(unit)
    return [_to_si(value * 1.0, p), p[1], unit]

func _affine(q):
    return parse(q[2])[3] != null

func _check_affine(q, what):
    if _affine(q):
        raise("ValueError", f"{what} : arithmétique interdite sur une unité à décalage ('{q[2]}'), convertissez d'abord en kelvin")

func _check_same(a, b, what):
    if not _same_dims(a[1], b[1]):
        raise("ValueError", f"{what} : dimensions incompatibles ({dimension_name(a[1])} et {dimension_name(b[1])})")

# Valeur de la grandeur exprimée dans l'unité donnée (ou dans son unité d'affichage si unit est null).
func q_to(q, unit=null):
    u := unit
    if u == null:
        u = q[2]
    p := parse(u)
    if not _same_dims(q[1], p[1]):
        raise("ValueError", f"q_to : '{u}' ({dimension_name(p[1])}) incompatible avec la grandeur ({dimension_name(q[1])})")
    return _from_si(q[0], p)

# Même grandeur, affichée dans une autre unité.
func q_in(q, unit):
    q_to(q, unit)
    return [q[0], q[1], unit]

func q_add(a, b):
    _check_affine(a, "q_add")
    _check_affine(b, "q_add")
    _check_same(a, b, "q_add")
    return [a[0] + b[0], a[1], a[2]]

func q_sub(a, b):
    _check_affine(a, "q_sub")
    _check_affine(b, "q_sub")
    _check_same(a, b, "q_sub")
    return [a[0] - b[0], a[1], a[2]]

func q_neg(a):
    _check_affine(a, "q_neg")
    return [0.0 - a[0], a[1], a[2]]

# Produit par un nombre sans dimension.
func q_scale(a, k):
    _check_affine(a, "q_scale")
    return [a[0] * k, a[1], a[2]]

func _label_mul(la, lb):
    if la == lb:
        return "(" + la + ")^2"
    return "(" + la + ")*(" + lb + ")"

func q_mul(a, b):
    _check_affine(a, "q_mul")
    _check_affine(b, "q_mul")
    return [a[0] * b[0], _dims_combine(a[1], b[1], 1), _label_mul(a[2], b[2])]

func q_div(a, b):
    _check_affine(a, "q_div")
    _check_affine(b, "q_div")
    if b[0] == 0.0:
        raise("ZeroDivisionError", "q_div : division par une grandeur nulle")
    if _same_dims(a[1], b[1]) and a[2] == b[2]:
        return [a[0] / b[0], _zeros(), "1"]
    return [a[0] / b[0], _dims_combine(a[1], b[1], -1), "(" + a[2] + ")/(" + b[2] + ")"]

# Puissance entière d'une grandeur.
func q_pow(a, n):
    _check_affine(a, "q_pow")
    if not is_int(n):
        raise("TypeError", "q_pow : exposant entier attendu")
    return [a[0] ** n, _dims_combine(_zeros(), a[1], n), "(" + a[2] + ")^" + str(n)]

# Comparaison : renvoie -1, 0 ou 1 (dimensions identiques exigées).
func q_cmp(a, b):
    _check_same(a, b, "q_cmp")
    if a[0] < b[0]:
        return -1
    if a[0] > b[0]:
        return 1
    return 0

func q_is_close(a, b, rel_tol=0.000000001):
    _check_same(a, b, "q_is_close")
    return math.abs(a[0] - b[0]) <= rel_tol * math.max(math.abs(a[0]), math.abs(b[0]))

# Texte « valeur unité » dans l'unité d'affichage (ou dans l'unité donnée).
func q_str(q, unit=null):
    u := unit
    if u == null:
        u = q[2]
    return f"{q_to(q, u)} {u}"
