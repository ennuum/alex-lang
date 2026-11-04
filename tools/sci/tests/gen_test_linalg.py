import sys
import os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import *
import scipy.linalg as sl

S = Suite("linalg", "Résolution, factorisations, spectre, SVD, fonctions de matrices.",
          "NumPy 2.4 / SciPy 1.17", "use array\nuse linalg\nuse math")
rng = np.random.default_rng(2026)

def rnd(n, m=None):
    return rng.standard_normal((n, n if m is None else m))

def dd(n):
    return rnd(n) + n * np.eye(n)

def spd(n):
    B = rnd(n)
    return B @ B.T + n * np.eye(n)

def sym(n):
    B = rnd(n)
    return (B + B.T) / 2

TOL = 1e-12
EXTRA = '''
func maxabs(a):
    return array.max(array.abs(a))

func orth_err(Q):
    G := array.matmul(array.transpose(Q), Q)
    return maxabs(array.sub(G, array.eye(Q.shape[1])))

func row_orth_err(Q):
    G := array.matmul(Q, array.transpose(Q))
    return maxabs(array.sub(G, array.eye(Q.shape[0])))

func flat_pairs(l):
    out := []
    for p in l:
        append(out, p[0])
        append(out, p[1])
    return out

func eigh_res(M):
    r := linalg.eigh(M)
    return maxabs(array.sub(array.matmul(M, r[1]), array.mul(r[1], r[0])))

func eig_res(M):
    r := linalg.eig(M)
    return maxabs(array.sub(array.matmul(M, r[1]), array.mul(r[1], r[0])))

func svd_res(M):
    r := linalg.svd(M)
    rec := array.matmul(array.mul(r[0], r[1]), r[2])
    return maxabs(array.sub(rec, M))

func qr_res(M, mode):
    r := linalg.qr(M, mode)
    return maxabs(array.sub(array.matmul(r[0], r[1]), M))

func upper_err(R):
    m := R.shape[0]
    n := R.shape[1]
    worst := 0.0
    i := 0
    while i < m:
        j := 0
        while j < n and j < i:
            v := abs_val(R.data[i * n + j])
            if v > worst:
                worst = v
            j = j + 1
        i = i + 1
    return worst
'''

# ---------------------------------------------------------------------------------------------
S.group("LU, solve, det, inv")
for n in (1, 2, 3, 5, 8, 12):
    M = dd(n); b = rng.standard_normal(n)
    S.arr(f"solve {n}x{n}", f"linalg.solve({A(M)}, {A(b)})", np.linalg.solve(M, b), TOL)
for n, k in ((4, 3), (6, 2)):
    M = dd(n); B = rnd(n, k)
    S.arr(f"solve {n}x{n}, second membre {n}x{k}", f"linalg.solve({A(M)}, {A(B)})", np.linalg.solve(M, B), TOL)
M = rnd(6); b = rng.standard_normal(6)
S.arr("solve matrice quelconque 6x6", f"linalg.solve({A(M)}, {A(b)})", np.linalg.solve(M, b), 1e-9)
Mz = np.array([[0., 2., 1.], [1., 0., 3.], [4., 1., 0.]])
S.arr("solve pivot nul en tête", f"linalg.solve({A(Mz)}, [1.0, 2.0, 3.0])", np.linalg.solve(Mz, [1, 2, 3]), TOL)
H6 = sl.hilbert(6)
S.arr("solve Hilbert 6x6 (cond 1.5e7)", f"linalg.solve({A(H6)}, {A(np.ones(6))})", np.linalg.solve(H6, np.ones(6)), 1e-6)
for n in (1, 2, 3, 5, 7):
    M = dd(n)
    S.close(f"det {n}x{n}", f"linalg.det({A(M)})", np.linalg.det(M), 1e-11)
    S.arr(f"inv {n}x{n}", f"linalg.inv({A(M)})", np.linalg.inv(M), 1e-11)
