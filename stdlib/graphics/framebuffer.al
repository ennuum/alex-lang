# ALEX STANDARD LIBRARY — graphics.framebuffer
#
# Cibles de rendu et affichage :
#   - Framebuffer : plusieurs attachements couleur (graphics.surface.Surface), profondeur, gabarit (stencil) ;
#     suréchantillonnage (samples 4 ou 16 : rendu en 2x / 4x puis réduction par moyenne, « resolve ») ;
#     vérification de complétude, effacement, lecture d'une zone, copie (blit) avec mise à l'échelle,
#     masquage par le gabarit ;
#   - FbDevice : vrai framebuffer Linux (/dev/fb0) décrit par /sys/class/graphics/fbN (taille virtuelle,
#     bits par point, pas d'une ligne) ; conversion d'une Surface en XRGB8888 / RGB888 / RGB565 et écriture
#     dans le périphérique (droits : groupe « video ») ; FbPresenter pour graphics.swapchain.
#
#   use graphics.framebuffer as gfb
#   fb := gfb.Framebuffer(320, 240, 1, true, true, 4)     # 1 couleur, profondeur, gabarit, 4 échantillons
#   pass := ctx.render_pass(fb.target(0))
#   ...
#   image := fb.resolve(0)                                 # Surface 320x240 lissée
#   dev := gfb.FbDevice("/dev/fb0")
#   dev.show(image)
#
# Erreurs : FramebufferError (attachements incohérents, indice inconnu), BackendUnavailable (/dev/fb absent
# ou illisible), FormatError (profondeur de couleur non prise en charge).

from core use len, to_int
from collections use append
use io as _io
use string as _s
use hardware._sys as _sys
use graphics.surface as _gs

