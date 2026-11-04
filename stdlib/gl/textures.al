# ALEX STANDARD LIBRARY — gl.textures
#
# Textures pour la carte graphique depuis les fichiers DDS et KTX2, envoyées telles quelles (glCompressedTexImage*)
# avec toutes leurs mipmaps : moins de mémoire vidéo et chargement sans décodage.
#
#   Formes   : 2D, CUBEMAPS (6 faces), TABLEAUX 2D, tableaux de cubemaps (OpenGL 4.0+), VOLUMES (3D).
#   Formats  : BC1..BC5, BC6H (HDR), BC7 ; ETC2 / EAC (cœur OpenGL 4.3 ou GL_ARB_ES3_compatibility) ;
#              ASTC LDR 4x4 .. 12x12 (GL_KHR_texture_compression_astc_ldr) ; RGBA8 / BGRA8, RGBA16F, RGBA32F.
#   KTX2     : sans supercompression, zlib ou ZSTD (décodeur natif, office.compression).
#   Secours  : si le pilote ne connaît pas BC1 / BC2 / BC3 (S3TC absent), décodage RGBA par le processeur.
#
#   use gl.render as gr
#   t := gr.load_texture("sol.dds")            # ou .ktx2 ; même interface que les autres textures (bind, width...)
#   ciel := gr.load_cubemap("ciel.ktx2")       # cubemap (ou 6 images) -> gr.Skybox(r, ciel)
#   use gl.textures as gt
#   print(gt.info("ciel.ktx2"))                # {"format", "width", "height", "depth", "layers", "faces", "target",
#                                              #  "levels", "compressed", "supercompression"}
#
# Refusé avec explication : Basis Universal (KTX2 BasisLZ / ETC1S / UASTC) : c'est un format intermédiaire qui doit
# être TRANSCODÉ (en BC7, ASTC ou ETC2) par le transcodeur de Binomial, non inclus ; convertir les fichiers à
# l'avance (toktx --encode astc / --t2 --bcmp=0, basisu -unpack...), ou les livrer en BC7 / ASTC.
# Les cubemaps DDS partielles (moins de 6 faces) sont refusées.
# Erreurs : ValueError (format non pris en charge, fichier invalide), IoError (fichier).

from core use len, type, to_int
from collections use append
use ffi
use io
use gl
use string as _str
use office.compression as _z

# ---------------------------------------------------------------------------------------------------------------------
# Texture
# ---------------------------------------------------------------------------------------------------------------------

const _TARGETS := {"2d": 0x0DE1, "cube": 0x8513, "2d_array": 0x8C1A, "cube_array": 0x9009, "3d": 0x806F}

_seamless := [false]

