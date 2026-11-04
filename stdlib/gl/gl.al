# ALEX STANDARD LIBRARY — gl
#
# OpenGL 3.3 (profil core) pour les jeux 2D et 3D, rendu par la CARTE GRAPHIQUE. Les fonctions gardent leur nom C
# (glClear, glDrawElements...) et sont appelées par ffi après la création d'un contexte par gl.window (WGL sous
# Windows, GLX sous Linux). Les adresses sont chargées une fois (wglGetProcAddress / glXGetProcAddressARB).
#
#   use gl
#   use gl.window as glw
#   w := glw.Window("Mon jeu", 1280, 720)               # fenêtre + contexte OpenGL 3.3, VSync
#   while w.is_open():
#       for e in w.poll():
#           if e["type"] == "key_down" and e["key"] == "escape":
#               w.close()
#       gl.glClearColor(0.1, 0.12, 0.2, 1.0)
#       gl.glClear(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT)
#       w.swap()
#
# Le moteur de rendu de haut niveau (shaders, maillages, textures, lumières, sprites 2D par lots) est gl.render.
#
# TABLEAUX : les fonctions qui attendent un pointeur reçoivent une adresse (int) : celle d'un ffi.Buffer
# (buf.address()) ou 0. Aides : gl.f32_buffer(liste), gl.u32_buffer(liste), gl.u16_buffer(liste), gl.gen(fonction),
# gl.shader_source(shader, texte), gl.uniform_matrix4(location, mat4).
#
# Erreurs : IoError (bibliothèque OpenGL absente), RuntimeError (contexte absent, fonction non chargée,
#   compilation de shader).

from core use len, type
from collections use append
use ffi
use os as _os
use string as _s

# ---------------------------------------------------------------------------------------------------------------------
# Constantes OpenGL (sous-ensemble utile au profil core 3.3)
# ---------------------------------------------------------------------------------------------------------------------

const GL_FALSE := 0
const GL_TRUE := 1
const GL_NONE := 0
const GL_ZERO := 0
const GL_ONE := 1

const GL_DEPTH_BUFFER_BIT := 0x00000100
const GL_STENCIL_BUFFER_BIT := 0x00000400
const GL_COLOR_BUFFER_BIT := 0x00004000

const GL_POINTS := 0x0000
const GL_LINES := 0x0001
const GL_LINE_LOOP := 0x0002
const GL_LINE_STRIP := 0x0003
const GL_TRIANGLES := 0x0004
const GL_TRIANGLE_STRIP := 0x0005
const GL_TRIANGLE_FAN := 0x0006

const GL_NEVER := 0x0200
const GL_LESS := 0x0201
const GL_EQUAL := 0x0202
const GL_LEQUAL := 0x0203
const GL_GREATER := 0x0204
const GL_NOTEQUAL := 0x0205
const GL_GEQUAL := 0x0206
const GL_ALWAYS := 0x0207

const GL_SRC_COLOR := 0x0300
const GL_ONE_MINUS_SRC_COLOR := 0x0301
const GL_SRC_ALPHA := 0x0302
const GL_ONE_MINUS_SRC_ALPHA := 0x0303
const GL_DST_ALPHA := 0x0304
const GL_ONE_MINUS_DST_ALPHA := 0x0305
const GL_DST_COLOR := 0x0306
const GL_ONE_MINUS_DST_COLOR := 0x0307

const GL_FRONT := 0x0404
const GL_BACK := 0x0405
const GL_FRONT_AND_BACK := 0x0408
const GL_CW := 0x0900
const GL_CCW := 0x0901

const GL_CULL_FACE := 0x0B44
const GL_DEPTH_TEST := 0x0B71
const GL_STENCIL_TEST := 0x0B90
const GL_BLEND := 0x0BE2
const GL_SCISSOR_TEST := 0x0C11
const GL_MULTISAMPLE := 0x809D
const GL_FRAMEBUFFER_SRGB := 0x8DB9

const GL_LINE := 0x1B01
const GL_FILL := 0x1B02

const GL_NO_ERROR := 0
const GL_INVALID_ENUM := 0x0500
const GL_INVALID_VALUE := 0x0501
const GL_INVALID_OPERATION := 0x0502
const GL_OUT_OF_MEMORY := 0x0505
const GL_INVALID_FRAMEBUFFER_OPERATION := 0x0506

