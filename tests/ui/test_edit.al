# Tests de ui.text (mesure, indices) et ui.edit (sélection, édition, historique). Backend headless.
from core use type, len
use collections
use ui.text as text
use ui.edit as edit

func check(cond, name):
    if not cond:
        raise("AssertionError", "ÉCHEC : " + name)
    print("ok  " + name)

func near(a, b, eps=0.01):
    d := a - b
    return d < eps and d > 0 - eps

# ---- mesure ----
w := text.width("Hello", 14.0)
check(w > 20.0 and w < 60.0, "mesure : largeur plausible")
check(text.width("", 14.0) == 0.0, "mesure : chaîne vide")
check(near(text.width("Hello", 28.0), text.width("Hello", 14.0) * 2.0, 0.5), "mesure : proportionnelle à la taille")
check(text.width("Hello world", 14.0) > text.width("Hello", 14.0), "mesure : croissante")
check(text.line_height(14.0) > 14.0, "hauteur de ligne > taille")
check(near(text.prefix_width("Hello", 5, 14.0), w), "prefix_width : tout le texte")
check(text.prefix_width("Hello", 0, 14.0) == 0.0, "prefix_width : zéro caractère")
failed := false
try:
    text.measure("x", 0.0)
catch e:
    failed = true
check(failed, "taille nulle -> erreur")

# ---- index_at (clic -> curseur) ----
s := "Bonjour monde"
check(text.index_at(s, -10.0, 14.0) == 0, "index_at : avant le début")
check(text.index_at(s, 10000.0, 14.0) == len(s), "index_at : après la fin")
i := 0
ok := true
while i <= len(s):
    x := text.prefix_width(s, i, 14.0)
    if text.index_at(s, x, 14.0) != i:
        ok = false
    i += 1
check(ok, "index_at : retrouve chaque position de curseur exactement")
mid := (text.prefix_width(s, 3, 14.0) + text.prefix_width(s, 4, 14.0)) / 2.0
check(text.index_at(s, mid - 0.5, 14.0) == 3 and text.index_at(s, mid + 0.5, 14.0) == 4, "index_at : arrondi au caractère le plus proche")
u := "Café é 日本"
check(text.index_at(u, text.prefix_width(u, 5, 14.0), 14.0) == 5, "index_at : caractères accentués / non latins")

# ---- mots ----
t := "foo bar_baz  qux"
check(text.word_start(t, 7) == 4, "word_start : milieu de mot")
check(text.word_end(t, 4) == 11, "word_end : mot avec underscore")
check(text.word_end(t, 11) == 16, "word_end : saute les espaces")
b := text.word_bounds(t, 5)
check(b[0] == 4 and b[1] == 11, "word_bounds : double-clic sur un mot")
b = text.word_bounds(t, 11)
check(b[0] == 11 and b[1] == 13, "word_bounds : double-clic sur des espaces")

# ---- lignes ----
m := "ab\ncde\n\nf"
check(text.line_count(m) == 4 and text.line_of(m, 4) == 1 and text.line_of(m, 8) == 3, "lignes : comptage et numéro")
check(text.line_start(m, 4) == 3 and text.line_end(m, 4) == 6, "lignes : début / fin")
check(text.index_of_line(m, 2) == 7 and text.index_of_line(m, 3) == 8, "lignes : index_of_line")

# ---- édition ----
e := edit.create("")
check(edit.insert(e, "H") and edit.insert(e, "i") and e["text"] == "Hi" and e["caret"] == 2, "insert")
edit.insert(e, "\n")
check(e["text"] == "Hi " and e["caret"] == 3, "mono-ligne : retour chariot remplacé par un espace")
e = edit.create("Hello world")
edit.set_caret(e, 5)
edit.move(e, "left", true)
edit.move(e, "left", true)
check(edit.selected_text(e) == "lo", "Maj+Gauche étend la sélection")
edit.move(e, "right", false)
check(not edit.has_selection(e) and e["caret"] == 5, "flèche sans Maj : replie la sélection au bord")
edit.select_word(e, 8)
check(edit.selected_text(e) == "world", "select_word")
edit.insert(e, "monde")
check(e["text"] == "Hello monde" and e["caret"] == 11, "insert remplace la sélection")
edit.select_all(e)
check(edit.selected_text(e) == "Hello monde", "select_all")
edit.backspace(e)
check(e["text"] == "" and e["caret"] == 0, "backspace supprime la sélection")
check(edit.backspace(e) == false and edit.delete(e) == false, "backspace/delete en limites : rien")
e = edit.create("abc déf")
edit.backspace(e)
edit.backspace(e)
check(e["text"] == "abc d", "backspace : un caractère accentué entier")
edit.backspace(e, true)
check(e["text"] == "abc ", "Ctrl+Backspace : mot précédent")
e = edit.create("one two three")
edit.set_caret(e, 0)
edit.delete(e, true)
check(e["text"] == " two three", "Ctrl+Suppr : mot suivant")
edit.move(e, "end")
edit.move(e, "word_left")
check(e["caret"] == 5, "Ctrl+Gauche")
edit.move(e, "home")
check(e["caret"] == 0, "Début")

# ---- historique ----
e = edit.create("")
edit.insert(e, "a")
edit.insert(e, "b")
edit.insert(e, "c")
check(e["text"] == "abc", "frappes")
edit.undo(e)
check(e["text"] == "", "annulation : les frappes consécutives forment une seule étape")
edit.redo(e)
check(e["text"] == "abc", "rétablir")
edit.insert(e, "XYZ")
edit.undo(e)
check(e["text"] == "abc", "annulation d'un collage")
edit.undo(e)
check(e["text"] == "", "annulation : retour au début")
check(edit.undo(e) == false, "annuler sans historique : false")
edit.insert(e, "q")
check(len(e["redo"]) == 0, "une nouvelle édition vide la pile de rétablissement")

# ---- multi-ligne ----
e = edit.create("abc\ndefgh\nij", true)
edit.set_caret(e, 6)
edit.move(e, "up", false, 14.0)
check(text.line_of(e["text"], e["caret"]) == 0 and e["caret"] <= 3, "haut : ligne précédente (colonne conservée)")
edit.move(e, "down", false, 14.0)
edit.move(e, "down", false, 14.0)
check(text.line_of(e["text"], e["caret"]) == 2, "bas deux fois : dernière ligne")
edit.move(e, "down", false, 14.0)
check(e["caret"] == len(e["text"]), "bas sur la dernière ligne : fin du texte")
edit.set_caret(e, 5)
edit.move(e, "home")
check(e["caret"] == 4, "Début : début de LIGNE en multi-ligne")
edit.move(e, "end")
check(e["caret"] == 9, "Fin : fin de ligne")
edit.select_line(e, 5)
check(edit.selected_text(e) == "defgh", "triple-clic : ligne entière")
edit.insert(e, "A\nB")
check(e["text"] == "abc\nA\nB\nij", "insert multi-ligne")

failed = false
try:
    edit.move(e, "diagonale")
catch err:
    failed = true
check(failed, "déplacement inconnu -> erreur")
print("UI EDIT: OK")
