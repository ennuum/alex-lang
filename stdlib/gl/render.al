# ALEX STANDARD LIBRARY — gl.render
#
# Moteur de rendu GPU pour les jeux 2D et 3D, au-dessus de gl (OpenGL 3.3 core) : maillages sur la carte (depuis
# mesh.Mesh), textures (depuis multimedia.image, un fichier PNG / BMP / PNM ou des octets), matériaux, éclairage
# Blinn-Phong (ambiant, une lumière directionnelle, 8 lumières ponctuelles), brouillard, caméras de scene, rendu
# d'un graphe de scène, cibles de rendu (rendu dans une texture) et sprites 2D regroupés par lots.
#
#   use gl.window as glw
#   use gl.render as gr
#   use mesh
#   use math3d as m3
#   w := glw.Window("3D", 1280, 720)
#   r := gr.Renderer(w)
#   cube := gr.GpuMesh(mesh.box(1, 1, 1))
#   caisse := gr.Material([1.0, 1.0, 1.0, 1.0], gr.Texture.load("caisse.png"))
#   r.set_sun([-0.4, -1.0, -0.3], [1.0, 0.95, 0.9])
#   r.add_point_light([2, 2, 2], [1.0, 0.4, 0.2], 8.0)
#   batch := gr.SpriteBatch(r)
#   while w.is_open():
#       w.poll()
#       r.begin_frame([0.08, 0.1, 0.15, 1.0])
#       r.set_perspective(m3.radians(60), [0, 2, 5], [0, 0, 0])
#       r.draw(cube, m3.mat4_rotation_y(w.time()), caisse)
#       batch.begin()                                     # 2D en pixels, origine en haut à gauche
#       batch.rect(10, 10, 200, 20, [0.2, 0.8, 0.3, 1.0])
#       batch.end()
#       w.swap()
#
# CONVENTIONS : celles de math3d (main droite, Y vers le haut, matrices en ordre colonne). Les UV des maillages
#   suivent mesh (origine en bas à gauche) ; les textures sont envoyées ligne du haut en premier, le shader 3D
#   retourne v. En 2D, (0, 0) est le coin haut gauche de la fenêtre et les UV de sprites ont v vers le bas.
#
# Erreurs : RuntimeError (pas de contexte, shader), ValueError (données invalides).

from core use len, type, to_int
from collections use append
use ffi
use math
use math3d as m3
use gl
use multimedia.image.decode as _dec
use multimedia.image.jpeg as _jpeg
use gl.textures as _tex
use multimedia.image.convert as _conv
use io as _io
use string as _s
use animation as _anim

# ---------------------------------------------------------------------------------------------------------------------
# Shaders fournis
# ---------------------------------------------------------------------------------------------------------------------

const MAX_POINT_LIGHTS := 8

const LIT_VS := """#version 330 core
layout(location = 0) in vec3 a_pos;
layout(location = 1) in vec3 a_nrm;
layout(location = 2) in vec2 a_uv;
uniform mat4 u_model;
uniform mat4 u_vp;
uniform vec4 u_uv_rect;
out vec3 v_wpos;
out vec3 v_nrm;
out vec2 v_uv;
void main() {
    vec4 wp = u_model * vec4(a_pos, 1.0);
    v_wpos = wp.xyz;
    v_nrm = mat3(transpose(inverse(u_model))) * a_nrm;
    v_uv = u_uv_rect.xy + vec2(a_uv.x, 1.0 - a_uv.y) * u_uv_rect.zw;
    gl_Position = u_vp * wp;
}
"""

const LIT_FS := """#version 330 core
in vec3 v_wpos;
in vec3 v_nrm;
in vec2 v_uv;
out vec4 o_color;
uniform sampler2D u_tex;
uniform vec4 u_color;
uniform vec3 u_emissive;
uniform float u_spec;
uniform float u_shiny;
uniform int u_unlit;
uniform vec3 u_cam;
uniform vec3 u_ambient;
uniform vec3 u_sun_dir;
uniform vec3 u_sun_color;
uniform int u_nlights;
uniform vec4 u_lpos[8];
uniform vec3 u_lcol[8];
uniform vec3 u_fog_color;
uniform vec2 u_fog;
void main() {
    vec4 base = texture(u_tex, v_uv) * u_color;
    if (base.a < 0.01) discard;
    vec3 c = base.rgb;
    if (u_unlit == 0) {
        vec3 n = normalize(v_nrm);
        if (!gl_FrontFacing) n = -n;
        vec3 v = normalize(u_cam - v_wpos);
        vec3 diff = u_ambient;
        vec3 spec = vec3(0.0);
        vec3 l = normalize(-u_sun_dir);
        float nl = max(dot(n, l), 0.0);
        diff += u_sun_color * nl;
        if (nl > 0.0) spec += u_sun_color * pow(max(dot(n, normalize(l + v)), 0.0), u_shiny);
        for (int i = 0; i < u_nlights; i++) {
            vec3 d = u_lpos[i].xyz - v_wpos;
            float dist = length(d);
            float range = u_lpos[i].w;
            if (dist < range) {
                l = d / dist;
                float att = 1.0 - dist / range;
                att *= att;
                nl = max(dot(n, l), 0.0);
                diff += u_lcol[i] * nl * att;
                if (nl > 0.0) spec += u_lcol[i] * pow(max(dot(n, normalize(l + v)), 0.0), u_shiny) * att;
            }
        }
        c = c * diff + spec * u_spec;
    }
    c += u_emissive;
    if (u_fog.y > u_fog.x) {
        float f = clamp((length(u_cam - v_wpos) - u_fog.x) / (u_fog.y - u_fog.x), 0.0, 1.0);
        c = mix(c, u_fog_color, f);
    }
    o_color = vec4(c, base.a);
}
"""

const SPRITE_VS := """#version 330 core
layout(location = 0) in vec2 a_pos;
layout(location = 1) in vec2 a_uv;
layout(location = 2) in vec4 a_col;
uniform mat4 u_proj;
out vec2 v_uv;
out vec4 v_col;
void main() {
    v_uv = a_uv;
    v_col = a_col;
    gl_Position = u_proj * vec4(a_pos, 0.0, 1.0);
}
"""

const SPRITE_FS := """#version 330 core
in vec2 v_uv;
in vec4 v_col;
out vec4 o_color;
uniform sampler2D u_tex;
void main() {
    o_color = texture(u_tex, v_uv) * v_col;
}
"""

# ---------------------------------------------------------------------------------------------------------------------
# Shader : programme + cache des emplacements d'uniformes
# ---------------------------------------------------------------------------------------------------------------------

class Shader:
    func init(vertex_src, fragment_src, attributes=null):
        self.id = gl.create_program(vertex_src, fragment_src, attributes)
        self._loc = {}

    func loc(name):
        if name in self._loc:
            return self._loc[name]
        l := gl.glGetUniformLocation(self.id, name)
        self._loc[name] = l
        return l

    func bind():
        gl.glUseProgram(self.id)

    func set_int(name, v):
        l := self.loc(name)
        if l >= 0:
            gl.glUniform1i(l, v)

    func set_float(name, v):
        l := self.loc(name)
        if l >= 0:
            gl.glUniform1f(l, v)

    func set_vec2(name, v):
        l := self.loc(name)
        if l >= 0:
            gl.glUniform2f(l, v[0], v[1])

    func set_vec3(name, v):
        l := self.loc(name)
        if l >= 0:
            gl.glUniform3f(l, v[0], v[1], v[2])

    func set_vec4(name, v):
        l := self.loc(name)
        if l >= 0:
            gl.glUniform4f(l, v[0], v[1], v[2], v[3])

    func set_mat4(name, m):
        gl.uniform_matrix4(self.loc(name), m)

    func set_mat3(name, m):
        gl.uniform_matrix3(self.loc(name), m)

    func delete():
        if self.id != 0:
            gl.glDeleteProgram(self.id)
            self.id = 0

