use math
from core use len, is_int
from collections use append

# ALEX STANDARD LIBRARY - random
# Génération pseudo-aléatoire et simulations Monte-Carlo. Pure ALEX, aucune dépendance native.
#
#   use random
#   random.seed(42)
#   x := random.random()               # flottant dans [0, 1)
#   n := random.randint(1, 6)          # entier dans [1, 6] (bornes incluses)
#   g := random.new(7)                 # générateur indépendant, reproductible
#   y := random.normal(sigma=2.0, g=g) # arguments nommés acceptés ; sans g= : générateur global
#
# Le générateur est TOUJOURS le dernier paramètre de chaque tirage.
#
# ALGORITHMES
#   - Générateur : xoshiro128** (Blackman & Vigna, 2018), état de 128 bits, période 2^128 - 1.
#     Toute l'arithmétique reste sur 32 bits (masque 0xFFFFFFFF) : aucun dépassement d'entier 64 bits,
#     résultats identiques sur toutes les plateformes. Séquence validée contre l'implémentation de référence.
#   - Initialisation : finaliseur murmur3 (fmix32) appliqué à une suite de Weyl ; les 4 mots d'état ne sont
#     jamais tous nuls.
#   - Flottants : 53 bits d'aléa (comme Python), jamais égal à 1.0.
#   - Entiers bornés : rejet par masque de bits, SANS biais modulo.
#   - Normale : méthode polaire de Marsaglia ; Gamma : Marsaglia-Tsang ; Poisson : Knuth puis PTRS (Hörmann) ;
#     Binomiale : scission récursive par loi Beta (exacte, O(log n)).
#
# REPRODUCTIBILITÉ : pour une même graine, la même suite est produite, y compris entre versions du langage.
# Un générateur est une liste [s0, s1, s2, s3, normale_en_cache] ; ne la modifiez pas à la main.
#
# CE MODULE N'EST PAS CRYPTOGRAPHIQUE : ne l'utilisez pas pour générer des secrets.

const _M32 := 4294967295

# --- Arithmétique 32 bits ---

# (a * b) mod 2^32 pour a, b dans [0, 2^32) ; découpé en 16 bits : aucun produit ne dépasse 2^48.
func _mul32(a, b):
    lo := a * (b & 65535)
    hi := (a * (b >> 16)) & 65535
    return (lo + (hi << 16)) & _M32

func _rotl(x, k):
    return ((x << k) | (x >> (32 - k))) & _M32

# Finaliseur murmur3 sur une suite de Weyl : produit des mots d'état de bonne qualité à partir d'une graine.
# state est une liste à un élément (le compteur de Weyl).
func _splitmix32(state):
    state[0] = (state[0] + 2654435769) & _M32
    z := state[0]
    z = _mul32(z ^ (z >> 16), 2246822507)
    z = _mul32(z ^ (z >> 13), 3266489909)
    return (z ^ (z >> 16)) & _M32

# --- Création et état ---

# Crée un générateur à partir d'une graine entière (de signe quelconque, jusqu'à 64 bits).
func new(seed_value):
    if not is_int(seed_value):
        raise("TypeError", "random.new : la graine doit être un entier")
    low := seed_value & _M32
    high := (seed_value >> 32) & _M32
    weyl := [(low ^ _mul32(high, 2654435769)) & _M32]
    g := [0, 0, 0, 0, null]
    i := 0
    while i < 4:
        g[i] = _splitmix32(weyl)
        i += 1
    if g[0] == 0 and g[1] == 0 and g[2] == 0 and g[3] == 0:
        g[0] = 1
    return g

_DEFAULT := new(20240229)

# Renvoie g, ou le générateur global si g est null.
func _gen(g):
    if g == null:
        return _DEFAULT
    return g

# Réinitialise le générateur global (ou le générateur g donné) avec une graine.
func seed(seed_value, g=null):
    fresh := new(seed_value)
    target := _gen(g)
    i := 0
    while i < 5:
        target[i] = fresh[i]
        i += 1

# Copie indépendante d'un générateur (même état : produira la même suite).
func copy(g=null):
    src := _gen(g)
    return [src[0], src[1], src[2], src[3], src[4]]

# --- Tirages de base ---

