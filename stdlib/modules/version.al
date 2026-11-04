# ALEX STANDARD LIBRARY — modules.version
#
# Versions sémantiques (SemVer 2.0.0) et contraintes — mêmes règles que le gestionnaire de paquets
# (`alexc pkg`, src/Semver.cpp), plus les intervalles composés.
#
#   use modules.version as ver
#   v := ver.parse("1.4.2-rc.1+build.7")
#   print(v.major, v.pre, v.is_prerelease())            # 1 rc.1 true
#   print(ver.compare("1.0.0-rc.1", "1.0.0"))           # -1 (une pré-version précède la finale)
#   print(ver.satisfies("1.4.2", "^1.2"))               # true
#   print(ver.satisfies("2.0.0", ">=1.2 <2.0"))         # false (intervalle : ET)
#   print(ver.satisfies("3.1.0", "^1.0 || ^3.0"))       # true  (alternative : OU)
#   print(ver.max_satisfying(["1.2.0", "1.9.3", "2.0.0"], "~1.9"))   # 1.9.3
#   print(ver.parse("1.2.3").bump("minor"))             # 1.3.0
#
# Contraintes : "*", "1.2.3" ou "^1.2.3" (même MAJOR ; 0.x fige le MINOR ; 0.0.x fige le PATCH),
# "~1.2.3" (même MAJOR.MINOR), "=1.2.3" (exacte), ">=1.2", ">1.2", "<=1.2", "<2.0", "1.x" / "1.2.x",
# combinaisons « A B » (ET) et « A || B » (OU). Version partielle : "1.2" = "1.2.0".
# Pré-versions (comme npm/Cargo) : une pré-version ne satisfait une contrainte que si celle-ci porte
# elle-même une pré-version sur le même MAJOR.MINOR.PATCH (ou est exacte).
#
# Erreurs : VersionError (version ou contrainte mal formée), TypeError.

from core use len, type, to_int
from collections use append
use string as _s

const ERROR := "VersionError"

func _digits(s):
    if s == "":
        return false
    for c in s:
        if c < '0' or c > '9':
            return false
    return true

func _num(s, what, text):
    if not _digits(s):
        raise(ERROR, "version : " + what + " '" + s + "' invalide dans \"" + text + "\"")
    if len(s) > 1 and s[0] == '0':
        raise(ERROR, "version : zéro de tête interdit dans \"" + text + "\"")
    return to_int(s)

class Version:
    func init(major=0, minor=0, patch=0, pre="", build=""):
        self.major = major
        self.minor = minor
        self.patch = patch
        self.pre = pre
        self.build = build

    func is_prerelease():
        return self.pre != ""

    func core():
        return Version(self.major, self.minor, self.patch)

    # Version suivante : "major", "minor", "patch", "pre" (rc.1 -> rc.2, ou 1.2.3 -> 1.2.4-0).
    func bump(part, pre_tag=null):
        if part == "major":
            return Version(self.major + 1, 0, 0)
        if part == "minor":
            return Version(self.major, self.minor + 1, 0)
        if part == "patch":
            if self.pre != "":
                return Version(self.major, self.minor, self.patch)
            return Version(self.major, self.minor, self.patch + 1)
        if part == "pre":
            if self.pre == "":
                tag := "0"
                if pre_tag != null:
                    tag = pre_tag + ".1"
                return Version(self.major, self.minor, self.patch + 1, tag)
            ids := _s.split(self.pre, ".")
            last := ids[len(ids) - 1]
            if _digits(last):
                ids[len(ids) - 1] = str(to_int(last) + 1)
            else:
                append(ids, "1")
            return Version(self.major, self.minor, self.patch, _s.join(".", ids))
        raise("ArgumentError", "Version.bump : partie inconnue '" + str(part) + "' (major, minor, patch, pre)")

    func compare(other):
        return compare(self, other)

    func __eq__(other):
        return isinstance(other, Version) and compare(self, other) == 0

    func __lt__(other):
        return compare(self, other) < 0

    func __le__(other):
        return compare(self, other) <= 0

    func __gt__(other):
        return compare(self, other) > 0

    func __ge__(other):
        return compare(self, other) >= 0

    func hash_code():
        return (self.major * 1000003 + self.minor * 1009 + self.patch) * 31 + len(self.pre)

    func __str__():
        out := str(self.major) + "." + str(self.minor) + "." + str(self.patch)
        if self.pre != "":
            out += "-" + self.pre
        if self.build != "":
            out += "+" + self.build
        return out