# Texture créée à partir de niveaux de mipmaps déjà prêts (un tampon par niveau : couches, faces et tranches
# contiguës dans l'ordre d'OpenGL).
class CompressedTexture:
    func init(width, height, fmt, levels, compressed, filter="linear", wrap="repeat", mipmaps=true, shape=null):
        sh := shape if shape != null else {"target": "2d", "depth": 1, "layers": 0, "faces": 1}
        self.kind = "texture"
        self.width = width
        self.height = height
        self.depth = sh["depth"]
        self.layers = sh["layers"]
        self.faces = sh["faces"]
        self.shape = sh["target"]
        self.target = _TARGETS[sh["target"]]
        self.channels = 4
        self.format = fmt["name"]
        self.compressed = compressed
        self.id = gl.gen("glGenTextures")
        t := self.target
        gl.glBindTexture(t, self.id)
        gl.glPixelStorei(gl.GL_UNPACK_ALIGNMENT, 1)
        if sh["target"] == "cube" or sh["target"] == "cube_array":
            if not _seamless[0]:
                gl.glEnable(gl.GL_TEXTURE_CUBE_MAP_SEAMLESS)
                _seamless[0] = true
        nlev := len(levels) if mipmaps else 1
        k := 0
        while k < nlev:
            lv := levels[k]
            b := lv[2]
            if sh["target"] == "2d":
                self._img2d(t, k, fmt, lv[0], lv[1], b, 0, b.size())
            elif sh["target"] == "cube":
                fs := b.size() // 6
                f := 0
                while f < 6:
                    self._img2d(gl.GL_TEXTURE_CUBE_MAP_POSITIVE_X + f, k, fmt, lv[0], lv[1], b, f * fs, fs)
                    f += 1
            else:
                d := lv[3]
                if compressed:
                    gl.glCompressedTexImage3D(t, k, fmt["gl"], lv[0], lv[1], d, 0, b.size(), b.address())
                else:
                    gl.glTexImage3D(t, k, fmt["gl"], lv[0], lv[1], d, 0, fmt["upload"], fmt["type"], b.address())
            b.free()
            k += 1
        gl.glTexParameteri(t, gl.GL_TEXTURE_BASE_LEVEL, 0)
        gl.glTexParameteri(t, gl.GL_TEXTURE_MAX_LEVEL, nlev - 1)
        self.mipmaps = nlev > 1
        if mipmaps and nlev == 1 and not compressed:
            gl.glGenerateMipmap(t)
            self.mipmaps = true
            gl.glTexParameteri(t, gl.GL_TEXTURE_MAX_LEVEL, 1000)
        self.set_filter(filter)
        self.set_wrap(wrap)

    func _img2d(target, k, fmt, w, h, b, off, size):
        if self.compressed:
            gl.glCompressedTexImage2D(target, k, fmt["gl"], w, h, 0, size, b.address() + off)
        else:
            gl.glTexImage2D(target, k, fmt["gl"], w, h, 0, fmt["upload"], fmt["type"], b.address() + off)

    func set_filter(filter):
        gl.glBindTexture(self.target, self.id)
        if filter == "nearest":
            gl.glTexParameteri(self.target, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST_MIPMAP_NEAREST if self.mipmaps else gl.GL_NEAREST)
            gl.glTexParameteri(self.target, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST)
        else:
            gl.glTexParameteri(self.target, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR_MIPMAP_LINEAR if self.mipmaps else gl.GL_LINEAR)
            gl.glTexParameteri(self.target, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR)

    func set_wrap(wrap):
        gl.glBindTexture(self.target, self.id)
        mode := gl.GL_REPEAT
        if wrap == "clamp" or self.shape == "cube" or self.shape == "cube_array":
            mode = gl.GL_CLAMP_TO_EDGE
        elif wrap == "mirror":
            mode = gl.GL_MIRRORED_REPEAT
        gl.glTexParameteri(self.target, gl.GL_TEXTURE_WRAP_S, mode)
        gl.glTexParameteri(self.target, gl.GL_TEXTURE_WRAP_T, mode)
        if self.target != 0x0DE1:
            gl.glTexParameteri(self.target, gl.GL_TEXTURE_WRAP_R, mode)

    func bind(unit=0):
        gl.glActiveTexture(gl.GL_TEXTURE0 + unit)
        gl.glBindTexture(self.target, self.id)

    # Pixels RGBA8 d'un niveau relus depuis la carte (décompressés par le pilote) ; face : cubemap (0..5).
    func read_rgba(level=0, face=0):
        w := self.width >> level if (self.width >> level) > 0 else 1
        h := self.height >> level if (self.height >> level) > 0 else 1
        d := 1
        tgt := self.target
        if self.shape == "cube":
            tgt = gl.GL_TEXTURE_CUBE_MAP_POSITIVE_X + face
        elif self.shape == "2d_array":
            d = self.layers
        elif self.shape == "cube_array":
            d = self.layers * 6
        elif self.shape == "3d":
            d = self.depth >> level if (self.depth >> level) > 0 else 1
        b := ffi.Buffer(w * h * d * 4)
        gl.glBindTexture(self.target, self.id)
        gl.glPixelStorei(0x0D05, 1)                        # GL_PACK_ALIGNMENT
        gl.glGetTexImage(tgt, level, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, b.address())
        px := b.read_array("u8", w * h * d * 4)
        b.free()
        return px

    func delete():
        if self.id != 0:
            gl.delete("glDeleteTextures", self.id)
            self.id = 0