# ---------------------------------------------------------------------------------------------------------------------
# Textures
# ---------------------------------------------------------------------------------------------------------------------

class Texture:
    # Texture vide (pixels = null) ou remplie : `pixels` list d'octets ligne du haut en premier, `channels` 1, 3 ou 4.
    func init(width, height, pixels=null, channels=4, filter="linear", wrap="repeat", mipmaps=true):
        if width <= 0 or height <= 0:
            raise("ValueError", "Texture : dimensions invalides " + str(width) + "x" + str(height))
        self.kind = "texture"
        self.width = width
        self.height = height
        self.channels = channels
        self.id = gl.gen("glGenTextures")
        gl.glBindTexture(gl.GL_TEXTURE_2D, self.id)
        fmt := gl.GL_RGBA
        internal := gl.GL_RGBA8
        if channels == 3:
            fmt = gl.GL_RGB
            internal = gl.GL_RGB8
        elif channels == 1:
            fmt = gl.GL_RED
            internal = gl.GL_R8
        elif channels != 4:
            raise("ValueError", "Texture : 1, 3 ou 4 canaux attendus")
        gl.glPixelStorei(gl.GL_UNPACK_ALIGNMENT, 1)
        buf := null
        addr := 0
        if pixels != null and type(pixels) != "list":
            # ffi.Buffer déjà rempli (décodeurs natifs : JPEG, DDS...)
            addr = pixels.address()
        elif pixels != null:
            if len(pixels) != width * height * channels:
                raise("ValueError", "Texture : " + str(width * height * channels) + " octets attendus, " + str(len(pixels)) + " reçus")
            buf = ffi.Buffer(len(pixels))
            buf.write_array("u8", pixels)
            addr = buf.address()
        gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, internal, width, height, 0, fmt, gl.GL_UNSIGNED_BYTE, addr)
        if buf != null:
            buf.free()
        if channels == 1:
            gl.glTexParameteri(gl.GL_TEXTURE_2D, 0x8E43, gl.GL_RED)        # swizzle : gris sur r, g, b
            gl.glTexParameteri(gl.GL_TEXTURE_2D, 0x8E44, gl.GL_RED)
            gl.glTexParameteri(gl.GL_TEXTURE_2D, 0x8E45, gl.GL_RED)
        self.mipmaps = mipmaps and pixels != null
        self.set_filter(filter)
        self.set_wrap(wrap)
        if self.mipmaps:
            gl.glGenerateMipmap(gl.GL_TEXTURE_2D)

    func set_filter(filter):
        gl.glBindTexture(gl.GL_TEXTURE_2D, self.id)
        if filter == "nearest":
            gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST_MIPMAP_NEAREST if self.mipmaps else gl.GL_NEAREST)
            gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST)
        else:
            gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR_MIPMAP_LINEAR if self.mipmaps else gl.GL_LINEAR)
            gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR)

    func set_wrap(wrap):
        gl.glBindTexture(gl.GL_TEXTURE_2D, self.id)
        mode := gl.GL_REPEAT
        if wrap == "clamp":
            mode = gl.GL_CLAMP_TO_EDGE
        elif wrap == "mirror":
            mode = gl.GL_MIRRORED_REPEAT
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, mode)
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, mode)

    # Remplace une zone (octets ligne du haut en premier, même nombre de canaux).
    func update(x, y, w, h, pixels):
        buf := ffi.Buffer(len(pixels))
        buf.write_array("u8", pixels)
        fmt := gl.GL_RGBA if self.channels == 4 else (gl.GL_RGB if self.channels == 3 else gl.GL_RED)
        gl.glBindTexture(gl.GL_TEXTURE_2D, self.id)
        gl.glPixelStorei(gl.GL_UNPACK_ALIGNMENT, 1)
        gl.glTexSubImage2D(gl.GL_TEXTURE_2D, 0, x, y, w, h, fmt, gl.GL_UNSIGNED_BYTE, buf.address())
        buf.free()
        if self.mipmaps:
            gl.glGenerateMipmap(gl.GL_TEXTURE_2D)

    func bind(unit=0):
        gl.glActiveTexture(gl.GL_TEXTURE0 + unit)
        gl.glBindTexture(gl.GL_TEXTURE_2D, self.id)

    func delete():
        if self.id != 0:
            gl.delete("glDeleteTextures", self.id)
            self.id = 0

# Texture depuis une multimedia.image.image.Image (gray, rgb, rgba).
func texture_from_image(img, filter="linear", wrap="repeat", mipmaps=true):
    return Texture(img.width, img.height, img.pixels, img.channels, filter, wrap, mipmaps)

# Texture depuis un fichier : PNG, BMP, PNM, JPEG (décodés), DDS et KTX2 (blocs compressés BC1..BC7 envoyés tels
# quels à la carte, mipmaps du fichier ; RGBA non compressé).
func load_texture(path, filter="linear", wrap="repeat", mipmaps=true):
    low := _lower(path)
    if _ends(low, ".dds"):
        return _tex.load_dds(path, filter, wrap, mipmaps)
    if _ends(low, ".ktx2"):
        return _tex.load_ktx2(path, filter, wrap, mipmaps)
    if _ends(low, ".jpg") or _ends(low, ".jpeg"):
        return texture_from_bytes(_io.read_bytes(path), filter, wrap, mipmaps)
    return texture_from_image(_dec.load(path), filter, wrap, mipmaps)

# Texture depuis les octets d'un fichier image (PNG, BMP, PNM, JPEG, DDS, KTX2) : textures intégrées aux .glb.
func texture_from_bytes(data, filter="linear", wrap="repeat", mipmaps=true):
    if len(data) >= 3 and data[0] == 255 and data[1] == 216 and data[2] == 255:
        r := _jpeg.decode_rgba(data, null, true)
        t := Texture(r["width"], r["height"], r["buffer"], 4, filter, wrap, mipmaps)
        r["buffer"].free()
        return t
    if len(data) >= 4 and data[0] == 68 and data[1] == 68 and data[2] == 83 and data[3] == 32:
        return _tex.dds_texture(data, filter, wrap, mipmaps)
    if len(data) >= 12 and data[0] == 171 and data[1] == 75 and data[2] == 84 and data[3] == 88:
        return _tex.ktx2_texture(data, filter, wrap, mipmaps)
    return texture_from_image(_dec.decode(data), filter, wrap, mipmaps)

func _lower(p):
    return _s.lower(p)

func _ends(p, e):
    return _s.ends_with(p, e)

# Cubemap : un fichier DDS / KTX2 contenant 6 faces, ou une liste de 6 images (PNG, JPEG, BMP...) dans l'ordre
# +X, -X, +Y, -Y, +Z, -Z (droite, gauche, haut, bas, avant, arrière). Pour Skybox ou les reflets.
func load_cubemap(source, filter="linear", mipmaps=true):
    if type(source) == "str":
        t := load_texture(source, filter, "clamp", mipmaps)
        shape := ""
        try:
            shape = t.shape
        catch e:
            shape = ""
        if shape != "cube":
            raise("ValueError", "gl.render.load_cubemap : " + source + " n'est pas une cubemap (6 faces)")
        return t
    if len(source) != 6:
        raise("ValueError", "gl.render.load_cubemap : 6 images attendues (+X, -X, +Y, -Y, +Z, -Z)")
    faces := []
    for p in source:
        data := _io.read_bytes(p)
        if len(data) >= 3 and data[0] == 255 and data[1] == 216 and data[2] == 255:
            r := _jpeg.decode_rgba(data, null, true)
            append(faces, [r["width"], r["height"], r["buffer"]])
        else:
            img := _conv.to_mode(_dec.decode(data), "rgba")
            append(faces, [img.width, img.height, img.pixels])
    t := _tex.cubemap_from_rgba(faces, filter, mipmaps)
    for f in faces:
        if type(f[2]) != "list":
            f[2].free()
    return t

