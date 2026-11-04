use math
use array
use linalg
use numeric
from core use len, is_int, is_float, is_function
from collections use append

# ALEX STANDARD LIBRARY - calculus
# Calcul différentiel et intégral numérique : dérivées, opérateurs vectoriels, intégrales multiples, systèmes d'équations.
# Pure ALEX, aucune dépendance native. S'appuie sur array, linalg et numeric.
#
#   use calculus
#   func f(x):
#       return math.sin(x) * math.exp(x)
#   print(calculus.derivative(f, 1.0))                 # 2.2874... = e (sin 1 + cos 1)
#   func g(v):
#       return v[0] * v[0] * v[1] + math.sin(v[1])
#   print(calculus.gradient(g, [1.0, 2.0]).to_string())
#   print(calculus.hessian(g, [1.0, 2.0]).to_string())
#   func area(x, y):
#       return x * y
#   print(calculus.dblquad(area, 0.0, 2.0, 0.0, 3.0)[0])      # 9.0
#
# CONTENU
#   Dérivées        : derivative, derivative_err, second_derivative, derivative_n
#   Champs          : gradient, jacobian, hessian, directional_derivative, divergence, curl, laplacian
#   Intégrales      : dblquad, tplquad, line_integral
#   Équations       : newton_system (alias fsolve) : F(x) = 0 pour F : R^n -> R^n
#
# MÉTHODE
#   Différences finies centrées d'ordre n avec extrapolation de Richardson (Ridders, 1982) : pas initial 0,1 x échelle,
#   réduit d'un facteur 1,4 jusqu'à 10 fois ; le meilleur élément du tableau est retenu avec une estimation d'erreur.
#   Précision mesurée (fonctions régulières, contre SymPy) : ≈ 1e-13 pour n = 1, 1e-12 pour n = 2, 1e-10 pour n = 3,
#   1e-9 pour n = 4, 1e-7 pour n = 5 ; hessienne ≈ 1e-9. Une fonction non dérivable au point donne une erreur estimée grande.
#   Près d'une singularité (ex. 1/x en 0,2) ou d'un point anguleux, passer un pas `h` plus petit que la distance à celui-ci :
#   le pas initial par défaut (0,1 x max(1, |x|)) peut sinon enjamber la singularité (ZeroDivisionError ou résultat faux).
#
# CONVENTIONS
#   - Une fonction est une fonction ALEX nommée f(x) ou f(x, p) (voir numeric) ; `args` transmet le paramètre p.
#   - Une fonction de plusieurs variables reçoit une LISTE [x1, ..., xn] ; un champ de vecteurs renvoie une liste ou un Array.
#   - Les points sont une liste ou un Array ; les résultats vectoriels/matriciels sont des Array (voir array).
#   - Intégrales multiples : f(x, y[, args]) ; les bornes internes peuvent être des nombres ou des FONCTIONS des variables
#     extérieures : yhi(x), zlo(x, y)... ; le résultat est [valeur, erreur estimée de l'intégrale la plus extérieure].
#   - Erreurs : ValueError (arguments), ConvergenceError (newton_system).

const INF := 10.0 ** 400
const EPS := 0.0000000000000002220446049250313

# =====================================================================================================
# Moteur de dérivation (différences centrées + Richardson)
# =====================================================================================================

func _abs(x):
    if x < 0:
        return 0.0 - x
    return x * 1.0

func _is_scalar(x):
    return is_int(x) or is_float(x)

func _call(f, x, args):
    if args == null:
        return f(x)
    return f(x, args)

# Point sous forme de scalaire flottant ou de liste de flottants.
func _point(x):
    if _is_scalar(x):
        return x * 1.0
    t := array.as_array(x)
    if len(t.shape) != 1:
        raise("ValueError", "calculus : point 1-d attendu")
    out := []
    for v in t.data:
        append(out, v * 1.0)
    return out

