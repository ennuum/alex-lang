# ALEX - tests du module file (ALEX pur). Lancer depuis la racine : ./alex run tests/test_file.al
use file
use filesystem as fs
use io
use collections as _c
use os
from core use len
use string as _s
use testing
from testing use assert_eq, assert_true, assert_false, assert_null, assert_raises

_ctx := {"dir": null}

func setup():
    _ctx["dir"] = fs.make_temp_dir("alex_test_file_")

func teardown():
    fs.remove_tree(_ctx["dir"], true)

func P(rel):
    return os.join(_ctx["dir"], rel)

testing.before_each(setup)
testing.after_each(teardown)

func t_basic():
    assert_false(file.exists(P("a.txt")))
    file.write(P("a.txt"), "bonjour")
    assert_true(file.exists(P("a.txt")))
    assert_eq(file.read(P("a.txt")), "bonjour")
    assert_eq(file.size(P("a.txt")), 7)
    file.append(P("a.txt"), " monde")
    assert_eq(file.read(P("a.txt")), "bonjour monde")
    file.write(P("a.txt"), "")
    assert_eq(file.read(P("a.txt")), "")
    file.append(P("neuf.txt"), "x")
    assert_eq(file.read(P("neuf.txt")), "x")
    assert_false(file.exists(P("")))
    assert_false(file.exists(_ctx["dir"]))

testing.test("write / append / read / exists / size", t_basic)

func t_exact():
    # contenu rendu tel quel : fins de ligne, Unicode, espaces
    text := "é😀\r\nligne \n\n  fin\r"
    file.write(P("e.txt"), text)
    assert_eq(file.read(P("e.txt")), text)
    assert_eq(file.size(P("e.txt")), 22)

testing.test("read rend le contenu exact", t_exact)

func t_read_or():
    assert_eq(file.read_or(P("absent")), null)
    assert_eq(file.read_or(P("absent"), "défaut"), "défaut")
    file.write(P("a"), "x")
    assert_eq(file.read_or(P("a"), "défaut"), "x")
    assert_raises(() => file.read_or(5), "TypeError")

testing.test("read_or", t_read_or)

func t_lines():
    file.write(P("l"), "a\nb\nc\n")
    assert_eq(file.read_lines(P("l")), ["a", "b", "c"])
    assert_eq(file.read_lines(P("l"), true), ["a\n", "b\n", "c\n"])
    file.write(P("l"), "a\nb\nc")
    assert_eq(file.read_lines(P("l")), ["a", "b", "c"])
    assert_eq(file.read_lines(P("l"), true), ["a\n", "b\n", "c"])
    file.write(P("l"), "a\r\nb\rc\n")
    assert_eq(file.read_lines(P("l")), ["a", "b", "c"])
    assert_eq(file.read_lines(P("l"), true), ["a\n", "b\n", "c\n"])
    file.write(P("l"), "")
    assert_eq(file.read_lines(P("l")), [])
    file.write(P("l"), "\n")
    assert_eq(file.read_lines(P("l")), [""])
    file.write(P("l"), "\n\nx\n\n")
    assert_eq(file.read_lines(P("l")), ["", "", "x", ""])
    file.write(P("l"), "é\n😀\n")
    assert_eq(file.read_lines(P("l")), ["é", "😀"])
    assert_raises(() => file.read_lines(P("absent")), "IoError")

testing.test("read_lines : fins de ligne et cas limites", t_lines)

func t_count_head_tail():
    file.write_lines(P("n"), ["1", "2", "3", "4", "5"])
    assert_eq(file.line_count(P("n")), 5)
    assert_eq(file.head(P("n"), 2), ["1", "2"])
    assert_eq(file.tail(P("n"), 2), ["4", "5"])
    assert_eq(file.head(P("n"), 0), [])
    assert_eq(file.tail(P("n"), 0), [])
    assert_eq(file.head(P("n"), 99), ["1", "2", "3", "4", "5"])
    assert_eq(file.tail(P("n"), 99), ["1", "2", "3", "4", "5"])
    assert_eq(file.head(P("n")), ["1", "2", "3", "4", "5"])
    file.write(P("vide"), "")
    assert_eq(file.line_count(P("vide")), 0)
    assert_eq(file.head(P("vide")), [])
    assert_raises(() => file.head(P("n"), -1), "ValueError")
    assert_raises(() => file.tail(P("n"), "2"), "ValueError")
    assert_raises(() => file.head(P("n"), 1.5), "ValueError")