const SKY_VS := """#version 330 core
layout(location = 0) in vec3 a_pos;
uniform mat4 u_view;
uniform mat4 u_proj;
out vec3 v_dir;
void main() {
    v_dir = a_pos;
    vec4 p = u_proj * vec4(mat3(u_view) * a_pos, 1.0);
    gl_Position = p.xyww;
}
"""

const SKY_FS := """#version 330 core
in vec3 v_dir;
uniform samplerCube u_sky;
uniform vec3 u_tint;
out vec4 frag;
void main() {
    frag = vec4(texture(u_sky, normalize(v_dir)).rgb * u_tint, 1.0);
}
"""

# Ciel à l'infini : cubemap dessinée derrière toute la scène (profondeur maximale, sans la translation de la caméra).
#   ciel := gr.Skybox(r, gr.load_cubemap(["px.jpg", "nx.jpg", "py.jpg", "ny.jpg", "pz.jpg", "nz.jpg"]))
#   ... r.draw(...) ; ciel.draw()        # après les objets opaques (moins de pixels à calculer)
class Skybox:
    func init(renderer, cubemap, tint=null):
        self.renderer = renderer
        self.cubemap = cubemap
        self.tint = tint if tint != null else [1.0, 1.0, 1.0]
        self.shader = Shader(SKY_VS, SKY_FS)
        v := []
        for f in [[0, 1], [0, -1], [1, 1], [1, -1], [2, 1], [2, -1]]:
            ax := f[0]
            sg := f[1] * 1.0
            u := (ax + 1) % 3
            w2 := (ax + 2) % 3
            for c in [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]]:
                p := [0.0, 0.0, 0.0]
                p[ax] = sg
                p[u] = c[0]
                p[w2] = c[1]
                v = v + p + [0.0, 0.0, 0.0, 0.0, 0.0]
        self.mesh = GpuMesh(null, v)

    func draw():
        r := self.renderer
        s := self.shader
        s.bind()
        s.set_mat4("u_view", r.view)
        s.set_mat4("u_proj", r.proj)
        s.set_int("u_sky", 0)
        s.set_vec3("u_tint", self.tint)
        self.cubemap.bind(0)
        gl.glDepthFunc(gl.GL_LEQUAL)
        gl.glDepthMask(false)
        gl.glDisable(gl.GL_CULL_FACE)
        self.mesh.draw()
        gl.glDepthMask(true)
        gl.glEnable(gl.GL_CULL_FACE)
        r._active = null
        r._mat = null
        r.stats["draws"] = r.stats["draws"] + 1

    func delete():
        self.mesh.delete()
        self.shader.delete()

# Texture 1 x 1 d'une couleur [r, g, b, a] (0..1).
func solid_texture(color):
    px := [to_int(_clamp01(color[0]) * 255.0), to_int(_clamp01(color[1]) * 255.0), to_int(_clamp01(color[2]) * 255.0), to_int(_clamp01(color[3] if len(color) > 3 else 1.0) * 255.0)]
    return Texture(1, 1, px, 4, "nearest", "repeat", false)

# Damier (essais, sols) : cases de `cell` pixels, couleurs a et b (octets RGBA).
func checker_texture(size=64, cell=8, a=null, b=null):
    ca := a if a != null else [200, 200, 200, 255]
    cb := b if b != null else [90, 90, 90, 255]
    px := []
    y := 0
    while y < size:
        x := 0
        while x < size:
            c := ca if (to_int(x / cell) + to_int(y / cell)) % 2 == 0 else cb
            append(px, c[0])
            append(px, c[1])
            append(px, c[2])
            append(px, c[3])
            x += 1
        y += 1
    return Texture(size, size, px, 4, "nearest", "repeat", true)

func _clamp01(v):
    if v < 0.0:
        return 0.0
    if v > 1.0:
        return 1.0
    return v * 1.0

# ---------------------------------------------------------------------------------------------------------------------
# Maillages sur la carte
# ---------------------------------------------------------------------------------------------------------------------

# Maillage chargé dans un VAO : sommets entrelacés position (3) + normale (3) + uv (2), indices 32 bits.
class GpuMesh:
    # `source` : mesh.Mesh (positions, normals, uvs, indices) ; ou null avec `vertices` (list plate de 8 flottants
    # par sommet) et `indices`.
    func init(source=null, vertices=null, indices=null, mode=null):
        verts := vertices
        idx := indices
        if source != null:
            verts = source.to_interleaved("pnu")
            idx = source.indices
        if verts == null or len(verts) == 0:
            raise("ValueError", "GpuMesh : aucun sommet")
        self.vertex_count = to_int(len(verts) / 8)
        self.mode = mode if mode != null else gl.GL_TRIANGLES
        self.vao = gl.gen("glGenVertexArrays")
        gl.glBindVertexArray(self.vao)
        self.vbo = gl.gen("glGenBuffers")
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo)
        vb := gl.f32_buffer(verts)
        gl.glBufferData(gl.GL_ARRAY_BUFFER, 4 * len(verts), vb.address(), gl.GL_STATIC_DRAW)
        vb.free()
        gl.glEnableVertexAttribArray(0)
        gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, false, 32, 0)
        gl.glEnableVertexAttribArray(1)
        gl.glVertexAttribPointer(1, 3, gl.GL_FLOAT, false, 32, 12)
        gl.glEnableVertexAttribArray(2)
        gl.glVertexAttribPointer(2, 2, gl.GL_FLOAT, false, 32, 24)
        self.ebo = 0
        self.index_count = 0
        if idx != null and len(idx) > 0:
            self.ebo = gl.gen("glGenBuffers")
            gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.ebo)
            ib := gl.u32_buffer(idx)
            gl.glBufferData(gl.GL_ELEMENT_ARRAY_BUFFER, 4 * len(idx), ib.address(), gl.GL_STATIC_DRAW)
            ib.free()
            self.index_count = len(idx)
        gl.glBindVertexArray(0)
        self.bounds = null
        if source != null:
            try:
                self.bounds = source.bounds()
            catch e:
                self.bounds = null

    func draw():
        gl.glBindVertexArray(self.vao)
        if self.ebo != 0:
            gl.glDrawElements(self.mode, self.index_count, gl.GL_UNSIGNED_INT, 0)
        else:
            gl.glDrawArrays(self.mode, 0, self.vertex_count)

    func delete():
        if self.vao != 0:
            gl.delete("glDeleteBuffers", self.vbo)
            if self.ebo != 0:
                gl.delete("glDeleteBuffers", self.ebo)
            gl.delete("glDeleteVertexArrays", self.vao)
            self.vao = 0

# ---------------------------------------------------------------------------------------------------------------------
# Matériaux
# ---------------------------------------------------------------------------------------------------------------------

class Material:
    func init(color=null, texture=null, specular=0.3, shininess=32.0, unlit=false, emissive=null):
        self.color = color if color != null else [1.0, 1.0, 1.0, 1.0]
        if len(self.color) == 3:
            self.color = [self.color[0], self.color[1], self.color[2], 1.0]
        self.texture = texture
        self.specular = specular
        self.shininess = shininess
        self.unlit = unlit
        self.emissive = emissive if emissive != null else [0.0, 0.0, 0.0]
        self.uv_rect = [0.0, 0.0, 1.0, 1.0]        # décalage (x, y) et échelle (w, h) des UV : répétition, atlas
        self.transparent = self.color[3] < 1.0
        self.double_sided = false

# ---------------------------------------------------------------------------------------------------------------------
# Renderer
# ---------------------------------------------------------------------------------------------------------------------

