# ALEX STANDARD LIBRARY — multimedia.image.jpeg
#
# Décodeur JPEG (JFIF / Exif / Adobe) :
#   - séquentiel de base et étendu, PROGRESSIF (sélection spectrale et approximations successives) ;
#   - codage de Huffman ou ARITHMÉTIQUE (SOF9 / SOF10, conditionnement DAC) ;
#   - précision 8 ou 12 bits (12 bits ramenés à 8 en sortie) ;
#   - SANS PERTE (SOF3, prédicteurs 1..7, transformation ponctuelle, précision 2..16 bits) ;
#   - intervalles de reprise (RST), gris, YCbCr, RGB, CMYK et YCCK (marqueur Adobe APP14), sous-échantillonnage
#     quelconque (4:4:4, 4:2:2, 4:2:0, 4:1:1...), tables de quantification 8 / 16 bits ;
#   - orientation Exif lue, et appliquée sur demande (apply_orientation).
# L'analyse des segments est en ALEX ; le décodage entropique, l'IDCT, la conversion de couleurs (interpolation de la
# chrominance comme libjpeg) et les rotations sont en code natif.
#
#   use multimedia.image.jpeg as jpeg
#   r := jpeg.decode_rgba(octets)          # {"width", "height", "buffer" (ffi.Buffer RGBA), "orientation", "info"}
#   r := jpeg.decode_rgba(octets, null, true)   # orientation Exif appliquée (photos d'appareils et de téléphones)
#   img := jpeg.decode(octets)             # multimedia.image.image.Image RGBA (passe aussi par decode.decode)
#
# Refusés : hiérarchique (SOF5..7, SOF13..15) et sans perte arithmétique (SOF11), absents en pratique.
# Erreurs : CorruptDataError (flux invalide), UnsupportedError, LimitError.

from core use len, type, to_int
from collections use append
use math
use ffi
use _native_ffi as _nf
use multimedia.core.errors as merr
use multimedia.security.limits as lim
use multimedia.image.image as mi

const ZIGZAG := [0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6,
                 7, 14, 21, 28, 35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51, 58, 59, 52, 45, 38, 31,
                 39, 46, 53, 60, 61, 54, 47, 55, 62, 63]

# Table Qe du codeur arithmétique (T.81 tableau D.2), au format de libjpeg :
# Qe << 16 | état suivant après MPS << 8 | bascule du MPS << 7 | état suivant après LPS. L'état 113 est fixe.
const ARITAB := [1511850369, 629539342, 286524176, 134939666, 64488724, 31065623, 15009561, 7276572, 3541278, 1706529,
                 854819, 396297, 199946, 68876, 1518276495, 1059393572, 754061606, 545002023, 398005032, 293737514,
                 216995115, 161551917, 120526638, 89921584, 67508529, 50534963, 37755700, 28384310, 21241144, 16064057,
                 12001083, 9052220, 6824254, 5120575, 3875616, 2885921, 1524704677, 1212950080, 973940545, 787556419,
                 639576388, 523446853, 430451526, 353905736, 293023049, 242495050, 201011019, 167260237, 140587342,
                 117846607, 97334064, 81671218, 68105522, 56833587, 47462196, 39598133, 33044790, 27540023, 23083832,
                 19217465, 16137530, 13319739, 11222845, 9379901, 1527923137, 1292124752, 1093419857, 936920146,
                 803751251, 691816020, 595150678, 517949527, 447301975, 391006792, 337922888, 295455818, 258690378,
                 223432267, 196497229, 171978829, 1479692752, 1293701720, 1133400921, 1004360794, 888034651, 783177308,
                 697980765, 622217046, 1433426392, 1286167135, 1155095392, 1042439265, 941907299, 850681443, 773281373,
                 1453875423, 1330012517, 1206215270, 1104110439, 1010656360, 928931171, 1378969193, 1276077930,
                 1178167403, 1096704871, 1445423849, 1357343596, 1267033965, 1435987310, 1347382127, 1511026670,
                 1428319600, 1508601840, 1511879025]

func _corrupt(msg):
    merr.fail(merr.CORRUPT, "jpeg : " + msg)

_idct_tab := [null]

func _idct_table():
    if _idct_tab[0] == null:
        v := []
        x := 0
        while x < 8:
            u := 0
            while u < 8:
                cu := math.sqrt(0.5) if u == 0 else 1.0
                append(v, 0.5 * cu * math.cos((2 * x + 1) * u * math.PI / 16.0))
                u += 1
            x += 1
        b := ffi.Buffer(512)
        b.write_array("f64", v)
        _idct_tab[0] = b
    return _idct_tab[0]

