# ALEX STANDARD LIBRARY — graphics.pipeline
#
# Pipeline graphique logiciel (comme celui d'une carte, en Alex) :
#   1. nuanceur de sommets (graphics.shader) pour chaque sommet ;
#   2. assemblage : triangles (listes, ou indexés), lignes, points ;
#   3. découpage par le plan proche (w > 0), division perspective, transformation vers la fenêtre ;
#   4. élimination des faces arrière (sens trigonométrique = face avant) ;
#   5. rastérisation par fonctions d'arêtes au centre des points, interpolation des varyings CORRIGÉE en
#      perspective ;
#   6. test et écriture de profondeur, nuanceur de fragments, mélange (aucun, alpha, additif).
#
#   p := Pipeline(sh.vertex_color())
#   p.cull = "back"
#   p.blend = "alpha"
#   stats := p.draw(surface, vb, null, uniforms)      # dict triangles, fragments, rejected, culled
#
# Les statistiques du dernier dessin sont dans p.stats.

from core use len, to_int, to_float, type
from collections use append
use graphics.surface as gs
use graphics.buffer as gb

const NEAR_EPS := 0.00001

class Pipeline:
    func init(shader, topology="triangles"):
        self.shader = shader
        self.topology = topology          # "triangles", "lines", "points"
        self.cull = "back"                # "back", "front", "none"
        self.depth_test = true
        self.depth_write = true
        self.blend = "none"               # "none", "alpha", "additive"
        self.point_size = 1
        self.stats = {}

    # Dessine dans surface les sommets de vb (indices de ib si donné) avec les uniforms (UniformBuffer).
    # viewport : [x, y, largeur, hauteur] (null : toute la surface).
    func draw(surface, vb, ib=null, uniforms=null, viewport=null):
        u := uniforms if uniforms != null else gb.UniformBuffer()
        vp := viewport if viewport != null else [0, 0, surface.width, surface.height]
        self.stats = {"vertices": 0, "primitives": 0, "culled": 0, "clipped": 0, "fragments": 0, "rejected": 0, "depth_failed": 0}
        # 1. sommets
        outs := []
        n := vb.count()
        i := 0
        vs := self.shader.vertex
        while i < n:
            o := vs(vb.vertex(i), u)
            append(outs, [o[0], _flat(o[1])])
            i += 1
        self.stats["vertices"] = n
        order := ib.indices if ib != null else [k for k in 0..n]
        # 2. assemblage
        if self.topology == "triangles":
            k := 0
            while k + 2 < len(order):
                self._triangle(surface, outs[order[k]], outs[order[k + 1]], outs[order[k + 2]], u, vp)
                k += 3
        elif self.topology == "lines":
            k := 0
            while k + 1 < len(order):
                self._line(surface, outs[order[k]], outs[order[k + 1]], u, vp)
                k += 2
        else:
            for k in order:
                self._point(surface, outs[k], u, vp)
        return self.stats

    # ---- triangles
    func _triangle(surface, a, b, c, u, vp):
        self.stats["primitives"] = self.stats["primitives"] + 1
        poly := _clip_near([a, b, c])
        if len(poly) < 3:
            self.stats["clipped"] = self.stats["clipped"] + 1
            return
        k := 1
        while k + 1 < len(poly):
            self._raster(surface, _to_screen(poly[0], vp), _to_screen(poly[k], vp), _to_screen(poly[k + 1], vp), u)
            k += 1

    func _raster(surface, p0, p1, p2, u):
        # p = [x, y, z, 1/w, varyings/w]
        area := (p1[0] - p0[0]) * (p2[1] - p0[1]) - (p1[1] - p0[1]) * (p2[0] - p0[0])
        if area == 0.0:
            return
        # écran : y vers le bas, donc le sens trigonométrique de la scène donne une aire négative
        front := area < 0.0
        if (self.cull == "back" and not front) or (self.cull == "front" and front):
            self.stats["culled"] = self.stats["culled"] + 1
            return
        minx := to_int(_min3(p0[0], p1[0], p2[0]))
        maxx := to_int(_max3(p0[0], p1[0], p2[0])) + 1
        miny := to_int(_min3(p0[1], p1[1], p2[1]))
        maxy := to_int(_max3(p0[1], p1[1], p2[1])) + 1
        if minx < 0:
            minx = 0
        if miny < 0:
            miny = 0
        if maxx > surface.width:
            maxx = surface.width
        if maxy > surface.height:
            maxy = surface.height
        nv := len(p0[4])
        fs := self.shader.fragment
        y := miny
        while y < maxy:
            py := y + 0.5
            x := minx
            while x < maxx:
                px := x + 0.5
                w0 := (p2[0] - p1[0]) * (py - p1[1]) - (p2[1] - p1[1]) * (px - p1[0])
                w1 := (p0[0] - p2[0]) * (py - p2[1]) - (p0[1] - p2[1]) * (px - p2[0])
                w2 := (p1[0] - p0[0]) * (py - p0[1]) - (p1[1] - p0[1]) * (px - p0[0])
                inside := (w0 >= 0.0 and w1 >= 0.0 and w2 >= 0.0) or (w0 <= 0.0 and w1 <= 0.0 and w2 <= 0.0)
                if inside:
                    b0 := w0 / area
                    b1 := w1 / area
                    b2 := w2 / area
                    z := b0 * p0[2] + b1 * p1[2] + b2 * p2[2]
                    self._fragment(surface, x, y, z, b0, b1, b2, p0, p1, p2, nv, fs, u)
                x += 1
            y += 1

    func _fragment(surface, x, y, z, b0, b1, b2, p0, p1, p2, nv, fs, u):
        idx := y * surface.width + x
        if self.depth_test and surface.has_depth:
            if z > surface.depth[idx] or z < 0.0 or z > 1.0:
                self.stats["depth_failed"] = self.stats["depth_failed"] + 1
                return
        iw := b0 * p0[3] + b1 * p1[3] + b2 * p2[3]
        vary := []
        k := 0
        while k < nv:
            append(vary, (b0 * p0[4][k] + b1 * p1[4][k] + b2 * p2[4][k]) / iw)
            k += 1
        col := fs(vary, u)
        if col == null:
            self.stats["rejected"] = self.stats["rejected"] + 1
            return
        self._write(surface, idx, z, col)

    func _write(surface, idx, z, col):
        c := gs.rgba(col[0], col[1], col[2], col[3] if len(col) > 3 else 1.0)
        if self.blend == "alpha":
            c = gs.blend_over(surface.color[idx], c)
        elif self.blend == "additive":
            c = gs.blend_add(surface.color[idx], c)
        surface.color[idx] = c
        if self.depth_write and surface.has_depth:
            surface.depth[idx] = z
        self.stats["fragments"] = self.stats["fragments"] + 1

    # ---- lignes et points
    func _line(surface, a, b, u, vp):
        self.stats["primitives"] = self.stats["primitives"] + 1
        if a[0][3] <= NEAR_EPS or b[0][3] <= NEAR_EPS:
            self.stats["clipped"] = self.stats["clipped"] + 1
            return
        p := _to_screen(a, vp)
        q := _to_screen(b, vp)
        dx := q[0] - p[0]
        dy := q[1] - p[1]
        steps := to_int(_max3(_abs(dx), _abs(dy), 1.0))
        nv := len(p[4])
        fs := self.shader.fragment
        s := 0
        while s <= steps:
            t := 1.0 * s / steps
            x := to_int(p[0] + dx * t)
            y := to_int(p[1] + dy * t)
            if x >= 0 and y >= 0 and x < surface.width and y < surface.height:
                self._fragment(surface, x, y, p[2] + (q[2] - p[2]) * t, 1.0 - t, t, 0.0, p, q, q, nv, fs, u)
            s += 1

    func _point(surface, a, u, vp):
        self.stats["primitives"] = self.stats["primitives"] + 1
        if a[0][3] <= NEAR_EPS:
            return
        p := _to_screen(a, vp)
        half := self.point_size // 2
        fs := self.shader.fragment
        nv := len(p[4])
        y := to_int(p[1]) - half
        while y <= to_int(p[1]) + half:
            x := to_int(p[0]) - half
            while x <= to_int(p[0]) + half:
                if x >= 0 and y >= 0 and x < surface.width and y < surface.height:
                    self._fragment(surface, x, y, p[2], 1.0, 0.0, 0.0, p, p, p, nv, fs, u)
                x += 1
            y += 1