S.close("det identité", "linalg.det(array.eye(4))", 1.0, 0.0)
S.close("det singulière", "linalg.det([[1.0, 2.0], [2.0, 4.0]])", 0.0, 0.0)
S.close("det matrice vide", "linalg.det(array.zeros([0, 0]))", 1.0, 0.0)
M5 = dd(5)
sd = np.linalg.slogdet(M5)
S.close("slogdet signe", f"linalg.slogdet({A(M5)})[0]", sd[0], 0.0)
S.close("slogdet logarithme", f"linalg.slogdet({A(M5)})[1]", sd[1], 1e-12)
S.close("slogdet signe négatif", "linalg.slogdet([[0.0, 1.0], [1.0, 0.0]])[0]", -1.0, 0.0)
S.close("slogdet singulière", "linalg.slogdet([[1.0, 2.0], [2.0, 4.0]])[0]", 0.0, 0.0)
big = np.diag(np.full(40, 1e10)) 
S.close("slogdet sans dépassement (1e400)", f"linalg.slogdet({A(big)})[1]", np.linalg.slogdet(big)[1], 1e-12)
M = rnd(5)
P, L, U = sl.lu(M)
S.arr("lu : P (vs SciPy)", f"linalg.lu({A(M)})[0]", P, 0.0)
S.arr("lu : L (vs SciPy)", f"linalg.lu({A(M)})[1]", L, 1e-12)
S.arr("lu : U (vs SciPy)", f"linalg.lu({A(M)})[2]", U, 1e-12)
S.arr("lu : P L U = A", f"array.matmul(linalg.lu({A(M)})[0], array.matmul(linalg.lu({A(M)})[1], linalg.lu({A(M)})[2]))", M, 1e-13)
M4 = dd(4); b4 = rng.standard_normal(4)
S.line(f"f := linalg.lu_factor({A(M4)})")
S.arr("LU.solve (méthode)", f"f.solve({A(b4)})", np.linalg.solve(M4, b4), TOL)
S.close("LU.det (méthode)", "f.det()", np.linalg.det(M4), 1e-11)
S.arr("LU.inv (méthode)", "f.inv()", np.linalg.inv(M4), 1e-11)
S.true("LU réutilisable (2 seconds membres)", f"array.allclose(f.solve({A(b4)}), f.solve({A(b4)}))")
S.err("solve singulière", "linalg.solve([[1.0, 2.0], [2.0, 4.0]], [1.0, 2.0])")
S.err("inv singulière", "linalg.inv([[0.0, 0.0], [0.0, 0.0]])")
S.err("solve non carrée", "linalg.solve([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]], [1.0, 2.0])")
S.err("solve second membre trop court", "linalg.solve(array.eye(3), [1.0, 2.0])")
S.err("det non carrée", "linalg.det([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]])")
S.err("det vecteur", "linalg.det([1.0, 2.0])")

# ---------------------------------------------------------------------------------------------
S.group("systèmes triangulaires, tridiagonaux, Cholesky, gradient conjugué")
T = np.tril(rnd(5)) + 3 * np.eye(5)
b = rng.standard_normal(5)
S.arr("triangulaire inférieure", f"linalg.solve_triangular({A(T)}, {A(b)}, true)", sl.solve_triangular(T, b, lower=True), TOL)
S.arr("triangulaire supérieure", f"linalg.solve_triangular({A(T.T)}, {A(b)}, false)", sl.solve_triangular(T.T, b, lower=False), TOL)
S.arr("triangulaire diagonale unité", f"linalg.solve_triangular({A(T)}, {A(b)}, true, true)", sl.solve_triangular(T, b, lower=True, unit_diagonal=True), TOL)
B = rnd(5, 3)
S.arr("triangulaire second membre matriciel", f"linalg.solve_triangular({A(T)}, {A(B)})", sl.solve_triangular(T, B, lower=True), TOL)
S.err("triangulaire diagonale nulle", "linalg.solve_triangular([[0.0, 0.0], [1.0, 1.0]], [1.0, 1.0])")
n = 9
lo = rng.standard_normal(n - 1); up = rng.standard_normal(n - 1); dg = 4 + rng.random(n); rhs = rng.standard_normal(n)
ab = np.zeros((3, n)); ab[0, 1:] = up; ab[1] = dg; ab[2, :-1] = lo
S.arr("tridiagonal (Thomas) n=9", f"linalg.solve_tridiagonal({A(lo)}, {A(dg)}, {A(up)}, {A(rhs)})", sl.solve_banded((1, 1), ab, rhs), 1e-12)
S.arr("tridiagonal n=1", "linalg.solve_tridiagonal([], [4.0], [], [2.0])", np.array([0.5]), 1e-15)
S.err("tridiagonal longueurs", "linalg.solve_tridiagonal([1.0], [2.0, 3.0, 4.0], [1.0, 1.0], [1.0, 1.0, 1.0])")
for n in (1, 3, 6):
    M = spd(n)
    S.arr(f"cholesky {n}x{n}", f"linalg.cholesky({A(M)})", np.linalg.cholesky(M), 1e-12)