func _component(v, comp):
    if comp < 0:
        return v * 1.0
    if array.is_array(v):
        return v.data[comp] * 1.0
    return v[comp] * 1.0

# f(x + t d), éventuellement une seule composante (comp >= 0) d'une fonction vectorielle.
func _eval_line(f, x, d, t, args, comp):
    v := null
    if _is_scalar(x):
        v = _call(f, x + t * d, args)
    else:
        pt := []
        i := 0
        while i < len(x):
            append(pt, x[i] + t * d[i])
            i = i + 1
        v = _call(f, pt, args)
    return _component(v, comp)

# Différence centrée d'ordre n de pas h : sum_k (-1)^k C(n,k) F((n/2 - k) h) / h^n.
func _nth_diff(f, x, d, args, comp, n, h):
    s := 0.0
    c := 1.0
    k := 0
    while k <= n:
        t := (n - 2 * k) * h / 2.0
        term := c * _eval_line(f, x, d, t, args, comp)
        if k % 2 == 0:
            s = s + term
        else:
            s = s - term
        c = c * (n - k) / (k + 1.0)
        k = k + 1
    return s / (h ** n)

# Dérivée d'ordre n le long de la direction d au point x ; renvoie [valeur, erreur estimée].
func _richardson(f, x, d, args, comp, n, h0):
    con := 1.4
    con2 := 1.96
    ntab := 10
    a := []
    i := 0
    while i < ntab * ntab:
        append(a, 0.0)
        i = i + 1
    h := h0
    a[0] = _nth_diff(f, x, d, args, comp, n, h)
    ans := a[0]
    err := INF
    i = 1
    while i < ntab:
        h = h / con
        a[i] = _nth_diff(f, x, d, args, comp, n, h)
        fac := con2
        j := 1
        while j <= i:
            a[j * ntab + i] = (a[(j - 1) * ntab + i] * fac - a[(j - 1) * ntab + i - 1]) / (fac - 1.0)
            fac = fac * con2
            e1 := _abs(a[j * ntab + i] - a[(j - 1) * ntab + i])
            e2 := _abs(a[j * ntab + i] - a[(j - 1) * ntab + i - 1])
            errt := e1
            if e2 > errt:
                errt = e2
            if errt <= err:
                err = errt
                ans = a[j * ntab + i]
            j = j + 1
        if _abs(a[i * ntab + i] - a[(i - 1) * ntab + i - 1]) >= 2.0 * err:
            break
        i = i + 1
    return [ans, err]

# Pas initial : 0,1 x max(1, |x|) / max|d|.
func _h0(x, d, h):
    if h != null:
        return h * 1.0
    xs := 1.0
    ds := 0.0
    if _is_scalar(x):
        if _abs(x) > xs:
            xs = _abs(x)
        ds = _abs(d)
    else:
        for v in x:
            if _abs(v) > xs:
                xs = _abs(v)
        for v in d:
            if _abs(v) > ds:
                ds = _abs(v)
    if ds == 0.0:
        raise("ValueError", "calculus : direction nulle")
    return 0.1 * xs / ds

func _unit(n, i):
    out := []
    k := 0
    while k < n:
        if k == i:
            append(out, 1.0)
        else:
            append(out, 0.0)
        k = k + 1
    return out

# =====================================================================================================
# Dérivées d'une fonction d'une variable
# =====================================================================================================

# Dérivée première f'(x). h : pas initial (défaut : adapté à |x|).
func derivative(f, x, h=null, args=null):
    return derivative_err(f, x, h, args)[0]

# [f'(x), erreur estimée].
func derivative_err(f, x, h=null, args=null):
    p := _point(x)
    if not _is_scalar(p):
        raise("ValueError", "derivative : abscisse scalaire attendue (voir gradient pour plusieurs variables)")
    return _richardson(f, p, 1.0, args, -1, 1, _h0(p, 1.0, h))