testing.test("line_count / head / tail", t_count_head_tail)

func t_write_lines():
    file.write_lines(P("w"), ["a", "b"])
    assert_eq(file.read(P("w")), "a\nb\n")
    file.append_lines(P("w"), ["c"])
    assert_eq(file.read(P("w")), "a\nb\nc\n")
    file.write_lines(P("w"), ["x", "y"], "\r\n")
    assert_eq(file.read(P("w")), "x\r\ny\r\n")
    file.write_lines(P("w"), [])
    assert_eq(file.read(P("w")), "")
    file.write_lines(P("w"), ("t", "u"))
    assert_eq(file.read(P("w")), "t\nu\n")
    assert_raises(() => file.write_lines(P("w"), "abc"), "TypeError")
    assert_raises(() => file.write_lines(P("w"), ["a", 1]), "TypeError")
    assert_raises(() => file.append_lines(P("w"), [null]), "TypeError")
    # une liste invalide ne modifie pas le fichier
    assert_eq(file.read(P("w")), "t\nu\n")

testing.test("write_lines / append_lines", t_write_lines)

func t_type_errors():
    assert_raises(() => file.read(5), "TypeError")
    assert_raises(() => file.write(P("z"), 5), "TypeError")
    assert_raises(() => file.write(5, "x"), "TypeError")
    assert_raises(() => file.append(P("z"), null), "TypeError")
    assert_raises(() => file.exists(null), "TypeError")
    assert_raises(() => file.read(P("absent")), "IoError")
    assert_raises(() => file.write(P("no/such/dir.txt"), "x"), "IoError")
    assert_raises(() => file.size(P("absent")), "IoError")

testing.test("erreurs de type et d'E/S", t_type_errors)

func t_delete():
    file.write(P("d"), "x")
    assert_true(file.delete(P("d")))
    assert_false(file.exists(P("d")))
    assert_false(file.delete(P("d"), true))
    assert_raises(() => file.delete(P("d")), "IoError", "introuvable")
    # un dossier n'est pas un fichier
    fs.ensure_dir(P("dir"))
    assert_raises(() => file.delete(P("dir")), "IoError")
    assert_true(fs.is_dir(P("dir")))

testing.test("delete", t_delete)

func t_atomic():
    file.write_atomic(P("c.json"), "v1")
    assert_eq(file.read(P("c.json")), "v1")
    file.write_atomic(P("c.json"), "v2 é")
    assert_eq(file.read(P("c.json")), "v2 é")
    # aucun fichier temporaire ne reste
    assert_eq(fs.list_dir(_ctx["dir"]), ["c.json"])
    # dossier cible : refus, rien d'écrit
    fs.ensure_dir(P("dir"))
    assert_raises(() => file.write_atomic(P("dir"), "x"), "IoError", "dossier")
    assert_eq(fs.list_dir(P("dir")), [])
    # dossier parent absent : échec propre, aucun résidu
    assert_raises(() => file.write_atomic(P("nope/f.txt"), "x"), "IoError")
    assert_eq(fs.list_dir(_ctx["dir"]), ["c.json", "dir"])
    assert_raises(() => file.write_atomic(P("c.json"), 1), "TypeError")
    assert_eq(file.read(P("c.json")), "v2 é")

testing.test("write_atomic", t_atomic)

func t_atomic_mode():
    if os.platform() == "windows":
        return null
    file.write(P("m"), "x")
    os.chmod(P("m"), "600")
    file.write_atomic(P("m"), "y")
    assert_eq(file.read(P("m")), "y")
    assert_eq(os.permissions(P("m")) % 512, 384)