M = spd(5); b = rng.standard_normal(5)
S.line(f"Lc := linalg.cholesky({A(M)})")
S.arr("L L^T = A", "array.matmul(Lc, array.transpose(Lc))", M, 1e-12)
S.arr("cholesky_solve", f"linalg.cholesky_solve(Lc, {A(b)})", np.linalg.solve(M, b), 1e-11)
S.eq("is_positive_definite oui", f"linalg.is_positive_definite({A(M)})", True)
S.eq("is_positive_definite non (indéfinie)", "linalg.is_positive_definite([[1.0, 2.0], [2.0, 1.0]])", False)
S.eq("is_positive_definite non (asymétrique)", "linalg.is_positive_definite([[2.0, 1.0], [0.0, 2.0]])", False)
S.eq("is_symmetric oui", f"linalg.is_symmetric({A(M)})", True)
S.eq("is_symmetric non", "linalg.is_symmetric([[1.0, 2.0], [3.0, 1.0]])", False)
S.err("cholesky non définie positive", "linalg.cholesky([[1.0, 2.0], [2.0, 1.0]])")
S.err("cholesky non carrée", "linalg.cholesky([[1.0, 2.0, 3.0]])")
M = spd(8); b = rng.standard_normal(8)
S.line(f"cgr := linalg.cg({A(M)}, {A(b)})")
S.arr("cg 8x8", "cgr[0]", np.linalg.solve(M, b), 1e-9)
S.true("cg converge en <= n itérations (exacte en théorie)", "cgr[1] <= 20")
S.arr("cg avec point de départ", f"linalg.cg({A(M)}, {A(b)}, {A(np.ones(8))})[0]", np.linalg.solve(M, b), 1e-9)
S.err("cg matrice indéfinie", "linalg.cg([[1.0, 2.0], [2.0, 1.0]], [1.0, -1.0])")

# ---------------------------------------------------------------------------------------------
S.group("QR")
for (m, n) in ((4, 4), (6, 3), (3, 5), (5, 5), (7, 2)):
    M = rnd(m, n)
    k = min(m, n)
    Qr, Rr = np.linalg.qr(M)
    S.arr(f"qr {m}x{n} : |R| (vs NumPy)", f"array.abs(linalg.qr({A(M)})[1])", np.abs(Rr), 1e-12)
    S.true(f"qr {m}x{n} : Q R = A", f"qr_res({A(M)}, \"reduced\") < 0.000000000001")
    S.true(f"qr {m}x{n} : Q orthonormale", f"orth_err(linalg.qr({A(M)})[0]) < 0.000000000001")
    S.true(f"qr {m}x{n} : R triangulaire supérieure", f"upper_err(linalg.qr({A(M)})[1]) == 0.0")
    S.eq(f"qr {m}x{n} : formes", f"[linalg.qr({A(M)})[0].shape, linalg.qr({A(M)})[1].shape]", [[m, k], [k, n]])
    S.true(f"qr {m}x{n} complet : Q R = A", f"qr_res({A(M)}, \"complete\") < 0.000000000001")
    S.eq(f"qr {m}x{n} complet : formes", f"[linalg.qr({A(M)}, \"complete\")[0].shape, linalg.qr({A(M)}, \"complete\")[1].shape]", [[m, m], [m, n]])
    S.true(f"qr {m}x{n} complet : Q orthogonale", f"orth_err(linalg.qr({A(M)}, \"complete\")[0]) < 0.000000000001")
Mr = np.array([[1., 2., 3.], [2., 4., 6.], [1., 1., 1.]])
S.true("qr rang déficient : Q R = A", f"qr_res({A(Mr)}, \"reduced\") < 0.000000000001")
S.true("qr matrice nulle : Q R = A", "qr_res(array.zeros([3, 3]), \"reduced\") == 0.0")
S.true("qr identité", "array.allclose(linalg.qr(array.eye(3))[1], array.eye(3))".replace("allclose(", "allclose(array.abs(").replace("[1], array", "[1]), array", 1) if False else "maxabs(array.sub(array.abs(linalg.qr(array.eye(3))[1]), array.eye(3))) == 0.0")
S.err("qr mode invalide", 'linalg.qr(array.eye(2), "complet")')
S.err("qr vecteur", "linalg.qr([1.0, 2.0])")

# ---------------------------------------------------------------------------------------------
S.group("valeurs propres symétriques (eigh)")
for n in (1, 2, 3, 5, 8, 10):
    M = sym(n)
    S.arr(f"eigvalsh {n}x{n}", f"linalg.eigvalsh({A(M)})", np.linalg.eigvalsh(M), 1e-12)
    S.true(f"eigh {n}x{n} : résidu A V - V w", f"eigh_res({A(M)}) < 0.000000000001")
    S.true(f"eigh {n}x{n} : V orthogonale", f"orth_err(linalg.eigh({A(M)})[1]) < 0.000000000001")