# ---------------------------------------------------------------------------------------------------------------------
# Huffman et lecture de bits (poids fort d'abord, octets 0xFF00 déjà retirés)
# ---------------------------------------------------------------------------------------------------------------------

class _Huff:
    func init(counts, symbols):
        # table rapide sur 9 bits : [longueur, symbole] ; codes plus longs : maxcode / valptr
        self.fast = [-1 for k in 0..512]
        self.fastlen = [0 for k in 0..512]
        self.maxcode = [-1 for k in 0..18]
        self.valptr = [0 for k in 0..18]
        self.mincode = [0 for k in 0..18]
        self.symbols = symbols
        code := 0
        k := 0
        l := 1
        while l <= 16:
            n := counts[l - 1]
            if n > 0:
                self.valptr[l] = k
                self.mincode[l] = code
                j := 0
                while j < n:
                    if l <= 9:
                        base := code << (9 - l)
                        span := 1 << (9 - l)
                        f := 0
                        while f < span:
                            self.fast[base + f] = symbols[k]
                            self.fastlen[base + f] = l
                            f += 1
                    code += 1
                    k += 1
                    j += 1
                self.maxcode[l] = code - 1
            code = code << 1
            l += 1

# Table de Huffman sérialisée pour le code natif (822 entiers 32 bits).
func _huff_words(h):
    out := []
    k := 0
    while k < 512:
        if h.fastlen[k] > 0:
            append(out, (h.fastlen[k] << 16) | h.fast[k])
        else:
            append(out, 4294967295)
        k += 1
    for v in h.maxcode:
        append(out, v & 4294967295)
    for v in h.valptr:
        append(out, v)
    for v in h.mincode:
        append(out, v)
    syms := [x for x in h.symbols]
    while len(syms) < 256:
        append(syms, 0)
    for v in syms[0:256]:
        append(out, v)
    return out

# ---------------------------------------------------------------------------------------------------------------------
# Décodage
# ---------------------------------------------------------------------------------------------------------------------

func _u16(b, o):
    return (b[o] << 8) | b[o + 1]

func _exif_orientation(b, o, n):
    # APP1 « Exif\0\0 » + TIFF : balise 0x0112
    if n < 14 or b[o] != 69 or b[o + 1] != 120 or b[o + 2] != 105 or b[o + 3] != 102:
        return 1
    t := o + 6
    le := b[t] == 73
    ifd := _rd(b, t + 4, 4, le)
    cnt := _rd(b, t + ifd, 2, le)
    k := 0
    while k < cnt:
        e := t + ifd + 2 + 12 * k
        if e + 12 > o + n:
            return 1
        if _rd(b, e, 2, le) == 0x0112:
            return _rd(b, e + 8, 2, le)
        k += 1
    return 1

func _rd(b, o, n, le):
    v := 0
    k := 0
    while k < n:
        if le:
            v = v | (b[o + k] << (8 * k))
        else:
            v = (v << 8) | b[o + k]
        k += 1
    return v