# Cubemap depuis 6 images RGBA8 [[largeur, hauteur, ffi.Buffer ou liste d'octets]...] dans l'ordre +X, -X, +Y, -Y,
# +Z, -Z (conventions OpenGL).
func cubemap_from_rgba(faces, filter="linear", mipmaps=true):
    if len(faces) != 6:
        raise("ValueError", "gl.textures : 6 faces attendues (+X, -X, +Y, -Y, +Z, -Z)")
    w := faces[0][0]
    h := faces[0][1]
    if w != h:
        raise("ValueError", "gl.textures : les faces d'une cubemap doivent être carrées")
    blob := ffi.Buffer(w * h * 4 * 6)
    k := 0
    for f in faces:
        if f[0] != w or f[1] != h:
            raise("ValueError", "gl.textures : faces de tailles différentes")
        if type(f[2]) == "list":
            blob.write_array("u8", f[2], k * w * h * 4)
        else:
            blob.copy_from(f[2], w * h * 4, k * w * h * 4)
        k += 1
    return CompressedTexture(w, h, _fmt("RGBA8"), [[w, h, blob, 1]], false, filter, "clamp", mipmaps,
                             {"target": "cube", "depth": 1, "layers": 0, "faces": 6})

# ---------------------------------------------------------------------------------------------------------------------
# Formats
# ---------------------------------------------------------------------------------------------------------------------

func _f(name, glfmt, block, ext, upload=0, bw=4, bh=4, typ=0x1401, bpp=4):
    return {"name": name, "gl": glfmt, "block": block, "ext": ext, "upload": upload, "bw": bw, "bh": bh,
            "type": typ, "bpp": bpp}

const _EXT_S3TC := ["GL_EXT_texture_compression_s3tc", "GL_EXT_texture_compression_dxt1"]
const _EXT_RGTC := ["GL_ARB_texture_compression_rgtc", "GL_EXT_texture_compression_rgtc"]
const _EXT_BPTC := ["GL_ARB_texture_compression_bptc"]
const _EXT_ETC := ["GL_ARB_ES3_compatibility"]
const _EXT_ASTC := ["GL_KHR_texture_compression_astc_ldr", "GL_KHR_texture_compression_astc_hdr"]
const _ASTC_DIMS := [[4, 4], [5, 4], [5, 5], [6, 5], [6, 6], [8, 5], [8, 6], [8, 8], [10, 5], [10, 6], [10, 8],
                     [10, 10], [12, 10], [12, 12]]