testing.test("write_atomic conserve les droits du fichier remplacé", t_atomic_mode)

func t_open_read():
    file.write(P("r"), "ab\ncde\nf")
    f := file.open(P("r"))
    assert_eq(f.path, P("r"))
    assert_eq(f.mode, "r")
    assert_false(f.eof())
    assert_eq(f.read_line(), "ab\n")
    assert_eq(f.read_line(), "cde\n")
    assert_false(f.eof())
    assert_eq(f.read_line(), "f")
    assert_true(f.eof())
    assert_eq(f.read_line(), "")
    assert_eq(f.read(), "")
    f.rewind()
    assert_false(f.eof())
    assert_eq(f.read(), "ab\ncde\nf")
    f.rewind()
    assert_eq(f.read_lines(), ["ab", "cde", "f"])
    f.rewind()
    assert_eq(f.read_lines(true), ["ab\n", "cde\n", "f"])
    assert_false(f.is_closed())
    f.close()
    assert_true(f.is_closed())

testing.test("File : lecture ligne à ligne", t_open_read)

func t_read_size():
    file.write(P("r"), "é😀\nxyz\nw")
    f := file.open(P("r"))
    assert_eq(f.read(1), "é")
    assert_eq(f.read(1), "😀")
    assert_eq(f.read(0), "")
    assert_eq(f.read(2), "\nx")
    # read_line reprend au milieu de la ligne courante
    assert_eq(f.read_line(), "yz\n")
    assert_eq(f.read(10), "w")
    assert_eq(f.read(3), "")
    assert_true(f.eof())
    f.rewind()
    assert_eq(f.read(100), "é😀\nxyz\nw")
    f.rewind()
    assert_eq(f.read(3), "é😀\n")
    assert_eq(f.read(), "xyz\nw")
    assert_raises(() => f.read(-1), "ValueError")
    assert_raises(() => f.read("1"), "ValueError")
    f.close()

testing.test("File.read(size) : positions en caractères", t_read_size)

func t_read_crlf():
    file.write(P("r"), "a\r\nb\rc")
    f := file.open(P("r"))
    assert_eq(f.read_lines(), ["a", "b", "c"])
    f.close()
    g := file.open(P("r"))
    assert_eq(g.read(), "a\nb\nc")
    g.close()

testing.test("File : fins de ligne normalisées à la lecture", t_read_crlf)

func t_open_write():
    file.write(P("w"), "ancien")
    f := file.open(P("w"), "w")
    # "w" vide le fichier dès l'ouverture
    assert_eq(file.read(P("w")), "")
    assert_eq(f.write("é"), 1)
    assert_eq(f.write(""), 0)
    assert_eq(f.write_line("tre"), 4)
    assert_eq(f.write_lines(["1", "2"]), 4)
    # les écritures sont immédiates : visibles sans flush
    assert_eq(file.read(P("w")), "étre\n1\n2\n")
    f.flush()
    f.write_line()
    f.close()
    assert_eq(file.read(P("w")), "étre\n1\n2\n\n")
    assert_true(f.is_closed())

testing.test("File : écriture immédiate, flush, close", t_open_write)

func t_open_append():
    file.write(P("a"), "début\n")
    f := file.open(P("a"), "a")
    assert_eq(file.read(P("a")), "début\n")
    f.write_line("suite")
    f.close()
    assert_eq(file.read(P("a")), "début\nsuite\n")
    g := file.open(P("neuf"), "a")
    assert_true(file.exists(P("neuf")))
    g.close()
    assert_eq(file.read(P("neuf")), "")

testing.test("File : mode a", t_open_append)

func t_immediate():
    f := file.open(P("big"), "w")
    i := 0
    while i < 1000:
        f.write("x")
        i += 1
    assert_eq(file.size(P("big")), 1000)
    assert_eq(f.tell(), 1000)
    f.close()
    assert_eq(file.size(P("big")), 1000)

testing.test("File : 1000 écritures successives", t_immediate)

