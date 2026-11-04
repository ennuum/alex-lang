use math
use array
from core use len, is_int, is_float, is_list, is_tuple, is_str
from collections use append

# ALEX STANDARD LIBRARY - linalg
# Algèbre linéaire dense sur des matrices `array` (2-d) et des vecteurs (1-d). Pure ALEX, aucune dépendance native.
#
#   use array
#   use linalg
#   A := array.from_list([[4.0, 3.0], [6.0, 3.0]])
#   x := linalg.solve(A, [10.0, 12.0])                 # résout A x = b
#   print(linalg.det(A), linalg.norm(x))
#   f := linalg.lu_factor(A)                           # factorisation réutilisable
#   print(f.solve([1.0, 0.0]).to_string())
#   r := linalg.eigh(array.from_list([[2.0, 1.0], [1.0, 2.0]]))   # [valeurs propres, vecteurs propres]
#
# CONTENU
#   Résolution       : solve, solve_triangular, solve_tridiagonal, lstsq, cg, inv, pinv
#   Factorisations   : lu_factor / class LU, lu, cholesky, cholesky_solve, qr, svd
#   Spectre          : eigh, eigvalsh (symétrique) ; eigvals, eig (général réel) ; svdvals
#   Invariants       : det, slogdet, rank, cond, norm, trace, null_space
#   Matrices         : matrix_power, expm, kron, cross, tril, triu, is_symmetric, is_positive_definite
#   Vecteurs         : normalize, project, angle, cross
#
# CONVENTIONS
#   - Entrées : Array, liste imbriquée ou nombre (conversion automatique par array.as_array). Rien n'est modifié en place.
#   - Les matrices sont stockées ligne par ligne dans .data ; M[i][j] = data[i * cols + j].
#   - Erreurs : "ValueError" (forme incompatible), "LinAlgError" (matrice singulière, non définie positive,
#     non-convergence). Le texte de l'erreur est en français.
#   - Les valeurs propres complexes (eigvals) sont des listes [re, im] compatibles avec le module complex.
#   - Les signes des vecteurs propres / singuliers sont arbitraires (un vecteur v ou -v) : comparer des projecteurs
#     ou des résidus, pas les composantes brutes.
#
# ALGORITHMES
#   LU avec pivot partiel (Doolittle) ; Cholesky ; QR par réflexions de Householder ; eigh par rotations de Jacobi
#   cycliques (précision relative élevée) ; eigvals par réduction de Hessenberg (Householder) puis QR à double décalage
#   de Francis ; SVD par la méthode de Jacobi unilatérale de Hestenes (précision relative élevée, valeurs singulières
#   décroissantes) ; expm par Padé d'ordre 13 avec mise à l'échelle (Higham 2005).
#
# LIMITES
#   - Dense uniquement, ≈ 4 M d'opérations/s : prévoir ≈ 0,2 s pour une résolution 100x100 et ≈ 1 s pour une SVD 30x30.
#   - eig ne calcule les vecteurs propres que si TOUTES les valeurs propres sont réelles (sinon utiliser eigvals).
#   - svd renvoie la forme « économique » (U m x k, s k, Vt k x n avec k = min(m, n)).

const INF := 10.0 ** 400
const EPS := 0.0000000000000002220446049250313

# =====================================================================================================
# Utilitaires internes
# =====================================================================================================

func _abs(x):
    if x < 0:
        return 0.0 - x
    return x * 1.0

func _sign1(x):
    if x < 0:
        return -1.0
    return 1.0

func _filled(n, v):
    out := []
    i := 0
    while i < n:
        append(out, v)
        i = i + 1
    return out

func _copy(l):
    out := []
    for x in l:
        append(out, x * 1.0)
    return out

# Matrice 2-d en entrée : renvoie l'Array (vérifié).
func _m2(a, who):
    t := array.as_array(a)
    if len(t.shape) != 2:
        raise("ValueError", f"{who} : matrice 2-d attendue (forme {t.shape})")
    return t

func _sq(a, who):
    t := _m2(a, who)
    if t.shape[0] != t.shape[1]:
        raise("ValueError", f"{who} : matrice carrée attendue (forme {t.shape})")
    return t

func _vec(a, who):
    t := array.as_array(a)
    if len(t.shape) != 1:
        raise("ValueError", f"{who} : vecteur 1-d attendu (forme {t.shape})")
    return t

func _identity_data(n):
    out := _filled(n * n, 0.0)
    i := 0
    while i < n:
        out[i * n + i] = 1.0
        i = i + 1
    return out

# Transposée de données plates rows x cols -> cols x rows.
func _tr(data, rows, cols):
    out := _filled(rows * cols, 0.0)
    i := 0
    while i < rows:
        j := 0
        while j < cols:
            out[j * rows + i] = data[i * cols + j]
            j = j + 1
        i = i + 1
    return out

# Produit de données plates (m x n) . (n x p).
func _mm(a, b, m, n, p):
    res := _filled(m * p, 0.0)
    i := 0
    while i < m:
        k := 0
        while k < n:
            aik := a[i * n + k]
            if aik != 0.0:
                j := 0
                while j < p:
                    res[i * p + j] = res[i * p + j] + aik * b[k * p + j]
                    j = j + 1
            k = k + 1
        i = i + 1
    return res

# =====================================================================================================
# Factorisation LU et résolution de systèmes
# =====================================================================================================

# Factorisation LU avec pivot partiel : P A = L U. `lu` contient L (sous la diagonale, diagonale unité implicite)
# et U (diagonale et au-dessus) ; perm[i] = ligne d'origine placée en position i ; sign = signe de la permutation ;
# singular = vrai si un pivot est nul.
class LU:
    func init(n, lu, perm, sign, singular):
        self.n = n
        self.lu = lu
        self.perm = perm
        self.sign = sign
        self.singular = singular

    func solve(b):
        return lu_solve(self, b)

    func det():
        return lu_det(self)

    func inv():
        return lu_inv(self)

