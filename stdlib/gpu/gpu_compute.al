# ALEX STANDARD LIBRARY — gpu.gpu_compute
#
# Calcul data-parallèle « façon GPU » : un NOYAU (kernel) est appliqué à une grille d'indices découpée en
# groupes de travail ; le ComputeDevice exécute les groupes en série ou EN PARALLÈLE sur les cœurs du
# processeur (thread.thread_pool). Le même code tournera sur un vrai GPU quand un dorsal (Vulkan / OpenCL)
# sera branché : l'API ne change pas.
#
# Un noyau est une fonction de PREMIER NIVEAU d'un module : kernel(début, fin, arg1, arg2...) qui renvoie la
# list des résultats des indices [début, fin). Ses arguments sont copiés vers les fils.
#
#   use gpu.gpu_compute as gc
#   func carre(debut, fin, xs):                        # premier niveau
#       return [xs[i] * xs[i] for i in debut..fin]
#   if thread.is_main():
#       dev := gc.ComputeDevice("threads", 4)
#       r := dev.dispatch(carre, 1000, [donnees], 256)  # 1000 éléments, groupes de 256
#       y := dev.saxpy(2.0, x, y0)                       # noyaux fournis : saxpy, add, scale, dot, sum,
#       c := dev.matmul(a, b, n, m, p)                   # matmul, convolve2d, map_lut, histogram
#       dev.shutdown()
#
# Dorsaux : "serial" (un seul fil, toujours disponible), "threads" (ThreadPool).

from core use len, to_int, to_float
from collections use append
use thread.thread_pool as tp
use os

# ---------------------------------------------------------------- noyaux fournis (premier niveau)
func k_saxpy(start, stop, a, x, y):
    return [a * x[i] + y[i] for i in start..stop]

func k_add(start, stop, x, y):
    return [x[i] + y[i] for i in start..stop]

func k_mul(start, stop, x, y):
    return [x[i] * y[i] for i in start..stop]

func k_scale(start, stop, a, x):
    return [a * x[i] for i in start..stop]

# Somme partielle : une valeur par groupe.
func k_sum(start, stop, x):
    s := 0.0
    i := start
    while i < stop:
        s += x[i]
        i += 1
    return [s]

func k_dot(start, stop, x, y):
    s := 0.0
    i := start
    while i < stop:
        s += x[i] * y[i]
        i += 1
    return [s]

# Lignes [start, stop) de C = A (n x m) · B (m x p), matrices aplaties ligne par ligne.
func k_matmul(start, stop, a, b, m, p):
    out := []
    r := start
    while r < stop:
        c := 0
        while c < p:
            s := 0.0
            k := 0
            while k < m:
                s += a[r * m + k] * b[k * p + c]
                k += 1
            append(out, s)
            c += 1
        r += 1
    return out

# Lignes [start, stop) de la convolution 2D (bords à zéro) d'une image w x h par un noyau kw x kh.
func k_convolve(start, stop, img, w, h, kern, kw, kh):
    out := []
    ox := kw // 2
    oy := kh // 2
    y := start
    while y < stop:
        x := 0
        while x < w:
            s := 0.0
            j := 0
            while j < kh:
                yy := y + j - oy
                if yy >= 0 and yy < h:
                    i := 0
                    while i < kw:
                        xx := x + i - ox
                        if xx >= 0 and xx < w:
                            s += img[yy * w + xx] * kern[j * kw + i]
                        i += 1
                j += 1
            append(out, s)
            x += 1
        y += 1
    return out

func k_lut(start, stop, x, table):
    return [table[x[i]] for i in start..stop]

# Histogramme partiel (bins classes de valeurs entières 0..bins-1) : bins valeurs par groupe.
func k_histogram(start, stop, x, bins):
    h := [0 for i in 0..bins]
    i := start
    while i < stop:
        v := x[i]
        if v >= 0 and v < bins:
            h[v] = h[v] + 1
        i += 1
    return h