class Renderer:
    func init(window):
        self.window = window
        if not gl.ready():
            raise("RuntimeError", "gl.render.Renderer : aucun contexte OpenGL (créer d'abord une gl.window.Window)")
        self.lit = Shader(LIT_VS, LIT_FS)
        self.white = solid_texture([1.0, 1.0, 1.0, 1.0])
        self.default_material = Material()
        self.view = m3.mat4_identity()
        self.proj = m3.mat4_identity()
        self.vp = m3.mat4_identity()
        self.eye = [0.0, 0.0, 0.0]
        self.ambient = [0.25, 0.25, 0.3]
        self.sun_dir = [-0.3, -1.0, -0.4]
        self.sun_color = [0.9, 0.9, 0.85]
        self.lights = []
        self.fog = [0.0, 0.0]
        self.fog_color = [0.5, 0.6, 0.7]
        self.stats = {"draws": 0, "triangles": 0}
        self._mat = null
        self._active = null
        self._lights_dirty = true
        self._lbuf = ffi.Buffer(4 * 4 * MAX_POINT_LIGHTS)
        self._cbuf = ffi.Buffer(4 * 3 * MAX_POINT_LIGHTS)
        gl.glEnable(gl.GL_DEPTH_TEST)
        gl.glDepthFunc(gl.GL_LEQUAL)
        gl.glEnable(gl.GL_CULL_FACE)
        gl.glCullFace(gl.GL_BACK)
        gl.glFrontFace(gl.GL_CCW)
        gl.glBlendFunc(gl.GL_SRC_ALPHA, gl.GL_ONE_MINUS_SRC_ALPHA)

    # Début d'image : viewport à la taille de la fenêtre, effacement couleur + profondeur.
    func begin_frame(clear_color=null):
        c := clear_color if clear_color != null else [0.0, 0.0, 0.0, 1.0]
        gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, 0)
        gl.glViewport(0, 0, self.window.width, self.window.height)
        gl.glDepthMask(true)
        gl.glClearColor(c[0], c[1], c[2], c[3] if len(c) > 3 else 1.0)
        gl.glClear(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT)
        self.stats = {"draws": 0, "triangles": 0}
        self._mat = null
        self._active = null
        self._lights_dirty = true

    # ---- caméra ----
    func set_view_projection(view, proj, eye):
        self.view = view
        self.proj = proj
        self.vp = m3.mat4_mul(proj, view)
        self.eye = [eye[0] * 1.0, eye[1] * 1.0, eye[2] * 1.0]
        self._lights_dirty = true

    # Perspective regardant `target` depuis `eye` (aspect de la fenêtre).
    func set_perspective(fovy, eye, target, near=0.1, far=500.0, up=null):
        u := up if up != null else [0.0, 1.0, 0.0]
        self.set_view_projection(m3.mat4_look_at(eye, target, u), m3.mat4_perspective(fovy, self.window.aspect(), near, far), eye)

    # Caméra de scene (scene.Camera) ; l'aspect est mis à celui de la fenêtre.
    func set_camera(cam):
        cam.aspect = self.window.aspect()
        wm := cam.world_matrix()
        self.set_view_projection(cam.view_matrix(), cam.projection_matrix(), m3.mat4_get_translation(wm))

    # ---- lumières ----
    func set_ambient(color):
        self.ambient = color
        self._lights_dirty = true

    func set_sun(direction, color):
        self.sun_dir = direction
        self.sun_color = color
        self._lights_dirty = true

    # Lumière ponctuelle ; rend sa fiche {"position", "color", "range"} (modifiable).
    func add_point_light(position, color, range=10.0):
        l := {"position": position, "color": color, "range": range}
        append(self.lights, l)
        self._lights_dirty = true
        return l

    func clear_lights():
        self.lights = []
        self._lights_dirty = true

    # Brouillard linéaire de `start` à `end` (end <= start : désactivé).
    func set_fog(start, end, color=null):
        self.fog = [start * 1.0, end * 1.0]
        if color != null:
            self.fog_color = color
        self._lights_dirty = true

    func _upload_lights(sh=null):
        s := sh if sh != null else self.lit
        s.set_vec3("u_ambient", self.ambient)
        s.set_vec3("u_sun_dir", self.sun_dir)
        s.set_vec3("u_sun_color", self.sun_color)
        s.set_vec2("u_fog", self.fog)
        s.set_vec3("u_fog_color", self.fog_color)
        n := len(self.lights)
        if n > MAX_POINT_LIGHTS:
            n = MAX_POINT_LIGHTS
        s.set_int("u_nlights", n)
        if n > 0:
            pos := []
            col := []
            k := 0
            while k < n:
                l := self.lights[k]
                append(pos, l["position"][0] * 1.0)
                append(pos, l["position"][1] * 1.0)
                append(pos, l["position"][2] * 1.0)
                append(pos, l["range"] * 1.0)
                append(col, l["color"][0] * 1.0)
                append(col, l["color"][1] * 1.0)
                append(col, l["color"][2] * 1.0)
                k += 1
            self._lbuf.write_array("f32", pos)
            self._cbuf.write_array("f32", col)
            gl.glUniform4fv(s.loc("u_lpos[0]"), n, self._lbuf.address())
            gl.glUniform3fv(s.loc("u_lcol[0]"), n, self._cbuf.address())
        self._lights_dirty = false

    func _bind_material(m, sh=null):
        if m == self._mat:
            return
        s := sh if sh != null else self.lit
        s.set_vec4("u_color", m.color)
        s.set_vec3("u_emissive", m.emissive)
        s.set_float("u_spec", m.specular)
        s.set_float("u_shiny", m.shininess)
        s.set_int("u_unlit", 1 if m.unlit else 0)
        s.set_vec4("u_uv_rect", m.uv_rect)
        t := m.texture if m.texture != null else self.white
        t.bind(0)
        if m.transparent:
            gl.glEnable(gl.GL_BLEND)
            gl.glDepthMask(false)
        else:
            gl.glDisable(gl.GL_BLEND)
            gl.glDepthMask(true)
        if m.double_sided:
            gl.glDisable(gl.GL_CULL_FACE)
        else:
            gl.glEnable(gl.GL_CULL_FACE)
        self._mat = m

    # Active un programme d'éclairage (lit ou skinning) : caméra, lumières, matériau à renvoyer s'il change.
    func use_shader(s):
        if s != self._active or self._lights_dirty:
            s.bind()
            s.set_int("u_tex", 0)
            s.set_mat4("u_vp", self.vp)
            s.set_vec3("u_cam", self.eye)
            self._upload_lights(s)
            self._mat = null
            self._active = s
        return s

    # Dessine un GpuMesh avec une matrice monde (Mat4) et un matériau.
    func draw(gpu_mesh, model=null, material=null):
        s := self.use_shader(self.lit)
        mm := model if model != null else m3.mat4_identity()
        s.set_mat4("u_model", mm)
        self._bind_material(material if material != null else self.default_material, s)
        gpu_mesh.draw()
        self.stats["draws"] += 1
        if gpu_mesh.ebo != 0:
            self.stats["triangles"] += to_int(gpu_mesh.index_count / 3)

    # Dessine un graphe de scene : nœuds visibles dont `drawable` est un GpuMesh ou {"mesh": GpuMesh,
    # "material": Material}. Les lumières de la scène (scene.Light) remplacent celles du renderer.
    func draw_scene(world, camera=null):
        cam := camera if camera != null else world.camera
        if cam != null:
            self.set_camera(cam)
        lights := []
        try:
            lights = world.lights()
        catch e:
            lights = []
        if len(lights) > 0:
            self.lights = []
            for l in lights:
                wp := l.world_position()
                if l.kind == "directional":
                    self.sun_dir = l.direction()
                    self.sun_color = m3.vec3_scale(l.color, l.intensity)
                else:
                    append(self.lights, {"position": wp, "color": m3.vec3_scale(l.color, l.intensity), "range": l.range})
            self._lights_dirty = true
        opaque := []
        transparent := []
        for item in world.render_list("front_to_back", cam):
            node := item[0]
            d := node.drawable
            if d != null:
                gm := d
                mat := null
                if type(d) == "dict":
                    gm = d["mesh"]
                    mat = d["material"] if "material" in d else null
                if mat != null and mat.transparent:
                    append(transparent, [node, gm, mat])
                else:
                    append(opaque, [node, gm, mat])
        for e in opaque:
            self.draw(e[1], e[0].world_matrix(), e[2])
        k := len(transparent) - 1                 # du plus loin au plus proche
        while k >= 0:
            e := transparent[k]
            self.draw(e[1], e[0].world_matrix(), e[2])
            k -= 1
        gl.glDepthMask(true)
        gl.glDisable(gl.GL_BLEND)

    func set_wireframe(on):
        gl.glPolygonMode(gl.GL_FRONT_AND_BACK, gl.GL_LINE if on else gl.GL_FILL)

