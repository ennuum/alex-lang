# ALEX STANDARD LIBRARY — regex
# Expressions régulières en ALEX pur : moteur à retour arrière (backtracking), syntaxe proche de Python/PCRE.
#
#   use regex
#   regex.test("^[a-z]+@[a-z]+\\.com$", "ada@exemple.com")          # true
#   m := regex.search("(\\d+)-(?P<mois>\\d+)", "le 12-05")          # m["text"] == "12-05", m["groups"] == ["12", "05"]
#   regex.find_all("\\w+", "un deux trois")                          # ["un", "deux", "trois"]
#   regex.replace("(\\w+)@", "ada@x", "<\\1>@")                      # "<ada>@x"
#   regex.split("\\s*,\\s*", "a , b,c")                              # ["a", "b", "c"]
#
# Syntaxe : littéraux, . (tout sauf \n, sauf drapeau s), classes [abc] [a-z] [^a-z] (avec \d \w \s dedans),
#   \d \D \w \W \s \S, ancres ^ $ \b \B, groupes (...), (?:...), nommés (?P<nom>...) ou (?<nom>...),
#   alternance a|b, quantificateurs * + ? {n} {n,} {n,m} (suffixe ? = paresseux), références arrière \1..\9,
#   anticipations (?=...) (?!...), échappements \n \t \r et \. \\ etc. (tout caractère échappé est littéral).
# Non supporté : lookbehind, groupes atomiques, quantificateurs possessifs, classes POSIX, \p{...}.
# Drapeaux (paramètre `flags`, ex. "im" ; pas de (?i) en ligne) : i = insensible à la casse (ASCII, latin, grec, cyrillique), m = ^ $ par ligne, s = . accepte \n.
# \d = 0-9 ; \w = lettres (ASCII, latin, grec, cyrillique, hébreu, arabe, kana, CJK, hangul), chiffres et _ ; \s = espace, \t \n \r et espaces Unicode usuels.
#
# Un « motif » est une str (compilée et mise en cache) ou le résultat de regex.compile(...).
# Objet match : {"text": str, "start": int, "end": int, "groups": [str|null...], "named": {nom: str|null}}.
# Les positions sont en points de code. Un groupe qui n'a pas participé vaut null.
# Erreurs : raise("RegexError", message) pour un motif invalide ; TypeError pour un mauvais type d'argument.
# Attention : le moteur est récursif et exponentiel dans les pires cas (ex. (a+)+b) ; éviter les motifs imbriqués
#   ambigus sur des entrées non fiables. Les répétitions simples (a*, [a-z]+, .*) sont itératives, sans limite de taille.

from core use len, type
from collections use append, keys, contains_key, clear
use string

func _fail(message):
    raise("RegexError", message)

const _INF := 2147483647

# --- casse et lettres Unicode (latin, grec, cyrillique) ---------------------------------------------------
# string.lower / string.upper ne traitent que l'ASCII ; regex a donc sa propre table de casse, limitée aux
# alphabets courants (Latin-1, Latin étendu A, grec, cyrillique). Les autres caractères sont inchangés.

func _lower_code(o):
    if o < 128:
        if o >= 65 and o <= 90:
            return o + 32
        return o
    if (o >= 192 and o <= 222 and o != 215) or (o >= 913 and o <= 937 and o != 930) or (o >= 1040 and o <= 1071):
        return o + 32
    if o >= 1024 and o <= 1039:
        return o + 80
    if (o >= 256 and o <= 311) or (o >= 330 and o <= 375) or (o >= 1120 and o <= 1175):
        if o % 2 == 0:
            return o + 1
        return o
    if (o >= 313 and o <= 328) or (o >= 377 and o <= 382):
        if o % 2 == 1:
            return o + 1
        return o
    return o

