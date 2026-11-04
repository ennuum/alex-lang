# ALEX STANDARD LIBRARY — atomic._common (interne) : vérifications partagées par les types atomiques.

from core use type
use _native_sync as _s

func need_int(fn, v):
    if type(v) != "int":
        raise("TypeError", fn + " : int attendu (obtenu '" + type(v) + "')")

func need_timeout(fn, t):
    if t != null and type(t) != "int" and type(t) != "float":
        raise("TypeError", fn + " : délai nombre ou null attendu")
    if t != null and t < 0:
        raise("ArgumentError", fn + " : délai négatif")

# Objet natif existant, du type attendu (pour attach) ; ArgumentError sinon.
func check_kind(fn, id, kind):
    if type(id) != "int":
        raise("TypeError", fn + " : identifiant (int) attendu")
    k := _s.kind(id)
    if k == null:
        raise("ArgumentError", fn + " : objet " + str(id) + " inconnu ou détruit")
    if k != kind:
        raise("TypeError", fn + " : l'objet " + str(id) + " est un(e) " + k + ", pas un(e) " + kind)