func _flat(v):
    out := []
    for x in v:
        if type_is_list(x):
            for y in x:
                append(out, to_float(y))
        else:
            append(out, to_float(x))
    return out

func type_is_list(x):
    return type(x) == "list"

func _abs(x):
    return -x if x < 0 else x

func _min3(a, b, c):
    m := a
    if b < m:
        m = b
    if c < m:
        m = c
    return m

func _max3(a, b, c):
    m := a
    if b > m:
        m = b
    if c > m:
        m = c
    return m

# Sommet découpé [position4, varyings] -> [x écran, y écran, z 0..1, 1/w, varyings/w].
func _to_screen(v, vp):
    p := v[0]
    iw := 1.0 / p[3]
    nx := p[0] * iw
    ny := p[1] * iw
    nz := p[2] * iw
    sx := vp[0] + (nx * 0.5 + 0.5) * vp[2]
    sy := vp[1] + (1.0 - (ny * 0.5 + 0.5)) * vp[3]
    return [sx, sy, nz * 0.5 + 0.5, iw, [x * iw for x in v[1]]]

# Découpe d'un polygone par le plan proche z >= -w (Sutherland-Hodgman, interpolation des varyings).
func _clip_near(poly):
    out := []
    n := len(poly)
    i := 0
    while i < n:
        a := poly[i]
        b := poly[(i + 1) % n]
        da := a[0][2] + a[0][3]
        db := b[0][2] + b[0][3]
        if da >= 0.0:
            append(out, a)
        if (da >= 0.0) != (db >= 0.0):
            t := da / (da - db)
            pa := a[0]
            pb := b[0]
            pos := [pa[k] + (pb[k] - pa[k]) * t for k in 0..4]
            var := [a[1][k] + (b[1][k] - a[1][k]) * t for k in 0..len(a[1])]
            append(out, [pos, var])
        i += 1
    # w doit rester positif
    return [v for v in out if v[0][3] > NEAR_EPS]