const GL_VENDOR := 0x1F00
const GL_RENDERER := 0x1F01
const GL_VERSION := 0x1F02
const GL_SHADING_LANGUAGE_VERSION := 0x8B8C
const GL_MAX_TEXTURE_SIZE := 0x0D33
const GL_VIEWPORT := 0x0BA2

const GL_BYTE := 0x1400
const GL_UNSIGNED_BYTE := 0x1401
const GL_SHORT := 0x1402
const GL_UNSIGNED_SHORT := 0x1403
const GL_INT := 0x1404
const GL_UNSIGNED_INT := 0x1405
const GL_FLOAT := 0x1406

const GL_RED := 0x1903
const GL_RGB := 0x1907
const GL_RGBA := 0x1908
const GL_BGRA := 0x80E1
const GL_R8 := 0x8229
const GL_RG := 0x8227
const GL_RGB8 := 0x8051
const GL_RGBA8 := 0x8058
const GL_SRGB8_ALPHA8 := 0x8C43
const GL_RGBA16F := 0x881A
const GL_RGBA32F := 0x8814
const GL_HALF_FLOAT := 0x140B
const GL_EXTENSIONS := 0x1F03
const GL_NUM_EXTENSIONS := 0x821D
const GL_TEXTURE_BASE_LEVEL := 0x813C
const GL_TEXTURE_MAX_LEVEL := 0x813D
const GL_COMPRESSED_RGBA_S3TC_DXT1_EXT := 0x83F1
const GL_COMPRESSED_RGBA_S3TC_DXT3_EXT := 0x83F2
const GL_COMPRESSED_RGBA_S3TC_DXT5_EXT := 0x83F3
const GL_COMPRESSED_RGB_S3TC_DXT1_EXT := 0x83F0
const GL_COMPRESSED_RED_RGTC1 := 0x8DBB
const GL_COMPRESSED_RG_RGTC2 := 0x8DBD
const GL_COMPRESSED_RGBA_BPTC_UNORM := 0x8E8C
const GL_COMPRESSED_SRGB_ALPHA_BPTC_UNORM := 0x8E8D
const GL_DEPTH_COMPONENT := 0x1902
const GL_DEPTH_COMPONENT24 := 0x81A6
const GL_DEPTH24_STENCIL8 := 0x88F0
const GL_DEPTH_STENCIL := 0x84F9
const GL_UNSIGNED_INT_24_8 := 0x84FA

const GL_TEXTURE_2D := 0x0DE1
const GL_TEXTURE_CUBE_MAP := 0x8513
const GL_TEXTURE_CUBE_MAP_POSITIVE_X := 0x8515
const GL_TEXTURE_CUBE_MAP_SEAMLESS := 0x884F
const GL_TEXTURE_CUBE_MAP_ARRAY := 0x9009
const GL_TEXTURE_2D_ARRAY := 0x8C1A
const GL_TEXTURE_3D := 0x806F
const GL_TEXTURE_WRAP_R := 0x8072
# ETC2 / EAC (cœur OpenGL 4.3, GL_ARB_ES3_compatibility) et ASTC (GL_KHR_texture_compression_astc_ldr)
const GL_COMPRESSED_R11_EAC := 0x9270
const GL_COMPRESSED_SIGNED_R11_EAC := 0x9271
const GL_COMPRESSED_RG11_EAC := 0x9272
const GL_COMPRESSED_SIGNED_RG11_EAC := 0x9273
const GL_COMPRESSED_RGB8_ETC2 := 0x9274
const GL_COMPRESSED_SRGB8_ETC2 := 0x9275
const GL_COMPRESSED_RGB8_PUNCHTHROUGH_ALPHA1_ETC2 := 0x9276
const GL_COMPRESSED_SRGB8_PUNCHTHROUGH_ALPHA1_ETC2 := 0x9277
const GL_COMPRESSED_RGBA8_ETC2_EAC := 0x9278
const GL_COMPRESSED_SRGB8_ALPHA8_ETC2_EAC := 0x9279
const GL_COMPRESSED_RGBA_ASTC_4x4 := 0x93B0
const GL_COMPRESSED_SRGB8_ALPHA8_ASTC_4x4 := 0x93D0
const GL_TEXTURE_MAG_FILTER := 0x2800
const GL_TEXTURE_MIN_FILTER := 0x2801
const GL_TEXTURE_WRAP_S := 0x2802
const GL_TEXTURE_WRAP_T := 0x2803
const GL_NEAREST := 0x2600
const GL_LINEAR := 0x2601
const GL_NEAREST_MIPMAP_NEAREST := 0x2700
const GL_LINEAR_MIPMAP_NEAREST := 0x2701
const GL_NEAREST_MIPMAP_LINEAR := 0x2702
const GL_LINEAR_MIPMAP_LINEAR := 0x2703
const GL_REPEAT := 0x2901
const GL_CLAMP_TO_EDGE := 0x812F
const GL_MIRRORED_REPEAT := 0x8370
const GL_TEXTURE0 := 0x84C0
const GL_UNPACK_ALIGNMENT := 0x0CF5
const GL_PACK_ALIGNMENT := 0x0D05

