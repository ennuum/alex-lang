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