func t_modes():
    file.write(P("m"), "x")
    r := file.open(P("m"))
    assert_raises(() => r.write("y"), "IoError", "pas ouvert en écriture")
    assert_raises(() => r.write_line("y"), "IoError")
    assert_raises(() => r.write_lines(["y"]), "IoError")
    assert_raises(() => r.truncate(), "IoError")
    r.flush()
    r.close()
    w := file.open(P("m"), "w")
    assert_raises(() => w.read(), "IoError", "pas ouvert en lecture")
    assert_raises(() => w.read_line(), "IoError")
    assert_raises(() => w.read_lines(), "IoError")
    assert_raises(() => w.eof(), "IoError")
    w.close()
    assert_raises(() => file.open(P("m"), 3), "TypeError")
    assert_raises(() => file.open(5), "TypeError")
    assert_raises(() => file.open(P("absent")), "IoError")
    assert_raises(() => file.open(P("absent"), "r+"), "IoError")
    assert_raises(() => file.open(P("no/dir.txt"), "w"), "IoError")
    assert_raises(() => file.open(_ctx["dir"]), "IoError")

testing.test("File : modes et erreurs d'ouverture", t_modes)

func t_closed():
    file.write(P("c"), "a\nb\n")
    f := file.open(P("c"))
    f.close()
    f.close()
    assert_raises(() => f.read(), "ValueError", "fermé")
    assert_raises(() => f.read_line(), "ValueError")
    assert_raises(() => f.eof(), "ValueError")
    assert_raises(() => f.flush(), "ValueError")
    w := file.open(P("c"), "w")
    w.write("x")
    w.close()
    assert_eq(file.read(P("c")), "x")
    assert_raises(() => w.write("y"), "ValueError", "fermé")
    assert_eq(file.read(P("c")), "x")

testing.test("File : fichier fermé", t_closed)

func t_write_validation():
    w := file.open(P("v"), "w")
    assert_raises(() => w.write(5), "TypeError")
    assert_raises(() => w.write_line(7), "TypeError")
    assert_raises(() => w.write_lines(["a", 1]), "TypeError")
    assert_raises(() => w.write_lines("abc"), "TypeError")
    w.close()
    # tout ou rien : rien n'a été écrit
    assert_eq(file.read(P("v")), "")

testing.test("File : validation des arguments d'écriture", t_write_validation)

func t_with_open():
    file.write(P("w"), "1\n2\n3\n")
    assert_eq(file.with_open(P("w"), (f) => len(f.read_lines())), 3)
    holder := {"f": null}
    func keep(f):
        holder["f"] = f
        return f.read_line()
    assert_eq(file.with_open(P("w"), keep), "1\n")
    assert_true(holder["f"].is_closed())
    func writer(f):
        f.write_line("a")
        f.write_line("b")
        return "ok"
    assert_eq(file.with_open(P("o"), writer, "w"), "ok")
    assert_eq(file.read(P("o")), "a\nb\n")
    func boom(f):
        holder["f"] = f
        f.write("partiel")
        raise("CustomError", "échec voulu")
    assert_raises(() => file.with_open(P("o"), boom, "w"), "CustomError", "échec voulu")
    # fermé malgré l'erreur, et le contenu déjà écrit est conservé
    assert_true(holder["f"].is_closed())
    assert_eq(file.read(P("o")), "partiel")
    assert_raises(() => file.with_open(P("absent"), (f) => 1), "IoError")
    assert_raises(() => file.with_open(P("w"), (f) => 1, "zz"), "ValueError")

testing.test("with_open : fermeture garantie", t_with_open)

func t_roundtrip():
    lines := []
    i := 0
    while i < 600:
        _c.append(lines, "ligne " + str(i) + " é")
        i += 1
    file.write_lines(P("big"), lines)
    assert_eq(file.line_count(P("big")), 600)
    assert_eq(file.read_lines(P("big")), lines)
    assert_eq(file.head(P("big"), 1), ["ligne 0 é"])
    assert_eq(file.tail(P("big"), 1), ["ligne 599 é"])
    f := file.open(P("big2"), "w")
    f.write_lines(lines)
    f.close()
    assert_eq(file.read(P("big2")), file.read(P("big")))