const GL_ARRAY_BUFFER := 0x8892
const GL_ELEMENT_ARRAY_BUFFER := 0x8893
const GL_UNIFORM_BUFFER := 0x8A11
const GL_STREAM_DRAW := 0x88E0
const GL_STATIC_DRAW := 0x88E4
const GL_DYNAMIC_DRAW := 0x88E8

const GL_FRAGMENT_SHADER := 0x8B30
const GL_VERTEX_SHADER := 0x8B31
const GL_GEOMETRY_SHADER := 0x8DD9
const GL_COMPILE_STATUS := 0x8B81
const GL_LINK_STATUS := 0x8B82
const GL_INFO_LOG_LENGTH := 0x8B84

const GL_FRAMEBUFFER := 0x8D40
const GL_READ_FRAMEBUFFER := 0x8CA8
const GL_DRAW_FRAMEBUFFER := 0x8CA9
const GL_RENDERBUFFER := 0x8D41
const GL_COLOR_ATTACHMENT0 := 0x8CE0
const GL_DEPTH_ATTACHMENT := 0x8D00
const GL_DEPTH_STENCIL_ATTACHMENT := 0x821A
const GL_FRAMEBUFFER_COMPLETE := 0x8CD5

# ---------------------------------------------------------------------------------------------------------------------
# Table des fonctions : [nom, types des arguments, type de retour] (types de ffi)
# ---------------------------------------------------------------------------------------------------------------------