func _fmt(name):
    if name == "BC1":
        return _f("BC1", gl.GL_COMPRESSED_RGBA_S3TC_DXT1_EXT, 8, _EXT_S3TC)
    if name == "BC1_RGB":
        return _f("BC1_RGB", gl.GL_COMPRESSED_RGB_S3TC_DXT1_EXT, 8, _EXT_S3TC)
    if name == "BC2":
        return _f("BC2", gl.GL_COMPRESSED_RGBA_S3TC_DXT3_EXT, 16, _EXT_S3TC)
    if name == "BC3":
        return _f("BC3", gl.GL_COMPRESSED_RGBA_S3TC_DXT5_EXT, 16, _EXT_S3TC)
    if name == "BC4":
        return _f("BC4", gl.GL_COMPRESSED_RED_RGTC1, 8, _EXT_RGTC)
    if name == "BC4_SNORM":
        return _f("BC4_SNORM", 0x8DBC, 8, _EXT_RGTC)
    if name == "BC5":
        return _f("BC5", gl.GL_COMPRESSED_RG_RGTC2, 16, _EXT_RGTC)
    if name == "BC5_SNORM":
        return _f("BC5_SNORM", 0x8DBE, 16, _EXT_RGTC)
    if name == "BC6H_UF16":
        return _f("BC6H_UF16", 0x8E8F, 16, _EXT_BPTC)
    if name == "BC6H_SF16":
        return _f("BC6H_SF16", 0x8E8E, 16, _EXT_BPTC)
    if name == "BC7":
        return _f("BC7", gl.GL_COMPRESSED_RGBA_BPTC_UNORM, 16, _EXT_BPTC)
    if name == "BC7_SRGB":
        return _f("BC7_SRGB", gl.GL_COMPRESSED_SRGB_ALPHA_BPTC_UNORM, 16, _EXT_BPTC)
    if name == "ETC2_RGB8":
        return _f(name, gl.GL_COMPRESSED_RGB8_ETC2, 8, _EXT_ETC)
    if name == "ETC2_RGB8_SRGB":
        return _f(name, gl.GL_COMPRESSED_SRGB8_ETC2, 8, _EXT_ETC)
    if name == "ETC2_RGB8A1":
        return _f(name, gl.GL_COMPRESSED_RGB8_PUNCHTHROUGH_ALPHA1_ETC2, 8, _EXT_ETC)
    if name == "ETC2_RGB8A1_SRGB":
        return _f(name, gl.GL_COMPRESSED_SRGB8_PUNCHTHROUGH_ALPHA1_ETC2, 8, _EXT_ETC)
    if name == "ETC2_RGBA8":
        return _f(name, gl.GL_COMPRESSED_RGBA8_ETC2_EAC, 16, _EXT_ETC)
    if name == "ETC2_RGBA8_SRGB":
        return _f(name, gl.GL_COMPRESSED_SRGB8_ALPHA8_ETC2_EAC, 16, _EXT_ETC)
    if name == "EAC_R11":
        return _f(name, gl.GL_COMPRESSED_R11_EAC, 8, _EXT_ETC)
    if name == "EAC_R11_SNORM":
        return _f(name, gl.GL_COMPRESSED_SIGNED_R11_EAC, 8, _EXT_ETC)
    if name == "EAC_RG11":
        return _f(name, gl.GL_COMPRESSED_RG11_EAC, 16, _EXT_ETC)
    if name == "EAC_RG11_SNORM":
        return _f(name, gl.GL_COMPRESSED_SIGNED_RG11_EAC, 16, _EXT_ETC)
    if _str.starts_with(name, "ASTC_"):
        k := 0
        for dm in _ASTC_DIMS:
            tag := "ASTC_" + str(dm[0]) + "x" + str(dm[1])
            if name == tag:
                return _f(name, gl.GL_COMPRESSED_RGBA_ASTC_4x4 + k, 16, _EXT_ASTC, 0, dm[0], dm[1])
            if name == tag + "_SRGB":
                return _f(name, gl.GL_COMPRESSED_SRGB8_ALPHA8_ASTC_4x4 + k, 16, _EXT_ASTC, 0, dm[0], dm[1])
            k += 1
    if name == "RGBA8":
        return _f("RGBA8", gl.GL_RGBA8, 0, [], gl.GL_RGBA)
    if name == "BGRA8":
        return _f("BGRA8", gl.GL_RGBA8, 0, [], gl.GL_BGRA)
    if name == "RGBA16F":
        return _f("RGBA16F", gl.GL_RGBA16F, 0, [], gl.GL_RGBA, 1, 1, gl.GL_HALF_FLOAT, 8)
    if name == "RGBA32F":
        return _f("RGBA32F", gl.GL_RGBA32F, 0, [], gl.GL_RGBA, 1, 1, gl.GL_FLOAT, 16)
    raise("ValueError", "gl.textures : format " + str(name) + " non pris en charge")

# Taille d'une image (une face / couche / tranche) d'un niveau.
func _level_size(fmt, w, h):
    if fmt["block"] == 0:
        return w * h * fmt["bpp"]
    return ((w + fmt["bw"] - 1) // fmt["bw"]) * ((h + fmt["bh"] - 1) // fmt["bh"]) * fmt["block"]

func _gl_version():
    return gl.get_integer(0x821B) * 10 + gl.get_integer(0x821C)      # MAJOR / MINOR_VERSION

# Le pilote accepte-t-il ce format ? (RGTC de base depuis 3.0, BPTC depuis 4.2, ETC2 / EAC depuis 4.3)
func supported(fmt):
    if fmt["block"] == 0:
        return true
    n := fmt["name"]
    if _str.starts_with(n, "BC4") or _str.starts_with(n, "BC5"):
        return true
    if _str.starts_with(n, "BC6") or _str.starts_with(n, "BC7"):
        if _gl_version() >= 42:
            return true
    if _str.starts_with(n, "ETC") or _str.starts_with(n, "EAC"):
        if _gl_version() >= 43:
            return true
    for e in fmt["ext"]:
        if gl.has_extension(e):
            return true
    return false

func _u32(b, o):
    return b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)

func _u64(b, o):
    return _u32(b, o) | (_u32(b, o + 4) << 32)

func _buffer(data, o, n):
    if o + n > len(data):
        raise("ValueError", "gl.textures : fichier tronqué")
    b := ffi.Buffer(n if n > 0 else 1)
    if n > 0:
        b.write_array("u8", data[o:o + n])
    return b

func _mip(v, k):
    r := v >> k
    return r if r > 0 else 1