testing.test("aller-retour sur un fichier de 600 lignes", t_roundtrip)

func t_io_primitives():
    p := P("prim.bin")
    io.create_file(p)
    assert_raises(() => io.create_file(p), "IoError", "existe déjà")
    assert_eq(io.read_bytes(p), [])
    io.write_bytes(p, [1, 2, 255, 0, 10])
    assert_eq(io.read_bytes(p), [1, 2, 255, 0, 10])
    assert_eq(io.read_bytes(p, 2, 2), [255, 0])
    assert_eq(io.read_bytes(p, 4, 100), [10])
    assert_eq(io.read_bytes(p, 5), [])
    assert_eq(io.read_bytes(p, 99), [])
    assert_eq(io.write_bytes_at(p, [7], 1), 1)
    assert_eq(io.read_bytes(p), [1, 7, 255, 0, 10])
    # au-delà de la fin : le trou est rempli de zéros
    assert_eq(io.write_bytes_at(p, [9, 9], 7), 2)
    assert_eq(io.read_bytes(p), [1, 7, 255, 0, 10, 0, 0, 9, 9])
    assert_eq(io.write_bytes_at(p, [5]), 1)
    assert_eq(len(io.read_bytes(p)), 10)
    io.truncate(p, 3)
    assert_eq(io.read_bytes(p), [1, 7, 255])
    io.truncate(p, 5)
    assert_eq(io.read_bytes(p), [1, 7, 255, 0, 0])
    assert_raises(() => io.write_bytes(p, [256]), "ArgumentError")
    assert_raises(() => io.write_bytes(p, [-1]), "ArgumentError")
    assert_raises(() => io.write_bytes(p, ["a"]), "TypeError")
    assert_raises(() => io.write_bytes(p, "abc"), "TypeError")
    assert_raises(() => io.read_bytes(p, -1), "ArgumentError")
    assert_raises(() => io.read_bytes(P("absent")), "IoError")
    assert_raises(() => io.read_bytes(_ctx["dir"]), "IoError")
    assert_raises(() => io.write_bytes_at(P("absent"), [1], 0), "IoError")
    assert_raises(() => io.truncate(P("absent"), 0), "IoError")
    assert_raises(() => io.truncate(p, -1), "ArgumentError")

testing.test("io : octets à une position, troncature, création exclusive", t_io_primitives)

func t_io_text_positions():
    p := P("t.txt")
    # é = 2 octets, 😀 = 4 octets, "\r\n" = 2 octets rendus "\n"
    io.write_file(p, "é😀\r\nab\rcd\nfin")
    assert_eq(io.read_line(p), ["é😀\n", 8])
    assert_eq(io.read_line(p, 8), ["ab\n", 3])
    assert_eq(io.read_line(p, 11), ["cd\n", 3])
    assert_eq(io.read_line(p, 14), ["fin", 3])
    assert_eq(io.read_line(p, 17), ["", 0])
    assert_eq(io.read_line(p, 99), ["", 0])
    assert_eq(io.read_text(p, 0, 2), ["é😀", 6])
    assert_eq(io.read_text(p, 0, 3), ["é😀\n", 8])
    assert_eq(io.read_text(p, 6, 0), ["", 0])
    assert_eq(io.read_text(p), ["é😀\nab\ncd\nfin", 17])
    # au milieu d'un caractère : l'octet orphelin compte pour un caractère
    assert_eq(io.read_text(p, 1, 1)[1], 1)
    assert_eq(io.write_at(p, "XY", 0), 2)
    assert_eq(io.read_text(p, 0, 3)[0], "XY😀")
    assert_eq(io.write_at(p, "!"), 1)
    assert_eq(io.read_text(p)[0], "XY😀\nab\ncd\nfin!")
    assert_raises(() => io.read_text(P("absent")), "IoError")
    assert_raises(() => io.read_line(P("absent")), "IoError")
    assert_raises(() => io.write_at(P("absent"), "x", 0), "IoError")
    assert_raises(() => io.write_at(p, 5, 0), "TypeError")
    assert_raises(() => io.read_text(p, -1), "ArgumentError")