# ---------------------------------------------------------------------------------------------------------------------
# Cible de rendu : dessiner dans une texture (post-traitement, miroirs, mini-carte)
# ---------------------------------------------------------------------------------------------------------------------

class RenderTarget:
    func init(width, height, depth=true):
        self.width = width
        self.height = height
        self.texture = Texture(width, height, null, 4, "linear", "clamp", false)
        self.fbo = gl.gen("glGenFramebuffers")
        gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, self.fbo)
        gl.glFramebufferTexture2D(gl.GL_FRAMEBUFFER, gl.GL_COLOR_ATTACHMENT0, gl.GL_TEXTURE_2D, self.texture.id, 0)
        self.rbo = 0
        if depth:
            self.rbo = gl.gen("glGenRenderbuffers")
            gl.glBindRenderbuffer(gl.GL_RENDERBUFFER, self.rbo)
            gl.glRenderbufferStorage(gl.GL_RENDERBUFFER, gl.GL_DEPTH24_STENCIL8, width, height)
            gl.glFramebufferRenderbuffer(gl.GL_FRAMEBUFFER, gl.GL_DEPTH_STENCIL_ATTACHMENT, gl.GL_RENDERBUFFER, self.rbo)
        st := gl.glCheckFramebufferStatus(gl.GL_FRAMEBUFFER)
        gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, 0)
        if st != gl.GL_FRAMEBUFFER_COMPLETE:
            raise("RuntimeError", "RenderTarget : tampon d'image incomplet (" + str(st) + ")")

    # Dessiner dans la cible jusqu'à end() ; efface si clear_color est donné.
    func begin(clear_color=null):
        gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, self.fbo)
        gl.glViewport(0, 0, self.width, self.height)
        if clear_color != null:
            gl.glDepthMask(true)
            gl.glClearColor(clear_color[0], clear_color[1], clear_color[2], clear_color[3])
            gl.glClear(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT)

    func end(window):
        gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, 0)
        gl.glViewport(0, 0, window.width, window.height)

    func delete():
        if self.fbo != 0:
            gl.delete("glDeleteFramebuffers", self.fbo)
            if self.rbo != 0:
                gl.delete("glDeleteRenderbuffers", self.rbo)
            self.texture.delete()
            self.fbo = 0

# ---------------------------------------------------------------------------------------------------------------------
# Sprites 2D par lots
# ---------------------------------------------------------------------------------------------------------------------

# Région d'une texture (atlas, feuille de sprites) en pixels.
class Region:
    func init(texture, x, y, w, h):
        self.kind = "region"
        self.texture = texture
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.u0 = x * 1.0 / texture.width
        self.v0 = y * 1.0 / texture.height
        self.u1 = (x + w) * 1.0 / texture.width
        self.v1 = (y + h) * 1.0 / texture.height

# Découpe une feuille de sprites en régions de `fw` x `fh` pixels (ligne par ligne).
func grid_regions(texture, fw, fh, count=null):
    out := []
    cols := to_int(texture.width / fw)
    rows := to_int(texture.height / fh)
    n := count if count != null else cols * rows
    k := 0
    while k < n:
        append(out, Region(texture, (k % cols) * fw, to_int(k / cols) * fh, fw, fh))
        k += 1
    return out

const _SPRITE_FLOATS := 32           # 4 sommets x (x, y, u, v, r, g, b, a)