func lu_factor(a):
    t := _sq(a, "lu_factor")
    n := t.shape[0]
    lu := _copy(t.data)
    perm := []
    i := 0
    while i < n:
        append(perm, i)
        i = i + 1
    sign := 1
    singular := false
    k := 0
    while k < n:
        p := k
        best := _abs(lu[k * n + k])
        i = k + 1
        while i < n:
            v := _abs(lu[i * n + k])
            if v > best:
                best = v
                p = i
            i = i + 1
        if best == 0.0:
            singular = true
        else:
            if p != k:
                j := 0
                while j < n:
                    tmp := lu[k * n + j]
                    lu[k * n + j] = lu[p * n + j]
                    lu[p * n + j] = tmp
                    j = j + 1
                tp := perm[k]
                perm[k] = perm[p]
                perm[p] = tp
                sign = 0 - sign
            piv := lu[k * n + k]
            i = k + 1
            while i < n:
                f := lu[i * n + k] / piv
                lu[i * n + k] = f
                if f != 0.0:
                    j := k + 1
                    while j < n:
                        lu[i * n + j] = lu[i * n + j] - f * lu[k * n + j]
                        j = j + 1
                i = i + 1
        k = k + 1
    return LU(n, lu, perm, sign, singular)

# Résout A x = b à partir d'un LU ; b vecteur (n) ou matrice (n x k).
func lu_solve(f, b):
    if f.singular:
        raise("LinAlgError", "solve : matrice singulière")
    n := f.n
    bt := array.as_array(b)
    nd := len(bt.shape)
    if nd != 1 and nd != 2:
        raise("ValueError", "solve : second membre 1-d ou 2-d attendu")
    if bt.shape[0] != n:
        raise("ValueError", f"solve : second membre de {bt.shape[0]} lignes pour une matrice {n}x{n}")
    nrhs := 1
    if nd == 2:
        nrhs = bt.shape[1]
    lu := f.lu
    out := _filled(n * nrhs, 0.0)
    c := 0
    while c < nrhs:
        y := _filled(n, 0.0)
        i := 0
        while i < n:
            s := bt.data[f.perm[i] * nrhs + c] * 1.0
            j := 0
            while j < i:
                s = s - lu[i * n + j] * y[j]
                j = j + 1
            y[i] = s
            i = i + 1
        i = n - 1
        while i >= 0:
            s := y[i]
            j := i + 1
            while j < n:
                s = s - lu[i * n + j] * y[j]
                j = j + 1
            y[i] = s / lu[i * n + i]
            i = i - 1
        i = 0
        while i < n:
            out[i * nrhs + c] = y[i]
            i = i + 1
        c = c + 1
    if nd == 1:
        return array.wrap([n], out)
    return array.wrap([n, nrhs], out)

func lu_det(f):
    if f.singular:
        return 0.0
    d := f.sign * 1.0
    i := 0
    while i < f.n:
        d = d * f.lu[i * f.n + i]
        i = i + 1
    return d

func lu_inv(f):
    return lu_solve(f, array.eye(f.n))

# Renvoie [P, L, U] avec A = P L U (matrices carrées).
func lu(a):
    f := lu_factor(a)
    n := f.n
    L := _identity_data(n)
    U := _filled(n * n, 0.0)
    i := 0
    while i < n:
        j := 0
        while j < n:
            if j < i:
                L[i * n + j] = f.lu[i * n + j]
            else:
                U[i * n + j] = f.lu[i * n + j]
            j = j + 1
        i = i + 1
    P := _filled(n * n, 0.0)
    i = 0
    while i < n:
        P[f.perm[i] * n + i] = 1.0
        i = i + 1
    return [array.wrap([n, n], P), array.wrap([n, n], L), array.wrap([n, n], U)]

# Résout A x = b (A carrée inversible, b vecteur ou matrice).
func solve(a, b):
    return lu_solve(lu_factor(a), b)

func det(a):
    t := _sq(a, "det")
    if t.shape[0] == 0:
        return 1.0
    return lu_det(lu_factor(t))

# [signe, ln|det|] sans dépassement de capacité ; signe 0 si la matrice est singulière.
func slogdet(a):
    t := _sq(a, "slogdet")
    f := lu_factor(t)
    if f.singular:
        return [0.0, 0.0 - INF]
    s := f.sign * 1.0
    logd := 0.0
    i := 0
    while i < f.n:
        d := f.lu[i * f.n + i]
        if d < 0:
            s = 0.0 - s
            d = 0.0 - d
        logd = logd + math.ln(d)
        i = i + 1
    return [s, logd]

func inv(a):
    t := _sq(a, "inv")
    f := lu_factor(t)
    if f.singular:
        raise("LinAlgError", "inv : matrice singulière")
    return lu_inv(f)

# Résout un système triangulaire (lower : triangle inférieur, unit : diagonale supposée égale à 1).
func solve_triangular(a, b, lower=true, unit=false):
    t := _sq(a, "solve_triangular")
    n := t.shape[0]
    bt := array.as_array(b)
    nd := len(bt.shape)
    if (nd != 1 and nd != 2) or bt.shape[0] != n:
        raise("ValueError", "solve_triangular : second membre incompatible")
    nrhs := 1
    if nd == 2:
        nrhs = bt.shape[1]
    out := _filled(n * nrhs, 0.0)
    c := 0
    while c < nrhs:
        if lower:
            i := 0
            while i < n:
                s := bt.data[i * nrhs + c] * 1.0
                j := 0
                while j < i:
                    s = s - t.data[i * n + j] * out[j * nrhs + c]
                    j = j + 1
                if not unit:
                    d := t.data[i * n + i]
                    if d == 0:
                        raise("LinAlgError", "solve_triangular : diagonale nulle")
                    s = s / d
                out[i * nrhs + c] = s
                i = i + 1
        else:
            i := n - 1
            while i >= 0:
                s := bt.data[i * nrhs + c] * 1.0
                j := i + 1
                while j < n:
                    s = s - t.data[i * n + j] * out[j * nrhs + c]
                    j = j + 1
                if not unit:
                    d := t.data[i * n + i]
                    if d == 0:
                        raise("LinAlgError", "solve_triangular : diagonale nulle")
                    s = s / d
                out[i * nrhs + c] = s
                i = i - 1
        c = c + 1
    if nd == 1:
        return array.wrap([n], out)
    return array.wrap([n, nrhs], out)

