# ALEX STANDARD LIBRARY — graphics.graphics_errors
#
# Erreurs du rendu et vérification des données d'un dessin avant de le lancer :
#   GraphicsError        erreur générale
#   ShaderError          shader incompatible avec les sommets (attributs manquants, varyings)
#   PipelineError        topologie inconnue, état incohérent
#   FormatError          format de sommet / de pixel inconnu ou données mal formées
#   BackendUnavailable   dorsal de rendu absent (graphics.graphics_backend)
#   FramebufferError     attachements de tailles différentes, attachement manquant
#
#   use graphics.graphics_errors as ge
#   pbs := ge.check_draw(vb, ib, "triangles")
#   for p in pbs:
#       print(p)        # « indice 7 hors des 4 sommets (élément 5) », « triangle dégénéré 2 »...
#   ge.require_valid(vb, ib)       # lève FormatError au premier problème
#
# Erreurs : celles ci-dessus.

from core use len, type
from collections use append

const GRAPHICS := "GraphicsError"
const SHADER := "ShaderError"
const PIPELINE := "PipelineError"
const FORMAT := "FormatError"
const BACKEND := "BackendUnavailable"
const FRAMEBUFFER := "FramebufferError"

const TOPOLOGIES := ["triangles", "lines", "points"]

func is_graphics_error(t):
    return t == GRAPHICS or t == SHADER or t == PIPELINE or t == FORMAT or t == BACKEND or t == FRAMEBUFFER

func _bad_number(x):
    return x != x or x > 1.0e30 or x < -1.0e30

# Liste des problèmes d'un dessin (vide si tout va bien) : nombre de sommets, indices hors limites, nombre
# d'indices incompatible avec la topologie, positions non finies, triangles dégénérés (indices répétés).
func check_draw(vb, ib=null, topology="triangles", max_reports=20):
    out := []
    if not (topology in TOPOLOGIES):
        append(out, "topologie inconnue « " + str(topology) + " » (" + str(TOPOLOGIES) + ")")
        return out
    n := vb.count()
    per := 3 if topology == "triangles" else (2 if topology == "lines" else 1)
    if n == 0:
        append(out, "aucun sommet")
        return out
    if vb.layout.has("position"):
        off := vb.layout.offset("position")
        sz := vb.layout.size("position")
        i := 0
        while i < n and len(out) < max_reports:
            k := 0
            while k < sz:
                if _bad_number(vb.data[i * vb.layout.stride + off + k]):
                    append(out, "position non finie au sommet " + str(i))
                    break
                k += 1
            i += 1
    else:
        append(out, "le format de sommet n'a pas d'attribut « position »")
    if ib == null:
        if n % per != 0:
            append(out, str(n) + " sommets : pas un multiple de " + str(per) + " pour « " + topology + " »")
        return out
    idx := ib.indices
    if len(idx) % per != 0:
        append(out, str(len(idx)) + " indices : pas un multiple de " + str(per) + " pour « " + topology + " »")
    e := 0
    while e < len(idx) and len(out) < max_reports:
        v := idx[e]
        if type(v) != "int" or v < 0 or v >= n:
            append(out, "indice " + str(v) + " hors des " + str(n) + " sommets (élément " + str(e) + ")")
        e += 1
    if topology == "triangles":
        t := 0
        while t + 2 < len(idx) and len(out) < max_reports:
            if idx[t] == idx[t + 1] or idx[t + 1] == idx[t + 2] or idx[t] == idx[t + 2]:
                append(out, "triangle dégénéré " + str(t // 3) + " (indices répétés)")
            t += 3
    return out

func require_valid(vb, ib=null, topology="triangles"):
    pbs := check_draw(vb, ib, topology, 1)
    if len(pbs) > 0:
        raise(FORMAT, "dessin invalide : " + pbs[0])
    return true

# Vérifie qu'un format de sommets fournit les attributs attendus par un shader (liste de noms).
func check_attributes(layout, required):
    missing := [a for a in required if not layout.has(a)]
    if len(missing) > 0:
        raise(SHADER, "attributs manquants pour le shader : " + str(missing) + " (format : " + layout.describe() + ")")
    return true