const FUNCTIONS := [
    ["glGetError", [], "u32"],
    ["glGetString", ["u32"], "cstr"],
    ["glGetIntegerv", ["u32", "ptr"], "void"],
    ["glFinish", [], "void"],
    ["glFlush", [], "void"],
    ["glViewport", ["i32", "i32", "i32", "i32"], "void"],
    ["glScissor", ["i32", "i32", "i32", "i32"], "void"],
    ["glClearColor", ["f32", "f32", "f32", "f32"], "void"],
    ["glClearDepth", ["f64"], "void"],
    ["glClear", ["u32"], "void"],
    ["glEnable", ["u32"], "void"],
    ["glDisable", ["u32"], "void"],
    ["glBlendFunc", ["u32", "u32"], "void"],
    ["glBlendFuncSeparate", ["u32", "u32", "u32", "u32"], "void"],
    ["glDepthFunc", ["u32"], "void"],
    ["glDepthMask", ["u8"], "void"],
    ["glColorMask", ["u8", "u8", "u8", "u8"], "void"],
    ["glCullFace", ["u32"], "void"],
    ["glFrontFace", ["u32"], "void"],
    ["glPolygonMode", ["u32", "u32"], "void"],
    ["glLineWidth", ["f32"], "void"],
    ["glPixelStorei", ["u32", "i32"], "void"],
    ["glReadPixels", ["i32", "i32", "i32", "i32", "u32", "u32", "ptr"], "void"],
    ["glGenBuffers", ["i32", "ptr"], "void"],
    ["glDeleteBuffers", ["i32", "ptr"], "void"],
    ["glBindBuffer", ["u32", "u32"], "void"],
    ["glBufferData", ["u32", "i64", "ptr", "u32"], "void"],
    ["glBufferSubData", ["u32", "i64", "i64", "ptr"], "void"],
    ["glBindBufferBase", ["u32", "u32", "u32"], "void"],
    ["glGenVertexArrays", ["i32", "ptr"], "void"],
    ["glDeleteVertexArrays", ["i32", "ptr"], "void"],
    ["glBindVertexArray", ["u32"], "void"],
    ["glEnableVertexAttribArray", ["u32"], "void"],
    ["glDisableVertexAttribArray", ["u32"], "void"],
    ["glVertexAttribPointer", ["u32", "i32", "u32", "u8", "i32", "i64"], "void"],
    ["glVertexAttribDivisor", ["u32", "u32"], "void"],
    ["glCreateShader", ["u32"], "u32"],
    ["glShaderSource", ["u32", "i32", "ptr", "ptr"], "void"],
    ["glCompileShader", ["u32"], "void"],
    ["glGetShaderiv", ["u32", "u32", "ptr"], "void"],
    ["glGetShaderInfoLog", ["u32", "i32", "ptr", "ptr"], "void"],
    ["glDeleteShader", ["u32"], "void"],
    ["glCreateProgram", [], "u32"],
    ["glAttachShader", ["u32", "u32"], "void"],
    ["glBindAttribLocation", ["u32", "u32", "cstr"], "void"],
    ["glLinkProgram", ["u32"], "void"],
    ["glGetProgramiv", ["u32", "u32", "ptr"], "void"],
    ["glGetProgramInfoLog", ["u32", "i32", "ptr", "ptr"], "void"],
    ["glUseProgram", ["u32"], "void"],
    ["glDeleteProgram", ["u32"], "void"],
    ["glGetUniformLocation", ["u32", "cstr"], "i32"],
    ["glGetUniformBlockIndex", ["u32", "cstr"], "u32"],
    ["glUniformBlockBinding", ["u32", "u32", "u32"], "void"],
    ["glUniform1i", ["i32", "i32"], "void"],
    ["glUniform1f", ["i32", "f32"], "void"],
    ["glUniform2f", ["i32", "f32", "f32"], "void"],
    ["glUniform3f", ["i32", "f32", "f32", "f32"], "void"],
    ["glUniform4f", ["i32", "f32", "f32", "f32", "f32"], "void"],
    ["glUniform1fv", ["i32", "i32", "ptr"], "void"],
    ["glUniform3fv", ["i32", "i32", "ptr"], "void"],
    ["glUniform4fv", ["i32", "i32", "ptr"], "void"],
    ["glUniformMatrix3fv", ["i32", "i32", "u8", "ptr"], "void"],
    ["glUniformMatrix4fv", ["i32", "i32", "u8", "ptr"], "void"],
    ["glGenTextures", ["i32", "ptr"], "void"],
    ["glDeleteTextures", ["i32", "ptr"], "void"],
    ["glBindTexture", ["u32", "u32"], "void"],
    ["glActiveTexture", ["u32"], "void"],
    ["glTexImage2D", ["u32", "i32", "i32", "i32", "i32", "i32", "u32", "u32", "ptr"], "void"],
    ["glTexSubImage2D", ["u32", "i32", "i32", "i32", "i32", "i32", "u32", "u32", "ptr"], "void"],
    ["glTexParameteri", ["u32", "u32", "i32"], "void"],
    ["glCompressedTexImage2D", ["u32", "i32", "u32", "i32", "i32", "i32", "i32", "ptr"], "void"],
    ["glGetTexImage", ["u32", "i32", "u32", "u32", "ptr"], "void"],
    ["glTexImage3D", ["u32", "i32", "i32", "i32", "i32", "i32", "i32", "u32", "u32", "ptr"], "void"],
    ["glCompressedTexImage3D", ["u32", "i32", "u32", "i32", "i32", "i32", "i32", "i32", "ptr"], "void"],
    ["glGetStringi", ["u32", "u32"], "cstr"],
    ["glGenerateMipmap", ["u32"], "void"],
    ["glDrawArrays", ["u32", "i32", "i32"], "void"],
    ["glDrawElements", ["u32", "i32", "u32", "i64"], "void"],
    ["glDrawArraysInstanced", ["u32", "i32", "i32", "i32"], "void"],
    ["glDrawElementsInstanced", ["u32", "i32", "u32", "i64", "i32"], "void"],
    ["glGenFramebuffers", ["i32", "ptr"], "void"],
    ["glDeleteFramebuffers", ["i32", "ptr"], "void"],
    ["glBindFramebuffer", ["u32", "u32"], "void"],
    ["glFramebufferTexture2D", ["u32", "u32", "u32", "u32", "i32"], "void"],
    ["glCheckFramebufferStatus", ["u32"], "u32"],
    ["glGenRenderbuffers", ["i32", "ptr"], "void"],
    ["glDeleteRenderbuffers", ["i32", "ptr"], "void"],
    ["glBindRenderbuffer", ["u32", "u32"], "void"],
    ["glRenderbufferStorage", ["u32", "u32", "i32", "i32"], "void"],
    ["glFramebufferRenderbuffer", ["u32", "u32", "u32", "u32"], "void"],
    ["glBlitFramebuffer", ["i32", "i32", "i32", "i32", "i32", "i32", "i32", "i32", "u32", "u32"], "void"],
]