class Framebuffer:
    # samples : 1, 4 (2x2) ou 16 (4x4).
    func init(width, height, colors=1, depth=true, stencil=false, samples=1):
        if width <= 0 or height <= 0:
            raise("FramebufferError", "Framebuffer : dimensions invalides")
        if samples != 1 and samples != 4 and samples != 16:
            raise("FramebufferError", "Framebuffer : 1, 4 ou 16 échantillons")
        if colors < 0 or colors > 8:
            raise("FramebufferError", "Framebuffer : 0 à 8 attachements couleur")
        self.width = width
        self.height = height
        self.samples = samples
        self.scale = 1 if samples == 1 else (2 if samples == 4 else 4)
        w := width * self.scale
        h := height * self.scale
        self.colors = [_gs.Surface(w, h, depth and i == 0) for i in 0..colors]
        self.has_depth = depth
        self.stencil = [0 for i in 0..w * h] if stencil else null

    func internal_size():
        return [self.width * self.scale, self.height * self.scale]

    func count():
        return len(self.colors)

    # Surface où dessiner (taille interne : multipliée par le facteur de suréchantillonnage).
    func target(i=0):
        if i < 0 or i >= len(self.colors):
            raise("FramebufferError", "Framebuffer : pas d'attachement couleur " + str(i))
        return self.colors[i]

    func attach(i, surface):
        sz := self.internal_size()
        if surface.width != sz[0] or surface.height != sz[1]:
            raise("FramebufferError", "attachement " + str(i) + " de " + str(surface.width) + "x" + str(surface.height) + ", " + str(sz[0]) + "x" + str(sz[1]) + " attendu")
        if i == len(self.colors):
            append(self.colors, surface)
        elif i >= 0 and i < len(self.colors):
            self.colors[i] = surface
        else:
            raise("FramebufferError", "Framebuffer : indice d'attachement " + str(i) + " invalide")

    func check_complete():
        if len(self.colors) == 0 and not self.has_depth:
            raise("FramebufferError", "Framebuffer sans aucun attachement")
        sz := self.internal_size()
        for c in self.colors:
            if c.width != sz[0] or c.height != sz[1]:
                raise("FramebufferError", "attachements de tailles différentes")
        return true

    func clear(color=0xFF000000, depth=1.0, stencil=0):
        for c in self.colors:
            c.clear(color)
            if c.has_depth:
                c.clear_depth(depth)
        if self.stencil != null:
            self.stencil = [stencil for i in 0..len(self.stencil)]

    # Gabarit : écrit value dans un rectangle (coordonnées de la taille finale).
    func stencil_rect(x, y, w, h, value):
        if self.stencil == null:
            raise("FramebufferError", "Framebuffer sans gabarit")
        k := self.scale
        iw := self.width * k
        ih := self.height * k
        yy := y * k
        while yy < (y + h) * k and yy < ih:
            if yy >= 0:
                xx := x * k
                while xx < (x + w) * k and xx < iw:
                    if xx >= 0:
                        self.stencil[yy * iw + xx] = value
                    xx += 1
            yy += 1

    # Copie dans l'attachement i les points de src (même taille interne) dont le gabarit vaut ref
    # (op « equal ») ou en diffère (« not_equal »). Renvoie le nombre de points copiés.
    func masked_copy(src, ref, i=0, op="equal"):
        if self.stencil == null:
            raise("FramebufferError", "Framebuffer sans gabarit")
        dst := self.target(i)
        if src.width != dst.width or src.height != dst.height:
            raise("FramebufferError", "masked_copy : tailles différentes")
        n := 0
        j := 0
        while j < len(self.stencil):
            hit := self.stencil[j] == ref
            if op == "not_equal":
                hit = not hit
            if hit:
                dst.color[j] = src.color[j]
                n += 1
            j += 1
        return n

    # Surface de la taille finale : moyenne des échantillons.
    func resolve(i=0):
        src := self.target(i)
        k := self.scale
        if k == 1:
            return src.copy()
        out := _gs.Surface(self.width, self.height, false)
        div := k * k
        y := 0
        while y < self.height:
            x := 0
            while x < self.width:
                acc := [0, 0, 0, 0]
                dy := 0
                while dy < k:
                    row := (y * k + dy) * src.width + x * k
                    dx := 0
                    while dx < k:
                        c := src.color[row + dx]
                        acc[0] += (c >> 16) & 255
                        acc[1] += (c >> 8) & 255
                        acc[2] += c & 255
                        acc[3] += (c >> 24) & 255
                        dx += 1
                    dy += 1
                out.color[y * self.width + x] = _gs.pack((acc[0] + div // 2) // div, (acc[1] + div // 2) // div, (acc[2] + div // 2) // div, (acc[3] + div // 2) // div)
                x += 1
            y += 1
        return out

    # Zone de l'image finale (couleurs empaquetées ARGB), ligne par ligne.
    func read_pixels(x, y, w, h, i=0):
        img := self.resolve(i)
        out := []
        r := y
        while r < y + h:
            c := x
            while c < x + w:
                append(out, img.color[r * img.width + c])
                c += 1
            r += 1
        return out

    func describe():
        t := "Framebuffer " + str(self.width) + "x" + str(self.height) + ", " + str(len(self.colors)) + " couleur(s)"
        if self.has_depth:
            t += ", profondeur"
        if self.stencil != null:
            t += ", gabarit"
        if self.samples > 1:
            t += ", " + str(self.samples) + " échantillons"
        return t

# Copie src[sx, sy, sw, sh] vers dst[dx, dy, dw, dh] (mise à l'échelle au plus proche).
func blit(src, dst, sx, sy, sw, sh, dx, dy, dw, dh):
    if sw <= 0 or sh <= 0 or dw <= 0 or dh <= 0:
        return 0
    n := 0
    y := 0
    while y < dh:
        ty := dy + y
        if ty >= 0 and ty < dst.height:
            yy := sy + (y * sh) // dh
            x := 0
            while x < dw:
                tx := dx + x
                if tx >= 0 and tx < dst.width:
                    xx := sx + (x * sw) // dw
                    if xx >= 0 and xx < src.width and yy >= 0 and yy < src.height:
                        dst.color[ty * dst.width + tx] = src.color[yy * src.width + xx]
                        n += 1
                x += 1
        y += 1
    return n

# Octets d'une Surface dans un format de framebuffer : bpp 32 (XRGB8888 : B, G, R, X), 24 (B, G, R), 16 (RGB565
# petit-boutiste) ; stride : octets par ligne (0 : serré) ; les lignes sont complétées de zéros.
func encode(surface, bpp, stride=0):
    if bpp != 32 and bpp != 24 and bpp != 16:
        raise("FormatError", "framebuffer : " + str(bpp) + " bits par point non pris en charge (16, 24, 32)")
    bytes_pp := bpp // 8
    line := surface.width * bytes_pp
    st := stride if stride > 0 else line
    if st < line:
        raise("FormatError", "framebuffer : pas de ligne " + str(st) + " < " + str(line))
    out := []
    y := 0
    while y < surface.height:
        x := 0
        while x < surface.width:
            c := surface.color[y * surface.width + x]
            r := (c >> 16) & 255
            g := (c >> 8) & 255
            b := c & 255
            if bpp == 32:
                append(out, b)
                append(out, g)
                append(out, r)
                append(out, 255)
            elif bpp == 24:
                append(out, b)
                append(out, g)
                append(out, r)
            else:
                v := ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
                append(out, v & 255)
                append(out, v >> 8)
            x += 1
        pad := st - line
        while pad > 0:
            append(out, 0)
            pad -= 1
        y += 1
    return out

class FbDevice:
    func init(path="/dev/fb0"):
        self.path = path
        name := _s.split(path, "/")
        self.node = name[len(name) - 1]
        sysd := "/sys/class/graphics/" + self.node
        if not _sys.exists(path):
            raise("BackendUnavailable", "framebuffer " + path + " absent (pilote fbdev / simpledrm non chargé)")
        size := _sys.read(sysd + "/virtual_size")
        bpp := _sys.read(sysd + "/bits_per_pixel")
        if size == null or bpp == null:
            raise("BackendUnavailable", "framebuffer " + path + " : description " + sysd + " illisible")
        wh := _s.split(size, ",")
        self.width = to_int(_s.trim(wh[0]))
        self.height = to_int(_s.trim(wh[1]))
        self.bpp = to_int(bpp)
        st := _sys.read(sysd + "/stride")
        self.stride = to_int(st) if st != null else self.width * (self.bpp // 8)
        nm := _sys.read(sysd + "/name")
        self.name = nm if nm != null else self.node
        self.frames = 0

    func describe():
        return self.path + " (" + self.name + ") " + str(self.width) + "x" + str(self.height) + " " + str(self.bpp) + " bits, ligne " + str(self.stride) + " octets"

    # Affiche une Surface : recadrée / complétée de noir à la taille de l'écran, puis écrite d'un bloc.
    func show(surface):
        img := surface
        if surface.width != self.width or surface.height != self.height:
            img = _gs.Surface(self.width, self.height, false)
            img.clear(0xFF000000)
            blit(surface, img, 0, 0, surface.width, surface.height, 0, 0, surface.width, surface.height)
        data := encode(img, self.bpp, self.stride)
        try:
            _io.write_bytes_at(_sys.p(self.path), data, 0)
        catch e:
            raise("BackendUnavailable", "écriture dans " + self.path + " impossible (" + e.message + ") : groupe « video » requis")
        self.frames += 1
        return len(data)

class FbPresenter:
    func init(device):
        self.device = device
        self.count = 0

    func present(surface):
        self.device.show(surface)
        self.count += 1

func devices():
    out := []
    for n in _sys.list("/sys/class/graphics"):
        if _s.starts_with(n, "fb"):
            append(out, "/dev/" + n)
    return out