# Système tridiagonal par l'algorithme de Thomas : sub (n-1), diag (n), sup (n-1), rhs (n). O(n).
func solve_tridiagonal(sub, dg, sup, rhs):
    d := _vec(dg, "solve_tridiagonal")
    lo := _vec(sub, "solve_tridiagonal")
    up := _vec(sup, "solve_tridiagonal")
    r := _vec(rhs, "solve_tridiagonal")
    n := d.shape[0]
    if lo.shape[0] != n - 1 or up.shape[0] != n - 1 or r.shape[0] != n:
        raise("ValueError", "solve_tridiagonal : longueurs incompatibles (sub, sup : n-1 ; diag, rhs : n)")
    cp := _filled(n, 0.0)
    dp := _filled(n, 0.0)
    if d.data[0] == 0:
        raise("LinAlgError", "solve_tridiagonal : pivot nul")
    cp[0] = 0.0
    if n > 1:
        cp[0] = up.data[0] / d.data[0]
    dp[0] = r.data[0] / d.data[0]
    i := 1
    while i < n:
        den := d.data[i] - lo.data[i - 1] * cp[i - 1]
        if den == 0:
            raise("LinAlgError", "solve_tridiagonal : pivot nul")
        if i < n - 1:
            cp[i] = up.data[i] / den
        dp[i] = (r.data[i] - lo.data[i - 1] * dp[i - 1]) / den
        i = i + 1
    x := _filled(n, 0.0)
    x[n - 1] = dp[n - 1]
    i = n - 2
    while i >= 0:
        x[i] = dp[i] - cp[i] * x[i + 1]
        i = i - 1
    return array.wrap([n], x)

# =====================================================================================================
# Cholesky
# =====================================================================================================

# Facteur triangulaire inférieur L tel que A = L L^T (A symétrique définie positive).
func cholesky(a):
    t := _sq(a, "cholesky")
    n := t.shape[0]
    L := _filled(n * n, 0.0)
    j := 0
    while j < n:
        s := t.data[j * n + j] * 1.0
        k := 0
        while k < j:
            s = s - L[j * n + k] * L[j * n + k]
            k = k + 1
        if s <= 0.0:
            raise("LinAlgError", "cholesky : matrice non définie positive")
        d := math.sqrt(s)
        L[j * n + j] = d
        i := j + 1
        while i < n:
            s2 := t.data[i * n + j] * 1.0
            k = 0
            while k < j:
                s2 = s2 - L[i * n + k] * L[j * n + k]
                k = k + 1
            L[i * n + j] = s2 / d
            i = i + 1
        j = j + 1
    return array.wrap([n, n], L)

# Résout A x = b connaissant L = cholesky(A).
func cholesky_solve(L, b):
    y := solve_triangular(L, b, true, false)
    return solve_triangular(array.transpose(L), y, false, false)

func is_symmetric(a, tol=0.0000000001):
    t := _m2(a, "is_symmetric")
    if t.shape[0] != t.shape[1]:
        return false
    n := t.shape[0]
    scale := 1.0
    for x in t.data:
        if _abs(x) > scale:
            scale = _abs(x)
    i := 0
    while i < n:
        j := i + 1
        while j < n:
            if _abs(t.data[i * n + j] - t.data[j * n + i]) > tol * scale:
                return false
            j = j + 1
        i = i + 1
    return true

func is_positive_definite(a):
    if not is_symmetric(a):
        return false
    ok := true
    try:
        cholesky(a)
    catch e:
        ok = false
    return ok

# =====================================================================================================
# QR (réflexions de Householder)
# =====================================================================================================

# Renvoie [Q, R] avec A = Q R. mode "reduced" : Q m x k, R k x n (k = min(m, n)) ; mode "complete" : Q m x m, R m x n.
func qr(a, mode="reduced"):
    t := _m2(a, "qr")
    m := t.shape[0]
    n := t.shape[1]
    R := _copy(t.data)
    k := m
    if n < m:
        k = n
    vs := []
    betas := []
    j := 0
    while j < k:
        nrm2 := 0.0
        i := j
        while i < m:
            nrm2 = nrm2 + R[i * n + j] * R[i * n + j]
            i = i + 1
        v := _filled(m, 0.0)
        beta := 0.0
        if nrm2 > 0.0:
            nx := math.sqrt(nrm2)
            alpha := 0.0 - _sign1(R[j * n + j]) * nx
            i = j
            while i < m:
                v[i] = R[i * n + j]
                i = i + 1
            v[j] = v[j] - alpha
            vv := 0.0
            i = j
            while i < m:
                vv = vv + v[i] * v[i]
                i = i + 1
            if vv > 0.0:
                beta = 2.0 / vv
                c := j
                while c < n:
                    s := 0.0
                    i = j
                    while i < m:
                        s = s + v[i] * R[i * n + c]
                        i = i + 1
                    s = s * beta
                    i = j
                    while i < m:
                        R[i * n + c] = R[i * n + c] - s * v[i]
                        i = i + 1
                    c = c + 1
                i = j + 1
                while i < m:
                    R[i * n + j] = 0.0
                    i = i + 1
        append(vs, v)
        append(betas, beta)
        j = j + 1
    qc := k
    if mode == "complete":
        qc = m
    elif mode != "reduced":
        raise("ValueError", "qr : mode 'reduced' ou 'complete' attendu")
    Q := _filled(m * qc, 0.0)
    i := 0
    while i < qc:
        Q[i * qc + i] = 1.0
        i = i + 1
    j = k - 1
    while j >= 0:
        v := vs[j]
        beta := betas[j]
        if beta != 0.0:
            c := 0
            while c < qc:
                s := 0.0
                i = j
                while i < m:
                    s = s + v[i] * Q[i * qc + c]
                    i = i + 1
                s = s * beta
                i = j
                while i < m:
                    Q[i * qc + c] = Q[i * qc + c] - s * v[i]
                    i = i + 1
                c = c + 1
        j = j - 1
    rrows := k
    if mode == "complete":
        rrows = m
    Rout := _filled(rrows * n, 0.0)
    i = 0
    while i < rrows:
        c := i
        while c < n:
            Rout[i * n + c] = R[i * n + c]
            c = c + 1
        i = i + 1
    return [array.wrap([m, qc], Q), array.wrap([rrows, n], Rout)]

# =====================================================================================================
# Valeurs propres : matrices symétriques (Jacobi)
# =====================================================================================================