# État : [0] fonction de chargement (nom -> adresse), [1] dict nom -> ffi.Function, [2] noms absents, [3] contexte prêt
_state := [null, {}, [], false]

# Appelée par gl.window quand un contexte est courant : `resolve(nom)` rend l'adresse (0 si absente).
func _install(resolve):
    _state[0] = resolve
    fns := {}
    missing := []
    for f in FUNCTIONS:
        addr := resolve(f[0])
        if addr != 0:
            fns[f[0]] = ffi.function_at(addr, f[0], f[1], f[2])
        else:
            append(missing, f[0])
    _state[1] = fns
    _state[2] = missing
    _state[3] = true
    return missing

func _uninstall():
    _state[1] = {}
    _state[3] = false

# Vrai si un contexte OpenGL a été créé et ses fonctions chargées.
func ready():
    return _state[3]

# Noms des fonctions de la table absentes du pilote.
func missing_functions():
    return _state[2]

# Fonction liée par son nom C (RuntimeError si absente).
func fn(name):
    fns := _state[1]
    if name in fns:
        return fns[name]
    if not _state[3]:
        raise("RuntimeError", "gl." + name + " : aucun contexte OpenGL (créer d'abord une gl.window.Window)")
    raise("RuntimeError", "gl." + name + " : fonction absente du pilote OpenGL")

# Charge une fonction d'extension hors table : `gl.load("glDebugMessageInsert", ["u32", ...], "void")`.
func load(name, arg_types, ret_type):
    if _state[0] == null:
        raise("RuntimeError", "gl.load : aucun contexte OpenGL")
    addr := _state[0](name)
    if addr == 0:
        raise("RuntimeError", "gl.load : '" + name + "' absente du pilote")
    f := ffi.function_at(addr, name, arg_types, ret_type)
    _state[1][name] = f
    return f

func _c(name, args):
    return fn(name).call(args)

# ---------------------------------------------------------------------------------------------------------------------
# Fonctions OpenGL (noms C)
# ---------------------------------------------------------------------------------------------------------------------

func glGetError():
    return _c("glGetError", [])
func glGetString(name):
    return _c("glGetString", [name])
func glGetIntegerv(pname, ptr):
    _c("glGetIntegerv", [pname, ptr])
func glFinish():
    _c("glFinish", [])
func glFlush():
    _c("glFlush", [])
func glViewport(x, y, w, h):
    _c("glViewport", [x, y, w, h])
func glScissor(x, y, w, h):
    _c("glScissor", [x, y, w, h])
func glClearColor(r, g, b, a):
    _c("glClearColor", [r, g, b, a])
func glClearDepth(d):
    _c("glClearDepth", [d])
func glClear(mask):
    _c("glClear", [mask])
func glEnable(cap):
    _c("glEnable", [cap])
func glDisable(cap):
    _c("glDisable", [cap])
func glBlendFunc(s, d):
    _c("glBlendFunc", [s, d])
func glBlendFuncSeparate(sr, dr, sa, da):
    _c("glBlendFuncSeparate", [sr, dr, sa, da])
func glDepthFunc(f):
    _c("glDepthFunc", [f])
func glDepthMask(flag):
    _c("glDepthMask", [1 if flag else 0])
func glColorMask(r, g, b, a):
    _c("glColorMask", [1 if r else 0, 1 if g else 0, 1 if b else 0, 1 if a else 0])
func glCullFace(m):
    _c("glCullFace", [m])
func glFrontFace(m):
    _c("glFrontFace", [m])
func glPolygonMode(face, mode):
    _c("glPolygonMode", [face, mode])
func glLineWidth(w):
    _c("glLineWidth", [w])
func glPixelStorei(p, v):
    _c("glPixelStorei", [p, v])
func glReadPixels(x, y, w, h, fmt, typ, ptr):
    _c("glReadPixels", [x, y, w, h, fmt, typ, ptr])
func glGenBuffers(n, ptr):
    _c("glGenBuffers", [n, ptr])