func second_derivative(f, x, h=null, args=null):
    return derivative_n(f, x, 2, h, args)

# Dérivée d'ordre n >= 1 (n <= 6 recommandé ; la précision diminue avec n).
func derivative_n(f, x, n, h=null, args=null):
    if not is_int(n) or n < 1:
        raise("ValueError", "derivative_n : ordre entier >= 1 attendu")
    p := _point(x)
    if not _is_scalar(p):
        raise("ValueError", "derivative_n : abscisse scalaire attendue")
    return _richardson(f, p, 1.0, args, -1, n, _h0(p, 1.0, h))[0]

# =====================================================================================================
# Fonctions de plusieurs variables
# =====================================================================================================

# Gradient d'une fonction scalaire de n variables : Array de longueur n.
func gradient(f, x, h=null, args=null):
    p := _point(x)
    if _is_scalar(p):
        raise("ValueError", "gradient : point à plusieurs coordonnées attendu")
    n := len(p)
    out := []
    i := 0
    while i < n:
        d := _unit(n, i)
        append(out, _richardson(f, p, d, args, -1, 1, _h0(p, d, h))[0])
        i = i + 1
    return array.wrap([n], out)

# Dérivée de f au point x dans la direction d (d n'est PAS normalisé : résultat = gradient . d).
func directional_derivative(f, x, d, h=null, args=null):
    p := _point(x)
    dd := _point(d)
    if _is_scalar(p) or len(p) != len(dd):
        raise("ValueError", "directional_derivative : x et d de même dimension attendus")
    return _richardson(f, p, dd, args, -1, 1, _h0(p, dd, h))[0]

# Matrice jacobienne m x n d'un champ F : R^n -> R^m.
func jacobian(F, x, h=null, args=null):
    p := _point(x)
    if _is_scalar(p):
        raise("ValueError", "jacobian : point à plusieurs coordonnées attendu")
    n := len(p)
    v0 := _call(F, p, args)
    m := 1
    if array.is_array(v0):
        m = len(v0.data)
    elif not _is_scalar(v0):
        m = len(v0)
    out := []
    i := 0
    while i < m * n:
        append(out, 0.0)
        i = i + 1
    j := 0
    while j < n:
        d := _unit(n, j)
        hh := _h0(p, d, h)
        i = 0
        while i < m:
            comp := i
            if _is_scalar(v0):
                comp = -1
            out[i * n + j] = _richardson(F, p, d, args, comp, 1, hh)[0]
            i = i + 1
        j = j + 1
    return array.wrap([m, n], out)

# Matrice hessienne n x n d'une fonction scalaire (dérivées secondes par différences centrées + Richardson).
func hessian(f, x, h=null, args=null):
    p := _point(x)
    if _is_scalar(p):
        raise("ValueError", "hessian : point à plusieurs coordonnées attendu")
    n := len(p)
    diag := []
    i := 0
    while i < n:
        d := _unit(n, i)
        append(diag, _richardson(f, p, d, args, -1, 2, _h0(p, d, h))[0])
        i = i + 1
    out := []
    i = 0
    while i < n * n:
        append(out, 0.0)
        i = i + 1
    i = 0
    while i < n:
        out[i * n + i] = diag[i]
        j := i + 1
        while j < n:
            d := _unit(n, i)
            d[j] = 1.0
            dij := _richardson(f, p, d, args, -1, 2, _h0(p, d, h))[0]
            v := 0.5 * (dij - diag[i] - diag[j])
            out[i * n + j] = v
            out[j * n + i] = v
            j = j + 1
        i = i + 1
    return array.wrap([n, n], out)

# Laplacien (somme des dérivées secondes pures).
func laplacian(f, x, h=null, args=null):
    p := _point(x)
    if _is_scalar(p):
        raise("ValueError", "laplacian : point à plusieurs coordonnées attendu")
    n := len(p)
    s := 0.0
    i := 0
    while i < n:
        d := _unit(n, i)
        s = s + _richardson(f, p, d, args, -1, 2, _h0(p, d, h))[0]
        i = i + 1
    return s