func _upper_code(o):
    if o < 128:
        if o >= 97 and o <= 122:
            return o - 32
        return o
    if (o >= 224 and o <= 254 and o != 247) or (o >= 945 and o <= 969 and o != 962) or (o >= 1072 and o <= 1103):
        return o - 32
    if o >= 1104 and o <= 1119:
        return o - 80
    if (o >= 256 and o <= 311) or (o >= 330 and o <= 375) or (o >= 1120 and o <= 1175):
        if o % 2 == 1:
            return o - 1
        return o
    if (o >= 313 and o <= 328) or (o >= 377 and o <= 382):
        if o % 2 == 0:
            return o - 1
        return o
    return o

func _lower(ch):
    o := string.ord(ch)
    l := _lower_code(o)
    if l == o:
        return ch
    return str(string.chr(l))

func _upper(ch):
    o := string.ord(ch)
    u := _upper_code(o)
    if u == o:
        return ch
    return str(string.chr(u))

# Lettre non ASCII : blocs latin, grec, cyrillique, hébreu, arabe, kana, CJK, hangul.
func _is_alpha_code(o):
    return o == 170 or o == 181 or o == 186 or (o >= 192 and o <= 214) or (o >= 216 and o <= 246) or (o >= 248 and o <= 705) or (o >= 880 and o <= 1327) or (o >= 1488 and o <= 1514) or (o >= 1569 and o <= 1610) or (o >= 12353 and o <= 12543) or (o >= 19968 and o <= 40959) or (o >= 44032 and o <= 55203)

func _is_digit(ch):
    o := string.ord(ch)
    return o >= 48 and o <= 57

func _is_word(ch):
    o := string.ord(ch)
    if (o >= 48 and o <= 57) or (o >= 65 and o <= 90) or (o >= 97 and o <= 122) or o == 95:
        return true
    return _is_alpha_code(o)

func _is_space(ch):
    o := string.ord(ch)
    return o == 32 or (o >= 9 and o <= 13) or o == 133 or o == 160 or o == 5760 or (o >= 8192 and o <= 8202) or o == 8232 or o == 8233 or o == 8239 or o == 8287 or o == 12288

func _class_hit(cls, ch):
    if cls == "d":
        return _is_digit(ch)
    if cls == "D":
        return not _is_digit(ch)
    if cls == "w":
        return _is_word(ch)
    if cls == "W":
        return not _is_word(ch)
    if cls == "s":
        return _is_space(ch)
    return not _is_space(ch)

func _text(chars, a, b):
    out := []
    while a < b:
        append(out, chars[a])
        a = a + 1
    return string.join("", out)

# --- analyse du motif -------------------------------------------------------------------------------------