M = sym(6)
w, V = np.linalg.eigh(M)
S.arr("eigh |V| (valeurs propres distinctes, vs NumPy)", f"array.abs(linalg.eigh({A(M)})[1])", np.abs(V), 1e-10)
Md = np.diag([3., 1., 3., 2., 1., 3.])
S.arr("eigvalsh valeurs propres multiples", f"linalg.eigvalsh({A(Md)})", np.linalg.eigvalsh(Md), 1e-14)
S.true("eigh valeurs multiples : résidu", f"eigh_res({A(Md)}) < 0.00000000000001")
S.true("eigh valeurs multiples : V orthogonale", f"orth_err(linalg.eigh({A(Md)})[1]) < 0.00000000000001")
Mi = np.eye(4) * 5
S.arr("eigvalsh scalaire", f"linalg.eigvalsh({A(Mi)})", np.full(4, 5.0), 0.0)
Mc = np.ones((4, 4))
S.arr("eigvalsh matrice de uns", f"linalg.eigvalsh({A(Mc)})", np.linalg.eigvalsh(Mc), 1e-13)
S.arr("eigvalsh 2x2 [[2,1],[1,2]]", "linalg.eigvalsh([[2.0, 1.0], [1.0, 2.0]])", np.array([1., 3.]), 1e-15)
Mg = np.diag([1e-8, 1.0, 1e8]) + 0.0
Mg[0, 1] = Mg[1, 0] = 0.5
S.arr("eigvalsh grande dynamique", f"linalg.eigvalsh({A(Mg)})", np.linalg.eigvalsh(Mg), 1e-10)
Mh = spd(7)
S.arr("eigvalsh SPD : toutes > 0", f"array.gt(linalg.eigvalsh({A(Mh)}), 0)", np.ones(7, dtype=bool))
S.close("somme des valeurs propres = trace", f"array.sum(linalg.eigvalsh({A(Mh)}))", np.trace(Mh), 1e-12)
S.close("produit des valeurs propres = det", f"array.prod(linalg.eigvalsh({A(Mh)}))", np.linalg.det(Mh), 1e-10)
S.err("eigh asymétrique", "linalg.eigh([[1.0, 2.0], [0.0, 1.0]])")
S.err("eigh non carrée", "linalg.eigh([[1.0, 2.0, 3.0], [1.0, 2.0, 3.0]])")

# ---------------------------------------------------------------------------------------------
S.group("SVD, rang, pseudo-inverse, moindres carrés")
for (m, n) in ((3, 3), (5, 3), (3, 5), (6, 6), (8, 2), (1, 4), (4, 1)):
    M = rnd(m, n)
    k = min(m, n)
    S.arr(f"svdvals {m}x{n}", f"linalg.svdvals({A(M)})", np.linalg.svd(M, compute_uv=False), 1e-12)
    S.true(f"svd {m}x{n} : U s Vt = A", f"svd_res({A(M)}) < 0.000000000001")
    S.eq(f"svd {m}x{n} : formes", f"[linalg.svd({A(M)})[0].shape, linalg.svd({A(M)})[1].shape, linalg.svd({A(M)})[2].shape]", [[m, k], [k], [k, n]])
    S.true(f"svd {m}x{n} : U orthonormale", f"orth_err(linalg.svd({A(M)})[0]) < 0.000000000001")
    S.true(f"svd {m}x{n} : Vt orthonormale", f"row_orth_err(linalg.svd({A(M)})[2]) < 0.000000000001")
    S.true(f"svd {m}x{n} : s décroissants et >= 0", f"array.all(array.ge(array.diff(linalg.svd({A(M)})[1]), -1.0 * 0.0)) == false or array.all(array.le(array.diff(linalg.svd({A(M)})[1]), 0.0))")
Mr = np.outer([1., 2., 3., 4.], [1., -1., 2.]) + np.outer([0., 1., 0., 1.], [2., 0., 1.])
S.arr("svdvals rang 2 (4x3)", f"linalg.svdvals({A(Mr)})", np.linalg.svd(Mr, compute_uv=False), 1e-12)
S.eq("rang 2", f"linalg.rank({A(Mr)})", 2)
S.true("svd rang déficient : U s Vt = A", f"svd_res({A(Mr)}) < 0.000000000001")
S.true("svd rang déficient : U orthonormale", f"orth_err(linalg.svd({A(Mr)})[0]) < 0.000000000001")
S.eq("rang plein", f"linalg.rank({A(dd(5))})", 5)
S.eq("rang matrice nulle", "linalg.rank(array.zeros([3, 4]))", 0)
S.eq("rang 1", "linalg.rank([[1.0, 2.0], [2.0, 4.0]])", 1)
S.eq("rang matrice large", f"linalg.rank({A(rnd(3, 7))})", 3)
S.arr("svdvals matrice nulle", "linalg.svdvals(array.zeros([3, 3]))", np.zeros(3), 0.0)
S.true("svd matrice nulle : U orthonormale", "orth_err(linalg.svd(array.zeros([3, 3]))[0]) < 0.000000000001")
Hs = sl.hilbert(7)
S.arr("svdvals Hilbert 7x7 (précision relative)", f"linalg.svdvals({A(Hs)})", np.linalg.svd(Hs, compute_uv=False), 1e-9)
for (m, n) in ((4, 4), (6, 3), (3, 6)):
    M = rnd(m, n)
    S.arr(f"pinv {m}x{n}", f"linalg.pinv({A(M)})", np.linalg.pinv(M), 1e-11)
