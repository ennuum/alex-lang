# ALEX - rendu GPU des modèles animés (skinning, morphing) et des textures DDS / KTX2 / JPEG ; décodage BC par le
# processeur. Linux : affichage X11 nécessaire (make test-gl). ./alex run tests/gamedev/test_gl_assets.al
use os
use io
use gl
use gl.window as glw
use gl.render as gr
use gl.textures as gt
use animation
use math3d as m3
use testing
use string as _s
from testing use assert_eq, assert_true

const DATA := "tests/gamedev/data/"

if os.platform() != "windows" and os.getenv("DISPLAY") == null:
    print("GL_ASSETS: ignoré (pas d'affichage ; lancer sous Xvfb : make test-gl)")
else:
    w := glw.Window("test3", 64, 64, {"vsync": false})
    r := gr.Renderer(w)
    b := gr.SpriteBatch(r)

    func px(p, x, y):
        k := 4 * ((63 - y) * 64 + x)
        return [p[k], p[k + 1], p[k + 2], p[k + 3]]

    func quads(tex):
        r.begin_frame([0.0, 0.0, 0.0, 1.0])
        b.begin()
        b.draw(tex, 0, 0, 64, 64)
        b.end()
        p := w.read_pixels()
        return [px(p, 8, 8), px(p, 56, 8), px(p, 8, 56), px(p, 56, 56)]

    func t_compressed():
        exp := [[255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255], [255, 255, 255, 255]]
        for f in ["bc1.dds", "bc1.ktx2", "rgba.ktx2", "zlib.ktx2"]:
            assert_eq(quads(gr.load_texture(DATA + f, "nearest", "clamp", false)), exp)
        assert_eq(gt.info(DATA + "bc1.dds")["levels"], 4)
        q := quads(gr.load_texture(DATA + "bc3.dds", "nearest", "clamp", false))
        assert_eq(q[0], [255, 255, 0, 255])
        assert_eq(gl.errors(), [])

    testing.test("DDS / KTX2 (BC1, BC3, RGBA, zlib) sur la carte", t_compressed)

    func t_bc_software():
        data := io.read_bytes(DATA + "bc1.dds")
        p := gt.parse_dds(data)
        px8 := gt.decode_bc(p["format"], data, p["levels"][0]["chunks"][0][0], 8, 8)
        assert_eq(px8[0:4], [255, 0, 0, 255])
        assert_eq(px8[4 * (8 * 7 + 7):4 * (8 * 7 + 7) + 4], [255, 255, 255, 255])

    testing.test("décodage BC1 par le processeur (secours)", t_bc_software)

    func near(a, b, tol):
        k := 0
        while k < len(a):
            dd := a[k] - b[k]
            if dd < 0:
                dd = 0 - dd
            if dd > tol:
                return false
            k += 1
        return true

    func t_mobile_formats():
        # ETC2 (couleur - 2), EAC R11, ASTC 4x4 et 6x6 (blocs unis) : décodés par le pilote
        exp := [[255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255], [255, 255, 255, 255]]
        q := quads(gr.load_texture(DATA + "etc2.ktx2", "nearest", "clamp", false))
        k := 0
        while k < 4:
            assert_true(near(q[k], exp[k], 3))
            k += 1
        assert_eq(quads(gr.load_texture(DATA + "astc4.ktx2", "nearest", "clamp", false)), exp)
        t6 := gr.load_texture(DATA + "astc6.ktx2", "nearest", "clamp", false)
        assert_eq([t6.width, t6.height, t6.format], [12, 12, "ASTC_6x6"])
        assert_eq(quads(t6), exp)
        e := gr.load_texture(DATA + "eac_r11.ktx2", "nearest", "clamp", false)
        q = quads(e)
        assert_true(near(q[0], [255, 0, 0, 255], 2) and near(q[1], [0, 0, 0, 255], 2) and near(q[2], [128, 0, 0, 255], 2))
        assert_eq(gl.errors(), [])

    testing.test("ETC2, EAC, ASTC 4x4 / 6x6 (KTX2)", t_mobile_formats)

    func t_zstd():
        exp := [[255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255], [255, 255, 255, 255]]
        assert_eq(gt.info(DATA + "zstd_bc1.ktx2")["supercompression"], "zstd")
        t := gr.load_texture(DATA + "zstd_bc1.ktx2", "nearest", "clamp", true)
        assert_eq(quads(t), exp)
        assert_eq(t.read_rgba(3)[0:4], [255, 0, 0, 255])

    testing.test("KTX2 supercompressé zstd (4 niveaux)", t_zstd)

    func t_shapes():
        faces := [[255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255], [255, 255, 0, 255], [255, 0, 255, 255], [0, 255, 255, 255]]
        for f in ["cube_bc1.dds", "cube_rgba.ktx2"]:
            c := gr.load_cubemap(DATA + f)
            assert_eq([c.shape, c.faces], ["cube", 6])
            k := 0
            while k < 6:
                assert_eq(c.read_rgba(0, k)[0:4], faces[k])
                k += 1
        c2 := gr.load_cubemap(DATA + "cube_bc1.dds")
        assert_eq(c2.read_rgba(2, 4)[0:4], faces[4])            # niveau 2 de la face +Z
        a := gr.load_texture(DATA + "array_bc1.ktx2", "nearest", "clamp", true)
        assert_eq([a.shape, a.layers], ["2d_array", 3])
        p := a.read_rgba(0)
        assert_eq([p[0:4], p[256:260], p[512:516]], [[255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255]])
        assert_eq(a.read_rgba(1)[128:132], [0, 0, 255, 255])
        d := gr.load_texture(DATA + "array_rgba.dds")
        assert_eq([d.shape, d.layers, d.read_rgba(0)[64:68]], ["2d_array", 2, [0, 255, 255, 255]])
        v := gr.load_texture(DATA + "vol_rgba.dds", "nearest", "clamp", false)
        assert_eq([v.shape, v.depth], ["3d", 4])
        pv := v.read_rgba(0)
        assert_eq([pv[0:4], pv[64:68], pv[128:132], pv[192:196]], [[255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255], [255, 255, 255, 255]])
        ca := gr.load_texture(DATA + "cubearray_rgba.ktx2", "nearest", "clamp", false)
        assert_eq([ca.shape, ca.layers], ["cube_array", 2])
        pc := ca.read_rgba(0)
        assert_eq([pc[0:4], pc[16 * 5:16 * 5 + 4], pc[16 * 6:16 * 6 + 4], pc[16 * 11:16 * 11 + 4]], [faces[0], faces[5], faces[5], faces[0]])
        info := gt.info(DATA + "cubearray_rgba.ktx2")
        assert_eq([info["target"], info["layers"], info["faces"]], ["cube_array", 2, 6])
        assert_eq(gl.errors(), [])

    testing.test("cubemaps, tableaux, tableaux de cubemaps, volumes (DDS / KTX2)", t_shapes)

    func t_skybox():
        c := gr.load_cubemap(DATA + "cube_rgba.ktx2", "nearest", false)
        sky := gr.Skybox(r, c)
        # regarder vers +X, -Z, +Y : couleur de la face au centre de l'écran
        for case in [[[1.0, 0.0, 0.0], [255, 0, 0]], [[0.0, 0.0, -1.0], [0, 255, 255]], [[-1.0, 0.0, 0.0], [0, 255, 0]], [[0.0, 0.0, 1.0], [255, 0, 255]]]:
            r.begin_frame([0.0, 0.0, 0.0, 1.0])
            r.set_perspective(m3.radians(60), [5.0, 1.0, 3.0], [5.0 + case[0][0], 1.0 + case[0][1], 3.0 + case[0][2]])
            sky.draw()
            c0 := px(w.read_pixels(), 32, 32)
            assert_eq(c0[0:3], case[1])
        sky.delete()
        # six images (PNG) -> cubemap
        c6 := gr.load_cubemap([DATA + "sky_" + t + ".png" for t in ["px", "nx", "py", "ny", "pz", "nz"]], "nearest", false)
        sky = gr.Skybox(r, c6)
        r.begin_frame([0.0, 0.0, 0.0, 1.0])
        r.set_perspective(m3.radians(60), [0.0, 0.0, 0.0], [0.0, 0.0, -1.0])
        sky.draw()
        assert_eq(px(w.read_pixels(), 32, 32)[0:3], [0, 255, 255])
        sky.delete()
        assert_eq(gl.errors(), [])

    testing.test("Skybox (cubemap à l'infini)", t_skybox)

    func t_morph6():
        # 6 cibles ; seule la 6e a un poids : le sommet haut en x = 6 monte de 1 (au-delà des 4 cibles d'avant)
        m := animation.load_gltf(DATA + "morph6.gltf")
        mr := gr.ModelRenderer(r, m)
        a := animation.Animator(m)
        a.update(0.0)
        r.begin_frame([0.0, 0.0, 0.0, 1.0])
        r.set_view_projection(m3.mat4_look_at([3.0, 1.0, 8.0], [3.0, 1.0, 0.0], [0.0, 1.0, 0.0]),
                              m3.mat4_ortho(-3.0, 3.0, -3.0, 3.0, 0.1, 20.0), [3.0, 1.0, 8.0])
        mr.draw(a)
        p := w.read_pixels()
        # pixel x = X * 64 / 6, y = (4 - Y) * 64 / 6
        lit := px(p, 60, 26)            # (5,7 ; 1,5) : dans la pointe soulevée
        empty := px(p, 32, 26)          # (3 ; 1,5) : au-dessus de la bande
        assert_true(lit[0] + lit[1] + lit[2] > 60)
        assert_eq(empty[0:3], [0, 0, 0])
        assert_true(px(p, 32, 37)[0] > 20)                     # la bande elle-même (3 ; 0,5)
        assert_eq(gl.errors(), [])

    testing.test("morphing : plus de 4 cibles dans le shader", t_morph6)

    func t_basis_refused():
        msg := ""
        try:
            gr.load_texture(DATA + "basis.ktx2")
        catch e:
            msg = str(e)
        assert_true(len(msg) > 0)
        assert_true(_s.contains(msg, "Basis"))

    testing.test("Basis Universal : refus expliqué", t_basis_refused)

    func t_jpeg_texture():
        t := gr.load_texture(DATA + "photo420.jpg", "nearest", "clamp", false)
        assert_eq([t.width, t.height], [202, 148])

    testing.test("texture JPEG", t_jpeg_texture)

    func t_skinned():
        m := animation.load_gltf(DATA + "bras.gltf")
        mr := gr.ModelRenderer(r, m)
        a := animation.Animator(m)
        func draw():
            r.begin_frame([0.0, 0.0, 0.0, 1.0])
            r.set_view_projection(m3.mat4_look_at([1.5, 1.0, 8.0], [1.5, 1.0, 0.0], [0.0, 1.0, 0.0]),
                                  m3.mat4_ortho(-3.0, 3.0, -3.0, 3.0, 0.1, 20.0), [1.5, 1.0, 8.0])
            mr.draw(a)
            return w.read_pixels()
        p := draw()
        # projection : pixel x = (x + 1,5) * 64 / 6, pixel y = (4 - y) * 64 / 6
        # repos : colonne rouge en x = 0 jusqu'à y = 2 : (0 ; 1,9) -> pixel (16, 22) rouge ; base en x = 0
        assert_true(px(p, 16, 22)[0] > 30)
        assert_true(px(p, 27, 40)[0] < 10)
        assert_true(px(p, 52, 30)[1] < 10)            # quad au repos : s'arrête à y = 1
        a.blend([["plie", 1.0], ["morph", 1.0]])
        a.update(0.999999)
        p = draw()
        # pliée : le haut de la colonne a quitté (0 ; 1,9) ; la base est passée en x = 1 (pixel 27)
        assert_true(px(p, 16, 22)[0] < 10)
        assert_true(px(p, 27, 40)[0] > 30)
        # quad morphé : le coin (4, 2) monte, (3,9 ; 1,2) -> pixel (52, 30) couvert (gris éclairé)
        assert_true(px(p, 52, 30)[1] > 60)
        assert_eq(gl.errors(), [])

    testing.test("modèle skinné + morphing (GPU)", t_skinned)

    failed := testing.run()
    w.close()
    if failed > 0:
        raise("AssertionError", str(failed) + " test(s) gl assets en échec")
    print("GL_ASSETS: OK")