class _Parser:
    func init(pattern):
        self.chars = []
        for c in pattern:
            append(self.chars, str(c))
        self.n = len(self.chars)
        self.pos = 0
        self.ngroups = 0
        self.names = {}

    func error(message):
        _fail(message + " (position " + str(self.pos) + ")")

    func peek():
        if self.pos < self.n:
            return self.chars[self.pos]
        return null

    func peek_at(k):
        if self.pos + k < self.n:
            return self.chars[self.pos + k]
        return null

    func parse_alt():
        branches := [self.parse_seq()]
        while self.peek() == "|":
            self.pos = self.pos + 1
            append(branches, self.parse_seq())
        if len(branches) == 1:
            return branches[0]
        return ["alt", branches]

    func parse_seq():
        items := []
        while self.pos < self.n:
            ch := self.chars[self.pos]
            if ch == "|" or ch == ")":
                break
            atom := self.parse_atom()
            atom = self.parse_quant(atom)
            append(items, atom)
        return ["seq", items]

    # Lit un entier décimal ; null s'il n'y a pas de chiffre.
    func read_int():
        start := self.pos
        v := 0
        while self.pos < self.n and _is_digit(self.chars[self.pos]):
            v = v * 10 + (string.ord(self.chars[self.pos]) - 48)
            self.pos = self.pos + 1
        if self.pos == start:
            return null
        return v

    func parse_quant(atom):
        ch := self.peek()
        mn := 0
        mx := _INF
        if ch == "*":
            self.pos = self.pos + 1
        elif ch == "+":
            mn = 1
            self.pos = self.pos + 1
        elif ch == "?":
            mx = 1
            self.pos = self.pos + 1
        elif ch == "{":
            save := self.pos
            self.pos = self.pos + 1
            a := self.read_int()
            if a == null:
                self.pos = save
                return atom
            mn = a
            mx = a
            if self.peek() == ",":
                self.pos = self.pos + 1
                b := self.read_int()
                if b == null:
                    mx = _INF
                else:
                    mx = b
            if self.peek() != "}":
                self.pos = save
                return atom
            self.pos = self.pos + 1
            if mx < mn:
                self.error("quantificateur {n,m} avec m < n")
        else:
            return atom
        kind := atom[0]
        if kind == "start" or kind == "end" or kind == "wordb" or kind == "nwordb" or kind == "look":
            self.error("rien à répéter")
        greedy := true
        if self.peek() == "?":
            greedy = false
            self.pos = self.pos + 1
        nxt := self.peek()
        if nxt == "*" or nxt == "+":
            self.error("quantificateurs possessifs / multiples non supportés")
        return ["rep", atom, mn, mx, greedy]

    func parse_atom():
        ch := self.chars[self.pos]
        if ch == "(":
            return self.parse_group()
        if ch == "[":
            return self.parse_class()
        if ch == ".":
            self.pos = self.pos + 1
            return ["any"]
        if ch == "^":
            self.pos = self.pos + 1
            return ["start"]
        if ch == "$":
            self.pos = self.pos + 1
            return ["end"]
        if ch == "*" or ch == "+" or ch == "?":
            self.error("rien à répéter")
        if ch == "\\":
            return self.parse_escape()
        self.pos = self.pos + 1
        return ["char", ch]

    func parse_group():
        self.pos = self.pos + 1
        idx := -1
        look := null
        if self.peek() == "?":
            nxt := self.peek_at(1)
            if nxt == ":":
                self.pos = self.pos + 2
            elif nxt == "=" or nxt == "!":
                look = (nxt == "!")
                self.pos = self.pos + 2
            elif nxt == "P" or nxt == "<":
                if nxt == "P":
                    self.pos = self.pos + 1
                if self.peek_at(1) != "<":
                    self.error("nom de groupe attendu : (?P<nom>...)")
                self.pos = self.pos + 2
                start := self.pos
                while self.pos < self.n and self.chars[self.pos] != ">":
                    self.pos = self.pos + 1
                if self.pos >= self.n:
                    self.error("nom de groupe non terminé")
                name := _text(self.chars, start, self.pos)
                self.pos = self.pos + 1
                if name == "" or not _is_word(name[0]) or _is_digit(name[0]):
                    self.error("nom de groupe invalide")
                if contains_key(self.names, name):
                    self.error("nom de groupe dupliqué '" + name + "'")
                self.ngroups = self.ngroups + 1
                idx = self.ngroups
                self.names[name] = idx
            else:
                self.error("construction (?" + str(nxt) + "...) non supportée")
        else:
            self.ngroups = self.ngroups + 1
            idx = self.ngroups
        inner := self.parse_alt()
        if self.peek() != ")":
            self.error("parenthèse fermante manquante")
        self.pos = self.pos + 1
        if look != null:
            return ["look", look, inner]
        return ["group", idx, inner]

    func parse_escape():
        self.pos = self.pos + 1
        if self.pos >= self.n:
            self.error("antislash final")
        ch := self.chars[self.pos]
        self.pos = self.pos + 1
        if ch == "d" or ch == "w" or ch == "s":
            return ["set", false, [["c", ch]]]
        if ch == "D" or ch == "W" or ch == "S":
            return ["set", false, [["c", ch]]]
        if ch == "b":
            return ["wordb"]
        if ch == "B":
            return ["nwordb"]
        if _is_digit(ch) and ch != "0":
            return ["backref", string.ord(ch) - 48]
        return ["char", self.simple_escape(ch)]

    func simple_escape(ch):
        if ch == "n":
            return "\n"
        if ch == "t":
            return "\t"
        if ch == "r":
            return "\r"
        return ch

    func parse_class():
        self.pos = self.pos + 1
        neg := false
        if self.peek() == "^":
            neg = true
            self.pos = self.pos + 1
        items := []
        first := true
        while true:
            if self.pos >= self.n:
                self.error("crochet fermant manquant")
            ch := self.chars[self.pos]
            if ch == "]" and not first:
                self.pos = self.pos + 1
                break
            first = false
            lo := self.class_atom()
            if type(lo) == "list":
                append(items, lo)
                continue
            if self.peek() == "-" and self.peek_at(1) != null and self.peek_at(1) != "]":
                self.pos = self.pos + 1
                hi := self.class_atom()
                if type(hi) == "list":
                    self.error("intervalle invalide dans la classe")
                if hi < lo:
                    self.error("intervalle inversé dans la classe")
                append(items, ["r", lo, hi])
            else:
                append(items, ["r", lo, lo])
        return ["set", neg, items]

    # Renvoie un point de code (int) ou un item ["c", classe].
    func class_atom():
        ch := self.chars[self.pos]
        self.pos = self.pos + 1
        if ch != "\\":
            return string.ord(ch)
        if self.pos >= self.n:
            self.error("antislash final")
        e := self.chars[self.pos]
        self.pos = self.pos + 1
        if e == "d" or e == "D" or e == "w" or e == "W" or e == "s" or e == "S":
            return ["c", e]
        if e == "b":
            return 8
        return string.ord(self.simple_escape(e))