func glDeleteBuffers(n, ptr):
    _c("glDeleteBuffers", [n, ptr])
func glBindBuffer(target, buf):
    _c("glBindBuffer", [target, buf])
func glBufferData(target, size, ptr, usage):
    _c("glBufferData", [target, size, ptr, usage])
func glBufferSubData(target, offset, size, ptr):
    _c("glBufferSubData", [target, offset, size, ptr])
func glBindBufferBase(target, index, buf):
    _c("glBindBufferBase", [target, index, buf])
func glGenVertexArrays(n, ptr):
    _c("glGenVertexArrays", [n, ptr])
func glDeleteVertexArrays(n, ptr):
    _c("glDeleteVertexArrays", [n, ptr])
func glBindVertexArray(vao):
    _c("glBindVertexArray", [vao])
func glEnableVertexAttribArray(i):
    _c("glEnableVertexAttribArray", [i])
func glDisableVertexAttribArray(i):
    _c("glDisableVertexAttribArray", [i])
func glVertexAttribPointer(i, size, typ, normalized, stride, offset):
    _c("glVertexAttribPointer", [i, size, typ, 1 if normalized else 0, stride, offset])
func glVertexAttribDivisor(i, d):
    _c("glVertexAttribDivisor", [i, d])
func glCreateShader(kind):
    return _c("glCreateShader", [kind])
func glShaderSource(sh, count, strings_ptr, lengths_ptr):
    _c("glShaderSource", [sh, count, strings_ptr, lengths_ptr])
func glCompileShader(sh):
    _c("glCompileShader", [sh])
func glGetShaderiv(sh, pname, ptr):
    _c("glGetShaderiv", [sh, pname, ptr])
func glGetShaderInfoLog(sh, size, len_ptr, ptr):
    _c("glGetShaderInfoLog", [sh, size, len_ptr, ptr])
func glDeleteShader(sh):
    _c("glDeleteShader", [sh])
func glCreateProgram():
    return _c("glCreateProgram", [])
func glAttachShader(p, sh):
    _c("glAttachShader", [p, sh])
func glBindAttribLocation(p, index, name):
    _c("glBindAttribLocation", [p, index, name])
func glLinkProgram(p):
    _c("glLinkProgram", [p])
func glGetProgramiv(p, pname, ptr):
    _c("glGetProgramiv", [p, pname, ptr])
func glGetProgramInfoLog(p, size, len_ptr, ptr):
    _c("glGetProgramInfoLog", [p, size, len_ptr, ptr])
func glUseProgram(p):
    _c("glUseProgram", [p])
func glDeleteProgram(p):
    _c("glDeleteProgram", [p])
func glGetUniformLocation(p, name):
    return _c("glGetUniformLocation", [p, name])
func glGetUniformBlockIndex(p, name):
    return _c("glGetUniformBlockIndex", [p, name])
func glUniformBlockBinding(p, index, binding):
    _c("glUniformBlockBinding", [p, index, binding])
func glUniform1i(loc, v):
    _c("glUniform1i", [loc, v])
func glUniform1f(loc, v):
    _c("glUniform1f", [loc, v])
func glUniform2f(loc, a, b):
    _c("glUniform2f", [loc, a, b])
func glUniform3f(loc, a, b, c):
    _c("glUniform3f", [loc, a, b, c])
func glUniform4f(loc, a, b, c, d):
    _c("glUniform4f", [loc, a, b, c, d])
func glUniform1fv(loc, count, ptr):
    _c("glUniform1fv", [loc, count, ptr])
func glUniform3fv(loc, count, ptr):
    _c("glUniform3fv", [loc, count, ptr])
func glUniform4fv(loc, count, ptr):
    _c("glUniform4fv", [loc, count, ptr])
func glUniformMatrix3fv(loc, count, transpose, ptr):
    _c("glUniformMatrix3fv", [loc, count, 1 if transpose else 0, ptr])
func glUniformMatrix4fv(loc, count, transpose, ptr):
    _c("glUniformMatrix4fv", [loc, count, 1 if transpose else 0, ptr])
func glGenTextures(n, ptr):
    _c("glGenTextures", [n, ptr])
func glDeleteTextures(n, ptr):
    _c("glDeleteTextures", [n, ptr])
func glBindTexture(target, tex):
    _c("glBindTexture", [target, tex])
func glActiveTexture(unit):
    _c("glActiveTexture", [unit])