# Analyse STRICTE : x.y.z[-pré][+build].
func parse(text):
    if isinstance(text, Version):
        return text
    if type(text) != "str":
        raise("TypeError", "version.parse : str attendue (obtenu '" + type(text) + "')")
    t := _s.trim(text)
    if _s.starts_with(t, "v"):
        t = _s.substring(t, 1, len(t))
    build := ""
    i := _s.find(t, "+")
    if i >= 0:
        build = _s.substring(t, i + 1, len(t))
        t = _s.substring(t, 0, i)
        if build == "":
            raise(ERROR, "version : métadonnées de build vides dans \"" + text + "\"")
    pre := ""
    j := _s.find(t, "-")
    if j >= 0:
        pre = _s.substring(t, j + 1, len(t))
        t = _s.substring(t, 0, j)
        if pre == "":
            raise(ERROR, "version : pré-version vide dans \"" + text + "\"")
        for ident in _s.split(pre, "."):
            if ident == "":
                raise(ERROR, "version : identifiant de pré-version vide dans \"" + text + "\"")
            if _digits(ident) and len(ident) > 1 and ident[0] == '0':
                raise(ERROR, "version : zéro de tête dans la pré-version de \"" + text + "\"")
    parts := _s.split(t, ".")
    if len(parts) != 3:
        raise(ERROR, "version : MAJEUR.MINEUR.CORRECTIF attendu (obtenu \"" + text + "\")")
    return Version(_num(parts[0], "majeur", text), _num(parts[1], "mineur", text), _num(parts[2], "correctif", text), pre, build)

# Version partielle acceptée : "1" = 1.0.0, "1.2" = 1.2.0.
func parse_loose(text):
    t := _s.trim(text)
    if _s.starts_with(t, "v"):
        t = _s.substring(t, 1, len(t))
    core := t
    rest := ""
    k := 0
    while k < len(t):
        if t[k] == '-' or t[k] == '+':
            core = _s.substring(t, 0, k)
            rest = _s.substring(t, k, len(t))
            break
        k += 1
    n := len(_s.split(core, "."))
    if n == 1:
        core = core + ".0.0"
    elif n == 2:
        core = core + ".0"
    return parse(core + rest)

func is_valid(text):
    try:
        parse(text)
        return true
    catch e:
        return false

func _cmp_int(a, b):
    if a < b:
        return -1
    if a > b:
        return 1
    return 0

func _cmp_pre(a, b):
    if a == b:
        return 0
    if a == "":
        return 1
    if b == "":
        return -1
    x := _s.split(a, ".")
    y := _s.split(b, ".")
    i := 0
    while i < len(x) and i < len(y):
        p := x[i]
        q := y[i]
        dp := _digits(p)
        dq := _digits(q)
        if dp and dq:
            c := _cmp_int(to_int(p), to_int(q))
            if c != 0:
                return c
        elif dp:
            return -1
        elif dq:
            return 1
        elif p != q:
            if p < q:
                return -1
            return 1
        i += 1
    return _cmp_int(len(x), len(y))

# -1 / 0 / 1 (build ignoré).
func compare(a, b):
    va := parse(a)
    vb := parse(b)
    c := _cmp_int(va.major, vb.major)
    if c == 0:
        c = _cmp_int(va.minor, vb.minor)
    if c == 0:
        c = _cmp_int(va.patch, vb.patch)
    if c == 0:
        c = _cmp_pre(va.pre, vb.pre)
    return c

func sort(versions, reverse=false):
    vs := [parse(v) for v in versions]
    i := 1
    while i < len(vs):
        v := vs[i]
        j := i - 1
        while j >= 0 and ((not reverse and compare(vs[j], v) > 0) or (reverse and compare(vs[j], v) < 0)):
            vs[j + 1] = vs[j]
            j -= 1
        vs[j + 1] = v
        i += 1
    return vs

# ---------------------------------------------------------------- contraintes