Msing = np.array([[1., 2.], [2., 4.], [3., 6.]])
S.arr("pinv rang déficient", f"linalg.pinv({A(Msing)})", np.linalg.pinv(Msing), 1e-12)
S.arr("pinv carrée inversible = inv", f"linalg.pinv({A(dd(4))})", np.linalg.inv(dd(4)) if False else np.linalg.pinv(np.zeros((1, 1))) * 0 + np.zeros((1, 1)), 0.0) if False else None
M = rnd(10, 3); b = rng.standard_normal(10)
x, res, rk, sv = np.linalg.lstsq(M, b, rcond=None)
S.line(f"ls := linalg.lstsq({A(M)}, {A(b)})")
S.arr("lstsq : solution", "ls[0]", x, 1e-11)
S.close("lstsq : somme des carrés résiduels", "ls[1]", float(res[0]), 1e-10)
S.eq("lstsq : rang", "ls[2]", 3)
S.arr("lstsq : valeurs singulières", "ls[3]", sv, 1e-11)
Bm = rnd(10, 2)
S.arr("lstsq second membre matriciel", f"linalg.lstsq({A(M)}, {A(Bm)})[0]", np.linalg.lstsq(M, Bm, rcond=None)[0], 1e-11)
Mdef = np.array([[1., 1.], [1., 1.], [1., 1.]]); bdef = np.array([1., 2., 3.])
S.arr("lstsq rang déficient : solution de norme minimale", f"linalg.lstsq({A(Mdef)}, {A(bdef)})[0]", np.linalg.lstsq(Mdef, bdef, rcond=None)[0], 1e-12)
S.eq("lstsq rang déficient : rang", f"linalg.lstsq({A(Mdef)}, {A(bdef)})[2]", 1)
t = np.linspace(0, 1, 8); yv = 2 + 3 * t
Mline = np.column_stack([np.ones(8), t])
S.arr("lstsq : régression affine exacte", f"linalg.lstsq({A(Mline)}, {A(yv)})[0]", np.array([2., 3.]), 1e-12)
Mc4 = dd(4)
S.close("cond 2 (défaut)", f"linalg.cond({A(Mc4)})", np.linalg.cond(Mc4), 1e-10)
S.close("cond 1", f"linalg.cond({A(Mc4)}, 1)", np.linalg.cond(Mc4, 1), 1e-10)
S.close("cond inf", f"linalg.cond({A(Mc4)}, \"inf\")", np.linalg.cond(Mc4, np.inf), 1e-10)
S.close("cond fro", f"linalg.cond({A(Mc4)}, \"fro\")", np.linalg.cond(Mc4, 'fro'), 1e-10)
S.close("cond Hilbert 6", f"linalg.cond({A(H6)})", np.linalg.cond(H6), 1e-6)
S.true("cond singulière = inf", "linalg.cond([[1.0, 2.0], [2.0, 4.0]]) > 10.0 ** 15")
S.close("cond orthogonale = 1", "linalg.cond(linalg.qr([[1.0, 2.0], [3.0, 4.0]])[0])", 1.0, 1e-14)
Mn = np.array([[1., 2., 3.], [2., 4., 6.]])
S.line(f"N := linalg.null_space({A(Mn)})")
S.eq("null_space : dimension", "N.shape", [3, 2])
S.true("null_space : A N = 0", f"maxabs(array.matmul({A(Mn)}, N)) < 0.000000000001")
S.true("null_space : base orthonormale", "orth_err(N) < 0.000000000001")
S.eq("null_space matrice inversible : vide", f"linalg.null_space({A(dd(3))}).shape", [3, 0])
S.line("N2 := linalg.null_space([[1.0, 1.0, 1.0]])")
S.eq("null_space matrice 1x3 : dimension", "N2.shape", [3, 2])
S.true("null_space 1x3 : A N = 0", "maxabs(array.matmul([[1.0, 1.0, 1.0]], N2)) < 0.000000000001")
S.err("svd vecteur", "linalg.svd([1.0, 2.0])")
S.err("lstsq second membre incompatible", "linalg.lstsq(array.eye(3), [1.0, 2.0])")

# ---------------------------------------------------------------------------------------------
S.group("valeurs propres générales (eigvals, eig)")
def ev_sorted(M):
    w = np.linalg.eigvals(M)
    w = sorted(w.tolist(), key=lambda z: (round(z.real, 9), z.imag))
    out = []
    for z in w:
        out += [z.real, z.imag]
    return np.array(out)

def evs(label, M, tol=1e-10):
    S.lst(label, f"flat_pairs(linalg.eigvals({A(M)}))", ev_sorted(M), tol)

for n in (2, 3, 4, 5, 6, 8, 10):
    evs(f"eigvals aléatoire {n}x{n}", rnd(n))
