# Calculatrice : application graphique Windows native, compilée par ALEX sans C ni éditeur de liens.
#   alexc build --native --windows --gui examples/windows/calculatrice.al -o calculatrice.exe
use wingui
use os
use math
use string
from core use len, to_float
from collections use contains_key

# ---- État : valeur accumulée, opération en attente, saisie en cours ----
acc := 0.0
op := ""
saisie := "0"
nouvelle := true      # le prochain chiffre commence une nouvelle saisie
erreur := false

func texte(x: float) -> str:
    if math.abs(x) < 1000000000000000.0:
        t := math.trunc(x)
        if to_float(str(t)) == x:   # valeur entière : sans « ,0 »
            return str(t)
    return string.replace(str(x), ".", ",")

func valeur(s: str) -> float:
    return to_float(string.replace(s, ",", "."))

func calcule(a: float, o: str, b: float) -> float:
    if o == "+":
        return a + b
    if o == "−":
        return a - b
    if o == "×":
        return a * b
    return a / b      # ZeroDivisionError si b == 0

# ---- Interface ----
fen := wingui.window("Calculatrice ALEX", 300, 396)
historique := wingui.label(fen, "", 12, 10, 276, 20, true)
ecran := wingui.edit(fen, "0", 12, 32, 276, 48, true, true)
wingui.set_font(ecran, wingui.font(22, true))

func affiche():
    wingui.set_text(ecran, saisie)

func remet_a_zero():
    acc = 0.0
    op = ""
    saisie = "0"
    nouvelle = true
    erreur = false
    wingui.set_text(historique, "")
    affiche()

func chiffre(c: str):
    if erreur:
        remet_a_zero()
    if nouvelle or saisie == "0":
        saisie = c
        if c == ",":
            saisie = "0,"
    elif c != "," or string.find(saisie, ",") < 0:
        if len(saisie) < 16:
            saisie = saisie + c
    nouvelle = false
    affiche()

func applique() -> bool:
    if op == "":
        acc = valeur(saisie)
        return true
    try:
        acc = calcule(acc, op, valeur(saisie))
    catch e:
        saisie = "Erreur"
        erreur = true
        wingui.set_text(historique, "division par zéro")
        affiche()
        return false
    saisie = texte(acc)
    return true

func operation(o: str):
    if erreur:
        return
    if not nouvelle or op == "":
        if not applique():
            return
    op = o
    nouvelle = true
    wingui.set_text(historique, saisie + " " + o)
    affiche()

func egal():
    if erreur or op == "":
        return
    h := texte(acc) + " " + op + " " + saisie + " ="
    if applique():
        wingui.set_text(historique, h)
        op = ""
        nouvelle = true
        affiche()

func efface_dernier():
    if erreur or nouvelle:
        return
    if len(saisie) <= 1 or (len(saisie) == 2 and string.starts_with(saisie, "-")):
        saisie = "0"
    else:
        saisie = string.substring(saisie, 0, len(saisie) - 1)
    affiche()

func signe():
    if erreur or saisie == "0":
        return
    if string.starts_with(saisie, "-"):
        saisie = string.substring(saisie, 1, len(saisie))
    else:
        saisie = "-" + saisie
    affiche()

# ---- Clavier de boutons : 5 rangées de 4 ----
boutons: dict[str, int] := {}
L := 66
H := 52
X0 := 12
Y0 := 92
P := 70
func touche(lib: str, col: int, rang: int, larg: int, f: func()):
    boutons[lib] = wingui.button(fen, lib, X0 + col * P, Y0 + rang * 58, larg, H, f)

touche("C", 0, 0, L, () => remet_a_zero())
touche("←", 1, 0, L, () => efface_dernier())
touche("±", 2, 0, L, () => signe())
rangees := [["7", "8", "9"], ["4", "5", "6"], ["1", "2", "3"]]
r := 0
for rangee in rangees:
    k := 0
    for c in rangee:
        touche(c, k, r + 1, L, () => chiffre(c))
        k += 1
    r += 1
i := 0
for o in ["÷", "×", "−", "+"]:
    touche(o, 3, i, L, () => operation(o))
    i += 1
touche("0", 0, 4, L + P, () => chiffre("0"))
touche(",", 2, 4, L, () => chiffre(","))
touche("=", 3, 4, L, () => egal())

# Auto-test (ALEX_CALC_AUTOTEST="7 × 8 =") : clics par BM_CLICK, état affiché après chacun ; puis image de la
# fenêtre si ALEX_CALC_CAPTURE donne un fichier .bmp, et fermeture.
auto := os.getenv("ALEX_CALC_AUTOTEST")
if auto != null:
    alias := {"*": "×", "/": "÷", "-": "−", "<": "←", "n": "±"}   # touches spéciales en ASCII
    for t in string.split(auto, " "):
        lib := t
        if contains_key(alias, t):
            lib = alias[t]
        wingui.click(boutons[lib])
        print("clic " + lib + " -> [" + wingui.get_text(historique) + "] [" + wingui.get_text(ecran) + "]")
    image := os.getenv("ALEX_CALC_CAPTURE")
    if image != null:
        wingui.capture(fen, image)
    wingui.close(fen)

wingui.run()