# Décode un JPEG en RGBA : {"width", "height", "buffer" (ffi.Buffer), "orientation" (Exif, 1 = normale), "info"}.
# apply_orientation : tourne / retourne l'image selon l'orientation Exif (largeur et hauteur échangées pour 5..8) ;
# "orientation" vaut alors 1 et info["exif_orientation"] garde la valeur lue.
func decode_rgba(b, limits=null, apply_orientation=false):
    l := lim.of(limits)
    if len(b) < 4 or b[0] != 0xFF or b[1] != 0xD8:
        _corrupt("marqueur SOI absent")
    qt := [null, null, null, null]
    dc_tabs := [null, null, null, null]
    ac_tabs := [null, null, null, null]
    comps := []
    width := 0
    height := 0
    progressive := false
    restart := 0
    orientation := 1
    hmax := 1
    vmax := 1
    mcux := 0
    mcuy := 0
    frame := false
    precision := 8
    coding := "huffman"
    process := "baseline"
    adobe := -1
    jfif := false
    dac := [0, 0, 0, 0, 1, 1, 1, 1, 5, 5, 5, 5]
    ar := null
    pos := 2
    n := len(b)
    data := null
    zz := null
    tabs := null
    while pos + 4 <= n:
        if b[pos] != 0xFF:
            pos += 1
            continue
        m := b[pos + 1]
        if m == 0xFF:
            pos += 1
            continue
        if m == 0xD8 or (m >= 0xD0 and m <= 0xD7) or m == 0x01:
            pos += 2
            continue
        if m == 0xD9:
            break
        seglen := _u16(b, pos + 2)
        start := pos + 4
        end := pos + 2 + seglen
        if end > n:
            _corrupt("segment tronqué")
        if m == 0xDB:
            o := start
            while o < end:
                pq := b[o] >> 4
                tq := b[o] & 15
                o += 1
                t := [0 for k in 0..64]
                k := 0
                while k < 64:
                    if pq == 0:
                        t[ZIGZAG[k]] = b[o]
                        o += 1
                    else:
                        t[ZIGZAG[k]] = _u16(b, o)
                        o += 2
                    k += 1
                qt[tq & 3] = t
        elif m == 0xC4:
            o := start
            while o < end:
                tc := b[o] >> 4
                th := b[o] & 3
                counts := b[o + 1:o + 17]
                total := 0
                for c in counts:
                    total += c
                syms := b[o + 17:o + 17 + total]
                h := _Huff(counts, syms)
                if tc == 0:
                    dc_tabs[th] = h
                else:
                    ac_tabs[th] = h
                o += 17 + total
        elif m == 0xC0 or m == 0xC1 or m == 0xC2 or m == 0xC3 or m == 0xC9 or m == 0xCA:
            if frame:
                _corrupt("plusieurs trames (JPEG hiérarchique non pris en charge)")
            precision = b[start]
            progressive = m == 0xC2 or m == 0xCA
            coding = "arithmetic" if m >= 0xC9 else "huffman"
            process = "lossless" if m == 0xC3 else ("progressive" if progressive else ("baseline" if m == 0xC0 else "extended"))
            if m == 0xC3:
                if precision < 2 or precision > 16:
                    _corrupt("précision sans perte invalide (" + str(precision) + ")")
            elif precision != 8 and precision != 12:
                _corrupt("précision invalide (" + str(precision) + " bits)")
            height = _u16(b, start + 1)
            width = _u16(b, start + 3)
            nc := b[start + 5]
            if width <= 0 or height <= 0:
                _corrupt("dimensions nulles (DNL non pris en charge)")
            l.check_dimensions(width, height)
            if nc != 1 and nc != 3 and nc != 4:
                merr.unsupported("jpeg à " + str(nc) + " composantes", "gris, YCbCr / RGB ou CMYK / YCCK seulement")
            k := 0
            while k < nc:
                o := start + 6 + 3 * k
                append(comps, {"id": b[o], "h": b[o + 1] >> 4, "v": b[o + 1] & 15, "tq": b[o + 2]})
                k += 1
            for c in comps:
                hmax = math.max(hmax, c["h"])
                vmax = math.max(vmax, c["v"])
            unit := 1 if m == 0xC3 else 8
            mcux = (width + unit * hmax - 1) // (unit * hmax)
            mcuy = (height + unit * vmax - 1) // (unit * vmax)
            for c in comps:
                if c["h"] < 1 or c["h"] > 4 or c["v"] < 1 or c["v"] > 4 or c["tq"] > 3:
                    _corrupt("composante invalide")
                c["bw"] = mcux * c["h"]
                c["bh"] = mcuy * c["v"]
                c["cw"] = (width * c["h"] + hmax - 1) // hmax
                c["ch"] = (height * c["v"] + vmax - 1) // vmax
                if m == 0xC3:
                    # échantillons 32 bits (prédiction) + plan 8 bits de sortie
                    c["coef"] = ffi.Buffer(c["bw"] * c["bh"] * 4)
                    c["plane"] = ffi.Buffer(c["bw"] * c["bh"])
                else:
                    c["coef"] = ffi.Buffer(c["bw"] * c["bh"] * 256)
            frame = true
        elif m == 0xCB:
            merr.unsupported("jpeg (SOF11)", "JPEG sans perte à codage arithmétique non pris en charge")
        elif m >= 0xC5 and m <= 0xCF and m != 0xC8 and m != 0xCC:
            merr.unsupported("jpeg (SOF" + str(m - 0xC0) + ")", "JPEG hiérarchique non pris en charge")
        elif m == 0xCC:
            # conditionnement arithmétique : DC (L, U) ou AC (K)
            o := start
            while o + 1 < end:
                tc := b[o] >> 4
                tb := b[o] & 3
                if tc == 0:
                    dac[tb] = b[o + 1] & 15
                    dac[4 + tb] = b[o + 1] >> 4
                else:
                    dac[8 + tb] = b[o + 1]
                o += 2
        elif m == 0xEE:
            if seglen >= 14 and b[start] == 65 and b[start + 1] == 100 and b[start + 2] == 111 and b[start + 3] == 98 and b[start + 4] == 101:
                adobe = b[start + 11]
        elif m == 0xE0:
            if seglen >= 7 and b[start] == 74 and b[start + 1] == 70 and b[start + 2] == 73 and b[start + 3] == 70:
                jfif = true
        elif m == 0xDD:
            restart = _u16(b, start)
        elif m == 0xE1:
            orientation = _exif_orientation(b, start, seglen - 2)
        elif m == 0xDA:
            if not frame:
                _corrupt("balayage avant l'en-tête de trame")
            ns := b[start]
            sc := []
            k := 0
            while k < ns:
                cid := b[start + 1 + 2 * k]
                tsel := b[start + 2 + 2 * k]
                for c in comps:
                    if c["id"] == cid:
                        c["td"] = tsel >> 4
                        c["ta"] = tsel & 15
                        append(sc, c)
                k += 1
            o := start + 1 + 2 * ns
            ss := b[o]
            se := b[o + 1]
            ah := b[o + 2] >> 4
            al := b[o + 2] & 15
            if data == null:
                data = ffi.Buffer(n)
                data.write_array("u8", b)
                zz = ffi.Buffer(256)
                zz.write_array("i32", ZIGZAG)
                tabs = ffi.Buffer(8 * 822 * 4)
            if process == "lossless":
                for c in sc:
                    if dc_tabs[c["td"] & 3] == null:
                        _corrupt("table de Huffman absente")
            if coding == "arithmetic":
                if ar == null:
                    ar = ffi.Buffer(26304)
                    ar.write_array("i64", ARITAB)
                ar.write_array("i64", dac, 2304)
                mode := 3 if progressive else 2
                pos = _scan(sc, data, ar, zz, restart, mcux, mcuy, mode, ss, se, ah, al, end, n)
                continue
            words := []
            k = 0
            while k < 8:
                h := dc_tabs[k] if k < 4 else ac_tabs[k - 4]
                if h == null:
                    words = words + [0] * 822
                else:
                    words = words + _huff_words(h)
                k += 1
            tabs.write_array("u32", words)
            if process == "lossless":
                pos = _scan(sc, data, tabs, zz, restart, mcux, mcuy, 4, ss, se, precision, al, end, n)
            else:
                pos = _scan(sc, data, tabs, zz, restart, mcux, mcuy, 1 if progressive else 0, ss, se, ah, al, end, n)
            continue
        pos = end
    if not frame:
        _corrupt("aucune trame d'image")
    # transformation de couleurs : marqueur Adobe, sinon JFIF / identifiants « R G B »
    xform := adobe
    if xform < 0:
        if len(comps) == 3:
            xform = 0 if (not jfif and comps[0]["id"] == 82 and comps[1]["id"] == 71 and comps[2]["id"] == 66) else 1
        else:
            xform = 0
    info := {"process": process, "coding": coding, "precision": precision, "components": len(comps),
             "colorspace": _colorspace(len(comps), xform), "exif_orientation": orientation}
    r := _finish(comps, width, height, hmax, vmax, qt, process, precision, xform, orientation, l)
    if data != null:
        data.free()
        zz.free()
        tabs.free()
    if ar != null:
        ar.free()
    r["info"] = info
    if apply_orientation and orientation >= 2 and orientation <= 8:
        r = _orient(r, orientation)
    return r