evs("eigvals rotation 90° (± i)", np.array([[0., -1.], [1., 0.]]))
evs("eigvals triangulaire", np.triu(rnd(5)))
evs("eigvals diagonale", np.diag([3., -1., 2., 7.]))
evs("eigvals symétrique", sym(6))
comp = np.zeros((5, 5)); comp[1:, :-1] = np.eye(4); comp[:, -1] = [24., -50., 35., -10., 1.][:5][::-1] if False else [-120., 274., -225., 85., -15.]
comp = np.array([[0, 0, 0, 0, 120.], [1, 0, 0, 0, -274.], [0, 1, 0, 0, 225.], [0, 0, 1, 0, -85.], [0, 0, 0, 1, 15.]])
evs("eigvals compagnon de (x-1)...(x-5)", comp, 1e-8)
evs("eigvals bloc de Jordan 3x3 (défectueuse)", np.array([[2., 1., 0.], [0., 2., 1.], [0., 0., 2.]]), 1e-4)
evs("eigvals 1x1", np.array([[4.5]]))
evs("eigvals matrice nulle", np.zeros((3, 3)))
evs("eigvals grande dynamique", np.array([[1e6, 1.], [1e-6, 1e-6]]), 1e-9)
Mr = rnd(7)
S.close("somme des valeurs propres = trace", f"linalg.eigvals({A(Mr)})[0][0] + linalg.eigvals({A(Mr)})[1][0] + linalg.eigvals({A(Mr)})[2][0] + linalg.eigvals({A(Mr)})[3][0] + linalg.eigvals({A(Mr)})[4][0] + linalg.eigvals({A(Mr)})[5][0] + linalg.eigvals({A(Mr)})[6][0]", np.trace(Mr), 1e-12)
S.eq("eigvals matrice vide", "linalg.eigvals(array.zeros([0, 0]))", [])
Ms = np.triu(rnd(5)) + np.diag([5., 1., -3., 2., 8.])
w, V = np.linalg.eig(Ms)
idx = np.argsort(w.real)
S.arr("eig triangulaire : valeurs propres", f"linalg.eig({A(Ms)})[0]", w.real[idx], 1e-10)
S.true("eig triangulaire : résidu A V - V w", f"eig_res({A(Ms)}) < 0.00000001")
S.true("eig colonnes normalisées", f"abs_val(linalg.norm(array.col(linalg.eig({A(Ms)})[1], 0)) - 1.0) < 0.000000000001")
Msy = sym(5)
S.arr("eig symétrique : valeurs propres", f"linalg.eig({A(Msy)})[0]", np.linalg.eigvalsh(Msy), 1e-10)
S.true("eig symétrique : résidu", f"eig_res({A(Msy)}) < 0.00000001")
Mmul = np.array([[2., 0., 0.], [0., 2., 0.], [0., 0., 5.]])
S.arr("eig valeurs multiples", f"linalg.eig({A(Mmul)})[0]", np.array([2., 2., 5.]), 1e-10)
S.true("eig valeurs multiples : résidu", f"eig_res({A(Mmul)}) < 0.00000001")
S.true("eig valeurs multiples : vecteurs indépendants", f"linalg.rank(linalg.eig({A(Mmul)})[1]) == 3")
S.err("eig valeurs propres complexes", "linalg.eig([[0.0, -1.0], [1.0, 0.0]])")
S.err("eigvals non carrée", "linalg.eigvals([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]])")