# Entier non signé de 32 bits uniforme sur [0, 2^32).
func next_u32(g=null):
    s := g
    if g == null:
        s = _DEFAULT
    s0 := s[0]
    s1 := s[1]
    s2 := s[2]
    s3 := s[3]
    # result = rotl(s1 * 5, 7) * 9 ; tout est inliné (aucun appel de fonction) : s1 * 5 et r * 9 < 2^36.
    r := (s1 * 5) & _M32
    r = (((r << 7) | (r >> 25)) & _M32) * 9 & _M32
    t := (s1 << 9) & _M32
    s2 = s2 ^ s0
    s3 = s3 ^ s1
    s1 = s1 ^ s2
    s0 = s0 ^ s3
    s2 = s2 ^ t
    s3 = ((s3 << 11) | (s3 >> 21)) & _M32
    s[0] = s0
    s[1] = s1
    s[2] = s2
    s[3] = s3
    return r

# Avance l'état de 2^64 tirages (jump de xoshiro128). Sert à fabriquer des flux non recouvrants.
func jump(g=null):
    s := _gen(g)
    masks := [2271477771, 4114797267, 1872770499, 2012404571]
    # Constantes de jump officielles : 0x8764000b, 0xf542d2d3, 0x6fa035c3, 0x77f2db5b
    s0 := 0
    s1 := 0
    s2 := 0
    s3 := 0
    w := 0
    while w < 4:
        b := 0
        while b < 32:
            if (masks[w] >> b) & 1 == 1:
                s0 = s0 ^ s[0]
                s1 = s1 ^ s[1]
                s2 = s2 ^ s[2]
                s3 = s3 ^ s[3]
            next_u32(s)
            b += 1
        w += 1
    s[0] = s0
    s[1] = s1
    s[2] = s2
    s[3] = s3
    s[4] = null

# Crée un nouveau générateur indépendant du générateur donné : il reprend l'état courant puis ce dernier
# saute de 2^64 tirages, de sorte que les deux flux ne se recouvrent jamais.
func spawn(g=null):
    child := copy(g)
    jump(g)
    return child

# Flottant uniforme sur [0, 1), 53 bits d'aléa.
func random(g=null):
    s := g
    if g == null:
        s = _DEFAULT
    a := next_u32(s) >> 5
    b := next_u32(s) >> 6
    return (a * 67108864.0 + b) / 9007199254740992.0

# Entier aléatoire de k bits, 0 <= k <= 62.
func getrandbits(k, g=null):
    if k < 0 or k > 62:
        raise("ValueError", "getrandbits : k doit être dans [0, 62]")
    if k == 0:
        return 0
    s := _gen(g)
    if k <= 32:
        return next_u32(s) >> (32 - k)
    hi := next_u32(s) >> (64 - k)
    lo := next_u32(s)
    return (hi << 32) | lo

# Entier uniforme sur [0, n) sans biais (n >= 1, n <= 2^62).
func randbelow(n, g=null):
    if n < 1:
        raise("ValueError", "randbelow : n doit être >= 1")
    if n == 1:
        return 0
    s := _gen(g)
    k := 0
    m := n - 1
    while m > 0:
        k += 1
        m = m >> 1
    r := getrandbits(k, s)
    while r >= n:
        r = getrandbits(k, s)
    return r

# Entier uniforme sur [a, b], bornes incluses.
func randint(a, b, g=null):
    if b < a:
        raise("ValueError", "randint : b doit être >= a")
    return a + randbelow(b - a + 1, g)

# Entier uniforme sur range(start, stop, step), comme en Python.
func randrange(start, stop, step=1, g=null):
    if step == 0:
        raise("ValueError", "randrange : step ne peut pas être nul")
    n := 0
    if step > 0:
        n = (stop - start + step - 1) // step
    else:
        n = (start - stop - step - 1) // (0 - step)
    if n <= 0:
        raise("ValueError", "randrange : intervalle vide")
    return start + step * randbelow(n, g)

# Booléen : true avec la probabilité p.
func bernoulli(p=0.5, g=null):
    if p < 0.0 or p > 1.0:
        raise("ValueError", "bernoulli : p doit être dans [0, 1]")
    return random(g) < p

# --- Distributions continues ---

# Uniforme sur [a, b).
func uniform(a=0.0, b=1.0, g=null):
    return a + (b - a) * random(g)

# Loi normale (Marsaglia polaire, deux valeurs par tour dont une mise en cache dans le générateur).
func normal(mu=0.0, sigma=1.0, g=null):
    if sigma < 0.0:
        raise("ValueError", "normal : sigma doit être >= 0")
    s := _gen(g)
    if s[4] != null:
        z := s[4]
        s[4] = null
        return mu + sigma * z
    u := 0.0
    v := 0.0
    q := 0.0
    ok := false
    while not ok:
        u = 2.0 * random(s) - 1.0
        v = 2.0 * random(s) - 1.0
        q = u * u + v * v
        if q < 1.0 and q > 0.0:
            ok = true
    f := math.sqrt(0.0 - 2.0 * math.ln(q) / q)
    s[4] = v * f
    return mu + sigma * u * f