# Description commune (rendue par parse_dds / parse_ktx2) :
# {"format" (dict), "width", "height", "depth", "layers" (0 : pas un tableau), "faces" (1 ou 6),
#  "target" ("2d", "cube", "2d_array", "cube_array", "3d"), "supercompression" (0 aucune, 2 zstd, 3 zlib),
#  "levels" : [{"width", "height", "depth", "images" (couches x faces x tranches), "chunks" [[décalage, taille]...],
#  "length" (taille décompressée)}]}
func _shape(w, h, depth, layers, faces):
    target := "2d"
    if depth > 1:
        if layers > 0 or faces > 1:
            raise("ValueError", "gl.textures : tableaux de volumes non pris en charge")
        target = "3d"
    elif faces == 6:
        target = "cube_array" if layers > 0 else "cube"
        if w != h:
            raise("ValueError", "gl.textures : faces de cubemap non carrées")
    elif faces != 1:
        raise("ValueError", "gl.textures : nombre de faces invalide (" + str(faces) + ")")
    elif layers > 0:
        target = "2d_array"
    return target

# ---------------------------------------------------------------------------------------------------------------------
# DDS
# ---------------------------------------------------------------------------------------------------------------------

func _fourcc(b, o):
    return _str.byte_pack(b[o:o + 4])

const _DXGI := {71: "BC1", 72: "BC1", 74: "BC2", 75: "BC2", 77: "BC3", 78: "BC3", 80: "BC4", 81: "BC4_SNORM",
                83: "BC5", 84: "BC5_SNORM", 95: "BC6H_UF16", 96: "BC6H_SF16", 98: "BC7", 99: "BC7_SRGB",
                28: "RGBA8", 29: "RGBA8", 87: "BGRA8", 91: "BGRA8", 10: "RGBA16F", 2: "RGBA32F"}

func parse_dds(b):
    if len(b) < 128 or _fourcc(b, 0) != "DDS ":
        raise("ValueError", "gl.textures : signature DDS absente")
    h := _u32(b, 12)
    w := _u32(b, 16)
    depth := _u32(b, 24) if (_u32(b, 8) & 0x800000) != 0 else 1
    mips := _u32(b, 28)
    if mips == 0:
        mips = 1
    pf_flags := _u32(b, 80)
    cc := _fourcc(b, 84)
    caps2 := _u32(b, 112)
    faces := 1
    layers := 0
    if (caps2 & 0x200) != 0:
        if (caps2 & 0xFC00) != 0xFC00:
            raise("ValueError", "gl.textures : cubemap DDS partielle (moins de 6 faces) non prise en charge")
        faces = 6
    if (caps2 & 0x200000) == 0:
        depth = 1
    off := 128
    name := null
    if (pf_flags & 4) != 0:
        if cc == "DXT1":
            name = "BC1"
        elif cc == "DXT2" or cc == "DXT3":
            name = "BC2"
        elif cc == "DXT4" or cc == "DXT5":
            name = "BC3"
        elif cc == "ATI1" or cc == "BC4U":
            name = "BC4"
        elif cc == "BC4S":
            name = "BC4_SNORM"
        elif cc == "ATI2" or cc == "BC5U":
            name = "BC5"
        elif cc == "BC5S":
            name = "BC5_SNORM"
        elif _u32(b, 84) == 113:
            name = "RGBA16F"
        elif _u32(b, 84) == 116:
            name = "RGBA32F"
        elif cc == "DX10":
            if len(b) < 148:
                raise("ValueError", "gl.textures : en-tête DX10 tronqué")
            dx := _u32(b, 128)
            dim := _u32(b, 132)
            misc := _u32(b, 136)
            arr := _u32(b, 140)
            off = 148
            if not (dx in _DXGI):
                raise("ValueError", "gl.textures : format DXGI " + str(dx) + " non pris en charge")
            name = _DXGI[dx]
            if dim == 4:
                depth = _u32(b, 24) if _u32(b, 24) > 0 else 1
            else:
                depth = 1
            if (misc & 4) != 0:
                faces = 6
            if arr > 1:
                layers = arr
        else:
            raise("ValueError", "gl.textures : DDS « " + cc + " » non pris en charge")
    else:
        bits := _u32(b, 88)
        rm := _u32(b, 92)
        if bits != 32:
            raise("ValueError", "gl.textures : DDS non compressé : 32 bits par pixel attendus")
        name = "RGBA8" if rm == 0xFF else "BGRA8"
    fmt := _fmt(name)
    target := _shape(w, h, depth, layers, faces)
    # disposition DDS : pour chaque couche, pour chaque face, la chaîne complète des niveaux
    nl := layers if layers > 0 else 1
    levels := []
    k := 0
    while k < mips:
        append(levels, {"width": _mip(w, k), "height": _mip(h, k), "depth": _mip(depth, k), "chunks": [],
                        "images": nl * faces * _mip(depth, k), "length": 0})
        k += 1
    li := 0
    while li < nl:
        f := 0
        while f < faces:
            k = 0
            while k < mips:
                lv := levels[k]
                n := _level_size(fmt, lv["width"], lv["height"]) * lv["depth"]
                append(lv["chunks"], [off, n])
                lv["length"] = lv["length"] + n
                off += n
                k += 1
            f += 1
        li += 1
    if off > len(b):
        raise("ValueError", "gl.textures : fichier DDS tronqué")
    return {"format": fmt, "width": w, "height": h, "depth": depth, "layers": layers, "faces": faces,
            "target": target, "levels": levels, "supercompression": 0}