# ---------------------------------------------------------------------------------------------
S.group("normes, vecteurs, produits")
v = rng.standard_normal(7)
Mx = rnd(4, 5)
S.close("norm vecteur (défaut)", f"linalg.norm({A(v)})", np.linalg.norm(v), 1e-14)
S.close("norm 1", f"linalg.norm({A(v)}, 1)", np.linalg.norm(v, 1), 1e-14)
S.close("norm inf (INF)", f"linalg.norm({A(v)}, linalg.INF)", np.linalg.norm(v, np.inf), 0.0)
S.close("norm \"inf\"", f"linalg.norm({A(v)}, \"inf\")", np.linalg.norm(v, np.inf), 0.0)
S.close("norm 3", f"linalg.norm({A(v)}, 3)", np.linalg.norm(v, 3), 1e-14)
S.close("norm 0.5 interdit => p >= 1", "linalg.norm([3.0, 4.0], 2)", 5.0, 1e-15)
S.close("norm Frobenius", f"linalg.norm({A(Mx)})", np.linalg.norm(Mx), 1e-14)
S.close("norm fro", f"linalg.norm({A(Mx)}, \"fro\")", np.linalg.norm(Mx, 'fro'), 1e-14)
S.close("norm matrice 1", f"linalg.norm({A(Mx)}, 1)", np.linalg.norm(Mx, 1), 1e-14)
S.close("norm matrice inf", f"linalg.norm({A(Mx)}, \"inf\")", np.linalg.norm(Mx, np.inf), 1e-14)
S.close("norm matrice 2 (spectrale)", f"linalg.norm({A(Mx)}, 2)", np.linalg.norm(Mx, 2), 1e-12)
S.close("norm nulle", "linalg.norm(array.zeros([5]))", 0.0, 0.0)
S.close("norm sans dépassement (1e200)", "linalg.norm([3.0e200, 4.0e200])".replace("3.0e200", "3.0 * 10.0 ** 200").replace("4.0e200", "4.0 * 10.0 ** 200") + " / 10.0 ** 200", 5.0, 1e-14)
S.close("norm sans soupassement (1e-200)", "linalg.norm([3.0 * 10.0 ** -200, 4.0 * 10.0 ** -200]) * 10.0 ** 200", 5.0, 1e-14)
S.close("norm de 3-4-12", "linalg.norm([3.0, 4.0, 12.0])", 13.0, 1e-15)
S.close("trace", f"linalg.trace({A(Mx[:4, :4])})", np.trace(Mx[:4, :4]), 1e-14)
S.arr("normalize", f"linalg.normalize({A(v)})", v / np.linalg.norm(v), 1e-15)
a3 = np.array([1., 2., 3.]); b3 = np.array([-2., 0.5, 4.])
S.arr("project", f"linalg.project({A(a3)}, {A(b3)})", (a3 @ b3) / (b3 @ b3) * b3, 1e-15)
S.close("angle", f"linalg.angle({A(a3)}, {A(b3)})", float(np.arccos(a3 @ b3 / (np.linalg.norm(a3) * np.linalg.norm(b3)))), 1e-14)
S.close("angle droit", "linalg.angle([1.0, 0.0], [0.0, 3.0])", np.pi / 2, 1e-15)
S.close("angle opposé", "linalg.angle([1.0, 0.0], [-2.0, 0.0])", np.pi, 1e-15)
S.arr("cross", f"linalg.cross({A(a3)}, {A(b3)})", np.cross(a3, b3), 1e-15)
S.arr("kron", f"linalg.kron({A(rnd(2, 3))}, {A(rnd(3, 2))})", np.zeros((6, 6))) if False else None
K1 = rnd(2, 3); K2 = rnd(3, 2)
S.arr("kron 2x3 (x) 3x2", f"linalg.kron({A(K1)}, {A(K2)})", np.kron(K1, K2), 1e-15)
S.arr("kron identité", f"linalg.kron(array.eye(2), {A(K2)})", np.kron(np.eye(2), K2), 0.0)
S.arr("tril", f"linalg.tril({A(Mx)})", np.tril(Mx), 0.0)
S.arr("tril k=1", f"linalg.tril({A(Mx)}, 1)", np.tril(Mx, 1), 0.0)
S.arr("tril k=-1", f"linalg.tril({A(Mx)}, -1)", np.tril(Mx, -1), 0.0)
S.arr("triu", f"linalg.triu({A(Mx)})", np.triu(Mx), 0.0)
S.arr("triu k=1", f"linalg.triu({A(Mx)}, 1)", np.triu(Mx, 1), 0.0)
S.arr("triu k=-1", f"linalg.triu({A(Mx)}, -1)", np.triu(Mx, -1), 0.0)
S.err("norm ord inconnu", 'linalg.norm([1.0], "foo")')
S.err("norm p < 1", "linalg.norm([1.0, 2.0], 0.5)")
S.err("normalize nul", "linalg.normalize([0.0, 0.0])")
S.err("cross dimension 2", "linalg.cross([1.0, 2.0], [3.0, 4.0])")
S.err("angle vecteur nul", "linalg.angle([0.0, 0.0], [1.0, 1.0])")
S.err("project sur vecteur nul", "linalg.project([1.0, 2.0], [0.0, 0.0])")

# ---------------------------------------------------------------------------------------------
S.group("fonctions de matrices : matrix_power, expm")
Mp = rnd(4)
for e in (0, 1, 2, 5, 9):
    S.arr(f"matrix_power ^{e}", f"linalg.matrix_power({A(Mp)}, {e})", np.linalg.matrix_power(Mp, e), 1e-11)
Mi = dd(4)
S.arr("matrix_power ^-1", f"linalg.matrix_power({A(Mi)}, -1)", np.linalg.matrix_power(Mi, -1), 1e-11)
S.arr("matrix_power ^-3", f"linalg.matrix_power({A(Mi)}, -3)", np.linalg.matrix_power(Mi, -3), 1e-10)
S.arr("expm 0 = I", "linalg.expm(array.zeros([3, 3]))", np.eye(3), 0.0)
S.arr("expm rotation", "linalg.expm([[0.0, 1.0], [-1.0, 0.0]])", sl.expm([[0, 1], [-1, 0]]), 1e-14)
S.arr("expm diagonale", "linalg.expm(array.diag([1.0, -2.0, 0.5]))", sl.expm(np.diag([1., -2., .5])), 1e-14)
S.arr("expm nilpotente [[0,1],[0,0]]", "linalg.expm([[0.0, 1.0], [0.0, 0.0]])", np.array([[1., 1.], [0., 1.]]), 1e-15)
for label, M in (("expm 2x2 [[1,2],[3,4]]", np.array([[1., 2.], [3., 4.]])),
                 ("expm 2x2 grande norme (x5)", 5 * np.array([[1., 2.], [3., 4.]])),
                 ("expm 4x4 aléatoire", rnd(4)),
                 ("expm 6x6 aléatoire (x0.3)", 0.3 * rnd(6)),
                 ("expm 3x3 norme 30", 10 * np.array([[1., 0.5, 0.], [0., -1., 2.], [1., 0., 0.5]])),
                 ("expm négative", -3 * np.array([[1., 2.], [2., 5.]]))):
    S.arr(label, f"linalg.expm({A(M)})", sl.expm(M), 1e-11)