# Valeurs propres (croissantes) et vecteurs propres (en colonnes) d'une matrice symétrique : [w, V] avec A V = V diag(w).
func eigh(a):
    t := _sq(a, "eigh")
    n := t.shape[0]
    if not is_symmetric(t, 0.000000001):
        raise("ValueError", "eigh : matrice symétrique attendue")
    A := _copy(t.data)
    # symétrisation exacte
    i := 0
    while i < n:
        j := i + 1
        while j < n:
            m := (A[i * n + j] + A[j * n + i]) * 0.5
            A[i * n + j] = m
            A[j * n + i] = m
            j = j + 1
        i = i + 1
    V := _identity_data(n)
    sweep := 0
    while sweep < 100:
        off := 0.0
        dg := 0.0
        i = 0
        while i < n:
            dg = dg + A[i * n + i] * A[i * n + i]
            j := i + 1
            while j < n:
                off = off + A[i * n + j] * A[i * n + j]
                j = j + 1
            i = i + 1
        if off == 0.0 or off <= EPS * EPS * 0.25 * (dg + off):
            break
        p := 0
        while p < n - 1:
            q := p + 1
            while q < n:
                apq := A[p * n + q]
                if apq != 0.0:
                    app := A[p * n + p]
                    aqq := A[q * n + q]
                    tau := (aqq - app) / (2.0 * apq)
                    tt := 1.0
                    if tau != 0.0:
                        tt = _sign1(tau) / (_abs(tau) + math.sqrt(1.0 + tau * tau))
                    c := 1.0 / math.sqrt(1.0 + tt * tt)
                    s := tt * c
                    k := 0
                    while k < n:
                        akp := A[k * n + p]
                        akq := A[k * n + q]
                        A[k * n + p] = c * akp - s * akq
                        A[k * n + q] = s * akp + c * akq
                        k = k + 1
                    k = 0
                    while k < n:
                        apk := A[p * n + k]
                        aqk := A[q * n + k]
                        A[p * n + k] = c * apk - s * aqk
                        A[q * n + k] = s * apk + c * aqk
                        k = k + 1
                    A[p * n + q] = 0.0
                    A[q * n + p] = 0.0
                    k = 0
                    while k < n:
                        vkp := V[k * n + p]
                        vkq := V[k * n + q]
                        V[k * n + p] = c * vkp - s * vkq
                        V[k * n + q] = s * vkp + c * vkq
                        k = k + 1
                q = q + 1
            p = p + 1
        sweep = sweep + 1
    w := []
    i = 0
    while i < n:
        append(w, A[i * n + i])
        i = i + 1
    order := array.argsort_list(w)
    ws := []
    Vs := _filled(n * n, 0.0)
    c := 0
    for src in order:
        append(ws, w[src])
        r := 0
        while r < n:
            Vs[r * n + c] = V[r * n + src]
            r = r + 1
        c = c + 1
    return [array.wrap([n], ws), array.wrap([n, n], Vs)]

func eigvalsh(a):
    return eigh(a)[0]

# =====================================================================================================
# SVD (Jacobi unilatérale de Hestenes)
# =====================================================================================================

# Complète les colonnes nulles de U (m x n, colonnes déjà normalisées pour les indices dans `good`) en une base orthonormale.
func _fill_orthonormal(U, m, n, good):
    j := 0
    while j < n:
        if not good[j]:
            cand := 0
            done := false
            while cand < m and not done:
                v := _filled(m, 0.0)
                v[cand] = 1.0
                rep := 0
                while rep < 2:
                    c := 0
                    while c < n:
                        if good[c]:
                            d := 0.0
                            r := 0
                            while r < m:
                                d = d + v[r] * U[r * n + c]
                                r = r + 1
                            r = 0
                            while r < m:
                                v[r] = v[r] - d * U[r * n + c]
                                r = r + 1
                        c = c + 1
                    rep = rep + 1
                nv := 0.0
                for x in v:
                    nv = nv + x * x
                nv = math.sqrt(nv)
                if nv > 0.5:
                    r := 0
                    while r < m:
                        U[r * n + j] = v[r] / nv
                        r = r + 1
                    good[j] = true
                    done = true
                cand = cand + 1
        j = j + 1

# SVD réduite : [U, s, Vt] avec A = U diag(s) Vt, s décroissant, U (m x k), Vt (k x n), k = min(m, n).
func svd(a):
    t := _m2(a, "svd")
    m := t.shape[0]
    n := t.shape[1]
    if m < n:
        r := svd(array.transpose(t))
        return [array.transpose(r[2]), r[1], array.transpose(r[0])]
    U := _copy(t.data)
    V := _identity_data(n)
    sweep := 0
    while sweep < 60:
        rotated := false
        p := 0
        while p < n - 1:
            q := p + 1
            while q < n:
                alpha := 0.0
                beta := 0.0
                gamma := 0.0
                k := 0
                while k < m:
                    up := U[k * n + p]
                    uq := U[k * n + q]
                    alpha = alpha + up * up
                    beta = beta + uq * uq
                    gamma = gamma + up * uq
                    k = k + 1
                if gamma != 0.0 and _abs(gamma) > EPS * math.sqrt(alpha * beta):
                    rotated = true
                    zeta := (beta - alpha) / (2.0 * gamma)
                    tt := 1.0
                    if zeta != 0.0:
                        tt = _sign1(zeta) / (_abs(zeta) + math.sqrt(1.0 + zeta * zeta))
                    c := 1.0 / math.sqrt(1.0 + tt * tt)
                    s := c * tt
                    k = 0
                    while k < m:
                        up := U[k * n + p]
                        uq := U[k * n + q]
                        U[k * n + p] = c * up - s * uq
                        U[k * n + q] = s * up + c * uq
                        k = k + 1
                    k = 0
                    while k < n:
                        vp := V[k * n + p]
                        vq := V[k * n + q]
                        V[k * n + p] = c * vp - s * vq
                        V[k * n + q] = s * vp + c * vq
                        k = k + 1
                q = q + 1
            p = p + 1
        if not rotated:
            break
        sweep = sweep + 1
    sig := []
    j := 0
    while j < n:
        s2 := 0.0
        k := 0
        while k < m:
            s2 = s2 + U[k * n + j] * U[k * n + j]
            k = k + 1
        append(sig, math.sqrt(s2))
        j = j + 1
    # tri décroissant
    neg := []
    for x in sig:
        append(neg, 0.0 - x)
    order := array.argsort_list(neg)
    smax := 0.0
    if n > 0:
        smax = sig[order[0]]
    Us := _filled(m * n, 0.0)
    Vts := _filled(n * n, 0.0)
    ss := []
    good := _filled(n, false)
    c := 0
    for src in order:
        sv := sig[src]
        append(ss, sv)
        if sv > smax * EPS * 4.0 and sv > 0.0:
            r := 0
            while r < m:
                Us[r * n + c] = U[r * n + src] / sv
                r = r + 1
            good[c] = true
        r := 0
        while r < n:
            Vts[c * n + r] = V[r * n + src]
            r = r + 1
        c = c + 1
    _fill_orthonormal(Us, m, n, good)
    return [array.wrap([m, n], Us), array.wrap([n], ss), array.wrap([n, n], Vts)]

func svdvals(a):
    return svd(a)[1]