func glTexImage2D(target, level, internal, w, h, border, fmt, typ, ptr):
    _c("glTexImage2D", [target, level, internal, w, h, border, fmt, typ, ptr])
func glTexSubImage2D(target, level, x, y, w, h, fmt, typ, ptr):
    _c("glTexSubImage2D", [target, level, x, y, w, h, fmt, typ, ptr])
func glTexParameteri(target, pname, v):
    _c("glTexParameteri", [target, pname, v])
func glCompressedTexImage2D(target, level, internal, w, h, border, size, ptr):
    _c("glCompressedTexImage2D", [target, level, internal, w, h, border, size, ptr])
func glGetTexImage(target, level, fmt, typ, ptr):
    _c("glGetTexImage", [target, level, fmt, typ, ptr])
func glTexImage3D(target, level, internal, w, h, d, border, fmt, typ, ptr):
    _c("glTexImage3D", [target, level, internal, w, h, d, border, fmt, typ, ptr])
func glCompressedTexImage3D(target, level, internal, w, h, d, border, size, ptr):
    _c("glCompressedTexImage3D", [target, level, internal, w, h, d, border, size, ptr])
func glGetStringi(name, index):
    return _c("glGetStringi", [name, index])
func glGenerateMipmap(target):
    _c("glGenerateMipmap", [target])
func glDrawArrays(mode, first, count):
    _c("glDrawArrays", [mode, first, count])
func glDrawElements(mode, count, typ, offset):
    _c("glDrawElements", [mode, count, typ, offset])
func glDrawArraysInstanced(mode, first, count, instances):
    _c("glDrawArraysInstanced", [mode, first, count, instances])
func glDrawElementsInstanced(mode, count, typ, offset, instances):
    _c("glDrawElementsInstanced", [mode, count, typ, offset, instances])
func glGenFramebuffers(n, ptr):
    _c("glGenFramebuffers", [n, ptr])
func glDeleteFramebuffers(n, ptr):
    _c("glDeleteFramebuffers", [n, ptr])
func glBindFramebuffer(target, fb):
    _c("glBindFramebuffer", [target, fb])
func glFramebufferTexture2D(target, attach, textarget, tex, level):
    _c("glFramebufferTexture2D", [target, attach, textarget, tex, level])
func glCheckFramebufferStatus(target):
    return _c("glCheckFramebufferStatus", [target])
func glGenRenderbuffers(n, ptr):
    _c("glGenRenderbuffers", [n, ptr])
func glDeleteRenderbuffers(n, ptr):
    _c("glDeleteRenderbuffers", [n, ptr])
func glBindRenderbuffer(target, rb):
    _c("glBindRenderbuffer", [target, rb])
func glRenderbufferStorage(target, fmt, w, h):
    _c("glRenderbufferStorage", [target, fmt, w, h])
func glFramebufferRenderbuffer(target, attach, rbtarget, rb):
    _c("glFramebufferRenderbuffer", [target, attach, rbtarget, rb])
func glBlitFramebuffer(sx0, sy0, sx1, sy1, dx0, dy0, dx1, dy1, mask, filter):
    _c("glBlitFramebuffer", [sx0, sy0, sx1, sy1, dx0, dy0, dx1, dy1, mask, filter])

# ---------------------------------------------------------------------------------------------------------------------
# Aides
# ---------------------------------------------------------------------------------------------------------------------

# ffi.Buffer rempli de flottants 32 bits / entiers 32 bits non signés / 16 bits non signés.
func f32_buffer(values):
    b := ffi.Buffer(4 * len(values) if len(values) > 0 else 4)
    if len(values) > 0:
        b.write_array("f32", values)
    return b

func u32_buffer(values):
    b := ffi.Buffer(4 * len(values) if len(values) > 0 else 4)
    if len(values) > 0:
        b.write_array("u32", values)
    return b

func u16_buffer(values):
    b := ffi.Buffer(2 * len(values) if len(values) > 0 else 2)
    if len(values) > 0:
        b.write_array("u16", values)
    return b

# Un nom d'objet OpenGL : gl.gen("glGenBuffers") -> int.
func gen(gen_name):
    b := ffi.Buffer(4)
    _c(gen_name, [1, b.address()])
    v := b.read("u32")
    b.free()
    return v

# Libère un nom : gl.delete("glDeleteBuffers", id).
func delete(del_name, id):
    b := ffi.Buffer(4)
    b.write("u32", id)
    _c(del_name, [1, b.address()])
    b.free()