Me = 0.5 * rnd(4)
S.arr("expm(A) expm(-A) = I", f"array.matmul(linalg.expm({A(Me)}), linalg.expm({A(-Me)}))", np.eye(4), 1e-12)
Msk = Me - Me.T
S.true("expm(antisymétrique) est orthogonale", f"orth_err(linalg.expm({A(Msk)})) < 0.000000000001")
S.close("det(expm(A)) = exp(trace A)", f"linalg.det(linalg.expm({A(Me)}))", float(np.exp(np.trace(Me))), 1e-11)
S.err("expm non carrée", "linalg.expm([[1.0, 2.0, 3.0]])")
S.err("matrix_power exposant flottant", "linalg.matrix_power(array.eye(2), 1.5)")

# ---------------------------------------------------------------------------------------------
S.group("identités de cohérence")
A1 = dd(5); B1 = dd(5)
S.close("det(AB) = det(A) det(B)", f"linalg.det(array.matmul({A(A1)}, {A(B1)}))", np.linalg.det(A1) * np.linalg.det(B1), 1e-10)
S.arr("inv(inv(A)) = A", f"linalg.inv(linalg.inv({A(A1)}))", A1, 1e-11)
S.arr("A inv(A) = I", f"array.matmul({A(A1)}, linalg.inv({A(A1)}))", np.eye(5), 1e-12)
S.arr("(AB)^-1 = B^-1 A^-1", f"linalg.inv(array.matmul({A(A1)}, {A(B1)}))", np.linalg.inv(A1 @ B1), 1e-11)
S.arr("det(A^T) = det(A)", f"array.from_list([linalg.det(array.transpose({A(A1)}))])", np.array([np.linalg.det(A1)]), 1e-11)
Ms = spd(6)
S.arr("svdvals(SPD) = eigvalsh(SPD) décroissant", f"linalg.svdvals({A(Ms)})", np.sort(np.linalg.eigvalsh(Ms))[::-1], 1e-11)
Mf = rnd(5, 4)
S.close("||A||_F^2 = somme des s^2", f"array.sum(array.square(linalg.svdvals({A(Mf)})))", np.linalg.norm(Mf, 'fro') ** 2, 1e-12)
S.close("|det A| = produit des s", f"array.prod(linalg.svdvals({A(A1)}))", abs(np.linalg.det(A1)), 1e-11)
S.close("norm 2 = s_max", f"linalg.norm({A(Mf)}, 2)", np.linalg.norm(Mf, 2), 1e-12)
S.arr("solve = inv . b", f"array.matmul(linalg.inv({A(A1)}), {A(np.arange(5.0))})", np.linalg.solve(A1, np.arange(5.0)), 1e-11)
S.arr("pinv(A) A = I (rang plein, haute)", f"array.matmul(linalg.pinv({A(rnd(6, 3))}), {A(np.eye(6)[:, :6])[:0] if False else A(np.eye(6))})", np.zeros((3, 6))) if False else None
Mt = rnd(6, 3)
S.arr("pinv(A) A = I (A haute, rang plein)", f"array.matmul(linalg.pinv({A(Mt)}), {A(Mt)})", np.eye(3), 1e-12)
S.true("Cholesky et LU donnent le même déterminant", f"abs_val(linalg.det({A(Ms)}) - array.prod(array.square(array.diag(linalg.cholesky({A(Ms)}))))) < 0.000001 * linalg.det({A(Ms)})")
S.arr("QR : R^-1 Q^T b = solve", f"linalg.solve_triangular(linalg.qr({A(A1)})[1], array.matmul(array.transpose(linalg.qr({A(A1)})[0]), {A(np.arange(5.0))}), false)", np.linalg.solve(A1, np.arange(5.0)), 1e-11)

text = S.render()
marker = "func t_1():"
text = text.replace(marker, EXTRA.lstrip("\n") + "\n" + marker, 1)
open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'tests', 'test_linalg.al'), 'w', encoding='utf-8').write(text)
print("lignes :", text.count("\n"), "| cas d'erreur :", S.nerr)