# --- exécution ---------------------------------------------------------------------------------------------

class _Matcher:
    func init(chars, ngroups, icase, multi, dotall):
        self.chars = chars
        self.n = len(chars)
        self.icase = icase
        self.multi = multi
        self.dotall = dotall
        self.caps = []
        k := 0
        while k <= ngroups:
            append(self.caps, null)
            k = k + 1

    func reset():
        k := 0
        while k < len(self.caps):
            self.caps[k] = null
            k = k + 1

    func set_hit(items, ch):
        o := string.ord(ch)
        for it in items:
            if it[0] == "r":
                if o >= it[1] and o <= it[2]:
                    return true
            elif _class_hit(it[1], ch):
                return true
        return false

    # Un nœud « un caractère » (char / any / set) accepte-t-il le caractère en i ?
    func one(node, i):
        if i >= self.n:
            return false
        ch := self.chars[i]
        kind := node[0]
        if kind == "char":
            if ch == node[1]:
                return true
            return self.icase and _lower(ch) == _lower(node[1])
        if kind == "any":
            return self.dotall or ch != "\n"
        hit := self.set_hit(node[2], ch)
        if not hit and self.icase:
            lo := _lower(ch)
            up := _upper(ch)
            if lo != ch:
                hit = self.set_hit(node[2], lo)
            if not hit and up != ch:
                hit = self.set_hit(node[2], up)
        return hit != node[1]

    func word_at(i):
        return i >= 0 and i < self.n and _is_word(self.chars[i])

    func seq(items, idx, i, k):
        if idx == len(items):
            return k(i)
        if idx == len(items) - 1:
            return self.m(items[idx], i, k)
        return self.m(items[idx], i, j => self.seq(items, idx + 1, j, k))

    func after_group(idx, start, j, k):
        prev := self.caps[idx]
        self.caps[idx] = [start, j]
        r := k(j)
        if r < 0:
            self.caps[idx] = prev
        return r

    func rep(node, count, i, k):
        sub := node[1]
        mn := node[2]
        mx := node[3]
        if node[4]:
            if count < mx:
                r := self.m(sub, i, j => self.rep_next(node, count, i, j, k))
                if r >= 0:
                    return r
            if count >= mn:
                return k(i)
            return -1
        if count >= mn:
            r := k(i)
            if r >= 0:
                return r
        if count < mx:
            return self.m(sub, i, j => self.rep_next(node, count, i, j, k))
        return -1

    # Évite les boucles infinies sur les sous-motifs qui acceptent le vide.
    func rep_next(node, count, i, j, k):
        if j == i and count >= node[2]:
            return -1
        return self.rep(node, count + 1, j, k)

    func m(node, i, k):
        kind := node[0]
        if kind == "char" or kind == "any" or kind == "set":
            if self.one(node, i):
                return k(i + 1)
            return -1
        if kind == "seq":
            return self.seq(node[1], 0, i, k)
        if kind == "alt":
            for branch in node[1]:
                r := self.m(branch, i, k)
                if r >= 0:
                    return r
            return -1
        if kind == "group":
            idx := node[1]
            if idx < 0:
                return self.m(node[2], i, k)
            return self.m(node[2], i, j => self.after_group(idx, i, j, k))
        if kind == "rep":
            sub := node[1]
            sk := sub[0]
            if sk == "char" or sk == "any" or sk == "set":
                return self.rep_simple(node, i, k)
            return self.rep(node, 0, i, k)
        if kind == "start":
            if i == 0 or (self.multi and self.chars[i - 1] == "\n"):
                return k(i)
            return -1
        if kind == "end":
            if i == self.n or (self.multi and self.chars[i] == "\n"):
                return k(i)
            return -1
        if kind == "wordb" or kind == "nwordb":
            at_b := self.word_at(i - 1) != self.word_at(i)
            if at_b == (kind == "wordb"):
                return k(i)
            return -1
        if kind == "backref":
            cap := self.caps[node[1]] if node[1] < len(self.caps) else null
            if cap == null:
                return -1
            length := cap[1] - cap[0]
            if i + length > self.n:
                return -1
            t := 0
            while t < length:
                a := self.chars[cap[0] + t]
                b := self.chars[i + t]
                if a != b and not (self.icase and _lower(a) == _lower(b)):
                    return -1
                t = t + 1
            return k(i + length)
        if kind == "look":
            r := self.m(node[2], i, j => j)
            if (r >= 0) != node[1]:
                return k(i)
            return -1
        _fail("nœud inconnu : " + kind)

    # Répétition d'un nœud « un caractère » : itérative (pas de récursion par caractère).
    func rep_simple(node, i, k):
        sub := node[1]
        mn := node[2]
        mx := node[3]
        if node[4]:
            cnt := 0
            while cnt < mx and self.one(sub, i + cnt):
                cnt = cnt + 1
            while cnt >= mn:
                r := k(i + cnt)
                if r >= 0:
                    return r
                cnt = cnt - 1
            return -1
        cnt := 0
        while cnt < mn:
            if not self.one(sub, i + cnt):
                return -1
            cnt = cnt + 1
        while true:
            r := k(i + cnt)
            if r >= 0:
                return r
            if cnt >= mx or not self.one(sub, i + cnt):
                return -1
            cnt = cnt + 1