func _colorspace(nc, xform):
    if nc == 1:
        return "gray"
    if nc == 3:
        return "ycbcr" if xform != 0 else "rgb"
    return "ycck" if xform == 2 else "cmyk"

# Applique une orientation Exif (2..8) au résultat de decode_rgba.
func _orient(r, o):
    w := r["width"]
    h := r["height"]
    dst := ffi.Buffer(w * h * 4)
    _nf.img_orient(r["buffer"]._live(), dst._live(), w, h, o)
    r["buffer"].free()
    r["buffer"] = dst
    if o >= 5:
        r["width"] = h
        r["height"] = w
    r["orientation"] = 1
    return r

# Applique l'orientation Exif o (1..8) à un tampon RGBA w x h ; rend [tampon, largeur, hauteur] (nouveau tampon).
func orient_rgba(buf, w, h, o):
    dst := ffi.Buffer(w * h * 4)
    _nf.img_orient(buf._live(), dst._live(), w, h, o)
    if o >= 5:
        return [dst, h, w]
    return [dst, w, h]

# Un balayage, décodé en code natif ; rend la position du marqueur suivant. mode : 0 / 1 Huffman séquentiel /
# progressif, 2 / 3 arithmétique séquentiel / progressif, 4 sans perte (ah = précision).
func _scan(sc, data, tabs, zz, restart, mcux, mcuy, mode, ss, se, ah, al, start, n):
    if len(sc) < 1 or len(sc) > 4:
        _corrupt("balayage invalide")
    single := len(sc) == 1
    lossless := mode == 4
    total := 0
    if single:
        c := sc[0]
        if lossless:
            total = c["cw"] * c["ch"]
        else:
            total = ((c["cw"] + 7) // 8) * ((c["ch"] + 7) // 8)
    else:
        total = mcux * mcuy
    if lossless and (ss < 1 or ss > 7):
        _corrupt("prédicteur sans perte invalide (" + str(ss) + ")")
    prm := [len(sc), ss, se, ah, al, mode, restart, mcux, mcuy, total, 1 if single else 0, start, n]
    for c in sc:
        if lossless:
            prm = prm + [c["coef"].address(), c["td"] & 3, c["ta"] & 3, c["plane"].address(), c["bw"], c["h"], c["v"], c["cw"]]
        else:
            prm = prm + [c["coef"].address(), c["td"] & 3, c["ta"] & 3, 0, c["bw"], c["h"], c["v"], (c["cw"] + 7) // 8]
    while len(prm) < 13 + 32:
        append(prm, 0)
    pb := ffi.Buffer(8 * len(prm))
    pb.write_array("i64", prm)
    end := _nf.jpeg_scan(pb._live(), data._live(), tabs._live(), zz._live())
    pb.free()
    return end

func _finish(comps, width, height, hmax, vmax, qt, process, precision, xform, orientation, l):
    tab := _idct_table()
    planes := []
    qb := ffi.Buffer(256)
    for c in comps:
        if process == "lossless":
            c["coef"].free()
            c["coef"] = null
            append(planes, [c["plane"], c["bw"]])
            continue
        nb := c["bw"] * c["bh"]
        q := qt[c["tq"]]
        if q == null:
            _corrupt("table de quantification absente")
        qb.write_array("i32", q)
        stride := c["bw"] * 8
        pb := ffi.Buffer(stride * c["bh"] * 8)
        _nf.jpeg_idct(c["coef"]._live(), nb, pb._live(), c["bw"], stride, tab._live(), qb._live(), precision)
        c["coef"].free()
        c["coef"] = null
        append(planes, [pb, stride])
    out := ffi.Buffer(width * height * 4)
    nc := len(comps)
    # [nc, pasY, pasCb, pasCr, hY, vY, hCb, vCb, hCr, vCr, hmax, vmax, transformation, hK, vK, pasK, réservé]
    ix := [0, 1 if nc > 1 else 0, 2 if nc > 2 else 0, 3 if nc > 3 else 0]
    vals := [nc, planes[ix[0]][1], planes[ix[1]][1], planes[ix[2]][1], comps[ix[0]]["h"], comps[ix[0]]["v"],
             comps[ix[1]]["h"], comps[ix[1]]["v"], comps[ix[2]]["h"], comps[ix[2]]["v"], hmax, vmax, xform,
             comps[ix[3]]["h"], comps[ix[3]]["v"], planes[ix[3]][1], 0]
    prm := ffi.Buffer(136)
    prm.write_array("i64", vals)
    _nf.jpeg_color(planes[ix[0]][0]._live(), planes[ix[1]][0]._live(), planes[ix[2]][0]._live(), out._live(), width, height, prm._live(), planes[ix[3]][0]._live())
    prm.free()
    qb.free()
    for p in planes:
        p[0].free()
    return {"width": width, "height": height, "buffer": out, "orientation": orientation}

# JPEG -> multimedia.image.image.Image RGBA (orientation Exif appliquée si apply_orientation).
func decode(b, limits=null, apply_orientation=false):
    r := decode_rgba(b, limits, apply_orientation)
    px := r["buffer"].read_array("u8", r["width"] * r["height"] * 4)
    r["buffer"].free()
    img := mi.Image(r["width"], r["height"], "rgba", px)
    img.meta["orientation"] = r["orientation"]
    img.meta["jpeg"] = r["info"]
    return img
