import numpy as np

def lit(v):
    """Littéral Alex d'une valeur Python / NumPy (sans notation exponentielle)."""
    if isinstance(v, (bool, np.bool_)):
        return "true" if v else "false"
    if isinstance(v, (int, np.integer)):
        return str(int(v))
    if isinstance(v, (float, np.floating)):
        v = float(v)
        if v != v or v in (float("inf"), float("-inf")):
            raise ValueError("valeur non finie")
        s = np.format_float_positional(v, unique=True, trim='0')
        if s.endswith('.'):
            s += '0'
        if '.' not in s:
            s += '.0'
        return s
    if isinstance(v, str):
        return '"' + v.replace('"', '\\"') + '"'
    if isinstance(v, np.ndarray):
        return lit(v.tolist())
    if isinstance(v, (list, tuple)):
        return "[" + ", ".join(lit(x) for x in v) + "]"
    raise TypeError(type(v))

def A(arr):
    """Expression Alex qui construit le tableau."""
    return f"array.from_list({lit(np.asarray(arr).tolist())})"

HEADER = '''# =============================================================================
# ALEX - tests du module stdlib/{mod}/{mod}.al
# {desc}
# Les valeurs attendues proviennent de {ref} (référence indépendante),
# jamais d'un calcul avec le module testé.
#
# Lancer DEPUIS LA RACINE DU PROJET :  ./alex run tests/test_{mod}.al
# Code de sortie 0 si tout passe, 1 sinon.
# =============================================================================
{uses}
from core use len, is_bool
from collections use append, clear

tally := [0, 0]
notes := []
failed_groups := []

func ok():
    tally[0] = tally[0] + 1

func fail(label, detail):
    tally[1] = tally[1] + 1
    append(notes, f"{{label}} : {{detail}}")

func abs_val(v):
    if v < 0:
        return 0 - v
    return v

func check(cond, label):
    if cond:
        ok()
    else:
        fail(label, "condition fausse")

func check_eq(actual, expected, label):
    if actual == expected:
        ok()
    else:
        fail(label, f"obtenu {{actual}}, attendu {{expected}}")

# Erreur relative (absolue si |attendu| < 1).
func check_close(actual, expected, tol, label):
    if actual == null:
        fail(label, f"obtenu null, attendu {{expected}}")
    else:
        scale := abs_val(expected)
        if scale < 1:
            scale = 1
        if abs_val(actual - expected) <= tol * scale:
            ok()
        else:
            fail(label, f"obtenu {{actual}}, attendu {{expected}}")

# Compare deux listes de nombres (même longueur, tolérance relative tol).
func check_list_close(actual, expected, tol, label):
    if len(actual) != len(expected):
        fail(label, f"longueurs {{len(actual)}} et {{len(expected)}}")
    else:
        i := 0
        bad := 0
        while i < len(actual):
            if is_bool(expected[i]) or is_bool(actual[i]):
                if actual[i] != expected[i]:
                    bad = bad + 1
                    if bad == 1:
                        fail(label, f"élément {{i}} : obtenu {{actual[i]}}, attendu {{expected[i]}}")
            else:
                sc := abs_val(expected[i])
                if sc < 1:
                    sc = 1
                if abs_val(actual[i] - expected[i]) > tol * sc:
                    bad = bad + 1
                    if bad == 1:
                        fail(label, f"élément {{i}} : obtenu {{actual[i]}}, attendu {{expected[i]}}")
            i += 1
        if bad == 0:
            ok()

func run(name, fn):
    clear(notes)
    before := tally[1]
    fn()
    if tally[1] > before:
        append(failed_groups, name)
        print(f"  [ÉCHEC]  {{name}}")
        for n in notes:
            print(f"      {{n}}")
    else:
        print(f"  [OK]     {{name}}")

# Vrai si fn() (sans argument) lève une erreur.
func raises(fn):
    threw := false
    try:
        fn()
    catch e:
        threw = true
    return threw

func finish(title, groups):
    total := tally[0] + tally[1]
    print("")
    print(f"=== {{title}} ===")
    print(f"Groupes : {{groups}}, vérifications : {{tally[0]}} réussies, {{tally[1]}} en échec (sur {{total}})")
    if tally[1] > 0:
        print(f"Groupes en échec : {{failed_groups}}")
        raise("AssertionError", f"{{tally[1]}} vérification(s) en échec")
    print(f"TOUS LES TESTS {{title}} PASSENT")
'''

ARR_HELPERS = '''
# Compare un Array à une forme et une liste plate attendues.
func check_arr(a, shape, flat, tol, label):
    if not array.is_array(a):
        fail(label, "un Array était attendu")
    elif not array.array_equal(array.from_list(a.shape), array.from_list(shape)):
        fail(label, f"forme obtenue {{a.shape}}, attendue {{shape}}")
    else:
        check_list_close(a.data, flat, tol, label)
'''

class Suite:
    def __init__(self, mod, desc, ref, uses, with_arr=True):
        self.mod, self.desc, self.ref, self.uses = mod, desc, ref, uses
        self.groups = []      # (name, funcname, [lines])
        self.errfuncs = []
        self.cur = None
        self.nerr = 0
        self.defs = []
        self.with_arr = with_arr

    def group(self, name):
        fn = "t_%d" % (len(self.groups) + 1)
        self.cur = (name, fn, [])
        self.groups.append(self.cur)

    def line(self, s):
        self.cur[2].append("    " + s)

    def arr(self, label, expr, expected, tol=0.0):
        e = np.asarray(expected)
        shape = list(e.shape)
        flat = e.reshape(-1).tolist()
        self.line(f'check_arr({expr}, {lit(shape)}, {lit(flat)}, {lit(float(tol))}, {lit(label)})')

    def close(self, label, expr, expected, tol=1e-13):
        self.line(f'check_close({expr}, {lit(float(expected))}, {lit(float(tol))}, {lit(label)})')

    def eq(self, label, expr, expected):
        self.line(f'check_eq({expr}, {lit(expected)}, {lit(label)})')

    def true(self, label, expr):
        self.line(f'check({expr}, {lit(label)})')

    def lst(self, label, expr, expected, tol=1e-13):
        self.line(f'check_list_close({expr}, {lit(list(np.asarray(expected).reshape(-1).tolist()))}, {lit(float(tol))}, {lit(label)})')

    def err(self, label, stmt):
        self.nerr += 1
        name = "e_%d" % self.nerr
        self.errfuncs.append(f"func {name}():\n    {stmt}\n")
        self.line(f'check(raises({name}), {lit("erreur : " + label)})')

    def define(self, code):
        self.defs.append(code.rstrip() + "\n")

    def raw(self, s):
        self.cur[2].append(s)

    def render(self):
        out = HEADER.format(mod=self.mod, desc=self.desc, ref=self.ref, uses=self.uses)
        if self.with_arr:
            out += ARR_HELPERS.format()
        out += "\n"
        out += "\n".join(self.defs) + "\n"
        out += "\n".join(self.errfuncs) + "\n"
        for name, fn, lines in self.groups:
            out += f"func {fn}():\n" + "\n".join(lines) + "\n\n"
        for name, fn, lines in self.groups:
            out += f'run({lit(name)}, {fn})\n'
        out += f'finish({lit(self.mod.upper())}, {len(self.groups)})\n'
        return out