# --- API : compilation --------------------------------------------------------------------------------------

_state := {"cache": {}}

func _parse_flags(flags):
    if type(flags) != "str":
        raise("TypeError", "regex : les drapeaux doivent être une str (ex. \"im\")")
    f := {"i": false, "m": false, "s": false}
    for c in flags:
        ch := str(c)
        if not contains_key(f, ch):
            _fail("drapeau inconnu '" + ch + "' (i, m, s)")
        f[ch] = true
    return f

# Compile un motif. Renvoie un dict opaque {"pattern", "flags", ...} utilisable à la place de la str.
func compile(pattern, flags=""):
    if type(pattern) != "str":
        raise("TypeError", "regex.compile : motif str attendu (obtenu '" + type(pattern) + "')")
    key := flags + "/" + pattern
    cache := _state["cache"]
    if contains_key(cache, key):
        return cache[key]
    f := _parse_flags(flags)
    p := _Parser(pattern)
    ast := p.parse_alt()
    if p.pos < p.n:
        p.error("parenthèse fermante inattendue")
    rx := {"pattern": pattern, "flags": flags, "ast": ast, "ngroups": p.ngroups, "names": p.names,
           "icase": f["i"], "multi": f["m"], "dotall": f["s"]}
    if len(cache) >= 128:
        cache = {}
        _state["cache"] = cache
    cache[key] = rx
    return rx