testing.test("io : texte à une position (octets consommés, fins de ligne)", t_io_text_positions)

func t_mode_rplus():
    file.write(P("m"), "hello world")
    f := file.open(P("m"), "r+")
    assert_eq(f.mode, "r+")
    assert_true(f.readable)
    assert_true(f.writable)
    assert_eq(f.read(5), "hello")
    assert_eq(f.tell(), 5)
    # écrase sur place, sans tronquer
    assert_eq(f.write("_W"), 2)
    assert_eq(f.tell(), 7)
    assert_eq(f.read(), "orld")
    assert_eq(f.size(), 11)
    assert_eq(file.read(P("m")), "hello_World")
    f.close()

testing.test("File : mode r+", t_mode_rplus)

func t_mode_wplus():
    f := file.open(P("m"), "w+")
    assert_eq(f.mode, "w+")
    f.write("abc\ndef\n")
    assert_true(f.eof())
    f.rewind()
    assert_false(f.eof())
    assert_eq(f.read_line(), "abc\n")
    assert_eq(f.read_lines(), ["def"])
    f.close()
    # w+ vide un fichier existant
    file.write(P("m"), "ancien contenu")
    g := file.open(P("m"), "w+")
    assert_eq(g.read(), "")
    g.close()

testing.test("File : mode w+", t_mode_wplus)

func t_mode_append():
    file.write(P("m"), "ab")
    f := file.open(P("m"), "a+")
    assert_eq(f.tell(), 2)
    assert_true(f.eof())
    f.seek(0)
    assert_eq(f.read(1), "a")
    # toute écriture va à la fin, quelle que soit la position
    f.write("Z")
    assert_eq(file.read(P("m")), "abZ")
    assert_eq(f.tell(), 3)
    f.seek(0)
    assert_eq(f.read(), "abZ")
    f.close()
    g := file.open(P("m"), "a")
    assert_eq(g.tell(), 3)
    assert_raises(() => g.read(), "IoError")
    g.seek(0)
    g.write("!")
    assert_eq(g.tell(), 4)
    g.close()
    assert_eq(file.read(P("m")), "abZ!")

testing.test("File : modes a et a+", t_mode_append)

func t_mode_exclusive():
    f := file.open(P("new"), "x")
    assert_eq(f.mode, "x")
    f.write("1")
    f.close()
    assert_raises(() => file.open(P("new"), "x"), "IoError", "existe déjà")
    assert_raises(() => file.open(P("new"), "x+"), "IoError", "existe déjà")
    assert_raises(() => file.open(P("new"), "xb"), "IoError")
    assert_eq(file.read(P("new")), "1")
    g := file.open(P("new2"), "x+")
    g.write("ab")
    g.rewind()
    assert_eq(g.read(), "ab")
    g.close()
    if os.platform() != "windows":
        # un lien symbolique, même cassé, compte comme « existe » : jamais suivi
        os.run("ln", ["-s", P("cible-absente"), P("lien")])
        assert_raises(() => file.open(P("lien"), "x"), "IoError", "existe déjà")
        assert_false(fs.exists(P("cible-absente")))

testing.test("File : mode x (création exclusive)", t_mode_exclusive)

func t_mode_strings():
    file.write(P("m"), "x")
    assert_eq(file.open(P("m"), "b+r").mode, "r+b")
    assert_eq(file.open(P("m"), "rb+").mode, "r+b")
    assert_eq(file.open(P("m"), "r+b").mode, "r+b")
    assert_eq(file.open(P("m"), "rb").mode, "rb")
    assert_eq(file.open(P("m"), "r").mode, "r")
    assert_true(file.open(P("m"), "rb").binary)
    assert_false(file.open(P("m"), "r+").binary)
    bad := ["", "q", "rr", "r++", "rbb", "rw", "xa", "r+x", "t", " r", "rt"]
    for m in bad:
        assert_raises(() => file.open(P("m"), m), "ValueError", "mode invalide")