class SpriteBatch:
    func init(renderer, capacity=4096):
        self.renderer = renderer
        self.capacity = capacity
        self.shader = Shader(SPRITE_VS, SPRITE_FS)
        self.vao = gl.gen("glGenVertexArrays")
        gl.glBindVertexArray(self.vao)
        self.vbo = gl.gen("glGenBuffers")
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo)
        gl.glBufferData(gl.GL_ARRAY_BUFFER, 4 * _SPRITE_FLOATS * capacity, 0, gl.GL_DYNAMIC_DRAW)
        gl.glEnableVertexAttribArray(0)
        gl.glVertexAttribPointer(0, 2, gl.GL_FLOAT, false, 32, 0)
        gl.glEnableVertexAttribArray(1)
        gl.glVertexAttribPointer(1, 2, gl.GL_FLOAT, false, 32, 8)
        gl.glEnableVertexAttribArray(2)
        gl.glVertexAttribPointer(2, 4, gl.GL_FLOAT, false, 32, 16)
        idx := []
        k := 0
        while k < capacity:
            b := 4 * k
            append(idx, b)
            append(idx, b + 1)
            append(idx, b + 2)
            append(idx, b + 2)
            append(idx, b + 3)
            append(idx, b)
            k += 1
        self.ebo = gl.gen("glGenBuffers")
        gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.ebo)
        ib := gl.u32_buffer(idx)
        gl.glBufferData(gl.GL_ELEMENT_ARRAY_BUFFER, 4 * len(idx), ib.address(), gl.GL_STATIC_DRAW)
        ib.free()
        gl.glBindVertexArray(0)
        self.staging = ffi.Buffer(4 * _SPRITE_FLOATS * capacity)
        self.count = 0
        self.texture = null
        self.active = false
        self.proj = null
        self.draw_calls = 0
        self.blend = "alpha"

    # Commence un lot. `projection` : Mat4 (par défaut pixels de la fenêtre, origine en haut à gauche) ou une
    # scene.Camera2D (sa matrice de vue est appliquée).
    func begin(projection=null):
        w := self.renderer.window
        if projection == null:
            self.proj = m3.mat4_ortho_screen(w.width, w.height)
        elif type(projection) == "list":
            self.proj = projection
        else:
            v := projection.view_matrix()
            p := projection.projection_matrix()
            if len(v) == 9:
                v = [v[0], v[1], 0.0, 0.0, v[3], v[4], 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, v[6], v[7], 0.0, 1.0]
            self.proj = m3.mat4_mul(p, v)
        self.active = true
        self.count = 0
        self.texture = null
        self.draw_calls = 0
        self.blend = "alpha"
        gl.glDisable(gl.GL_DEPTH_TEST)
        gl.glDisable(gl.GL_CULL_FACE)
        gl.glEnable(gl.GL_BLEND)
        gl.glBlendFunc(gl.GL_SRC_ALPHA, gl.GL_ONE_MINUS_SRC_ALPHA)

    # Mode de mélange : "alpha" (défaut), "add" (lumières, feu, étincelles), "multiply" (ombres).
    func set_blend(mode):
        self.flush()
        self.blend = mode
        if self.active:
            _apply_blend(mode)

    # Tuile (ou quad) avec ses UV et des retournements à la Tiled : flags 4 = horizontal, 2 = vertical,
    # 1 = diagonal (échange x / y, appliqué en premier).
    func draw_tile(texture, x, y, w, h, u0, v0, u1, v1, flags=0, color=null):
        c := color if color != null else _WHITE
        uv := _tile_uvs(u0, v0, u1, v1, flags)
        if not self.active:
            raise("RuntimeError", "SpriteBatch : appeler begin() avant de dessiner")
        if texture != self.texture or self.count >= self.capacity:
            self.flush()
            self.texture = texture
        a := c[3] if len(c) > 3 else 1.0
        self.staging.write_array("f32", [x, y, uv[0], uv[1], c[0], c[1], c[2], a, x + w, y, uv[2], uv[3], c[0], c[1], c[2], a, x + w, y + h, uv[4], uv[5], c[0], c[1], c[2], a, x, y + h, uv[6], uv[7], c[0], c[1], c[2], a], 4 * _SPRITE_FLOATS * self.count)
        self.count += 1

    func flush():
        if self.count == 0:
            return
        s := self.shader
        s.bind()
        s.set_mat4("u_proj", self.proj)
        s.set_int("u_tex", 0)
        self.texture.bind(0)
        gl.glBindVertexArray(self.vao)
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo)
        gl.glBufferSubData(gl.GL_ARRAY_BUFFER, 0, 4 * _SPRITE_FLOATS * self.count, self.staging.address())
        gl.glDrawElements(gl.GL_TRIANGLES, 6 * self.count, gl.GL_UNSIGNED_INT, 0)
        gl.glBindVertexArray(0)
        self.count = 0
        self.draw_calls += 1

    func _push(tex, x0, y0, x1, y1, x2, y2, x3, y3, u0, v0, u1, v1, c):
        if not self.active:
            raise("RuntimeError", "SpriteBatch : appeler begin() avant de dessiner")
        if tex != self.texture or self.count >= self.capacity:
            self.flush()
            self.texture = tex
        r := c[0]
        g := c[1]
        b := c[2]
        a := c[3] if len(c) > 3 else 1.0
        # écrit directement les 4 sommets dans le tampon d'envoi (un seul appel natif par sprite)
        self.staging.write_array("f32", [x0, y0, u0, v0, r, g, b, a, x1, y1, u1, v0, r, g, b, a, x2, y2, u1, v1, r, g, b, a, x3, y3, u0, v1, r, g, b, a], 4 * _SPRITE_FLOATS * self.count)
        self.count += 1

    # Dessine une texture (ou une Region) dans le rectangle (x, y, w, h). rotation (radians) autour de `origin`
    # (fraction du rectangle, [0.5, 0.5] = centre) ; flip_x / flip_y retournent l'image.
    func draw(image, x, y, w=null, h=null, color=null, rotation=0.0, origin=null, flip_x=false, flip_y=false):
        tex := image
        u0 := 0.0
        v0 := 0.0
        u1 := 1.0
        v1 := 1.0
        iw := 0
        ih := 0
        if image.kind == "region":
            tex = image.texture
            u0 = image.u0
            v0 = image.v0
            u1 = image.u1
            v1 = image.v1
            iw = image.w
            ih = image.h
        else:
            iw = tex.width
            ih = tex.height
        ww := (w if w != null else iw) * 1.0
        hh := (h if h != null else ih) * 1.0
        if flip_x:
            t := u0
            u0 = u1
            u1 = t
        if flip_y:
            t := v0
            v0 = v1
            v1 = t
        c := color if color != null else [1.0, 1.0, 1.0, 1.0]
        if rotation == 0.0 or rotation == 0:
            self._push(tex, x, y, x + ww, y, x + ww, y + hh, x, y + hh, u0, v0, u1, v1, c)
            return
        o := origin if origin != null else [0.5, 0.5]
        ox := x + ww * o[0]
        oy := y + hh * o[1]
        cs := math.cos(rotation)
        sn := math.sin(rotation)
        pts := [[x - ox, y - oy], [x + ww - ox, y - oy], [x + ww - ox, y + hh - oy], [x - ox, y + hh - oy]]
        q := []
        for p in pts:
            append(q, ox + p[0] * cs - p[1] * sn)
            append(q, oy + p[0] * sn + p[1] * cs)
        self._push(tex, q[0], q[1], q[2], q[3], q[4], q[5], q[6], q[7], u0, v0, u1, v1, c)

    # Rectangle plein d'une couleur.
    func rect(x, y, w, h, color):
        wt := self.renderer.white
        self._push(wt, x, y, x + w, y, x + w, y + h, x, y + h, 0.0, 0.0, 1.0, 1.0, color)

    # Segment d'épaisseur `width`.
    func line(x0, y0, x1, y1, color, width=1.0):
        dx := x1 - x0
        dy := y1 - y0
        l := math.sqrt((dx * dx + dy * dy) * 1.0)
        if l == 0:
            return
        nx := 0.0 - dy / l * width * 0.5
        ny := dx / l * width * 0.5
        wt := self.renderer.white
        self._push(wt, x0 + nx, y0 + ny, x1 + nx, y1 + ny, x1 - nx, y1 - ny, x0 - nx, y0 - ny, 0.0, 0.0, 1.0, 1.0, color)

    # Contour de rectangle.
    func rect_outline(x, y, w, h, color, width=1.0):
        self.rect(x, y, w, width, color)
        self.rect(x, y + h - width, w, width, color)
        self.rect(x, y, width, h, color)
        self.rect(x + w - width, y, width, h, color)

    # Disque (polygone de `segments` côtés).
    func circle(cx, cy, radius, color, segments=24):
        wt := self.renderer.white
        k := 0
        step := 2.0 * math.PI / segments
        while k < segments:
            a0 := step * k
            a1 := step * (k + 1)
            x0 := cx + math.cos(a0) * radius
            y0 := cy + math.sin(a0) * radius
            x1 := cx + math.cos(a1) * radius
            y1 := cy + math.sin(a1) * radius
            self._push(wt, cx, cy, x0, y0, x1, y1, cx, cy, 0.0, 0.0, 1.0, 1.0, color)
            k += 1

    func end():
        self.flush()
        self.active = false
        gl.glDisable(gl.GL_BLEND)
        gl.glEnable(gl.GL_DEPTH_TEST)
        gl.glEnable(gl.GL_CULL_FACE)

    func delete():
        if self.vao != 0:
            gl.delete("glDeleteBuffers", self.vbo)
            gl.delete("glDeleteBuffers", self.ebo)
            gl.delete("glDeleteVertexArrays", self.vao)
            self.staging.free()
            self.shader.delete()
            self.vao = 0

const _WHITE := [1.0, 1.0, 1.0, 1.0]

func _apply_blend(mode):
    if mode == "add":
        gl.glBlendFunc(gl.GL_SRC_ALPHA, gl.GL_ONE)
    elif mode == "multiply":
        gl.glBlendFunc(gl.GL_DST_COLOR, gl.GL_ONE_MINUS_SRC_ALPHA)
    else:
        gl.glBlendFunc(gl.GL_SRC_ALPHA, gl.GL_ONE_MINUS_SRC_ALPHA)

# UV des 4 coins (haut gauche, haut droit, bas droit, bas gauche) avec retournements (4 = H, 2 = V, 1 = diagonal).
func _tile_uvs(u0, v0, u1, v1, flags):
    du := u1 - u0
    dv := v1 - v0
    out := []
    for c in [[0, 0], [1, 0], [1, 1], [0, 1]]:
        x := c[0]
        y := c[1]
        if (flags & 2) != 0:
            y = 1 - y
        if (flags & 4) != 0:
            x = 1 - x
        if (flags & 1) != 0:
            t := x
            x = y
            y = t
        append(out, u0 + x * du)
        append(out, v0 + y * dv)
    return out

