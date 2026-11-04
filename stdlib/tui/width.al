# ALEX STANDARD LIBRARY — tui.width
#
# Largeur affichée du texte dans un terminal, en colonnes : 1 pour la plupart des caractères, 2 pour les
# caractères « larges » (CJK, hangûl, la plupart des émojis), 0 pour les marques combinantes et les caractères
# de contrôle. Découpage et coupure de texte à une largeur donnée.
#
#   use tui.width as width
#   width.of("日本")              # 4
#   width.truncate("bonjour", 5)  # "bonj…"
#   width.wrap("un texte assez long", 8)

from core use len, type
from collections use append
use string as _s

# Plages de caractères larges [début, fin] (simplification de la table Unicode East Asian Width W/F).
_WIDE := [[4352, 4447], [8986, 8987], [9001, 9002], [9193, 9196], [9200, 9200], [9203, 9203], [9725, 9726], [9748, 9749], [9800, 9811], [9855, 9855], [9875, 9875], [9889, 9889], [9898, 9899], [9917, 9918], [9924, 9925], [9934, 9934], [9940, 9940], [9962, 9962], [9970, 9971], [9973, 9973], [9978, 9978], [9981, 9981], [9989, 9989], [9994, 9995], [10024, 10024], [10060, 10060], [10062, 10062], [10067, 10069], [10071, 10071], [10133, 10135], [10160, 10160], [10175, 10175], [11035, 11036], [11088, 11088], [11093, 11093], [11904, 12350], [12353, 13311], [13312, 19903], [19968, 40959], [40960, 42191], [43360, 43391], [44032, 55203], [63744, 64255], [65040, 65049], [65072, 65131], [65281, 65376], [65504, 65510], [94176, 101640], [110592, 110959], [126980, 126980], [127183, 127183], [127374, 127374], [127377, 127386], [127488, 127569], [127744, 128591], [128640, 128767], [129280, 129535], [129648, 129791], [131072, 196605], [196608, 262141]]

# Plages de largeur nulle (marques combinantes, sélecteurs de variante, espaces sans largeur).
_ZERO := [[768, 879], [1155, 1161], [1425, 1469], [1552, 1562], [1611, 1631], [6832, 6911], [7616, 7679], [8203, 8207], [8232, 8238], [8288, 8292], [8400, 8432], [65024, 65039], [65056, 65071], [65279, 65279], [917760, 917999]]

func _in(ranges, cp):
    lo := 0
    hi := len(ranges) - 1
    while lo <= hi:
        mid := (lo + hi) // 2
        r := ranges[mid]
        if cp < r[0]:
            hi = mid - 1
        elif cp > r[1]:
            lo = mid + 1
        else:
            return true
    return false

# Largeur d'un caractère (code ou chaîne d'un caractère) : 0, 1 ou 2.
func char_width(c):
    cp := c
    if type(c) != "int":
        cp = _s.ord(c)
    if cp < 32 or (cp >= 127 and cp < 160):
        return 0
    if cp < 768:
        return 1
    if _in(_ZERO, cp):
        return 0
    if cp >= 4352 and _in(_WIDE, cp):
        return 2
    return 1

# Largeur affichée d'un texte (sans séquences ANSI : voir tui.markup.visible_width).
func of(text):
    w := 0
    for c in str(text):
        cp := _s.ord(c)
        if cp >= 32 and cp < 768 and cp != 127:
            w += 1
        else:
            w += char_width(cp)
    return w

# Texte coupé à width colonnes ; ellipsis (« … » par défaut, "" pour aucune) remplace la fin coupée.
func truncate(text, width, ellipsis="…"):
    text = str(text)
    if width <= 0:
        return ""
    if of(text) <= width:
        return text
    room := width - of(ellipsis)
    if room < 0:
        room = 0
        ellipsis = ""
    out := ""
    w := 0
    for c in text:
        cw := char_width(c)
        if w + cw > room:
            break
        out += str(c)
        w += cw
    return out + ellipsis

# Complète avec des espaces jusqu'à width colonnes (align : "left", "right", "center"), en coupant si besoin.
func pad(text, width, align="left"):
    t := truncate(text, width, "")
    gap := width - of(t)
    if gap <= 0:
        return t
    if align == "right":
        return _s.repeat(" ", gap) + t
    if align == "center":
        left := gap // 2
        return _s.repeat(" ", left) + t + _s.repeat(" ", gap - left)
    return t + _s.repeat(" ", gap)

# Lignes d'au plus width colonnes, coupées entre les mots (un mot trop long est coupé) ; les « \n » du texte
# sont respectés.
func wrap(text, width):
    if width < 1:
        width = 1
    out := []
    for para in _s.split(str(text), "\n"):
        line := ""
        lw := 0
        for word in _s.split(para, " "):
            ww := of(word)
            if lw > 0 and lw + 1 + ww <= width:
                line += " " + word
                lw += 1 + ww
                continue
            if lw > 0:
                append(out, line)
                line = ""
                lw = 0
            while ww > width:
                head := truncate(word, width, "")
                append(out, head)
                word = _s.slice(word, len(head))
                ww = of(word)
            line = word
            lw = ww
        append(out, line)
    return out

# Liste des caractères (graphèmes simples : un caractère suivi de ses marques combinantes) avec leur largeur :
# [[texte, largeur], ...]. Utilisé par le tampon d'écran.
func clusters(text):
    out := []
    for c in str(text):
        cw := char_width(c)
        if cw == 0 and len(out) > 0 and _s.ord(c) >= 32:
            last := out[len(out) - 1]
            last[0] = last[0] + str(c)
            continue
        if cw == 0:
            continue
        append(out, [str(c), cw])
    return out