func _rx(pattern, flags):
    if type(pattern) == "dict":
        return pattern
    return compile(pattern, flags)

func _chars(s, fn):
    if type(s) != "str":
        raise("TypeError", "regex." + fn + " : texte str attendu (obtenu '" + type(s) + "')")
    out := []
    for c in s:
        append(out, str(c))
    return out

func _build(rx, mt, chars, start, end):
    groups := []
    k := 1
    while k <= rx["ngroups"]:
        cap := mt.caps[k]
        if cap == null:
            append(groups, null)
        else:
            append(groups, _text(chars, cap[0], cap[1]))
        k = k + 1
    named := {}
    for name in keys(rx["names"]):
        named[name] = groups[rx["names"][name] - 1]
    return {"text": _text(chars, start, end), "start": start, "end": end, "groups": groups, "named": named}

func _matcher(rx, chars):
    return _Matcher(chars, rx["ngroups"], rx["icase"], rx["multi"], rx["dotall"])

# Essaie le motif exactement à la position `pos`.
func _match_at(rx, mt, chars, pos, need_end):
    mt.reset()
    r := -1
    if need_end:
        r = mt.m(rx["ast"], pos, j => j if j == mt.n else -1)
    else:
        r = mt.m(rx["ast"], pos, j => j)
    if r < 0:
        return null
    return _build(rx, mt, chars, pos, r)

# Correspondance ANCRÉE au début du texte (comme re.match de Python ; `match` est un mot-clé d'ALEX). Renvoie un match ou null.
func match_start(pattern, text, flags=""):
    rx := _rx(pattern, flags)
    chars := _chars(text, "match_start")
    return _match_at(rx, _matcher(rx, chars), chars, 0, false)

# Le texte ENTIER doit correspondre (comme re.fullmatch).
func fullmatch(pattern, text, flags=""):
    rx := _rx(pattern, flags)
    chars := _chars(text, "fullmatch")
    return _match_at(rx, _matcher(rx, chars), chars, 0, true)

func _search_from(rx, mt, chars, start):
    pos := start
    while pos <= len(chars):
        r := _match_at(rx, mt, chars, pos, false)
        if r != null:
            return r
        pos = pos + 1
    return null

# Première correspondance n'importe où dans le texte, à partir de `start` (défaut 0). match ou null.
func search(pattern, text, flags="", start=0):
    rx := _rx(pattern, flags)
    chars := _chars(text, "search")
    if type(start) != "int" or start < 0:
        raise("ValueError", "regex.search : start doit être un entier >= 0")
    return _search_from(rx, _matcher(rx, chars), chars, start)

# Vrai si le motif correspond quelque part dans le texte.
func test(pattern, text, flags=""):
    return search(pattern, text, flags) != null

# Toutes les correspondances sans chevauchement, comme objets match. Une correspondance vide avance d'un caractère.
func finditer(pattern, text, flags=""):
    rx := _rx(pattern, flags)
    chars := _chars(text, "finditer")
    mt := _matcher(rx, chars)
    out := []
    pos := 0
    while pos <= len(chars):
        r := _search_from(rx, mt, chars, pos)
        if r == null:
            break
        append(out, r)
        if r["end"] == r["start"]:
            pos = r["end"] + 1
        else:
            pos = r["end"]
    return out

# Textes des correspondances (liste de str).
func find_all(pattern, text, flags=""):
    out := []
    for r in finditer(pattern, text, flags):
        append(out, r["text"])
    return out