func lognormal(mu=0.0, sigma=1.0, g=null):
    return math.exp(normal(mu, sigma, g))

# Loi exponentielle de taux lam (moyenne 1/lam).
func exponential(lam=1.0, g=null):
    if lam <= 0.0:
        raise("ValueError", "exponential : lam doit être > 0")
    return (0.0 - math.ln(1.0 - random(g))) / lam

# Loi gamma de forme alpha > 0 et d'échelle theta (Marsaglia-Tsang, 2000).
func gamma(alpha, theta=1.0, g=null):
    if alpha <= 0.0 or theta <= 0.0:
        raise("ValueError", "gamma : alpha et theta doivent être > 0")
    s := _gen(g)
    if alpha < 1.0:
        u := random(s)
        while u == 0.0:
            u = random(s)
        return gamma(alpha + 1.0, theta, s) * u ** (1.0 / alpha)
    d := alpha - 1.0 / 3.0
    c := 1.0 / math.sqrt(9.0 * d)
    while true:
        x := normal(0.0, 1.0, s)
        v := 1.0 + c * x
        if v > 0.0:
            v = v * v * v
            u := random(s)
            if u < 1.0 - 0.0331 * x * x * x * x:
                return d * v * theta
            if u > 0.0 and math.ln(u) < 0.5 * x * x + d * (1.0 - v + math.ln(v)):
                return d * v * theta

# Loi bêta(alpha, beta) sur [0, 1].
func beta(alpha, beta_, g=null):
    if alpha <= 0.0 or beta_ <= 0.0:
        raise("ValueError", "beta : alpha et beta doivent être > 0")
    s := _gen(g)
    x := gamma(alpha, 1.0, s)
    y := gamma(beta_, 1.0, s)
    return x / (x + y)

# Loi du khi-deux à k degrés de liberté.
func chi_square(k, g=null):
    return gamma(k / 2.0, 2.0, g)

# Loi de Student à nu degrés de liberté.
func student_t(nu, g=null):
    s := _gen(g)
    z := normal(0.0, 1.0, s)
    return z / math.sqrt(chi_square(nu, s) / nu)

# Loi de Laplace (exponentielle double) de position mu et d'échelle b.
func laplace(mu=0.0, b=1.0, g=null):
    u := random(g) - 0.5
    sgn := 1.0
    if u < 0.0:
        sgn = -1.0
    return mu - b * sgn * math.ln(1.0 - 2.0 * math.abs(u))

# Loi de Weibull de forme k et d'échelle lam.
func weibull(k, lam=1.0, g=null):
    return lam * (0.0 - math.ln(1.0 - random(g))) ** (1.0 / k)

# --- Distributions discrètes ---

# Loi géométrique : nombre d'échecs avant le premier succès (support 0, 1, 2, ...), succès de probabilité p.
func geometric(p, g=null):
    if p <= 0.0 or p > 1.0:
        raise("ValueError", "geometric : p doit être dans ]0, 1]")
    if p == 1.0:
        return 0
    u := 1.0 - random(g)
    return math.floor(math.ln(u) / math.ln(1.0 - p))

# Loi de Poisson de moyenne lam >= 0.
func poisson(lam, g=null):
    if lam < 0.0:
        raise("ValueError", "poisson : lam doit être >= 0")
    if lam == 0.0:
        return 0
    s := _gen(g)
    if lam < 30.0:
        limit := math.exp(0.0 - lam)
        k := 0
        prod := random(s)
        while prod > limit:
            k += 1
            prod = prod * random(s)
        return k
    # PTRS : rejet avec transformation (Hörmann, 1993), valable pour lam >= 10.
    slam := math.sqrt(lam)
    loglam := math.ln(lam)
    b := 0.931 + 2.53 * slam
    a := -0.059 + 0.02483 * b
    invalpha := 1.1239 + 1.1328 / (b - 3.4)
    vr := 0.9277 - 3.6224 / (b - 2.0)
    while true:
        u := random(s) - 0.5
        v := 1.0 - random(s)
        us := 0.5 - math.abs(u)
        k := math.floor((2.0 * a / us + b) * u + lam + 0.43)
        if us >= 0.07 and v <= vr:
            return k
        if k >= 0 and not (us < 0.013 and v > us):
            if math.ln(v) + math.ln(invalpha) - math.ln(a / (us * us) + b) <= (0.0 - lam) + k * loglam - math.lgamma(k + 1.0):
                return k