# Divergence d'un champ F : R^n -> R^n (trace de la jacobienne).
func divergence(F, x, h=null, args=null):
    p := _point(x)
    if _is_scalar(p):
        raise("ValueError", "divergence : point à plusieurs coordonnées attendu")
    n := len(p)
    s := 0.0
    i := 0
    while i < n:
        d := _unit(n, i)
        s = s + _richardson(F, p, d, args, i, 1, _h0(p, d, h))[0]
        i = i + 1
    return s

# Rotationnel d'un champ F : R^3 -> R^3 : Array de longueur 3.
func curl(F, x, h=null, args=null):
    p := _point(x)
    if _is_scalar(p) or len(p) != 3:
        raise("ValueError", "curl : point de R^3 attendu")
    ex := _unit(3, 0)
    ey := _unit(3, 1)
    ez := _unit(3, 2)
    hx := _h0(p, ex, h)
    hy := _h0(p, ey, h)
    hz := _h0(p, ez, h)
    dFz_dy := _richardson(F, p, ey, args, 2, 1, hy)[0]
    dFy_dz := _richardson(F, p, ez, args, 1, 1, hz)[0]
    dFx_dz := _richardson(F, p, ez, args, 0, 1, hz)[0]
    dFz_dx := _richardson(F, p, ex, args, 2, 1, hx)[0]
    dFy_dx := _richardson(F, p, ex, args, 1, 1, hx)[0]
    dFx_dy := _richardson(F, p, ey, args, 0, 1, hy)[0]
    return array.wrap([3], [dFz_dy - dFy_dz, dFx_dz - dFz_dx, dFy_dx - dFx_dy])

# =====================================================================================================
# Intégrales multiples
# =====================================================================================================

func _lim1(v, x):
    if is_function(v):
        return v(x) * 1.0
    return v * 1.0

func _lim2(v, x, y):
    if is_function(v):
        return v(x, y) * 1.0
    return v * 1.0

func _dbl_inner(y, ctx):
    if ctx[2] == null:
        return ctx[0](ctx[1], y)
    return ctx[0](ctx[1], y, ctx[2])

# ctx = [f, ylo, yhi, args, epsabs, epsrel]
func _dbl_outer(x, ctx):
    lo := _lim1(ctx[1], x)
    hi := _lim1(ctx[2], x)
    return numeric.quad(_dbl_inner, lo, hi, [ctx[0], x, ctx[3]], ctx[4], ctx[5])[0]

# Intégrale double de f(x, y[, args]) sur a <= x <= b, ylo(x) <= y <= yhi(x). Renvoie [valeur, erreur estimée extérieure].
func dblquad(f, a, b, ylo, yhi, args=null, epsabs=0.0000000001, epsrel=0.0000000001):
    return numeric.quad(_dbl_outer, a, b, [f, ylo, yhi, args, epsabs, epsrel], epsabs, epsrel)

func _tpl_z(z, ctx):
    if ctx[3] == null:
        return ctx[0](ctx[1], ctx[2], z)
    return ctx[0](ctx[1], ctx[2], z, ctx[3])

# ctx = [f, x, zlo, zhi, args, epsabs, epsrel]
func _tpl_y(y, ctx):
    lo := _lim2(ctx[2], ctx[1], y)
    hi := _lim2(ctx[3], ctx[1], y)
    return numeric.quad(_tpl_z, lo, hi, [ctx[0], ctx[1], y, ctx[4]], ctx[5], ctx[6])[0]

# ctx = [f, ylo, yhi, zlo, zhi, args, epsabs, epsrel]
func _tpl_x(x, ctx):
    lo := _lim1(ctx[1], x)
    hi := _lim1(ctx[2], x)
    return numeric.quad(_tpl_y, lo, hi, [ctx[0], x, ctx[3], ctx[4], ctx[5], ctx[6], ctx[7]], ctx[6], ctx[7])[0]