# ---------------------------------------------------------------------------------------------------------------------
# Tampon de quads statique : décors et couches de tuiles envoyés une fois à la carte, dessinés en un appel
# ---------------------------------------------------------------------------------------------------------------------

class QuadBuffer:
    func init(texture):
        self.texture = texture
        self.data = []
        self.count = 0
        self.vao = 0
        self.vbo = 0
        self.ebo = 0
        self.uploaded = 0

    func clear():
        self.data = []
        self.count = 0

    # Ajoute un quad (x, y, l, h) avec ses UV, retournements (voir SpriteBatch.draw_tile) et couleur.
    func add(x, y, w, h, u0, v0, u1, v1, flags=0, color=null):
        c := color if color != null else _WHITE
        a := c[3] if len(c) > 3 else 1.0
        uv := _tile_uvs(u0, v0, u1, v1, flags)
        for q in [x, y, uv[0], uv[1], c[0], c[1], c[2], a, x + w, y, uv[2], uv[3], c[0], c[1], c[2], a, x + w, y + h, uv[4], uv[5], c[0], c[1], c[2], a, x, y + h, uv[6], uv[7], c[0], c[1], c[2], a]:
            append(self.data, q)
        self.count += 1

    # Envoie les quads à la carte (à rappeler après des modifications).
    func upload():
        if self.vao == 0:
            self.vao = gl.gen("glGenVertexArrays")
            self.vbo = gl.gen("glGenBuffers")
            self.ebo = gl.gen("glGenBuffers")
        gl.glBindVertexArray(self.vao)
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo)
        n := len(self.data)
        vb := gl.f32_buffer(self.data if n > 0 else [0.0])
        gl.glBufferData(gl.GL_ARRAY_BUFFER, 4 * (n if n > 0 else 1), vb.address(), gl.GL_STATIC_DRAW)
        vb.free()
        gl.glEnableVertexAttribArray(0)
        gl.glVertexAttribPointer(0, 2, gl.GL_FLOAT, false, 32, 0)
        gl.glEnableVertexAttribArray(1)
        gl.glVertexAttribPointer(1, 2, gl.GL_FLOAT, false, 32, 8)
        gl.glEnableVertexAttribArray(2)
        gl.glVertexAttribPointer(2, 4, gl.GL_FLOAT, false, 32, 16)
        idx := []
        k := 0
        while k < self.count:
            b := 4 * k
            for q in [b, b + 1, b + 2, b + 2, b + 3, b]:
                append(idx, q)
            k += 1
        gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.ebo)
        ib := gl.u32_buffer(idx if len(idx) > 0 else [0])
        gl.glBufferData(gl.GL_ELEMENT_ARRAY_BUFFER, 4 * (len(idx) if len(idx) > 0 else 1), ib.address(), gl.GL_STATIC_DRAW)
        ib.free()
        gl.glBindVertexArray(0)
        self.uploaded = self.count

    # Dessine avec la projection du SpriteBatch actif (le lot en cours est vidé avant).
    func draw(batch):
        if self.uploaded == 0:
            return
        batch.flush()
        s := batch.shader
        s.bind()
        s.set_mat4("u_proj", batch.proj)
        s.set_int("u_tex", 0)
        self.texture.bind(0)
        gl.glBindVertexArray(self.vao)
        gl.glDrawElements(gl.GL_TRIANGLES, 6 * self.uploaded, gl.GL_UNSIGNED_INT, 0)
        gl.glBindVertexArray(0)
        batch.draw_calls += 1

    func delete():
        if self.vao != 0:
            gl.delete("glDeleteBuffers", self.vbo)
            gl.delete("glDeleteBuffers", self.ebo)
            gl.delete("glDeleteVertexArrays", self.vao)
            self.vao = 0

# ---------------------------------------------------------------------------------------------------------------------
# Modèles animés : skinning et morphing dans le shader (stdlib animation)
# ---------------------------------------------------------------------------------------------------------------------

const MAX_MORPH := 128          # cibles de morphing par primitive (poids non nuls évalués dans le shader)
const _MORPH_W := 2048         # largeur de la texture des écarts de morphing

const SKIN_VS := """#version 330 core
layout(location = 0) in vec3 a_pos;
layout(location = 1) in vec3 a_nrm;
layout(location = 2) in vec2 a_uv;
layout(location = 3) in vec4 a_joints;
layout(location = 4) in vec4 a_weights;
uniform mat4 u_model;
uniform mat4 u_vp;
uniform vec4 u_uv_rect;
uniform int u_skinned;
uniform sampler2D u_jtex;
uniform sampler2D u_mtex;
uniform int u_nmorph;
uniform int u_nverts;
uniform float u_mw[128];
out vec3 v_wpos;
out vec3 v_nrm;
out vec2 v_uv;
mat4 joint_matrix(float j) {
    int i = int(j + 0.5);
    return mat4(texelFetch(u_jtex, ivec2(0, i), 0), texelFetch(u_jtex, ivec2(1, i), 0),
                texelFetch(u_jtex, ivec2(2, i), 0), texelFetch(u_jtex, ivec2(3, i), 0));
}
vec3 morph_texel(int idx) {
    return texelFetch(u_mtex, ivec2(idx % 2048, idx / 2048), 0).xyz;
}
void main() {
    vec3 p = a_pos;
    vec3 n = a_nrm;
    for (int t = 0; t < u_nmorph; t++) {
        float w = u_mw[t];
        if (w != 0.0) {
            int base = (t * u_nverts + gl_VertexID) * 2;
            p += w * morph_texel(base);
            n += w * morph_texel(base + 1);
        }
    }
    mat4 m = u_model;
    if (u_skinned != 0) {
        mat4 sk = a_weights.x * joint_matrix(a_joints.x) + a_weights.y * joint_matrix(a_joints.y)
                + a_weights.z * joint_matrix(a_joints.z) + a_weights.w * joint_matrix(a_joints.w);
        m = u_model * sk;
    }
    vec4 wp = m * vec4(p, 1.0);
    v_wpos = wp.xyz;
    v_nrm = mat3(transpose(inverse(m))) * n;
    v_uv = u_uv_rect.xy + vec2(a_uv.x, 1.0 - a_uv.y) * u_uv_rect.zw;
    gl_Position = u_vp * wp;
}
"""

const _SKIN_FLOATS := 16       # pos 3, normale 3, uv 2, os 4, poids 4