# Rang numérique : nombre de valeurs singulières > tol (défaut : max(m, n) * eps * s_max).
func rank(a, tol=null):
    t := _m2(a, "rank")
    s := svdvals(t)
    if len(s.data) == 0:
        return 0
    lim := tol
    if lim == null:
        mx := t.shape[0]
        if t.shape[1] > mx:
            mx = t.shape[1]
        lim = mx * EPS * s.data[0]
    r := 0
    for x in s.data:
        if x > lim:
            r = r + 1
    return r

# Pseudo-inverse de Moore-Penrose (valeurs singulières <= rcond * s_max ignorées).
func pinv(a, rcond=null):
    t := _m2(a, "pinv")
    r := svd(t)
    U := r[0]
    s := r[1]
    Vt := r[2]
    m := t.shape[0]
    n := t.shape[1]
    k := len(s.data)
    cut := rcond
    if cut == null:
        mx := m
        if n > mx:
            mx = n
        cut = mx * EPS
    smax := 0.0
    if k > 0:
        smax = s.data[0]
    out := _filled(n * m, 0.0)
    c := 0
    while c < k:
        if s.data[c] > cut * smax and s.data[c] > 0.0:
            inv_s := 1.0 / s.data[c]
            i := 0
            while i < n:
                vi := Vt.data[c * n + i] * inv_s
                if vi != 0.0:
                    j := 0
                    while j < m:
                        out[i * m + j] = out[i * m + j] + vi * U.data[j * k + c]
                        j = j + 1
                i = i + 1
        c = c + 1
    return array.wrap([n, m], out)

# Nombre de condition. p=null ou 2 : s_max / s_min (INF si singulière) ; p = 1, "inf" ou "fro" : norm(A) * norm(A^-1).
func cond(a, p=null):
    t := _m2(a, "cond")
    if p == null or p == 2:
        s := svdvals(t)
        if len(s.data) == 0:
            return 0.0
        smin := s.data[len(s.data) - 1]
        if smin == 0.0:
            return INF
        return s.data[0] / smin
    if t.shape[0] != t.shape[1]:
        raise("ValueError", "cond : matrice carrée attendue pour cette norme")
    f := lu_factor(t)
    if f.singular:
        return INF
    return norm(t, p) * norm(lu_inv(f), p)

# Base orthonormée du noyau (colonnes) : vecteurs x avec A x = 0.
func null_space(a, tol=null):
    t := _m2(a, "null_space")
    m := t.shape[0]
    n := t.shape[1]
    # SVD complète via A^T A est imprécis ; on utilise la SVD de [A ; 0] complétée à n lignes
    pad := t
    if m < n:
        pad = array.concatenate([t, array.zeros([n - m, n])], 0)
    r := svd(pad)
    s := r[1]
    Vt := r[2]
    smax := 0.0
    if len(s.data) > 0:
        smax = s.data[0]
    lim := tol
    if lim == null:
        mx := m
        if n > mx:
            mx = n
        lim = mx * EPS * smax
    cols := []
    c := 0
    while c < len(s.data):
        if s.data[c] <= lim:
            append(cols, c)
        c = c + 1
    k := len(cols)
    out := _filled(n * k, 0.0)
    jj := 0
    for c2 in cols:
        i := 0
        while i < n:
            out[i * k + jj] = Vt.data[c2 * n + i]
            i = i + 1
        jj = jj + 1
    return array.wrap([n, k], out)

# Moindres carrés min ||A x - b||_2 (norme minimale si A n'est pas de rang plein).
# Renvoie [x, somme des carrés des résidus, rang, valeurs singulières].
func lstsq(a, b):
    t := _m2(a, "lstsq")
    bt := array.as_array(b)
    nd := len(bt.shape)
    if (nd != 1 and nd != 2) or bt.shape[0] != t.shape[0]:
        raise("ValueError", "lstsq : second membre incompatible")
    P := pinv(t)
    x := array.matmul(P, bt)
    res := array.sub(array.matmul(t, x), bt)
    sq := array.sum(array.square(res))
    return [x, sq, rank(t), svdvals(t)]

# Gradient conjugué pour A symétrique définie positive. Renvoie [x, nombre d'itérations].
func cg(a, b, x0=null, tol=0.000000000001, maxiter=null):
    t := _sq(a, "cg")
    bv := _vec(b, "cg")
    n := t.shape[0]
    if bv.shape[0] != n:
        raise("ValueError", "cg : second membre incompatible")
    it_max := maxiter
    if it_max == null:
        it_max = 10 * n + 10
    x := _filled(n, 0.0)
    if x0 != null:
        x = _copy(array.as_array(x0).data)
    r := _filled(n, 0.0)
    i := 0
    while i < n:
        s := bv.data[i] * 1.0
        j := 0
        while j < n:
            s = s - t.data[i * n + j] * x[j]
            j = j + 1
        r[i] = s
        i = i + 1
    p := _copy(r)
    rs := 0.0
    for v in r:
        rs = rs + v * v
    bn := 0.0
    for v in bv.data:
        bn = bn + v * v
    bn = math.sqrt(bn)
    if bn == 0.0:
        bn = 1.0
    k := 0
    while k < it_max and math.sqrt(rs) > tol * bn:
        Ap := _filled(n, 0.0)
        i = 0
        while i < n:
            s := 0.0
            j := 0
            while j < n:
                s = s + t.data[i * n + j] * p[j]
                j = j + 1
            Ap[i] = s
            i = i + 1
        pAp := 0.0
        i = 0
        while i < n:
            pAp = pAp + p[i] * Ap[i]
            i = i + 1
        if pAp <= 0.0:
            raise("LinAlgError", "cg : matrice non définie positive")
        alpha := rs / pAp
        rs_new := 0.0
        i = 0
        while i < n:
            x[i] = x[i] + alpha * p[i]
            r[i] = r[i] - alpha * Ap[i]
            rs_new = rs_new + r[i] * r[i]
            i = i + 1
        beta := rs_new / rs
        i = 0
        while i < n:
            p[i] = r[i] + beta * p[i]
            i = i + 1
        rs = rs_new
        k = k + 1
    return [array.wrap([n], x), k]

# =====================================================================================================
# Valeurs propres : matrices réelles quelconques (Hessenberg + QR de Francis)
# =====================================================================================================