func _expand(repl, mt):
    chars := []
    for c in repl:
        append(chars, str(c))
    out := []
    i := 0
    n := len(chars)
    while i < n:
        c := chars[i]
        if c != "\\" or i + 1 >= n:
            append(out, c)
            i = i + 1
            continue
        d := chars[i + 1]
        if _is_digit(d):
            g := string.ord(d) - 48
            if g == 0:
                append(out, mt["text"])
            elif g > len(mt["groups"]):
                _fail("référence \\" + d + " invalide dans le remplacement (le motif n'a que " + str(len(mt["groups"])) + " groupe(s))")
            elif mt["groups"][g - 1] != null:
                append(out, mt["groups"][g - 1])
            i = i + 2
        elif d == "g" and i + 2 < n and chars[i + 2] == "<":
            j := i + 3
            while j < n and chars[j] != ">":
                j = j + 1
            if j >= n:
                _fail("\\g< non terminé dans le remplacement")
            name := _text(chars, i + 3, j)
            val := null
            if contains_key(mt["named"], name):
                val = mt["named"][name]
            elif len(name) > 0 and _is_digit(name[0]):
                g := 0
                for dd in name:
                    g = g * 10 + (string.ord(dd) - 48)
                if g == 0:
                    val = mt["text"]
                elif g <= len(mt["groups"]):
                    val = mt["groups"][g - 1]
                else:
                    _fail("groupe \\g<" + name + "> inexistant")
            else:
                _fail("groupe \\g<" + name + "> inexistant")
            if val != null:
                append(out, val)
            i = j + 1
        elif d == "\\":
            append(out, "\\")
            i = i + 2
        elif d == "n":
            append(out, "\n")
            i = i + 2
        elif d == "t":
            append(out, "\t")
            i = i + 2
        else:
            append(out, c)
            append(out, d)
            i = i + 2
    return string.join("", out)

# Remplace les correspondances. `repl` : str (avec \1 \g<nom> \0 \\ \n \t) ou fonction(match) -> str.
# count = 0 : toutes ; sinon au plus `count`.
func replace(pattern, text, repl, count=0, flags=""):
    rx := _rx(pattern, flags)
    chars := _chars(text, "replace")
    is_fn := type(repl) == "function"
    if not is_fn and type(repl) != "str":
        raise("TypeError", "regex.replace : repl doit être une str ou une fonction")
    mt := _matcher(rx, chars)
    out := []
    last := 0
    pos := 0
    done := 0
    while pos <= len(chars) and (count == 0 or done < count):
        r := _search_from(rx, mt, chars, pos)
        if r == null:
            break
        append(out, _text(chars, last, r["start"]))
        if is_fn:
            v := repl(r)
            if type(v) != "str":
                raise("TypeError", "regex.replace : la fonction doit renvoyer une str")
            append(out, v)
        else:
            append(out, _expand(repl, r))
        last = r["end"]
        done = done + 1
        if r["end"] == r["start"]:
            pos = r["end"] + 1
        else:
            pos = r["end"]
    append(out, _text(chars, last, len(chars)))
    return string.join("", out)

# Découpe le texte autour des correspondances (les groupes capturés sont insérés, comme Python).
# maxsplit = 0 : sans limite.
func split(pattern, text, maxsplit=0, flags=""):
    rx := _rx(pattern, flags)
    chars := _chars(text, "split")
    out := []
    last := 0
    done := 0
    for r in finditer(rx, text):
        if maxsplit > 0 and done >= maxsplit:
            break
        if r["end"] == r["start"] and (r["start"] == 0 or r["start"] == len(chars)):
            continue
        append(out, _text(chars, last, r["start"]))
        for g in r["groups"]:
            if g != null:
                append(out, g)
        last = r["end"]
        done = done + 1
    append(out, _text(chars, last, len(chars)))
    return out

# Échappe les caractères spéciaux pour insérer `text` tel quel dans un motif.
func escape(text):
    if type(text) != "str":
        raise("TypeError", "regex.escape : chaîne attendue")
    special := "\\.^$*+?{}[]()|-"
    out := []
    for c in text:
        ch := str(c)
        if string.contains(special, ch):
            append(out, "\\")
        append(out, ch)
    return string.join("", out)
