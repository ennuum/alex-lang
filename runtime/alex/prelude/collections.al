
from core use len, type

func append(l, x):
  __list_append(l, x)

# insert(l, i, x) : 0 <= i <= len(l) permis (i == len(l) insère à la
# toute fin) -- __list_insert (LIST_INSERT) applique cette borne,
# IndexError sinon (§10).
func insert(l, i, x):
  __list_insert(l, i, x)

func clear(l):
  __list_clear(l)

# i = null sert de sentinelle "index non fourni" -- par défaut (i omis
# ou null), retire et renvoie le DERNIER élément. Liste vide -> index
# -1, hors limites : __list_remove_at lève IndexError exactement comme
# le faisait pop() natif sur une liste vide (§10), sans `raise`
# explicite ici (LIST_REMOVE_AT porte déjà sa propre vérification de
# bornes -- contrairement à remove() ci-dessus, resté natif).
func pop(l, i = null):
  if i == null:
    i = len(l) - 1
  return __list_remove_at(l, i)

func sort(l):
  n := len(l)
  i := 0
  while i < n:
    j := 0
    while j < n - i - 1:
      if l[j] > l[j + 1]:
        tmp := l[j]
        l[j] = l[j + 1]
        l[j + 1] = tmp
      j = j + 1
    i = i + 1

func reverse(l):
  n := len(l)
  i := 0
  while i < n / 2:
    tmp := l[i]
    l[i] = l[n - 1 - i]
    l[n - 1 - i] = tmp
    i = i + 1

func contains(l, x):
  i := 0
  while i < len(l):
    if l[i] == x:
      return true
    i = i + 1
  return false

func index(l, x):
  i := 0
  while i < len(l):
    if l[i] == x:
      return i
    i = i + 1
  return 0 - 1

func count(l, x):
  n := 0
  i := 0
  while i < len(l):
    if l[i] == x:
      n = n + 1
    i = i + 1
  return n

# Polymorphe list/dict, comme la version native précédente. Placée
# APRÈS index() : les fonctions top-level ne sont PAS hoistées dans ce
# langage (un appel à une fonction définie plus bas dans le fichier
# lève NameError, vérifié en pratique) -- contrairement aux fonctions
# imbriquées/locales, ou à un appel récursif d'une fonction sur
# elle-même, qui restent résolus normalement (son propre nom est déjà
# déclaré au moment où son propre corps est analysé).
# list : recherche par valeur (égalité, index() ci-dessus) --
# ArgumentError si absente, levée explicitement (aucun opcode ne peut
# le vérifier seul, contrairement au cas dict juste en dessous).
# dict : __dict_remove_key lève KeyError elle-même si la clé est
# absente -- pas de vérification préalable nécessaire ici.
func remove(container, x):
  t := type(container)
  if t == "list":
    i := index(container, x)
    if i == 0 - 1:
      raise("ArgumentError", "remove(...) : valeur absente de la liste")
    __list_remove_at(container, i)
  if t == "dict":
    __dict_remove_key(container, x)
  if t != "list" and t != "dict":
    raise("TypeError", "'remove' : le premier argument doit être une list ou un dict")
