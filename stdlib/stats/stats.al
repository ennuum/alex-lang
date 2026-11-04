use math
use array
use linalg
from core use len, is_int, is_float, is_list
from collections use append

# ALEX STANDARD LIBRARY - stats
# Statistiques descriptives, lois de probabilité, tests d'hypothèses et régression. Pure ALEX.
#
#   use stats
#   x := [2.1, 2.5, 3.0, 3.2, 4.8, 5.1]
#   print(stats.mean(x), stats.std(x, 1), stats.median(x))
#   print(stats.quantile(x, 0.9))
#   r := stats.ttest_1samp(x, 3.0)                 # [t, p, df]
#   print(stats.norm_cdf(1.96), stats.t_ppf(0.975, 10))
#   fit := stats.linregress(x, [1.0, 2.1, 2.9, 4.2, 5.0, 6.1])   # [pente, ordonnée, r, p, erreur-type, erreur-type ordonnée]
#
# CONVENTIONS
#   - Les données sont un Array 1-d ou une liste plate de nombres. Rien n'est modifié en place.
#   - ddof = degrés de liberté perdus, comme NumPy : var/std valent 0 par défaut (population) ; passer 1 pour
#     l'estimateur sans biais d'un échantillon. cov/corr suivent NumPy (ddof = 1).
#   - quantile : interpolation linéaire entre statistiques d'ordre (méthode « linear » de NumPy, type 7).
#   - skew / kurtosis : estimateurs biaisés par défaut (bias=true), kurtosis « excédentaire » (loi normale -> 0), comme SciPy.
#   - Lois : <loi>_pdf (ou _pmf), _cdf, _sf (survie, précise dans la queue), _ppf (quantile). Paramètres de position/échelle
#     comme SciPy : norm_pdf(x, mu, sigma), expon_pdf(x, scale), gamma_pdf(x, a, scale), uniform_cdf(x, lo, hi).
#   - Tests : renvoient des listes [statistique, p-value, ...], p-values bilatérales sauf mention contraire.
#   - Erreurs : ValueError (données vides, paramètre hors domaine), ZeroDivisionError (variance nulle où la division est
#     nécessaire).
#
# PRÉCISION
#   Fonctions spéciales : gamma incomplète régularisée (série + fraction continue de Lentz) et bêta incomplète
#   régularisée (fraction continue), précision relative ≈ 1e-13. norm_ppf : approximation d'Acklam affinée par 2 pas de
#   Halley (≈ 1e-15). Les autres quantiles sont obtenus par encadrement + Newton/bissection (≈ 1e-12).

const INF := 10.0 ** 400
const NAN := INF - INF
const SQRT2 := 1.4142135623730951
const SQRT2PI := 2.5066282746310002
const LN_SQRT2PI := 0.9189385332046727
const EPS := 0.0000000000000002220446049250313

# =====================================================================================================
# Utilitaires
# =====================================================================================================

func _abs(x):
    if x < 0:
        return 0.0 - x
    return x * 1.0

# Liste plate de flottants issue d'un Array 1-d ou d'une liste.
func _flat(x, who):
    t := array.as_array(x)
    if len(t.shape) != 1:
        if len(t.shape) == 0:
            return [t.data[0] * 1.0]
        raise("ValueError", f"{who} : données 1-d attendues (forme {t.shape})")
    out := []
    for v in t.data:
        append(out, v * 1.0)
    return out

func _nonempty(x, who):
    d := _flat(x, who)
    if len(d) == 0:
        raise("ValueError", f"{who} : données vides")
    return d

func _sum(d):
    return array.sum(array.wrap([len(d)], d))

# =====================================================================================================
# Statistiques descriptives
# =====================================================================================================

func mean(x):
    d := _nonempty(x, "mean")
    return _sum(d) / len(d)

func weighted_mean(x, w):
    d := _nonempty(x, "weighted_mean")
    ww := _flat(w, "weighted_mean")
    if len(ww) != len(d):
        raise("ValueError", "weighted_mean : poids de longueur différente")
    sw := _sum(ww)
    if sw == 0.0:
        raise("ZeroDivisionError", "weighted_mean : somme des poids nulle")
    p := []
    i := 0
    while i < len(d):
        append(p, d[i] * ww[i])
        i = i + 1
    return _sum(p) / sw