func get_integer(pname):
    b := ffi.Buffer(64)
    glGetIntegerv(pname, b.address())
    v := b.read("i32")
    b.free()
    return v

# Source GLSL d'un shader (une seule chaîne).
func shader_source(sh, text):
    src := ffi.cstring(text)
    arr := ffi.Buffer(8)
    arr.write("ptr", src.address())
    glShaderSource(sh, 1, arr.address(), 0)
    arr.free()
    src.free()

func _log(getter, obj):
    lb := ffi.Buffer(4)
    _c("glGet" + getter + "iv", [obj, GL_INFO_LOG_LENGTH, lb.address()])
    n := lb.read("i32")
    lb.free()
    if n <= 1:
        return ""
    b := ffi.Buffer(n + 1)
    _c("glGet" + getter + "InfoLog", [obj, n, 0, b.address()])
    t := b.read_str()
    b.free()
    return t

# Compile un shader ; RuntimeError avec le journal du pilote en cas d'échec.
func compile_shader(kind, text):
    sh := glCreateShader(kind)
    shader_source(sh, text)
    glCompileShader(sh)
    st := ffi.Buffer(4)
    glGetShaderiv(sh, GL_COMPILE_STATUS, st.address())
    ok := st.read("i32")
    st.free()
    if ok == 0:
        msg := _log("Shader", sh)
        glDeleteShader(sh)
        what := "sommets" if kind == GL_VERTEX_SHADER else "fragments"
        raise("RuntimeError", "gl : compilation du shader de " + what + " impossible :\n" + msg)
    return sh

# Programme à partir des sources GLSL des sommets et des fragments ; `attributes` : {nom: indice} imposés.
func create_program(vertex_src, fragment_src, attributes=null):
    vs := compile_shader(GL_VERTEX_SHADER, vertex_src)
    fs := compile_shader(GL_FRAGMENT_SHADER, fragment_src)
    p := glCreateProgram()
    glAttachShader(p, vs)
    glAttachShader(p, fs)
    if attributes != null:
        for k in attributes:
            glBindAttribLocation(p, attributes[k], k)
    glLinkProgram(p)
    st := ffi.Buffer(4)
    glGetProgramiv(p, GL_LINK_STATUS, st.address())
    ok := st.read("i32")
    st.free()
    glDeleteShader(vs)
    glDeleteShader(fs)
    if ok == 0:
        msg := _log("Program", p)
        glDeleteProgram(p)
        raise("RuntimeError", "gl : édition des liens du programme impossible :\n" + msg)
    return p

# Tampon réutilisable pour les uniformes matriciels (évite une allocation par appel).
_scratch := [null]

func _scratch_buf():
    if _scratch[0] == null:
        _scratch[0] = ffi.Buffer(256)
    return _scratch[0]

# Mat4 (16 flottants, ordre colonne comme math3d) vers un uniforme mat4.
func uniform_matrix4(loc, m):
    if loc < 0:
        return
    b := _scratch_buf()
    b.write_array("f32", m)
    glUniformMatrix4fv(loc, 1, false, b.address())

# Mat3 (9 flottants, ordre colonne) vers un uniforme mat3.
func uniform_matrix3(loc, m):
    if loc < 0:
        return
    b := _scratch_buf()
    b.write_array("f32", m)
    glUniformMatrix3fv(loc, 1, false, b.address())

# Erreurs OpenGL en attente (liste vide si aucune).
func errors():
    out := []
    k := 0
    while k < 16:
        e := glGetError()
        if e == 0:
            return out
        append(out, e)
        k += 1
    return out

# Extensions OpenGL du pilote (ensemble de noms), mises en cache.
_ext := [null]
func extensions():
    if _ext[0] == null:
        d := {}
        n := get_integer(GL_NUM_EXTENSIONS)
        k := 0
        while k < n:
            d[glGetStringi(GL_EXTENSIONS, k)] = true
            k += 1
        _ext[0] = d
    return _ext[0]

func has_extension(name):
    return name in extensions()

# Description du pilote : {"vendor", "renderer", "version", "glsl"}.
func info():
    return {"vendor": glGetString(GL_VENDOR), "renderer": glGetString(GL_RENDERER),
            "version": glGetString(GL_VERSION), "glsl": glGetString(GL_SHADING_LANGUAGE_VERSION)}