# ---------------------------------------------------------------- périphérique de calcul
class ComputeDevice:
    func init(backend="threads", workers=null):
        if backend != "serial" and backend != "threads":
            raise("ArgumentError", "ComputeDevice : dorsal 'serial' ou 'threads'")
        self.backend = backend
        self.workers = workers if workers != null else os.cpu_count()
        self.pool = null
        if backend == "threads":
            self.pool = tp.ThreadPool(self.workers, "gpu")
        self.dispatches = 0
        self.groups = 0

    func name():
        if self.backend == "serial":
            return "processeur (série)"
        return "processeur (" + str(self.workers) + " fils)"

    # Exécute kernel sur [0, n) par groupes de group indices ; renvoie la concaténation des résultats dans
    # l'ordre des groupes.
    func dispatch(kernel, n, args, group=null):
        g := group
        if g == null:
            g = (n + self.workers * 4 - 1) // (self.workers * 4)
            if g < 64:
                g = 64
        ranges := []
        s := 0
        while s < n:
            e := s + g
            if e > n:
                e = n
            append(ranges, [s, e])
            s = e
        self.dispatches += 1
        self.groups += len(ranges)
        parts := []
        if self.backend == "serial" or len(ranges) == 1:
            for r in ranges:
                append(parts, _call(kernel, r[0], r[1], args))
        else:
            arg_lists := []
            for r in ranges:
                a := [r[0], r[1]]
                for x in args:
                    append(a, x)
                append(arg_lists, a)
            parts = self.pool.starmap(kernel, arg_lists)
        out := []
        for p in parts:
            for v in p:
                append(out, v)
        return out

    func saxpy(a, x, y):
        return self.dispatch(k_saxpy, len(x), [a, x, y])

    func add(x, y):
        return self.dispatch(k_add, len(x), [x, y])

    func mul(x, y):
        return self.dispatch(k_mul, len(x), [x, y])

    func scale(a, x):
        return self.dispatch(k_scale, len(x), [a, x])

    func sum(x):
        s := 0.0
        for p in self.dispatch(k_sum, len(x), [x]):
            s += p
        return s

    func dot(x, y):
        s := 0.0
        for p in self.dispatch(k_dot, len(x), [x, y]):
            s += p
        return s

    # C = A · B ; a : n x m, b : m x p (listes aplaties) ; renvoie n x p aplatie.
    func matmul(a, b, n, m, p):
        rows := n // (self.workers * 2)
        if rows < 1:
            rows = 1
        return self.dispatch(k_matmul, n, [a, b, m, p], rows)

    func convolve2d(img, w, h, kern, kw, kh):
        rows := h // (self.workers * 2)
        if rows < 1:
            rows = 1
        return self.dispatch(k_convolve, h, [img, w, h, kern, kw, kh], rows)

    func map_lut(x, table):
        return self.dispatch(k_lut, len(x), [x, table])

    func histogram(x, bins):
        parts := self.dispatch(k_histogram, len(x), [x, bins])
        h := [0 for i in 0..bins]
        i := 0
        while i < len(parts):
            h[i % bins] = h[i % bins] + parts[i]
            i += 1
        return h

    func shutdown():
        if self.pool != null:
            self.pool.shutdown()
            self.pool = null

    func describe():
        return self.name() + " : " + str(self.dispatches) + " lancements, " + str(self.groups) + " groupes"

func _call(kernel, s, e, args):
    n := len(args)
    if n == 0:
        return kernel(s, e)
    if n == 1:
        return kernel(s, e, args[0])
    if n == 2:
        return kernel(s, e, args[0], args[1])
    if n == 3:
        return kernel(s, e, args[0], args[1], args[2])
    if n == 4:
        return kernel(s, e, args[0], args[1], args[2], args[3])
    if n == 5:
        return kernel(s, e, args[0], args[1], args[2], args[3], args[4])
    if n == 6:
        return kernel(s, e, args[0], args[1], args[2], args[3], args[4], args[5])
    raise("ArgumentError", "gpu : 6 arguments de noyau au plus")