# Réduction de Hessenberg par réflexions de Householder (renvoie les données plates n x n).
func _hessenberg(data, n):
    H := _copy(data)
    k := 0
    while k < n - 2:
        nrm2 := 0.0
        i := k + 1
        while i < n:
            nrm2 = nrm2 + H[i * n + k] * H[i * n + k]
            i = i + 1
        if nrm2 > 0.0:
            x0 := H[(k + 1) * n + k]
            nx := math.sqrt(nrm2)
            alpha := 0.0 - _sign1(x0) * nx
            v := _filled(n, 0.0)
            i = k + 1
            while i < n:
                v[i] = H[i * n + k]
                i = i + 1
            v[k + 1] = v[k + 1] - alpha
            vv := 0.0
            i = k + 1
            while i < n:
                vv = vv + v[i] * v[i]
                i = i + 1
            if vv > 0.0:
                beta := 2.0 / vv
                c := 0
                while c < n:
                    s := 0.0
                    i = k + 1
                    while i < n:
                        s = s + v[i] * H[i * n + c]
                        i = i + 1
                    s = s * beta
                    i = k + 1
                    while i < n:
                        H[i * n + c] = H[i * n + c] - s * v[i]
                        i = i + 1
                    c = c + 1
                r := 0
                while r < n:
                    s := 0.0
                    j := k + 1
                    while j < n:
                        s = s + H[r * n + j] * v[j]
                        j = j + 1
                    s = s * beta
                    j = k + 1
                    while j < n:
                        H[r * n + j] = H[r * n + j] - s * v[j]
                        j = j + 1
                    r = r + 1
        k = k + 1
    i := 2
    while i < n:
        j := 0
        while j < i - 1:
            H[i * n + j] = 0.0
            j = j + 1
        i = i + 1
    return H

# QR à double décalage sur une matrice de Hessenberg (indices 1..n dans une grille (n+1)x(n+1)).
# Renvoie [wr, wi] (listes de longueur n) ; algorithme « hqr » classique.
func _hqr(hdata, n):
    w := n + 1
    a := _filled(w * w, 0.0)
    i := 1
    while i <= n:
        j := 1
        while j <= n:
            a[i * w + j] = hdata[(i - 1) * n + (j - 1)]
            j = j + 1
        i = i + 1
    wr := _filled(w, 0.0)
    wi := _filled(w, 0.0)
    anorm := 0.0
    i = 1
    while i <= n:
        j := i - 1
        if j < 1:
            j = 1
        while j <= n:
            anorm = anorm + _abs(a[i * w + j])
            j = j + 1
        i = i + 1
    nn := n
    t := 0.0
    while nn >= 1:
        its := 0
        l := 1
        again := true
        while again:
            l = nn
            while l >= 2:
                s := _abs(a[(l - 1) * w + (l - 1)]) + _abs(a[l * w + l])
                if s == 0.0:
                    s = anorm
                if _abs(a[l * w + (l - 1)]) <= EPS * s:
                    a[l * w + (l - 1)] = 0.0
                    break
                l = l - 1
            x := a[nn * w + nn]
            if l == nn:
                wr[nn] = x + t
                wi[nn] = 0.0
                nn = nn - 1
                again = false
            else:
                y := a[(nn - 1) * w + (nn - 1)]
                ww := a[nn * w + (nn - 1)] * a[(nn - 1) * w + nn]
                if l == nn - 1:
                    p := 0.5 * (y - x)
                    q := p * p + ww
                    z := math.sqrt(_abs(q))
                    x = x + t
                    if q >= 0.0:
                        z = p + _sign1(p) * z
                        wr[nn - 1] = x + z
                        wr[nn] = x + z
                        if z != 0.0:
                            wr[nn] = x - ww / z
                        wi[nn - 1] = 0.0
                        wi[nn] = 0.0
                    else:
                        wr[nn - 1] = x + p
                        wr[nn] = x + p
                        wi[nn - 1] = z
                        wi[nn] = 0.0 - z
                    nn = nn - 2
                    again = false
                else:
                    if its >= 60:
                        raise("LinAlgError", "eigvals : l'algorithme QR ne converge pas")
                    if its == 10 or its == 20:
                        t = t + x
                        k := 1
                        while k <= nn:
                            a[k * w + k] = a[k * w + k] - x
                            k = k + 1
                        s := _abs(a[nn * w + (nn - 1)]) + _abs(a[(nn - 1) * w + (nn - 2)])
                        x = 0.75 * s
                        y = x
                        ww = -0.4375 * s * s
                    its = its + 1
                    m := nn - 2
                    p := 0.0
                    q := 0.0
                    r := 0.0
                    z := 0.0
                    while m >= l:
                        z = a[m * w + m]
                        r = x - z
                        s := y - z
                        p = (r * s - ww) / a[(m + 1) * w + m] + a[m * w + (m + 1)]
                        q = a[(m + 1) * w + (m + 1)] - z - r - s
                        r = a[(m + 2) * w + (m + 1)]
                        s = _abs(p) + _abs(q) + _abs(r)
                        p = p / s
                        q = q / s
                        r = r / s
                        if m == l:
                            break
                        u := _abs(a[m * w + (m - 1)]) * (_abs(q) + _abs(r))
                        v := _abs(p) * (_abs(a[(m - 1) * w + (m - 1)]) + _abs(z) + _abs(a[(m + 1) * w + (m + 1)]))
                        if u <= EPS * v:
                            break
                        m = m - 1
                    i = m + 2
                    while i <= nn:
                        a[i * w + (i - 2)] = 0.0
                        if i != m + 2:
                            a[i * w + (i - 3)] = 0.0
                        i = i + 1
                    k := m
                    while k <= nn - 1:
                        if k != m:
                            p = a[k * w + (k - 1)]
                            q = a[(k + 1) * w + (k - 1)]
                            r = 0.0
                            if k != nn - 1:
                                r = a[(k + 2) * w + (k - 1)]
                            x = _abs(p) + _abs(q) + _abs(r)
                            if x != 0.0:
                                p = p / x
                                q = q / x
                                r = r / x
                        s := _sign1(p) * math.sqrt(p * p + q * q + r * r)
                        if s != 0.0:
                            if k == m:
                                if l != m:
                                    a[k * w + (k - 1)] = 0.0 - a[k * w + (k - 1)]
                            else:
                                a[k * w + (k - 1)] = 0.0 - s * x
                            p = p + s
                            x = p / s
                            y = q / s
                            z = r / s
                            q = q / p
                            r = r / p
                            j := k
                            while j <= nn:
                                p = a[k * w + j] + q * a[(k + 1) * w + j]
                                if k != nn - 1:
                                    p = p + r * a[(k + 2) * w + j]
                                    a[(k + 2) * w + j] = a[(k + 2) * w + j] - p * z
                                a[(k + 1) * w + j] = a[(k + 1) * w + j] - p * y
                                a[k * w + j] = a[k * w + j] - p * x
                                j = j + 1
                            mmin := nn
                            if k + 3 < nn:
                                mmin = k + 3
                            i = l
                            while i <= mmin:
                                p = x * a[i * w + k] + y * a[i * w + (k + 1)]
                                if k != nn - 1:
                                    p = p + z * a[i * w + (k + 2)]
                                    a[i * w + (k + 2)] = a[i * w + (k + 2)] - p * r
                                a[i * w + (k + 1)] = a[i * w + (k + 1)] - p * q
                                a[i * w + k] = a[i * w + k] - p
                                i = i + 1
                        k = k + 1
    out_r := []
    out_i := []
    i = 1
    while i <= n:
        append(out_r, wr[i])
        append(out_i, wi[i])
        i = i + 1
    return [out_r, out_i]