testing.test("File : analyse des modes", t_mode_strings)

func t_seek_tell():
    # 2 + 4 + 3 = 9 octets
    file.write(P("s"), "é😀abc")
    f := file.open(P("s"))
    assert_eq(f.tell(), 0)
    assert_eq(f.size(), 9)
    assert_eq(f.read(1), "é")
    assert_eq(f.tell(), 2)
    assert_eq(f.read(1), "😀")
    assert_eq(f.tell(), 6)
    assert_eq(f.seek(-1, 2), 8)
    assert_eq(f.read(), "c")
    assert_true(f.eof())
    assert_eq(f.seek(-3, 1), 6)
    assert_eq(f.read(2), "ab")
    assert_eq(f.seek(2), 2)
    assert_eq(f.read(1), "😀")
    assert_eq(f.seek(100), 100)
    assert_eq(f.read(), "")
    assert_eq(f.read_line(), "")
    assert_true(f.eof())
    f.rewind()
    assert_eq(f.tell(), 0)
    assert_raises(() => f.seek(-1), "ValueError", "négative")
    assert_raises(() => f.seek(-100, 1), "ValueError")
    assert_raises(() => f.seek(0, 3), "ValueError", "whence")
    assert_raises(() => f.seek("1"), "TypeError")
    assert_raises(() => f.seek(1.5), "TypeError")
    # la position n'a pas bougé après les erreurs
    assert_eq(f.tell(), 0)
    f.close()

testing.test("File : seek / tell / whence (positions en octets)", t_seek_tell)

func t_seek_write_extend():
    f := file.open(P("z"), "w+b")
    f.write([1, 2])
    f.seek(5)
    f.write([9])
    assert_eq(f.size(), 6)
    f.seek(0)
    assert_eq(f.read(), [1, 2, 0, 0, 0, 9])
    f.close()
    g := file.open(P("z"), "r+")
    g.seek(8)
    g.write("é")
    assert_eq(g.tell(), 10)
    assert_eq(file.size(P("z")), 10)
    g.close()

testing.test("File : écrire au-delà de la fin prolonge de zéros", t_seek_write_extend)

func t_binary():
    data := [0, 1, 127, 128, 255, 10, 13, 0]
    file.write_bytes(P("b"), data)
    assert_eq(file.read_bytes(P("b")), data)
    assert_eq(file.size(P("b")), 8)
    file.append_bytes(P("b"), [42])
    assert_eq(file.read_bytes(P("b")), [0, 1, 127, 128, 255, 10, 13, 0, 42])
    f := file.open(P("b"), "rb")
    assert_true(f.binary)
    assert_eq(f.read(3), [0, 1, 127])
    assert_eq(f.tell(), 3)
    assert_eq(f.read(2), [128, 255])
    assert_eq(f.read(), [10, 13, 0, 42])
    assert_eq(f.read(), [])
    assert_true(f.eof())
    assert_raises(() => f.read_line(), "ValueError", "mode texte")
    assert_raises(() => f.read_lines(), "ValueError")
    f.close()
    g := file.open(P("b"), "r+b")
    g.seek(2)
    assert_eq(g.write([200, 201]), 2)
    assert_eq(g.tell(), 4)
    assert_raises(() => g.write("texte"), "TypeError")
    assert_raises(() => g.write([256]), "ArgumentError")
    assert_raises(() => g.write_line("x"), "ValueError", "mode texte")
    assert_raises(() => g.write_lines(["x"]), "ValueError")
    g.close()
    assert_eq(file.read_bytes(P("b")), [0, 1, 200, 201, 255, 10, 13, 0, 42])
    h := file.open(P("b"), "ab")
    assert_eq(h.write([7, 8]), 2)
    assert_eq(h.tell(), 11)
    h.close()
    assert_eq(len(file.read_bytes(P("b"))), 11)
    t := file.open(P("t"), "w")
    assert_raises(() => t.write([65]), "TypeError")
    t.close()
    assert_raises(() => file.write_bytes(P("b"), "abc"), "TypeError")
    assert_raises(() => file.append_bytes(P("b"), 5), "TypeError")
    assert_raises(() => file.read_bytes(P("absent")), "IoError")
    # le texte reste intact d'un bout à l'autre, tous les octets passent
    all := []
    i := 0
    while i < 256:
        _c.append(all, i)
        i += 1
    file.write_bytes(P("all"), all)
    assert_eq(file.read_bytes(P("all")), all)
    assert_eq(file.size(P("all")), 256)