# Loi binomiale B(n, p) : scission récursive par loi bêta (Knuth, TAOCP 3.4.1), exacte.
func binomial(n, p, g=null):
    if n < 0:
        raise("ValueError", "binomial : n doit être >= 0")
    if p < 0.0 or p > 1.0:
        raise("ValueError", "binomial : p doit être dans [0, 1]")
    s := _gen(g)
    k := 0
    m := n
    q := p
    while m > 10:
        a := 1 + m // 2
        b := 1 + m - a
        x := beta(a * 1.0, b * 1.0, s)
        if x >= q:
            m = a - 1
            q = q / x
        else:
            k = k + a
            m = b - 1
            q = (q - x) / (1.0 - x)
    i := 0
    while i < m:
        if random(s) < q:
            k += 1
        i += 1
    return k

# --- Séquences ---

# Élément uniformément choisi dans une liste non vide.
func choice(items, g=null):
    if len(items) == 0:
        raise("IndexError", "choice : séquence vide")
    return items[randbelow(len(items), g)]

# Mélange une liste EN PLACE (Fisher-Yates) et la renvoie.
func shuffle(items, g=null):
    s := _gen(g)
    i := len(items) - 1
    while i > 0:
        j := randbelow(i + 1, s)
        tmp := items[i]
        items[i] = items[j]
        items[j] = tmp
        i -= 1
    return items

# Permutation aléatoire de 0 .. n-1.
func permutation(n, g=null):
    items := []
    i := 0
    while i < n:
        append(items, i)
        i += 1
    return shuffle(items, g)

# k éléments distincts tirés SANS remise (la liste d'origine n'est pas modifiée).
func sample(items, k, g=null):
    n := len(items)
    if k < 0 or k > n:
        raise("ValueError", "sample : k doit être dans [0, len(items)]")
    pool := []
    for x in items:
        append(pool, x)
    s := _gen(g)
    out := []
    i := 0
    while i < k:
        j := i + randbelow(n - i, s)
        tmp := pool[i]
        pool[i] = pool[j]
        pool[j] = tmp
        append(out, pool[i])
        i += 1
    return out

# k éléments tirés AVEC remise.
func choices(items, k, g=null):
    s := _gen(g)
    out := []
    i := 0
    while i < k:
        append(out, choice(items, s))
        i += 1
    return out

# Élément choisi selon des poids positifs (pas nécessairement normalisés).
func weighted_choice(items, weights, g=null):
    if len(items) != len(weights) or len(items) == 0:
        raise("ValueError", "weighted_choice : listes de même longueur non vide requises")
    total := 0.0
    for w in weights:
        if w < 0.0:
            raise("ValueError", "weighted_choice : poids négatif")
        total = total + w
    if total <= 0.0:
        raise("ValueError", "weighted_choice : somme des poids nulle")
    r := random(g) * total
    acc := 0.0
    i := 0
    while i < len(items):
        acc = acc + weights[i]
        if r < acc:
            return items[i]
        i += 1
    return items[len(items) - 1]

# --- Monte-Carlo ---

# Estime E[f(g)] : appelle f(g) n fois ; f reçoit le générateur. Renvoie [moyenne, erreur-type].
func monte_carlo(f, n, g=null):
    if n < 2:
        raise("ValueError", "monte_carlo : n doit être >= 2")
    s := _gen(g)
    mean := 0.0
    m2 := 0.0
    i := 1
    while i <= n:
        x := f(s)
        delta := x - mean
        mean = mean + delta / i
        m2 = m2 + delta * (x - mean)
        i += 1
    return [mean, math.sqrt(m2 / (n - 1) / n)]

# Intégrale de f sur [a, b] par Monte-Carlo : renvoie [estimation, erreur-type].
func integrate(f, a, b, n, g=null):
    if n < 2:
        raise("ValueError", "integrate : n doit être >= 2")
    s := _gen(g)
    width := b - a
    mean := 0.0
    m2 := 0.0
    i := 1
    while i <= n:
        x := f(a + width * random(s)) * width
        delta := x - mean
        mean = mean + delta / i
        m2 = m2 + delta * (x - mean)
        i += 1
    return [mean, math.sqrt(m2 / (n - 1) / n)]

# Estimation de pi par la méthode du quart de disque : renvoie [estimation, erreur-type].
func estimate_pi(n, g=null):
    s := _gen(g)
    inside := 0
    i := 0
    while i < n:
        x := random(s)
        y := random(s)
        if x * x + y * y < 1.0:
            inside += 1
        i += 1
    p := inside * 1.0 / n
    return [4.0 * p, 4.0 * math.sqrt(p * (1.0 - p) / n)]