# Valeurs propres d'une matrice réelle carrée : liste de [re, im] triée par (re, im) croissants.
func eigvals(a):
    t := _sq(a, "eigvals")
    n := t.shape[0]
    if n == 0:
        return []
    if n == 1:
        return [[t.data[0] * 1.0, 0.0]]
    H := _hessenberg(t.data, n)
    r := _hqr(H, n)
    pairs := []
    i := 0
    while i < n:
        append(pairs, [r[0][i], r[1][i]])
        i = i + 1
    # tri par partie réelle puis imaginaire (tri fusion sur une clé composite)
    keys := []
    for pr in pairs:
        append(keys, pr[0])
    order := array.argsort_list(keys)
    sorted_pairs := []
    for idx in order:
        append(sorted_pairs, pairs[idx])
    # à parties réelles égales (conjugués), partie imaginaire croissante
    i = 0
    while i < n - 1:
        j := 0
        while j < n - 1 - i:
            p1 := sorted_pairs[j]
            p2 := sorted_pairs[j + 1]
            same := _abs(p1[0] - p2[0]) <= 1000.0 * EPS * (_abs(p1[0]) + 1.0)
            if same and p1[1] > p2[1]:
                sorted_pairs[j] = p2
                sorted_pairs[j + 1] = p1
            j = j + 1
        i = i + 1
    return sorted_pairs

# Valeurs et vecteurs propres d'une matrice réelle dont toutes les valeurs propres sont réelles :
# [w (croissantes), V (colonnes normalisées)]. Les vecteurs viennent de l'itération inverse.
func eig(a):
    t := _sq(a, "eig")
    n := t.shape[0]
    ev := eigvals(t)
    w := []
    scale := 0.0
    for x in t.data:
        if _abs(x) > scale:
            scale = _abs(x)
    if scale == 0.0:
        scale = 1.0
    for e in ev:
        if _abs(e[1]) > 1000.0 * EPS * scale * n:
            raise("LinAlgError", "eig : valeurs propres complexes, utiliser eigvals")
        append(w, e[0])
    V := _filled(n * n, 0.0)
    done := []
    c := 0
    while c < n:
        lam := w[c]
        # décalage légèrement perturbé pour que (A - lam I) reste inversible
        shift := lam + scale * EPS * 100.0
        M := _copy(t.data)
        i := 0
        while i < n:
            M[i * n + i] = M[i * n + i] - shift
            i = i + 1
        f := lu_factor(array.wrap([n, n], M))
        if f.singular:
            M2 := _copy(t.data)
            i = 0
            while i < n:
                M2[i * n + i] = M2[i * n + i] - (shift + scale * EPS * 1000.0)
                i = i + 1
            f = lu_factor(array.wrap([n, n], M2))
        v := _filled(n, 1.0)
        i = 0
        while i < n:
            v[i] = 1.0 + 0.1 * math.sin(1.0 + i * 1.7 + c * 0.9)
            i = i + 1
        it := 0
        while it < 8:
            # orthogonalisation contre les vecteurs déjà trouvés de même valeur propre
            for prev in done:
                if _abs(w[prev] - lam) <= 0.000001 * (scale + 1.0):
                    d := 0.0
                    i = 0
                    while i < n:
                        d = d + v[i] * V[i * n + prev]
                        i = i + 1
                    i = 0
                    while i < n:
                        v[i] = v[i] - d * V[i * n + prev]
                        i = i + 1
            y := lu_solve(f, array.wrap([n], v))
            nv := 0.0
            for x in y.data:
                nv = nv + x * x
            nv = math.sqrt(nv)
            if nv == 0.0 or nv != nv or nv == INF:
                break
            v = _filled(n, 0.0)
            i = 0
            while i < n:
                v[i] = y.data[i] / nv
                i = i + 1
            it = it + 1
        # signe : plus grande composante positive
        big := 0
        i = 0
        while i < n:
            if _abs(v[i]) > _abs(v[big]):
                big = i
            i = i + 1
        sg := _sign1(v[big])
        i = 0
        while i < n:
            V[i * n + c] = v[i] * sg
            i = i + 1
        append(done, c)
        c = c + 1
    return [array.wrap([n], w), array.wrap([n, n], V)]

# =====================================================================================================
# Normes, produits, fonctions de matrices
# =====================================================================================================

# Norme d'un vecteur ou d'une matrice. ord : null (euclidienne pour un vecteur, Frobenius pour une matrice, comme NumPy),
# 2 (euclidienne ; spectrale pour une matrice), 1, INF ou "inf", "fro" (Frobenius), ou un réel p >= 1 (vecteurs).
func norm(x, ord=null):
    t := array.as_array(x)
    nd := len(t.shape)
    o := ord
    if is_str(o):
        if o == "inf":
            o = INF
        elif o != "fro":
            raise("ValueError", "norm : ord inconnu")
    if nd == 1 or nd == 0 or o == "fro" or (nd == 2 and o == null):
        if o == null or o == 2 or o == "fro":
            sc := 0.0
            for v in t.data:
                if _abs(v) > sc:
                    sc = _abs(v)
            if sc == 0.0:
                return 0.0
            if sc == INF:
                return INF
            s := 0.0
            for v in t.data:
                q := v / sc
                s = s + q * q
            return sc * math.sqrt(s)
        if o == 1:
            s := 0.0
            for v in t.data:
                s = s + _abs(v)
            return s
        if o == INF:
            s := 0.0
            for v in t.data:
                if _abs(v) > s:
                    s = _abs(v)
            return s
        if o == 0:
            return array.count_nonzero(t) * 1.0
        if o < 1:
            raise("ValueError", "norm : p >= 1 attendu")
        sc := 0.0
        for v in t.data:
            if _abs(v) > sc:
                sc = _abs(v)
        if sc == 0.0:
            return 0.0
        s := 0.0
        for v in t.data:
            s = s + (_abs(v) / sc) ** o
        return sc * s ** (1.0 / o)
    if nd != 2:
        raise("ValueError", "norm : vecteur ou matrice attendu")
    rows := t.shape[0]
    cols := t.shape[1]
    if o == 2:
        s := svdvals(t)
        if len(s.data) == 0:
            return 0.0
        return s.data[0]
    if o == 1:
        best := 0.0
        j := 0
        while j < cols:
            s := 0.0
            i := 0
            while i < rows:
                s = s + _abs(t.data[i * cols + j])
                i = i + 1
            if s > best:
                best = s
            j = j + 1
        return best
    if o == INF:
        best := 0.0
        i := 0
        while i < rows:
            s := 0.0
            j := 0
            while j < cols:
                s = s + _abs(t.data[i * cols + j])
                j = j + 1
            if s > best:
                best = s
            i = i + 1
        return best
    raise("ValueError", "norm : ord non supporté pour une matrice (null, 1, INF, 'fro')")

