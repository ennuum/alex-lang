# ALEX STANDARD LIBRARY — graphics.sampler
#
# Échantillonneur indépendant de la texture (comme VkSampler / GPUSampler) : la même texture peut être lue
# avec plusieurs réglages.
#   - filtres de réduction (min) et d'agrandissement (mag) : « nearest » ou « linear » ;
#   - mipmaps : « none », « nearest » (niveau le plus proche), « linear » (mélange de deux niveaux,
#     trilinéaire) ; lod_bias, min_lod, max_lod ;
#   - adressage par axe : « repeat », « clamp », « mirror », « border » (couleur de bord) ;
#   - sample(tex, u, v, lod) ; sample_grad(tex, u, v, du, dv) choisit le niveau d'après la taille d'un point
#     de l'écran en coordonnées de texture ;
#   - bind(tex) : objet avec sample(u, v), utilisable comme uniform « texture » des shaders fournis.
#
#   use graphics.sampler as gsm
#   s := gsm.Sampler("linear", "linear", "linear")
#   s.wrap_u = "mirror"
#   tex.build_mipmaps()
#   c := s.sample(tex, 0.25, 0.5, 1.3)          # [r, g, b, a] entre 0 et 1
#   u.set("texture", s.bind(tex))
#
# Erreurs : ArgumentError (filtre ou mode d'adressage inconnu).

from core use len, to_int
from collections use append
use math as _math
use graphics.surface as _gs

const FILTERS := ["nearest", "linear"]
const MIPMAPS := ["none", "nearest", "linear"]
const WRAPS := ["repeat", "clamp", "mirror", "border"]

func _floor(x):
    i := to_int(x)
    if x < 0 and i != x:
        return i - 1
    return i

class Sampler:
    func init(min_filter="linear", mag_filter="linear", mipmap="none", wrap="repeat"):
        self.min_filter = min_filter
        self.mag_filter = mag_filter
        self.mipmap = mipmap
        self.wrap_u = wrap
        self.wrap_v = wrap
        self.border = [0.0, 0.0, 0.0, 0.0]
        self.lod_bias = 0.0
        self.min_lod = 0.0
        self.max_lod = 1000.0
        self.samples = 0
        self.validate()

    func validate():
        if not (self.min_filter in FILTERS) or not (self.mag_filter in FILTERS):
            raise("ArgumentError", "Sampler : filtre « nearest » ou « linear »")
        if not (self.mipmap in MIPMAPS):
            raise("ArgumentError", "Sampler : mipmap « none », « nearest » ou « linear »")
        if not (self.wrap_u in WRAPS) or not (self.wrap_v in WRAPS):
            raise("ArgumentError", "Sampler : adressage parmi " + str(WRAPS))
        return true

    # Coordonnée entière ajustée selon le mode, ou -1 pour la couleur de bord.
    func _wrap(i, n, mode):
        if mode == "repeat":
            r := i % n
            return r + n if r < 0 else r
        if mode == "clamp":
            if i < 0:
                return 0
            return n - 1 if i >= n else i
        if mode == "mirror":
            p := 2 * n
            r := i % p
            if r < 0:
                r += p
            return p - 1 - r if r >= n else r
        if i < 0 or i >= n:
            return -1
        return i

    func _texel(tex, x, y):
        xi := self._wrap(x, tex.width, self.wrap_u)
        yi := self._wrap(y, tex.height, self.wrap_v)
        if xi < 0 or yi < 0:
            return self.border
        return _gs.to_floats(tex.pixels[yi * tex.width + xi])

    func _filter(tex, u, v, filt):
        if filt == "nearest":
            return self._texel(tex, _floor(u * tex.width), _floor(v * tex.height))
        fx := u * tex.width - 0.5
        fy := v * tex.height - 0.5
        x0 := _floor(fx)
        y0 := _floor(fy)
        tx := fx - x0
        ty := fy - y0
        c00 := self._texel(tex, x0, y0)
        c10 := self._texel(tex, x0 + 1, y0)
        c01 := self._texel(tex, x0, y0 + 1)
        c11 := self._texel(tex, x0 + 1, y0 + 1)
        out := []
        k := 0
        while k < 4:
            a := c00[k] + (c10[k] - c00[k]) * tx
            b := c01[k] + (c11[k] - c01[k]) * tx
            append(out, a + (b - a) * ty)
            k += 1
        return out

    # lod : niveau de détail (0 : texture de base, 1 : moitié...). Les mipmaps doivent avoir été construits
    # (tex.build_mipmaps()) pour que lod > 0 ait un effet.
    func sample(tex, u, v, lod=0.0):
        self.samples += 1
        l := lod + self.lod_bias
        if l < self.min_lod:
            l = self.min_lod
        if l > self.max_lod:
            l = self.max_lod
        if l <= 0.0 or self.mipmap == "none" or len(tex.mips) <= 1:
            filt := self.mag_filter if l <= 0.0 else self.min_filter
            return self._filter(tex, u, v, filt)
        top := len(tex.mips) - 1
        if self.mipmap == "nearest":
            lv := _floor(l + 0.5)
            if lv > top:
                lv = top
            return self._filter(tex.mips[lv], u, v, self.min_filter)
        l0 := _floor(l)
        if l0 >= top:
            return self._filter(tex.mips[top], u, v, self.min_filter)
        t := l - l0
        a := self._filter(tex.mips[l0], u, v, self.min_filter)
        b := self._filter(tex.mips[l0 + 1], u, v, self.min_filter)
        return [a[k] + (b[k] - a[k]) * t for k in 0..4]

    # du, dv : variation de u et v d'un point de l'écran au suivant.
    func lod_for(tex, du, dv):
        su := du * tex.width
        sv := dv * tex.height
        if su < 0:
            su = -su
        if sv < 0:
            sv = -sv
        m := su if su > sv else sv
        if m <= 1.0:
            return 0.0
        return _math.log2(m)

    func sample_grad(tex, u, v, du, dv):
        return self.sample(tex, u, v, self.lod_for(tex, du, dv))

    func bind(tex, lod=0.0):
        return BoundTexture(self, tex, lod)

    func describe():
        return "Sampler min=" + self.min_filter + " mag=" + self.mag_filter + " mip=" + self.mipmap + " wrap=" + self.wrap_u + "/" + self.wrap_v

class BoundTexture:
    func init(sampler, tex, lod):
        self.sampler = sampler
        self.texture = tex
        self.lod = lod
        self.width = tex.width
        self.height = tex.height

    func sample(u, v):
        return self.sampler.sample(self.texture, u, v, self.lod)

NEAREST_REPEAT := Sampler("nearest", "nearest", "none", "repeat")
LINEAR_CLAMP := Sampler("linear", "linear", "none", "clamp")
TRILINEAR := Sampler("linear", "linear", "linear", "repeat")