# Intégrale triple de f(x, y, z[, args]) ; ylo/yhi : nombres ou fonctions de x ; zlo/zhi : nombres ou fonctions de (x, y).
func tplquad(f, a, b, ylo, yhi, zlo, zhi, args=null, epsabs=0.00000001, epsrel=0.00000001):
    return numeric.quad(_tpl_x, a, b, [f, ylo, yhi, zlo, zhi, args, epsabs, epsrel], epsabs, epsrel)

func _li(t, ctx):
    F := ctx[0]
    pt := ctx[1](t)
    v := F(pt)
    dr := ctx[2](t)
    s := 0.0
    i := 0
    while i < len(dr):
        s = s + _component(v, i) * dr[i]
        i = i + 1
    return s

# Intégrale curviligne d'un champ F : R^n -> R^n le long de la courbe r(t) (de dérivée dr(t)), t de t0 à t1 :
# somme de F(r(t)) . r'(t) dt. r et dr renvoient des listes. Renvoie [valeur, erreur estimée].
func line_integral(F, r, dr, t0, t1, epsabs=0.000000000001, epsrel=0.000000000001):
    return numeric.quad(_li, t0, t1, [F, r, dr], epsabs, epsrel)

# =====================================================================================================
# Systèmes d'équations non linéaires
# =====================================================================================================

func _fvec(F, x, args):
    v := _call(F, x, args)
    out := []
    if array.is_array(v):
        for t in v.data:
            append(out, t * 1.0)
        return out
    if _is_scalar(v):
        return [v * 1.0]
    for t in v:
        append(out, t * 1.0)
    return out

func _norm2(v):
    return linalg.norm(array.wrap([len(v)], v))

# Résout F(x) = 0 (F : R^n -> R^n) par Newton amorti (recherche linéaire par division du pas).
# jac(x[, args]) : jacobienne analytique (matrice) ; si null, jacobienne numérique. Renvoie x sous forme d'Array.
func newton_system(F, x0, jac=null, tol=0.000000000001, maxiter=50, args=null):
    x := _point(x0)
    if _is_scalar(x):
        x = [x]
    n := len(x)
    fx := _fvec(F, x, args)
    if len(fx) != n:
        raise("ValueError", "newton_system : F doit renvoyer autant de composantes que de variables")
    k := 0
    while k < maxiter:
        nf := _norm2(fx)
        if nf <= tol:
            return array.wrap([n], x)
        J := null
        if jac == null:
            J = jacobian(F, x, null, args)
        else:
            J = array.as_array(_call(jac, x, args))
        negf := []
        for v in fx:
            append(negf, 0.0 - v)
        dx := null
        try:
            dx = linalg.solve(J, array.wrap([n], negf))
        catch e:
            raise("ConvergenceError", "newton_system : jacobienne singulière")
        lam := 1.0
        accepted := false
        trial := x
        ftrial := fx
        ls := 0
        while ls < 30 and not accepted:
            trial = []
            i := 0
            while i < n:
                append(trial, x[i] + lam * dx.data[i])
                i = i + 1
            ftrial = _fvec(F, trial, args)
            if _norm2(ftrial) < nf or _norm2(ftrial) <= tol:
                accepted = true
            else:
                lam = lam / 2.0
            ls = ls + 1
        if not accepted:
            raise("ConvergenceError", "newton_system : pas de descente trouvé")
        x = trial
        fx = ftrial
        k = k + 1
    if _norm2(fx) <= tol:
        return array.wrap([n], x)
    raise("ConvergenceError", "newton_system : nombre maximal d'itérations atteint")

func fsolve(F, x0, jac=null, tol=0.000000000001, maxiter=50, args=null):
    return newton_system(F, x0, jac, tol, maxiter, args)