testing.test("binaire : read_bytes / write_bytes / modes b", t_binary)

func t_truncate():
    file.write(P("tr"), "abcdef")
    f := file.open(P("tr"), "r+")
    f.seek(2)
    assert_eq(f.truncate(), 2)
    assert_eq(f.tell(), 2)
    assert_eq(file.read(P("tr")), "ab")
    assert_eq(f.truncate(4), 4)
    assert_eq(file.read_bytes(P("tr")), [97, 98, 0, 0])
    assert_raises(() => f.truncate(-1), "ValueError")
    assert_raises(() => f.truncate("2"), "ValueError")
    f.close()

testing.test("File.truncate", t_truncate)

func t_streaming():
    file.write(P("st"), "a\n")
    f := file.open(P("st"))
    assert_eq(f.read_line(), "a\n")
    assert_true(f.eof())
    # modifié « ailleurs » : le File lit l'état réel du fichier, rien n'est mis en cache
    file.append(P("st"), "b\n")
    assert_false(f.eof())
    assert_eq(f.read_line(), "b\n")
    assert_eq(f.read_line(), "")
    f.close()
    # fichier de 600 lignes lu ligne à ligne
    lines := []
    i := 0
    while i < 600:
        _c.append(lines, "ligne " + str(i) + " é")
        i += 1
    file.write_lines(P("big3"), lines)
    g := file.open(P("big3"))
    got := []
    line := g.read_line()
    while line != "":
        _c.append(got, _s.substring(line, 0, len(line) - 1))
        line = g.read_line()
    assert_eq(got, lines)
    g.close()

testing.test("File : lecture en flux (rien n'est mis en cache)", t_streaming)

func t_create():
    file.create(P("lock"), "pid 1")
    assert_eq(file.read(P("lock")), "pid 1")
    assert_raises(() => file.create(P("lock"), "autre"), "IoError", "existe déjà")
    assert_eq(file.read(P("lock")), "pid 1")
    file.create(P("empty"))
    assert_eq(file.size(P("empty")), 0)
    assert_raises(() => file.create(P("no/dir"), "x"), "IoError")
    assert_raises(() => file.create(P("x"), 5), "TypeError")
    assert_raises(() => file.create(5), "TypeError")
    if os.platform() != "windows":
        os.run("ln", ["-s", P("cible-absente"), P("lien")])
        assert_raises(() => file.create(P("lien"), "x"), "IoError", "existe déjà")
        assert_false(fs.exists(P("cible-absente")))

testing.test("file.create : création exclusive", t_create)

func t_atomic_bytes():
    file.write_atomic(P("ab"), [1, 2, 3])
    assert_eq(file.read_bytes(P("ab")), [1, 2, 3])
    file.write_atomic(P("ab"), "texte")
    assert_eq(file.read(P("ab")), "texte")
    assert_raises(() => file.write_atomic(P("ab"), 5), "TypeError")
    assert_raises(() => file.write_atomic(P("ab"), [300]), "ArgumentError")
    assert_eq(file.read(P("ab")), "texte")
    assert_eq(fs.list_dir(_ctx["dir"]), ["ab"])

testing.test("write_atomic : texte ou octets", t_atomic_bytes)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) file en échec")
print("FILE: OK")