func trace(a):
    return array.trace(a)

func normalize(v):
    t := _vec(v, "normalize")
    n := norm(t)
    if n == 0.0:
        raise("ZeroDivisionError", "normalize : vecteur nul")
    return array.div(t, n)

# Projection orthogonale de u sur v.
func project(u, v):
    a := _vec(u, "project")
    b := _vec(v, "project")
    d := array.dot(b, b)
    if d == 0:
        raise("ZeroDivisionError", "project : vecteur nul")
    return array.mul(b, array.dot(a, b) / d)

# Angle (radians) entre deux vecteurs, dans [0, pi].
func angle(u, v):
    a := _vec(u, "angle")
    b := _vec(v, "angle")
    na := norm(a)
    nb := norm(b)
    if na == 0.0 or nb == 0.0:
        raise("ZeroDivisionError", "angle : vecteur nul")
    c := array.dot(a, b) / (na * nb)
    if c > 1.0:
        c = 1.0
    if c < -1.0:
        c = -1.0
    return math.acos(c)

# Produit vectoriel de deux vecteurs de R^3.
func cross(u, v):
    a := _vec(u, "cross")
    b := _vec(v, "cross")
    if a.shape[0] != 3 or b.shape[0] != 3:
        raise("ValueError", "cross : vecteurs de dimension 3 attendus")
    x := a.data
    y := b.data
    return array.wrap([3], [x[1] * y[2] - x[2] * y[1], x[2] * y[0] - x[0] * y[2], x[0] * y[1] - x[1] * y[0]])

# Produit de Kronecker.
func kron(a, b):
    A := _m2(a, "kron")
    B := _m2(b, "kron")
    ar := A.shape[0]
    ac := A.shape[1]
    br := B.shape[0]
    bc := B.shape[1]
    out := _filled(ar * br * ac * bc, 0.0)
    cols := ac * bc
    i := 0
    while i < ar:
        j := 0
        while j < ac:
            aij := A.data[i * ac + j]
            k := 0
            while k < br:
                l := 0
                while l < bc:
                    out[(i * br + k) * cols + (j * bc + l)] = aij * B.data[k * bc + l]
                    l = l + 1
                k = k + 1
            j = j + 1
        i = i + 1
    return array.wrap([ar * br, cols], out)

# Triangle inférieur (éléments au-dessus de la k-ième diagonale mis à 0).
func tril(a, k=0):
    t := _m2(a, "tril")
    rows := t.shape[0]
    cols := t.shape[1]
    out := _copy(t.data)
    i := 0
    while i < rows:
        j := 0
        while j < cols:
            if j - i > k:
                out[i * cols + j] = 0.0
            j = j + 1
        i = i + 1
    return array.wrap([rows, cols], out)

# Triangle supérieur (éléments sous la k-ième diagonale mis à 0).
func triu(a, k=0):
    t := _m2(a, "triu")
    rows := t.shape[0]
    cols := t.shape[1]
    out := _copy(t.data)
    i := 0
    while i < rows:
        j := 0
        while j < cols:
            if j - i < k:
                out[i * cols + j] = 0.0
            j = j + 1
        i = i + 1
    return array.wrap([rows, cols], out)

# A^n par exponentiation rapide (n entier, négatif : puissance de l'inverse).
func matrix_power(a, n):
    t := _sq(a, "matrix_power")
    if not is_int(n):
        raise("TypeError", "matrix_power : exposant entier attendu")
    size := t.shape[0]
    base := t
    e := n
    if e < 0:
        base = inv(t)
        e = 0 - e
    result := array.eye(size)
    while e > 0:
        if e % 2 == 1:
            result = array.matmul(result, base)
        e = e // 2
        if e > 0:
            base = array.matmul(base, base)
    return result

# Exponentielle de matrice : Padé d'ordre 13 avec mise à l'échelle et élévation au carré (Higham, 2005).
func expm(a):
    t := _sq(a, "expm")
    n := t.shape[0]
    if n == 0:
        return array.zeros([0, 0])
    nrm := norm(t, 1)
    s := 0
    scaled := array.to_float(t)
    if nrm > 5.371920351148152:
        s = math.ceil(math.log2(nrm / 5.371920351148152))
        if s < 0:
            s = 0
        scaled = array.div(scaled, 2.0 ** s)
    b := [64764752532480000.0, 32382376266240000.0, 7771770303897600.0, 1187353796428800.0, 129060195264000.0, 10559470521600.0, 670442572800.0, 33522128640.0, 1323241920.0, 40840800.0, 960960.0, 16380.0, 182.0, 1.0]
    ident := array.eye(n)
    A2 := array.matmul(scaled, scaled)
    A4 := array.matmul(A2, A2)
    A6 := array.matmul(A4, A2)
    u_in := array.add(array.add(array.mul(A6, b[13]), array.mul(A4, b[11])), array.mul(A2, b[9]))
    u_mid := array.add(array.add(array.add(array.matmul(A6, u_in), array.mul(A6, b[7])), array.mul(A4, b[5])), array.add(array.mul(A2, b[3]), array.mul(ident, b[1])))
    U := array.matmul(scaled, u_mid)
    v_in := array.add(array.add(array.mul(A6, b[12]), array.mul(A4, b[10])), array.mul(A2, b[8]))
    V := array.add(array.add(array.add(array.matmul(A6, v_in), array.mul(A6, b[6])), array.mul(A4, b[4])), array.add(array.mul(A2, b[2]), array.mul(ident, b[0])))
    R := solve(array.sub(V, U), array.add(V, U))
    k := 0
    while k < s:
        R = array.matmul(R, R)
        k = k + 1
    return R