# Primitive d'un modèle animation (dict de animation.load_gltf) sur la carte : os, poids ; écarts de morphing dans
# une texture RGBA32F (position puis normale, par cible et par sommet).
class SkinnedGpuMesh:
    func init(prim):
        mm := prim["mesh"]
        n := len(mm.positions)
        js := prim["joints"]
        ws := prim["weights"]
        tg := prim["targets"]
        self.skinned = js != null
        self.nverts = n
        self.morphs = len(tg) if len(tg) < MAX_MORPH else MAX_MORPH
        data := []
        k := 0
        while k < n:
            p := mm.positions[k]
            q := mm.normals[k] if mm.has_normals() else [0.0, 1.0, 0.0]
            uv := mm.uvs[k] if mm.has_uvs() else [0.0, 0.0]
            for x in [p[0], p[1], p[2], q[0], q[1], q[2], uv[0], uv[1]]:
                append(data, x)
            if js != null:
                j := js[k]
                w := ws[k]
                s := w[0] + w[1] + w[2] + w[3]
                if s <= 0.0:
                    s = 1.0
                for x in [j[0], j[1], j[2], j[3], w[0] / s, w[1] / s, w[2] / s, w[3] / s]:
                    append(data, x * 1.0)
            else:
                for x in [0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0]:
                    append(data, x)
            k += 1
        self.vao = gl.gen("glGenVertexArrays")
        gl.glBindVertexArray(self.vao)
        self.vbo = gl.gen("glGenBuffers")
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo)
        vb := gl.f32_buffer(data)
        gl.glBufferData(gl.GL_ARRAY_BUFFER, 4 * len(data), vb.address(), gl.GL_STATIC_DRAW)
        vb.free()
        stride := 4 * _SKIN_FLOATS
        sizes := [3, 3, 2, 4, 4]
        off := 0
        a := 0
        while a < len(sizes):
            gl.glEnableVertexAttribArray(a)
            gl.glVertexAttribPointer(a, sizes[a], gl.GL_FLOAT, false, stride, 4 * off)
            off += sizes[a]
            a += 1
        self.ebo = gl.gen("glGenBuffers")
        gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.ebo)
        ib := gl.u32_buffer(mm.indices)
        gl.glBufferData(gl.GL_ELEMENT_ARRAY_BUFFER, 4 * len(mm.indices), ib.address(), gl.GL_STATIC_DRAW)
        ib.free()
        self.index_count = len(mm.indices)
        gl.glBindVertexArray(0)
        self.mtex = 0
        if self.morphs > 0:
            texels := self.morphs * n * 2
            rows := (texels + _MORPH_W - 1) // _MORPH_W
            md := []
            t := 0
            while t < self.morphs:
                tp := tg[t]["positions"]
                tn := tg[t]["normals"]
                k = 0
                while k < n:
                    d := tp[k] if tp != null else [0.0, 0.0, 0.0]
                    e := tn[k] if tn != null else [0.0, 0.0, 0.0]
                    for x in [d[0], d[1], d[2], 0.0, e[0], e[1], e[2], 0.0]:
                        append(md, x * 1.0)
                    k += 1
                t += 1
            while len(md) < rows * _MORPH_W * 4:
                append(md, 0.0)
            mb := gl.f32_buffer(md)
            self.mtex = gl.gen("glGenTextures")
            gl.glBindTexture(gl.GL_TEXTURE_2D, self.mtex)
            gl.glPixelStorei(gl.GL_UNPACK_ALIGNMENT, 4)
            gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, gl.GL_RGBA32F, _MORPH_W, rows, 0, gl.GL_RGBA, gl.GL_FLOAT, mb.address())
            gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST)
            gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST)
            mb.free()

    func draw():
        gl.glBindVertexArray(self.vao)
        gl.glDrawElements(gl.GL_TRIANGLES, self.index_count, gl.GL_UNSIGNED_INT, 0)

    func delete():
        if self.vao != 0:
            gl.delete("glDeleteBuffers", self.vbo)
            gl.delete("glDeleteBuffers", self.ebo)
            gl.delete("glDeleteVertexArrays", self.vao)
            if self.mtex != 0:
                gl.delete("glDeleteTextures", self.mtex)
            self.vao = 0

# Texture flottante des matrices d'os (4 texels RGBA32F par os, une ligne par os).
class JointTexture:
    func init(count):
        self.count = count if count > 0 else 1
        self.id = gl.gen("glGenTextures")
        gl.glBindTexture(gl.GL_TEXTURE_2D, self.id)
        gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, gl.GL_RGBA32F, 4, self.count, 0, gl.GL_RGBA, gl.GL_FLOAT, 0)
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST)
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST)

    # buf : ffi.Buffer de 16 flottants 32 bits par os (animation.Animator.joint_buffer).
    func update(buf):
        gl.glBindTexture(gl.GL_TEXTURE_2D, self.id)
        gl.glPixelStorei(gl.GL_UNPACK_ALIGNMENT, 4)
        gl.glTexSubImage2D(gl.GL_TEXTURE_2D, 0, 0, 0, 4, self.count, gl.GL_RGBA, gl.GL_FLOAT, buf.address())

    func delete():
        if self.id != 0:
            gl.delete("glDeleteTextures", self.id)
            self.id = 0

# Modèle animé complet (animation.Model) : maillages, matériaux et textures glTF, squelettes, morphing.
class ModelRenderer:
    # texture_loader(image) -> Texture ; image = {"uri"} ou {"bytes"} (par défaut : PNG / JPEG / BMP décodés).
    func init(renderer, model, texture_loader=null):
        self.renderer = renderer
        self.model = model
        self.shader = Shader(SKIN_VS, LIT_FS)
        self.meshes = [[SkinnedGpuMesh(p) for p in prims] for prims in model.meshes]
        ld := texture_loader if texture_loader != null else (im) => _load_model_image(im)
        texs := []
        for im in model.images:
            t := null
            try:
                t = ld(im)
            catch e:
                t = null
            append(texs, t)
        self.materials = []
        for md in model.materials:
            tex := texs[md["texture"]] if md["texture"] >= 0 and md["texture"] < len(texs) else null
            mt := Material(md["color"], tex, 0.25, 32.0, false, md["emissive"])
            mt.double_sided = md["double_sided"]
            mt.transparent = md["alpha"] == "BLEND"
            append(self.materials, mt)
        self.default_material = Material()
        self.joints = [JointTexture(len(sk["joints"])) for sk in model.skins]
        self._mwbuf = ffi.Buffer(4 * MAX_MORPH)
        self._rest = null

    # Dessine le modèle dans la pose de l'animateur (animation.Animator, ou null = pose de repos), placé par `world`.
    func draw(animator=null, world=null):
        r := self.renderer
        a := animator
        if a == null:
            if self._rest == null:
                self._rest = _anim.Animator(self.model)
            a = self._rest
        wm := world if world != null else m3.mat4_identity()
        s := r.use_shader(self.shader)
        s.set_int("u_jtex", 1)
        s.set_int("u_mtex", 2)
        k := 0
        while k < len(self.joints):
            self.joints[k].update(a.joint_buffer(k))
            k += 1
        for i in self.model.order:
            nd := self.model.nodes[i]
            if nd["mesh"] < 0:
                continue
            sk := nd["skin"]
            if sk >= 0:
                s.set_mat4("u_model", wm)
                s.set_int("u_skinned", 1)
                gl.glActiveTexture(gl.GL_TEXTURE0 + 1)
                gl.glBindTexture(gl.GL_TEXTURE_2D, self.joints[sk].id)
                gl.glActiveTexture(gl.GL_TEXTURE0)
            else:
                s.set_mat4("u_model", m3.mat4_mul(wm, a.world_matrix(i)))
                s.set_int("u_skinned", 0)
            w := a.morph_weights(i)
            prims := self.model.meshes[nd["mesh"]]
            gms := self.meshes[nd["mesh"]]
            p := 0
            while p < len(gms):
                g := gms[p]
                nm := g.morphs if w != null else 0
                s.set_int("u_nmorph", nm)
                if nm > 0:
                    s.set_int("u_nverts", g.nverts)
                    wl := [w[j] * 1.0 if j < len(w) else 0.0 for j in 0..nm]
                    self._mwbuf.write_array("f32", wl)
                    gl.glUniform1fv(s.loc("u_mw[0]"), nm, self._mwbuf.address())
                    gl.glActiveTexture(gl.GL_TEXTURE0 + 2)
                    gl.glBindTexture(gl.GL_TEXTURE_2D, g.mtex)
                    gl.glActiveTexture(gl.GL_TEXTURE0)
                mi := prims[p]["material"]
                mat := self.materials[mi] if mi >= 0 and mi < len(self.materials) else self.default_material
                r._bind_material(mat, s)
                g.draw()
                r.stats["draws"] += 1
                p += 1
        gl.glDepthMask(true)

    func delete():
        for lst in self.meshes:
            for g in lst:
                g.delete()
        for j in self.joints:
            j.delete()
        self.shader.delete()

func _load_model_image(im):
    if "uri" in im and im["uri"] != null:
        return load_texture(im["uri"])
    if "bytes" in im:
        return texture_from_bytes(im["bytes"])
    return null