func median(x):
    d := array.sort_list(_nonempty(x, "median"))
    n := len(d)
    if n % 2 == 1:
        return d[n // 2]
    return (d[n // 2 - 1] + d[n // 2]) / 2.0

# Valeur la plus fréquente (la plus petite en cas d'égalité).
func mode(x):
    d := array.sort_list(_nonempty(x, "mode"))
    best := d[0]
    best_n := 0
    cur := d[0]
    cnt := 0
    for v in d:
        if v == cur:
            cnt = cnt + 1
        else:
            cur = v
            cnt = 1
        if cnt > best_n:
            best_n = cnt
            best = cur
    return best

# Variance (ddof=0 : population ; ddof=1 : échantillon). Algorithme en deux passes.
func var(x, ddof=0):
    d := _nonempty(x, "var")
    n := len(d)
    if n - ddof <= 0:
        raise("ValueError", "var : pas assez de données pour ddof donné")
    m := _sum(d) / n
    dev := []
    for v in d:
        append(dev, (v - m) * (v - m))
    return _sum(dev) / (n - ddof)

func std(x, ddof=0):
    return math.sqrt(var(x, ddof))

# Erreur-type de la moyenne : s / sqrt(n) avec s l'écart-type d'échantillon.
func sem(x):
    d := _nonempty(x, "sem")
    return std(d, 1) / math.sqrt(len(d))

func ptp(x):
    d := _nonempty(x, "ptp")
    return array.max(d) - array.min(d)

func _central_moment(d, k):
    m := _sum(d) / len(d)
    t := []
    for v in d:
        append(t, (v - m) ** k)
    return _sum(t) / len(d)

# Coefficient d'asymétrie (Fisher-Pearson). bias=false : correction d'échantillon.
func skew(x, bias=true):
    d := _nonempty(x, "skew")
    n := len(d)
    m2 := _central_moment(d, 2)
    if m2 == 0.0:
        return NAN
    g1 := _central_moment(d, 3) / (m2 ** 1.5)
    if bias:
        return g1
    if n < 3:
        raise("ValueError", "skew : au moins 3 données pour bias=false")
    return math.sqrt(n * (n - 1.0)) / (n - 2.0) * g1

# Kurtosis excédentaire (loi normale = 0). bias=false : correction d'échantillon.
func kurtosis(x, bias=true):
    d := _nonempty(x, "kurtosis")
    n := len(d)
    m2 := _central_moment(d, 2)
    if m2 == 0.0:
        return NAN
    g2 := _central_moment(d, 4) / (m2 * m2) - 3.0
    if bias:
        return g2
    if n < 4:
        raise("ValueError", "kurtosis : au moins 4 données pour bias=false")
    return (n - 1.0) / ((n - 2.0) * (n - 3.0)) * ((n + 1.0) * g2 + 6.0)

# Quantile d'ordre q dans [0, 1], interpolation linéaire (type 7).
func quantile(x, q):
    d := array.sort_list(_nonempty(x, "quantile"))
    return _quantile_sorted(d, q)

func _quantile_sorted(d, q):
    if q < 0 or q > 1:
        raise("ValueError", "quantile : q doit être dans [0, 1]")
    n := len(d)
    pos := q * (n - 1)
    lo := math.floor(pos)
    if lo >= n - 1:
        return d[n - 1]
    frac := pos - lo
    return d[lo] + (d[lo + 1] - d[lo]) * frac

func percentile(x, p):
    return quantile(x, p / 100.0)

# Liste de quantiles (un seul tri).
func quantiles(x, qs):
    d := array.sort_list(_nonempty(x, "quantiles"))
    out := []
    for q in qs:
        append(out, _quantile_sorted(d, q))
    return out

# Écart interquartile.
func iqr(x):
    d := array.sort_list(_nonempty(x, "iqr"))
    return _quantile_sorted(d, 0.75) - _quantile_sorted(d, 0.25)

# Écart absolu médian (non mis à l'échelle).
func mad(x):
    d := _nonempty(x, "mad")
    m := median(d)
    dev := []
    for v in d:
        append(dev, _abs(v - m))
    return median(dev)

# Scores z : (x - moyenne) / écart-type.
func zscore(x, ddof=0):
    d := _nonempty(x, "zscore")
    m := mean(d)
    s := std(d, ddof)
    if s == 0.0:
        raise("ZeroDivisionError", "zscore : écart-type nul")
    out := []
    for v in d:
        append(out, (v - m) / s)
    return array.wrap([len(d)], out)

# Rangs 1..n (rangs moyens pour les ex aequo).
func rankdata(x):
    d := _nonempty(x, "rankdata")
    n := len(d)
    order := array.argsort_list(d)
    ranks := []
    i := 0
    while i < n:
        append(ranks, 0.0)
        i = i + 1
    i = 0
    while i < n:
        j := i
        while j + 1 < n and d[order[j + 1]] == d[order[i]]:
            j = j + 1
        avg := (i + j) / 2.0 + 1.0
        k := i
        while k <= j:
            ranks[order[k]] = avg
            k = k + 1
        i = j + 1
    return array.wrap([n], ranks)

# Résumé descriptif sous forme de dictionnaire.
func describe(x):
    d := _nonempty(x, "describe")
    r := {}
    r["n"] = len(d)
    r["min"] = array.min(d)
    r["max"] = array.max(d)
    r["mean"] = mean(d)
    if len(d) > 1:
        r["var"] = var(d, 1)
    else:
        r["var"] = NAN
    r["skew"] = skew(d)
    r["kurtosis"] = kurtosis(d)
    return r

# Histogramme : [effectifs (entiers), bornes (bins + 1)]. Dernière classe fermée à droite (comme NumPy).
func histogram(x, bins=10, lo=null, hi=null):
    d := _nonempty(x, "histogram")
    if not is_int(bins) or bins < 1:
        raise("ValueError", "histogram : bins entier >= 1 attendu")
    a := lo
    b := hi
    if a == null:
        a = array.min(d)
    if b == null:
        b = array.max(d)
    if a == b:
        a = a - 0.5
        b = b + 0.5
    if b < a:
        raise("ValueError", "histogram : intervalle invalide")
    counts := []
    i := 0
    while i < bins:
        append(counts, 0)
        i = i + 1
    width := (b - a) / bins
    for v in d:
        if v >= a and v <= b:
            k := math.floor((v - a) / width)
            if k >= bins:
                k = bins - 1
            # correction d'arrondi : s'assurer que v appartient bien à [edge_k, edge_k+1[
            if k > 0 and v < a + k * width:
                k = k - 1
            if k < bins - 1 and v >= a + (k + 1) * width:
                k = k + 1
            counts[k] = counts[k] + 1
    edges := array.linspace(a, b, bins + 1)
    return [counts, edges.data]

# =====================================================================================================
# Covariance et corrélation
# =====================================================================================================

func covariance(x, y, ddof=1):
    a := _nonempty(x, "covariance")
    b := _nonempty(y, "covariance")
    n := len(a)
    if len(b) != n:
        raise("ValueError", "covariance : séries de longueurs différentes")
    if n - ddof <= 0:
        raise("ValueError", "covariance : pas assez de données")
    ma := _sum(a) / n
    mb := _sum(b) / n
    t := []
    i := 0
    while i < n:
        append(t, (a[i] - ma) * (b[i] - mb))
        i = i + 1
    return _sum(t) / (n - ddof)

# Coefficient de corrélation de Pearson.
func corr(x, y):
    a := _nonempty(x, "corr")
    b := _nonempty(y, "corr")
    n := len(a)
    if len(b) != n:
        raise("ValueError", "corr : séries de longueurs différentes")
    ma := _sum(a) / n
    mb := _sum(b) / n
    sab := []
    saa := []
    sbb := []
    i := 0
    while i < n:
        da := a[i] - ma
        db := b[i] - mb
        append(sab, da * db)
        append(saa, da * da)
        append(sbb, db * db)
        i = i + 1
    den := math.sqrt(_sum(saa) * _sum(sbb))
    if den == 0.0:
        return NAN
    r := _sum(sab) / den
    if r > 1.0:
        r = 1.0
    if r < -1.0:
        r = -1.0
    return r

# Corrélation de rang de Spearman.
func spearman(x, y):
    return corr(rankdata(x), rankdata(y))

# Tau de Kendall (tau-b, avec correction des ex aequo).
func kendall(x, y):
    a := _nonempty(x, "kendall")
    b := _nonempty(y, "kendall")
    n := len(a)
    if len(b) != n:
        raise("ValueError", "kendall : séries de longueurs différentes")
    conc := 0
    disc := 0
    ta := 0
    tb := 0
    i := 0
    while i < n:
        j := i + 1
        while j < n:
            da := a[i] - a[j]
            db := b[i] - b[j]
            if da == 0 and db == 0:
                ta = ta + 1
                tb = tb + 1
            elif da == 0:
                ta = ta + 1
            elif db == 0:
                tb = tb + 1
            elif (da > 0) == (db > 0):
                conc = conc + 1
            else:
                disc = disc + 1
            j = j + 1
        i = i + 1
    n0 := n * (n - 1) / 2.0
    den := math.sqrt((n0 - ta) * (n0 - tb))
    if den == 0.0:
        return NAN
    return (conc - disc) / den

# Matrice de covariance. rowvar=true : chaque ligne est une variable (comme NumPy) ; sinon chaque colonne.
func cov_matrix(data, rowvar=true, ddof=1):
    t := array.as_array(data)
    if len(t.shape) != 2:
        raise("ValueError", "cov_matrix : matrice 2-d attendue")
    if not rowvar:
        t = array.transpose(t)
    p := t.shape[0]
    n := t.shape[1]
    if n - ddof <= 0:
        raise("ValueError", "cov_matrix : pas assez d'observations")
    rows := []
    i := 0
    while i < p:
        append(rows, array.row(t, i).data)
        i = i + 1
    out := []
    i = 0
    while i < p:
        j := 0
        while j < p:
            append(out, 0.0)
            j = j + 1
        i = i + 1
    i = 0
    while i < p:
        j := i
        while j < p:
            c := covariance(rows[i], rows[j], ddof)
            out[i * p + j] = c
            out[j * p + i] = c
            j = j + 1
        i = i + 1
    return array.wrap([p, p], out)

# Matrice de corrélation de Pearson.
func corr_matrix(data, rowvar=true):
    t := array.as_array(data)
    if len(t.shape) != 2:
        raise("ValueError", "corr_matrix : matrice 2-d attendue")
    if not rowvar:
        t = array.transpose(t)
    p := t.shape[0]
    rows := []
    i := 0
    while i < p:
        append(rows, array.row(t, i).data)
        i = i + 1
    out := []
    i = 0
    while i < p * p:
        append(out, 1.0)
        i = i + 1
    i = 0
    while i < p:
        j := i + 1
        while j < p:
            c := corr(rows[i], rows[j])
            out[i * p + j] = c
            out[j * p + i] = c
            j = j + 1
        i = i + 1
    return array.wrap([p, p], out)

# =====================================================================================================
# Fonctions spéciales : gamma et bêta incomplètes régularisées
# =====================================================================================================

# Série de P(a, x), valable pour x < a + 1.
func _gser(a, x):
    ap := a
    s := 1.0 / a
    term := s
    n := 0
    while n < 1000:
        ap = ap + 1.0
        term = term * x / ap
        s = s + term
        if _abs(term) < _abs(s) * 0.0000000000000001:
            break
        n = n + 1
    return s * math.exp(0.0 - x + a * math.ln(x) - math.lgamma(a))

# Fraction continue de Q(a, x) (Lentz), valable pour x >= a + 1.
func _gcf(a, x):
    tiny := (10.0 ** -300)
    b := x + 1.0 - a
    c := 1.0 / tiny
    d := 1.0 / b
    h := d
    i := 1
    while i < 1000:
        an := 0.0 - i * (i - a)
        b = b + 2.0
        d = an * d + b
        if _abs(d) < tiny:
            d = tiny
        c = b + an / c
        if _abs(c) < tiny:
            c = tiny
        d = 1.0 / d
        dl := d * c
        h = h * dl
        if _abs(dl - 1.0) < 0.0000000000000004:
            break
        i = i + 1
    return math.exp(0.0 - x + a * math.ln(x) - math.lgamma(a)) * h

# Gamma incomplète régularisée inférieure P(a, x).
func gammainc(a, x):
    if a <= 0:
        raise("ValueError", "gammainc : a > 0 attendu")
    if x <= 0:
        return 0.0
    if x == INF:
        return 1.0
    if x < a + 1.0:
        return _gser(a, x)
    return 1.0 - _gcf(a, x)

# Gamma incomplète régularisée supérieure Q(a, x) = 1 - P(a, x) (précise dans la queue).
func gammaincc(a, x):
    if a <= 0:
        raise("ValueError", "gammaincc : a > 0 attendu")
    if x <= 0:
        return 1.0
    if x == INF:
        return 0.0
    if x < a + 1.0:
        return 1.0 - _gser(a, x)
    return _gcf(a, x)

func _betacf(a, b, x):
    tiny := (10.0 ** -300)
    qab := a + b
    qap := a + 1.0
    qam := a - 1.0
    c := 1.0
    d := 1.0 - qab * x / qap
    if _abs(d) < tiny:
        d = tiny
    d = 1.0 / d
    h := d
    m := 1
    while m < 2000:
        m2 := 2 * m
        aa := m * (b - m) * x / ((qam + m2) * (a + m2))
        d = 1.0 + aa * d
        if _abs(d) < tiny:
            d = tiny
        c = 1.0 + aa / c
        if _abs(c) < tiny:
            c = tiny
        d = 1.0 / d
        h = h * d * c
        aa = 0.0 - (a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
        d = 1.0 + aa * d
        if _abs(d) < tiny:
            d = tiny
        c = 1.0 + aa / c
        if _abs(c) < tiny:
            c = tiny
        d = 1.0 / d
        dl := d * c
        h = h * dl
        if _abs(dl - 1.0) < 0.0000000000000004:
            break
        m = m + 1
    return h

# Bêta incomplète régularisée I_x(a, b).
func betainc(a, b, x):
    if a <= 0 or b <= 0:
        raise("ValueError", "betainc : a > 0 et b > 0 attendus")
    if x <= 0:
        return 0.0
    if x >= 1:
        return 1.0
    lbeta := math.lgamma(a + b) - math.lgamma(a) - math.lgamma(b)
    front := math.exp(lbeta + a * math.ln(x) + b * math.ln(1.0 - x))
    if x < (a + 1.0) / (a + b + 2.0):
        return front * _betacf(a, b, x) / a
    return 1.0 - front * _betacf(b, a, 1.0 - x) / b

# =====================================================================================================
# Loi normale
# =====================================================================================================

func norm_pdf(x, mu=0.0, sigma=1.0):
    if sigma <= 0:
        raise("ValueError", "norm_pdf : sigma > 0 attendu")
    z := (x - mu) / sigma
    return math.exp(-0.5 * z * z) / (sigma * SQRT2PI)

func norm_cdf(x, mu=0.0, sigma=1.0):
    if sigma <= 0:
        raise("ValueError", "norm_cdf : sigma > 0 attendu")
    return 0.5 * math.erfc(0.0 - (x - mu) / (sigma * SQRT2))

func norm_sf(x, mu=0.0, sigma=1.0):
    if sigma <= 0:
        raise("ValueError", "norm_sf : sigma > 0 attendu")
    return 0.5 * math.erfc((x - mu) / (sigma * SQRT2))

# Quantile de la loi normale standard pour 0 < p <= 0.5 (Acklam + 2 pas de Halley sur la queue gauche, précise).
func _norm_ppf_low(p):
    a := [-39.69683028665376, 220.9460984245205, -275.9285104469687, 138.357751867269, -30.66479806614716, 2.506628277459239]
    b := [-54.47609879822406, 161.5858368580409, -155.6989798598866, 66.80131188771972, -13.28068155288572]
    c := [-0.007784894002430293, -0.3223964580411365, -2.400758277161838, -2.549732539343734, 4.374664141464968, 2.938163982698783]
    d := [0.007784695709041462, 0.3224671290700398, 2.445134137142996, 3.754408661907416]
    x := 0.0
    if p < 0.02425:
        q := math.sqrt(-2.0 * math.ln(p))
        x = (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1.0)
    else:
        q := p - 0.5
        r := q * q
        x = (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q / (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1.0)
    k := 0
    while k < 2:
        e := 0.5 * math.erfc(0.0 - x / SQRT2) - p
        u := e * SQRT2PI * math.exp(x * x / 2.0)
        x = x - u / (1.0 + x * u / 2.0)
        k = k + 1
    return x

# Quantile de la loi normale. Utilise la symétrie pour p > 0.5 (1 - p est exact en flottant), donc précis dans les deux queues.
func norm_ppf(p, mu=0.0, sigma=1.0):
    if sigma <= 0:
        raise("ValueError", "norm_ppf : sigma > 0 attendu")
    if p < 0 or p > 1:
        raise("ValueError", "norm_ppf : p doit être dans [0, 1]")
    if p == 0:
        return 0.0 - INF
    if p == 1:
        return INF
    if p == 0.5:
        return mu * 1.0
    if p > 0.5:
        return mu + sigma * (0.0 - _norm_ppf_low(1.0 - p))
    return mu + sigma * _norm_ppf_low(p)

# =====================================================================================================
# Lois continues : Student, khi-deux, Fisher, gamma, bêta, exponentielle, uniforme
# =====================================================================================================

func t_pdf(x, df):
    if df <= 0:
        raise("ValueError", "t_pdf : df > 0 attendu")
    return math.exp(math.lgamma((df + 1.0) / 2.0) - math.lgamma(df / 2.0) - 0.5 * math.ln(df * math.PI) - (df + 1.0) / 2.0 * math.ln(1.0 + x * x / df))

func t_cdf(x, df):
    if df <= 0:
        raise("ValueError", "t_cdf : df > 0 attendu")
    if x == 0:
        return 0.5
    tail := 0.5 * betainc(df / 2.0, 0.5, df / (df + x * x))
    if x > 0:
        return 1.0 - tail
    return tail

func t_sf(x, df):
    return t_cdf(0.0 - x, df)

func chi2_pdf(x, df):
    if df <= 0:
        raise("ValueError", "chi2_pdf : df > 0 attendu")
    if x < 0:
        return 0.0
    if x == 0:
        if df < 2:
            return INF
        if df == 2:
            return 0.5
        return 0.0
    k := df / 2.0
    return math.exp((k - 1.0) * math.ln(x) - x / 2.0 - k * math.ln(2.0) - math.lgamma(k))

func chi2_cdf(x, df):
    if df <= 0:
        raise("ValueError", "chi2_cdf : df > 0 attendu")
    return gammainc(df / 2.0, x / 2.0)

func chi2_sf(x, df):
    if df <= 0:
        raise("ValueError", "chi2_sf : df > 0 attendu")
    return gammaincc(df / 2.0, x / 2.0)

func f_cdf(x, d1, d2):
    if d1 <= 0 or d2 <= 0:
        raise("ValueError", "f_cdf : degrés de liberté > 0 attendus")
    if x <= 0:
        return 0.0
    return betainc(d1 / 2.0, d2 / 2.0, d1 * x / (d1 * x + d2))

func f_sf(x, d1, d2):
    if d1 <= 0 or d2 <= 0:
        raise("ValueError", "f_sf : degrés de liberté > 0 attendus")
    if x <= 0:
        return 1.0
    return betainc(d2 / 2.0, d1 / 2.0, d2 / (d1 * x + d2))

func gamma_pdf(x, a, scale=1.0):
    if a <= 0 or scale <= 0:
        raise("ValueError", "gamma_pdf : a > 0 et scale > 0 attendus")
    if x < 0:
        return 0.0
    z := x / scale
    if z == 0:
        if a < 1:
            return INF
        if a == 1:
            return 1.0 / scale
        return 0.0
    return math.exp((a - 1.0) * math.ln(z) - z - math.lgamma(a)) / scale

func gamma_cdf(x, a, scale=1.0):
    if a <= 0 or scale <= 0:
        raise("ValueError", "gamma_cdf : a > 0 et scale > 0 attendus")
    return gammainc(a, x / scale)

func beta_pdf(x, a, b):
    if a <= 0 or b <= 0:
        raise("ValueError", "beta_pdf : a > 0 et b > 0 attendus")
    if x < 0 or x > 1:
        return 0.0
    if x == 0 or x == 1:
        if (x == 0 and a < 1) or (x == 1 and b < 1):
            return INF
        if (x == 0 and a == 1):
            return b * 1.0
        if (x == 1 and b == 1):
            return a * 1.0
        return 0.0
    return math.exp((a - 1.0) * math.ln(x) + (b - 1.0) * math.ln(1.0 - x) + math.lgamma(a + b) - math.lgamma(a) - math.lgamma(b))

func beta_cdf(x, a, b):
    return betainc(a, b, x)

func expon_pdf(x, scale=1.0):
    if scale <= 0:
        raise("ValueError", "expon_pdf : scale > 0 attendu")
    if x < 0:
        return 0.0
    return math.exp(0.0 - x / scale) / scale

func expon_cdf(x, scale=1.0):
    if scale <= 0:
        raise("ValueError", "expon_cdf : scale > 0 attendu")
    if x <= 0:
        return 0.0
    return 0.0 - math.expm1(0.0 - x / scale)

func expon_sf(x, scale=1.0):
    if x <= 0:
        return 1.0
    return math.exp(0.0 - x / scale)

func expon_ppf(p, scale=1.0):
    if p < 0 or p > 1 or scale <= 0:
        raise("ValueError", "expon_ppf : p dans [0, 1] et scale > 0 attendus")
    if p == 1:
        return INF
    return 0.0 - scale * math.log1p(0.0 - p)

func uniform_pdf(x, lo=0.0, hi=1.0):
    if hi <= lo:
        raise("ValueError", "uniform_pdf : hi > lo attendu")
    if x < lo or x > hi:
        return 0.0
    return 1.0 / (hi - lo)

func uniform_cdf(x, lo=0.0, hi=1.0):
    if hi <= lo:
        raise("ValueError", "uniform_cdf : hi > lo attendu")
    if x <= lo:
        return 0.0
    if x >= hi:
        return 1.0
    return (x - lo) / (hi - lo)

func uniform_ppf(p, lo=0.0, hi=1.0):
    if p < 0 or p > 1 or hi <= lo:
        raise("ValueError", "uniform_ppf : p dans [0, 1] et hi > lo attendus")
    return lo + p * (hi - lo)

# --- Quantiles par recherche (Student, khi-deux, Fisher, gamma, bêta) ---

# kind : 0 Student(a), 1 khi-deux(a), 2 Fisher(a, b), 3 gamma(a), 4 bêta(a, b)
func _cdf_kind(kind, x, a, b):
    if kind == 0:
        return t_cdf(x, a)
    if kind == 1:
        return chi2_cdf(x, a)
    if kind == 2:
        return f_cdf(x, a, b)
    if kind == 3:
        return gammainc(a, x)
    return betainc(a, b, x)

func _pdf_kind(kind, x, a, b):
    if kind == 0:
        return t_pdf(x, a)
    if kind == 1:
        return chi2_pdf(x, a)
    if kind == 2:
        if x <= 0:
            return 0.0
        lg := math.lgamma((a + b) / 2.0) - math.lgamma(a / 2.0) - math.lgamma(b / 2.0)
        return math.exp(lg + (a / 2.0) * math.ln(a / b) + (a / 2.0 - 1.0) * math.ln(x) - ((a + b) / 2.0) * math.ln(1.0 + a * x / b))
    if kind == 3:
        return gamma_pdf(x, a, 1.0)
    return beta_pdf(x, a, b)

# Inverse de la fonction de répartition sur [lo, hi] (hi peut être INF) : encadrement puis Newton sécurisé.
func _ppf_search(kind, p, a, b, lo, hi):
    if p < 0 or p > 1:
        raise("ValueError", "ppf : p doit être dans [0, 1]")
    if p == 0:
        return lo
    if p == 1:
        return hi
    left := lo
    right := hi
    if right == INF:
        right = 1.0
        if left > 0.0 - INF and left > right:
            right = left + 1.0
        while _cdf_kind(kind, right, a, b) < p:
            right = right * 2.0 + 1.0
            if right > (10.0 ** 300):
                break
    if left == 0.0 - INF:
        left = -1.0
        while _cdf_kind(kind, left, a, b) > p:
            left = left * 2.0 - 1.0
            if left < -(10.0 ** 300):
                break
    x := 0.5 * (left + right)
    k := 0
    while k < 300:
        fx := _cdf_kind(kind, x, a, b) - p
        if fx == 0.0:
            return x
        if fx > 0:
            right = x
        else:
            left = x
        dens := _pdf_kind(kind, x, a, b)
        nx := x
        if dens > 0 and dens < INF:
            nx = x - fx / dens
        if nx <= left or nx >= right or nx != nx:
            nx = 0.5 * (left + right)
        if _abs(nx - x) <= 0.0000000000000004 * _abs(nx) or right - left <= 0.0000000000000004 * _abs(nx):
            return nx
        x = nx
        k = k + 1
    return x

func t_ppf(p, df):
    if df <= 0:
        raise("ValueError", "t_ppf : df > 0 attendu")
    if p == 0.5:
        return 0.0
    if p > 0.5:
        return 0.0 - t_ppf(1.0 - p, df)
    return _ppf_search(0, p, df, 0.0, 0.0 - INF, INF)

func chi2_ppf(p, df):
    if df <= 0:
        raise("ValueError", "chi2_ppf : df > 0 attendu")
    return _ppf_search(3, p, df / 2.0, 0.0, 0.0, INF) * 2.0

func f_ppf(p, d1, d2):
    if d1 <= 0 or d2 <= 0:
        raise("ValueError", "f_ppf : degrés de liberté > 0 attendus")
    return _ppf_search(2, p, d1, d2, 0.0, INF)

func gamma_ppf(p, a, scale=1.0):
    if a <= 0 or scale <= 0:
        raise("ValueError", "gamma_ppf : a > 0 et scale > 0 attendus")
    return _ppf_search(3, p, a, 0.0, 0.0, INF) * scale

func beta_ppf(p, a, b):
    if a <= 0 or b <= 0:
        raise("ValueError", "beta_ppf : a > 0 et b > 0 attendus")
    return _ppf_search(4, p, a, b, 0.0, 1.0)

# =====================================================================================================
# Lois discrètes : binomiale, Poisson, géométrique
# =====================================================================================================

func _lchoose(n, k):
    return math.lgamma(n + 1.0) - math.lgamma(k + 1.0) - math.lgamma(n - k + 1.0)

func binom_pmf(k, n, p):
    if n < 0 or p < 0 or p > 1:
        raise("ValueError", "binom_pmf : n >= 0 et p dans [0, 1] attendus")
    if k < 0 or k > n:
        return 0.0
    if p == 0:
        if k == 0:
            return 1.0
        return 0.0
    if p == 1:
        if k == n:
            return 1.0
        return 0.0
    return math.exp(_lchoose(n, k) + k * math.ln(p) + (n - k) * math.log1p(0.0 - p))

func binom_cdf(k, n, p):
    if n < 0 or p < 0 or p > 1:
        raise("ValueError", "binom_cdf : n >= 0 et p dans [0, 1] attendus")
    kk := math.floor(k)
    if kk < 0:
        return 0.0
    if kk >= n:
        return 1.0
    if p == 0:
        return 1.0
    if p == 1:
        return 0.0
    return betainc(n - kk, kk + 1.0, 1.0 - p)

func poisson_pmf(k, lam):
    if lam < 0:
        raise("ValueError", "poisson_pmf : lambda >= 0 attendu")
    if k < 0:
        return 0.0
    if lam == 0:
        if k == 0:
            return 1.0
        return 0.0
    return math.exp(k * math.ln(lam) - lam - math.lgamma(k + 1.0))

func poisson_cdf(k, lam):
    if lam < 0:
        raise("ValueError", "poisson_cdf : lambda >= 0 attendu")
    kk := math.floor(k)
    if kk < 0:
        return 0.0
    if lam == 0:
        return 1.0
    return gammaincc(kk + 1.0, lam)

func geom_pmf(k, p):
    if p <= 0 or p > 1:
        raise("ValueError", "geom_pmf : p dans ]0, 1] attendu")
    if k < 1:
        return 0.0
    return p * (1.0 - p) ** (k - 1)

func geom_cdf(k, p):
    if p <= 0 or p > 1:
        raise("ValueError", "geom_cdf : p dans ]0, 1] attendu")
    kk := math.floor(k)
    if kk < 1:
        return 0.0
    return 1.0 - (1.0 - p) ** kk

# =====================================================================================================
# Tests d'hypothèses
# =====================================================================================================

# Test t de Student pour la moyenne d'un échantillon. Renvoie [t, p bilatérale, df].
func ttest_1samp(x, popmean):
    d := _nonempty(x, "ttest_1samp")
    n := len(d)
    if n < 2:
        raise("ValueError", "ttest_1samp : au moins 2 données")
    se := std(d, 1) / math.sqrt(n)
    if se == 0.0:
        raise("ZeroDivisionError", "ttest_1samp : variance nulle")
    t := (mean(d) - popmean) / se
    df := n - 1
    return [t, betainc(df / 2.0, 0.5, df / (df + t * t)), df]

# Test t pour deux échantillons indépendants (Welch par défaut). Renvoie [t, p bilatérale, df].
func ttest_ind(x, y, equal_var=false):
    a := _nonempty(x, "ttest_ind")
    b := _nonempty(y, "ttest_ind")
    n1 := len(a)
    n2 := len(b)
    if n1 < 2 or n2 < 2:
        raise("ValueError", "ttest_ind : au moins 2 données par échantillon")
    v1 := var(a, 1)
    v2 := var(b, 1)
    d := mean(a) - mean(b)
    t := 0.0
    df := 0.0
    if equal_var:
        df = n1 + n2 - 2.0
        sp2 := ((n1 - 1.0) * v1 + (n2 - 1.0) * v2) / df
        se := math.sqrt(sp2 * (1.0 / n1 + 1.0 / n2))
        if se == 0.0:
            raise("ZeroDivisionError", "ttest_ind : variance nulle")
        t = d / se
    else:
        s1 := v1 / n1
        s2 := v2 / n2
        se := math.sqrt(s1 + s2)
        if se == 0.0:
            raise("ZeroDivisionError", "ttest_ind : variance nulle")
        t = d / se
        df = (s1 + s2) * (s1 + s2) / (s1 * s1 / (n1 - 1.0) + s2 * s2 / (n2 - 1.0))
    return [t, betainc(df / 2.0, 0.5, df / (df + t * t)), df]

# Test t apparié. Renvoie [t, p bilatérale, df].
func ttest_rel(x, y):
    a := _nonempty(x, "ttest_rel")
    b := _nonempty(y, "ttest_rel")
    if len(a) != len(b):
        raise("ValueError", "ttest_rel : échantillons de longueurs différentes")
    diff := []
    i := 0
    while i < len(a):
        append(diff, a[i] - b[i])
        i = i + 1
    return ttest_1samp(diff, 0.0)

# Intervalle de confiance de la moyenne (loi de Student) : [bas, haut].
func mean_confidence_interval(x, confidence=0.95):
    d := _nonempty(x, "mean_confidence_interval")
    if len(d) < 2:
        raise("ValueError", "mean_confidence_interval : au moins 2 données")
    if confidence <= 0 or confidence >= 1:
        raise("ValueError", "mean_confidence_interval : niveau dans ]0, 1[")
    h := t_ppf(0.5 + confidence / 2.0, len(d) - 1) * sem(d)
    m := mean(d)
    return [m - h, m + h]

# Test du khi-deux d'adéquation. f_exp : effectifs attendus (défaut : uniformes). Renvoie [statistique, p].
func chisquare(f_obs, f_exp=null, ddof=0):
    o := _nonempty(f_obs, "chisquare")
    e := []
    if f_exp == null:
        m := _sum(o) / len(o)
        for v in o:
            append(e, m)
    else:
        e = _flat(f_exp, "chisquare")
    if len(e) != len(o):
        raise("ValueError", "chisquare : effectifs observés et attendus de longueurs différentes")
    s := 0.0
    i := 0
    while i < len(o):
        if e[i] <= 0:
            raise("ValueError", "chisquare : effectif attendu <= 0")
        s = s + (o[i] - e[i]) * (o[i] - e[i]) / e[i]
        i = i + 1
    df := len(o) - 1 - ddof
    if df < 1:
        raise("ValueError", "chisquare : degrés de liberté insuffisants")
    return [s, chi2_sf(s, df)]

# Test d'indépendance du khi-deux sur un tableau de contingence (sans correction de Yates).
# Renvoie [statistique, p, df, effectifs attendus].
func chi2_contingency(table):
    t := array.as_array(table)
    if len(t.shape) != 2:
        raise("ValueError", "chi2_contingency : tableau 2-d attendu")
    r := t.shape[0]
    c := t.shape[1]
    rows := array.sum(t, 1)
    cols := array.sum(t, 0)
    tot := array.sum(t)
    exp := array.div(array.outer(rows, cols), tot * 1.0)
    s := 0.0
    i := 0
    while i < r * c:
        e := exp.data[i]
        if e <= 0:
            raise("ValueError", "chi2_contingency : effectif attendu nul")
        s = s + (t.data[i] - e) * (t.data[i] - e) / e
        i = i + 1
    df := (r - 1) * (c - 1)
    return [s, chi2_sf(s, df), df, exp]

# ANOVA à un facteur : groups = liste de séries. Renvoie [F, p].
func f_oneway(groups):
    k := len(groups)
    if k < 2:
        raise("ValueError", "f_oneway : au moins 2 groupes")
    all_n := 0
    all_sum := 0.0
    data := []
    for g in groups:
        d := _nonempty(g, "f_oneway")
        append(data, d)
        all_n = all_n + len(d)
        all_sum = all_sum + _sum(d)
    grand := all_sum / all_n
    ssb := 0.0
    ssw := 0.0
    for d in data:
        m := _sum(d) / len(d)
        ssb = ssb + len(d) * (m - grand) * (m - grand)
        for v in d:
            ssw = ssw + (v - m) * (v - m)
    dfb := k - 1
    dfw := all_n - k
    if dfw < 1:
        raise("ValueError", "f_oneway : pas assez de données")
    if ssw == 0.0:
        raise("ZeroDivisionError", "f_oneway : variance intra-groupes nulle")
    F := (ssb / dfb) / (ssw / dfw)
    return [F, f_sf(F, dfb, dfw)]

# Corrélation de Pearson avec p-value bilatérale. Renvoie [r, p].
func pearsonr(x, y):
    a := _nonempty(x, "pearsonr")
    n := len(a)
    if n < 2:
        raise("ValueError", "pearsonr : au moins 2 données")
    r := corr(a, y)
    if r != r:
        return [r, NAN]
    if r == 1.0 or r == -1.0:
        return [r, 0.0]
    df := n - 2.0
    if df <= 0:
        return [r, 1.0]
    return [r, betainc(df / 2.0, 0.5, df / (df + df * r * r / (1.0 - r * r)))]

# =====================================================================================================
# Régression
# =====================================================================================================

# Régression linéaire simple y = intercept + pente * x.
# Renvoie [pente, ordonnée, r, p-value (pente), erreur-type pente, erreur-type ordonnée].
func linregress(x, y):
    a := _nonempty(x, "linregress")
    b := _nonempty(y, "linregress")
    n := len(a)
    if len(b) != n:
        raise("ValueError", "linregress : x et y de longueurs différentes")
    if n < 2:
        raise("ValueError", "linregress : au moins 2 points")
    ma := _sum(a) / n
    mb := _sum(b) / n
    sxx := []
    sxy := []
    syy := []
    i := 0
    while i < n:
        append(sxx, (a[i] - ma) * (a[i] - ma))
        append(sxy, (a[i] - ma) * (b[i] - mb))
        append(syy, (b[i] - mb) * (b[i] - mb))
        i = i + 1
    Sxx := _sum(sxx)
    Sxy := _sum(sxy)
    Syy := _sum(syy)
    if Sxx == 0.0:
        raise("ValueError", "linregress : toutes les valeurs de x sont identiques")
    slope := Sxy / Sxx
    intercept := mb - slope * ma
    r := 0.0
    if Syy > 0.0:
        r = Sxy / math.sqrt(Sxx * Syy)
        if r > 1.0:
            r = 1.0
        if r < -1.0:
            r = -1.0
    p := 0.0
    se := 0.0
    se_int := 0.0
    if n > 2:
        df := n - 2.0
        tiny := (10.0 ** -20)
        t := r * math.sqrt(df / ((1.0 - r + tiny) * (1.0 + r + tiny)))
        p = betainc(df / 2.0, 0.5, df / (df + t * t))
        se = math.sqrt((1.0 - r * r) * Syy / Sxx / df)
        se_int = se * math.sqrt(Sxx / n + ma * ma)
    return [slope, intercept, r, p, se, se_int]

# Moindres carrés ordinaires multiples avec ordonnée à l'origine. X : matrice n x p (observations en lignes),
# y : vecteur n. Renvoie [coefficients (intercept en premier), R^2].
func ols(X, y):
    xm := array.as_array(X)
    if len(xm.shape) == 1:
        xm = array.expand_dims(xm, 1)
    if len(xm.shape) != 2:
        raise("ValueError", "ols : matrice 2-d attendue")
    yv := array.as_array(y)
    n := xm.shape[0]
    if len(yv.shape) != 1 or yv.shape[0] != n:
        raise("ValueError", "ols : y doit être un vecteur de longueur n")
    design := array.concatenate([array.ones([n, 1]), xm], 1)
    sol := linalg.lstsq(design, yv)
    beta := sol[0]
    ssr := sol[1]
    ym := mean(yv)
    tot := []
    for v in yv.data:
        append(tot, (v - ym) * (v - ym))
    sst := _sum(tot)
    r2 := 1.0
    if sst > 0.0:
        r2 = 1.0 - ssr / sst
    return [beta, r2]