# Comparateur élémentaire : op in ["*", "=", "^", "~", ">=", ">", "<=", "<"] ; ref : Version.
class Comparator:
    func init(op, ref):
        self.op = op
        self.ref = ref

    func _base_ok(v):
        r := self.ref
        if self.op == "*":
            return true
        c := compare(v, r)
        if self.op == "=":
            return c == 0
        if self.op == ">=":
            return c >= 0
        if self.op == ">":
            return c > 0
        if self.op == "<=":
            return c <= 0
        if self.op == "<":
            return c < 0
        if self.op == "~":
            return c >= 0 and v.major == r.major and v.minor == r.minor
        if self.op == "^":
            if c < 0:
                return false
            if r.major > 0:
                return v.major == r.major
            if r.minor > 0:
                return v.major == 0 and v.minor == r.minor
            return v.major == 0 and v.minor == 0 and v.patch == r.patch
        return false

    func matches(v):
        if v.is_prerelease() and self.op != "=":
            # Admise seulement si la référence est une pré-version du même x.y.z.
            if self.op == "*" or not self.ref.is_prerelease():
                return false
            if v.major != self.ref.major or v.minor != self.ref.minor or v.patch != self.ref.patch:
                return false
        return self._base_ok(v)

    func __str__():
        if self.op == "*":
            return "*"
        return self.op + str(self.ref)

func _wildcard(tok):
    # "1.x", "1.2.x", "1.*" -> intervalle.
    parts := _s.split(tok, ".")
    nums := []
    for p in parts:
        if p == "x" or p == "X" or p == "*":
            break
        append(nums, _num(p, "composante", tok))
    if len(nums) == 0:
        return [Comparator("*", null)]
    if len(nums) == 1:
        return [Comparator(">=", Version(nums[0], 0, 0)), Comparator("<", Version(nums[0] + 1, 0, 0))]
    return [Comparator(">=", Version(nums[0], nums[1], 0)), Comparator("<", Version(nums[0], nums[1] + 1, 0))]

func _comparator(tok):
    if tok == "*" or tok == "x" or tok == "X":
        return [Comparator("*", null)]
    for op in [">=", "<=", ">", "<", "=", "^", "~"]:
        if _s.starts_with(tok, op):
            rest := _s.trim(_s.substring(tok, len(op), len(tok)))
            if rest == "":
                raise(ERROR, "contrainte : version manquante après '" + op + "'")
            return [Comparator(op, parse_loose(rest))]
    if _s.contains(tok, "x") or _s.contains(tok, "X") or _s.contains(tok, "*"):
        return _wildcard(tok)
    # Version nue = compatible (^), comme alex.toml.
    return [Comparator("^", parse_loose(tok))]

class Constraint:
    func init(text):
        self.text = text
        self.alternatives = []     # liste d'ensembles de comparateurs (OU d'ET)
        for alt in _s.split(text, "||"):
            group := []
            # « >= 1.2 » : rattacher l'opérateur isolé à sa version.
            toks := [x for x in _s.split(_s.trim(alt), " ") if x != ""]
            k := 0
            while k < len(toks):
                tok := toks[k]
                if (tok == ">=" or tok == "<=" or tok == ">" or tok == "<" or tok == "=" or tok == "^" or tok == "~") and k + 1 < len(toks):
                    tok = tok + toks[k + 1]
                    k += 1
                for c in _comparator(tok):
                    append(group, c)
                k += 1
            if len(group) == 0:
                raise(ERROR, "contrainte vide dans \"" + text + "\"")
            append(self.alternatives, group)

    func matches(version):
        v := parse(version)
        for group in self.alternatives:
            ok := true
            for c in group:
                if not c.matches(v):
                    ok = false
                    break
            if ok:
                return true
        return false

    func __str__():
        return self.text

func constraint(text):
    if isinstance(text, Constraint):
        return text
    if type(text) != "str" or _s.trim(text) == "":
        return Constraint("*")
    return Constraint(text)

func satisfies(version, text):
    return constraint(text).matches(version)

# Plus haute version satisfaisant la contrainte (null si aucune).
func max_satisfying(versions, text):
    c := constraint(text)
    best := null
    for v in versions:
        pv := parse(v)
        if c.matches(pv) and (best == null or compare(pv, best) > 0):
            best = pv
    return best

func min_satisfying(versions, text):
    c := constraint(text)
    best := null
    for v in versions:
        pv := parse(v)
        if c.matches(pv) and (best == null or compare(pv, best) < 0):
            best = pv
    return best

# Contrainte « ^ » par défaut pour une version publiée (comme `alexc pkg add`).
func caret(version):
    return "^" + str(parse(version).core())