# ---------------------------------------------------------------------------------------------------------------------
# KTX2
# ---------------------------------------------------------------------------------------------------------------------

const _KTX2_ID := [171, 75, 84, 88, 32, 50, 48, 187, 13, 10, 26, 10]

func _vk_name(vk):
    tab := {131: "BC1_RGB", 132: "BC1_RGB", 133: "BC1", 134: "BC1", 135: "BC2", 136: "BC2", 137: "BC3", 138: "BC3",
            139: "BC4", 140: "BC4_SNORM", 141: "BC5", 142: "BC5_SNORM", 143: "BC6H_UF16", 144: "BC6H_SF16",
            145: "BC7", 146: "BC7_SRGB", 147: "ETC2_RGB8", 148: "ETC2_RGB8_SRGB", 149: "ETC2_RGB8A1",
            150: "ETC2_RGB8A1_SRGB", 151: "ETC2_RGBA8", 152: "ETC2_RGBA8_SRGB", 153: "EAC_R11", 154: "EAC_R11_SNORM",
            155: "EAC_RG11", 156: "EAC_RG11_SNORM", 37: "RGBA8", 43: "RGBA8", 44: "BGRA8", 50: "BGRA8",
            97: "RGBA16F", 109: "RGBA32F"}
    if vk in tab:
        return tab[vk]
    if vk >= 157 and vk <= 184:
        dm := _ASTC_DIMS[(vk - 157) // 2]
        return "ASTC_" + str(dm[0]) + "x" + str(dm[1]) + ("_SRGB" if (vk - 157) % 2 == 1 else "")
    if vk >= 1000066000 and vk <= 1000066013:
        dm := _ASTC_DIMS[vk - 1000066000]
        raise("ValueError", "gl.textures : ASTC HDR " + str(dm[0]) + "x" + str(dm[1]) + " (SFLOAT) non pris en charge")
    raise("ValueError", "gl.textures : format Vulkan " + str(vk) + " non pris en charge")

func parse_ktx2(b):
    if len(b) < 80 or b[0:12] != _KTX2_ID:
        raise("ValueError", "gl.textures : signature KTX2 absente")
    vk := _u32(b, 12)
    w := _u32(b, 20)
    h := _u32(b, 24)
    if h == 0:
        h = 1
    depth := _u32(b, 28)
    if depth == 0:
        depth = 1
    layers := _u32(b, 32)
    faces := _u32(b, 36)
    if faces == 0:
        faces = 1
    nlev := _u32(b, 40)
    if nlev == 0:
        nlev = 1
    sc := _u32(b, 44)
    if vk == 0 or sc == 1:
        raise("ValueError", "gl.textures : KTX2 Basis Universal (BasisLZ / ETC1S / UASTC) non pris en charge : ce format doit être transcodé (BC7, ASTC, ETC2) par le transcodeur Basis, non inclus ; convertir le fichier à l'avance (toktx, basisu) en BC7, ASTC ou ETC2")
    if sc != 0 and sc != 2 and sc != 3:
        raise("ValueError", "gl.textures : supercompression KTX2 " + str(sc) + " non prise en charge (aucune, zstd ou zlib)")
    fmt := _fmt(_vk_name(vk))
    target := _shape(w, h, depth, layers, faces)
    if 80 + 24 * nlev > len(b):
        raise("ValueError", "gl.textures : index des niveaux KTX2 tronqué")
    levels := []
    k := 0
    while k < nlev:
        o := 80 + 24 * k
        lw := _mip(w, k)
        lh := _mip(h, k)
        ld := _mip(depth, k)
        n := _u64(b, o + 8)
        ulen := _u64(b, o + 16) if sc != 0 else n
        imgs := (layers if layers > 0 else 1) * faces * ld
        expect := _level_size(fmt, lw, lh) * imgs
        if ulen != expect:
            raise("ValueError", "gl.textures : taille du niveau " + str(k) + " incohérente (" + str(ulen) + " au lieu de " + str(expect) + ")")
        if _u64(b, o) + n > len(b):
            raise("ValueError", "gl.textures : fichier KTX2 tronqué")
        append(levels, {"width": lw, "height": lh, "depth": ld, "chunks": [[_u64(b, o), n]], "images": imgs,
                        "length": ulen})
        k += 1
    return {"format": fmt, "width": w, "height": h, "depth": depth, "layers": layers, "faces": faces,
            "target": target, "levels": levels, "supercompression": sc}

# ---------------------------------------------------------------------------------------------------------------------
# Décodage BC1 / BC2 / BC3 par le processeur (pilote sans S3TC)
# ---------------------------------------------------------------------------------------------------------------------

func _rgb565(c):
    r := (c >> 11) & 31
    g := (c >> 5) & 63
    bb := c & 31
    return [(r * 527 + 23) >> 6, (g * 259 + 33) >> 6, (bb * 527 + 23) >> 6]

func decode_bc(fmt, data, o, w, h):
    out := [0] * (w * h * 4)
    bs := fmt["block"]
    bw := (w + 3) // 4
    bh := (h + 3) // 4
    by := 0
    while by < bh:
        bx := 0
        while bx < bw:
            p := o + (by * bw + bx) * bs
            co := p + 8 if bs == 16 else p
            c0 := data[co] | (data[co + 1] << 8)
            c1 := data[co + 2] | (data[co + 3] << 8)
            a := _rgb565(c0)
            bcol := _rgb565(c1)
            pal := [a + [255], bcol + [255]]
            if c0 > c1 or bs == 16:
                append(pal, [(2 * a[0] + bcol[0]) // 3, (2 * a[1] + bcol[1]) // 3, (2 * a[2] + bcol[2]) // 3, 255])
                append(pal, [(a[0] + 2 * bcol[0]) // 3, (a[1] + 2 * bcol[1]) // 3, (a[2] + 2 * bcol[2]) // 3, 255])
            else:
                append(pal, [(a[0] + bcol[0]) // 2, (a[1] + bcol[1]) // 2, (a[2] + bcol[2]) // 2, 255])
                append(pal, [0, 0, 0, 0])
            idx := _u32(data, co + 4)
            alphas := null
            if fmt["name"] == "BC3":
                a0 := data[p]
                a1 := data[p + 1]
                ap := [a0, a1]
                if a0 > a1:
                    j := 1
                    while j < 7:
                        append(ap, ((7 - j) * a0 + j * a1) // 7)
                        j += 1
                else:
                    j := 1
                    while j < 5:
                        append(ap, ((5 - j) * a0 + j * a1) // 5)
                        j += 1
                    append(ap, 0)
                    append(ap, 255)
                bits := _u32(data, p + 2) | (data[p + 6] << 32) | (data[p + 7] << 40)
                alphas = [ap[(bits >> (3 * k)) & 7] for k in 0..16]
            elif fmt["name"] == "BC2":
                alphas = [((data[p + (k // 2)] >> (4 * (k % 2))) & 15) * 17 for k in 0..16]
            k := 0
            while k < 16:
                x := bx * 4 + (k % 4)
                y := by * 4 + (k // 4)
                if x < w and y < h:
                    c := pal[(idx >> (2 * k)) & 3]
                    q := 4 * (y * w + x)
                    out[q] = c[0]
                    out[q + 1] = c[1]
                    out[q + 2] = c[2]
                    out[q + 3] = alphas[k] if alphas != null else c[3]
                k += 1
            bx += 1
        by += 1
    return out

# ---------------------------------------------------------------------------------------------------------------------
# Création des textures
# ---------------------------------------------------------------------------------------------------------------------

# Octets d'un niveau (liste) ou tampon prêt, décompressé si besoin.
func _level_buffer(p, lv, data):
    sc := p["supercompression"]
    if sc == 0:
        if len(lv["chunks"]) == 1:
            c := lv["chunks"][0]
            return _buffer(data, c[0], c[1])
        b := ffi.Buffer(lv["length"])
        o := 0
        for c in lv["chunks"]:
            if c[0] + c[1] > len(data):
                raise("ValueError", "gl.textures : fichier tronqué")
            b.write_array("u8", data[c[0]:c[0] + c[1]], o)
            o += c[1]
        return b
    c := lv["chunks"][0]
    if sc == 3:
        raw := _z.decompress(data[c[0]:c[0] + c[1]], "zlib")
        if len(raw) != lv["length"]:
            raise("ValueError", "gl.textures : niveau zlib de taille incorrecte")
        return _buffer(raw, 0, len(raw))
    src := _buffer(data, c[0], c[1])
    out := null
    try:
        out = _z.zstd_decompress_buffer(src, 0, c[1], lv["length"])
    catch e:
        src.free()
        raise("ValueError", "gl.textures : niveau zstd invalide (" + str(e) + ")")
    src.free()
    return out

func _make(p, data, filter, wrap, mipmaps):
    fmt := p["format"]
    use_gpu := supported(fmt)
    soft := fmt["name"] == "BC1" or fmt["name"] == "BC1_RGB" or fmt["name"] == "BC2" or fmt["name"] == "BC3"
    if not use_gpu and not soft:
        raise("ValueError", "gl.textures : le pilote ne gère pas " + fmt["name"] + " (extension absente)")
    if (p["target"] == "cube_array") and _gl_version() < 40 and not gl.has_extension("GL_ARB_texture_cube_map_array"):
        raise("ValueError", "gl.textures : tableaux de cubemaps : OpenGL 4.0 ou GL_ARB_texture_cube_map_array requis")
    levels := []
    for lv in p["levels"]:
        b := _level_buffer(p, lv, data)
        if not use_gpu:
            # décodage image par image (faces, couches, tranches)
            isz := _level_size(fmt, lv["width"], lv["height"])
            raw := b.read_array("u8", b.size())
            b.free()
            out := ffi.Buffer(lv["width"] * lv["height"] * 4 * lv["images"])
            i := 0
            while i < lv["images"]:
                px := decode_bc(fmt, raw, i * isz, lv["width"], lv["height"])
                out.write_array("u8", px, i * lv["width"] * lv["height"] * 4)
                i += 1
            b = out
        d := lv["depth"]
        if p["target"] == "2d_array":
            d = p["layers"]
        elif p["target"] == "cube_array":
            d = p["layers"] * 6
        append(levels, [lv["width"], lv["height"], b, d])
    if not use_gpu:
        fmt = _fmt("RGBA8")
    shape := {"target": p["target"], "depth": p["depth"], "layers": p["layers"], "faces": p["faces"]}
    return CompressedTexture(p["width"], p["height"], fmt, levels, use_gpu and fmt["block"] > 0, filter, wrap, mipmaps, shape)

func dds_texture(data, filter="linear", wrap="repeat", mipmaps=true):
    return _make(parse_dds(data), data, filter, wrap, mipmaps)

func ktx2_texture(data, filter="linear", wrap="repeat", mipmaps=true):
    return _make(parse_ktx2(data), data, filter, wrap, mipmaps)

func load_dds(path, filter="linear", wrap="repeat", mipmaps=true):
    return dds_texture(io.read_bytes(path), filter, wrap, mipmaps)

func load_ktx2(path, filter="linear", wrap="repeat", mipmaps=true):
    return ktx2_texture(io.read_bytes(path), filter, wrap, mipmaps)

func parse(b):
    return parse_ktx2(b) if len(b) >= 4 and b[0] == 171 else parse_dds(b)

# Informations d'un fichier DDS / KTX2 sans le charger sur la carte.
func info(path):
    p := parse(io.read_bytes(path))
    return {"format": p["format"]["name"], "width": p["width"], "height": p["height"], "depth": p["depth"],
            "layers": p["layers"], "faces": p["faces"], "target": p["target"], "levels": len(p["levels"]),
            "compressed": p["format"]["block"] > 0, "supercompression": ["none", "basislz", "zstd", "zlib"][p["supercompression"]]}
