# ALEX - tests du module filesystem (ALEX pur). Lancer depuis la racine : ./alex run tests/test_filesystem.al
use filesystem as fs
use file
use os
from core use len
use string as _s
use testing
from testing use assert_eq, assert_true, assert_false, assert_null, assert_raises, assert_contains

# Chaque test dispose d'un dossier temporaire neuf, supprimé ensuite. Aucun test ne supprime autre chose que
# ce dossier : les garde-fous de suppression sont vérifiés en appelant _refuse_unsafe, qui lève ou rend null
# mais ne supprime rien.
_ctx := {"dir": null, "cwd": null}

func setup():
    _ctx["cwd"] = os.cwd()
    _ctx["dir"] = fs.make_temp_dir("alex_test_fs_")

func teardown():
    os.chdir(_ctx["cwd"])
    fs.remove_tree(_ctx["dir"], true)

func P(rel):
    return os.join(_ctx["dir"], rel)

# Arborescence type :
#   a/one.txt  a/b/two.al  a/b/c/three.al  a/x/ (vide)  top.al
func build_tree():
    fs.ensure_dir(P("a/b/c"))
    fs.ensure_dir(P("a/x"))
    fs.ensure_file(P("a/one.txt"))
    fs.ensure_file(P("a/b/two.al"))
    fs.ensure_file(P("a/b/c/three.al"))
    fs.ensure_file(P("top.al"))

func has_symlinks():
    return os.platform() != "windows"

func make_link(target, link):
    r := os.run("ln", ["-s", target, link])
    assert_eq(r["code"], 0, "création du lien symbolique")

testing.before_each(setup)
testing.after_each(teardown)

func t_kind():
    build_tree()
    assert_eq(fs.kind_of(P("a")), "dir")
    assert_eq(fs.kind_of(P("top.al")), "file")
    assert_null(fs.kind_of(P("absent")))
    assert_true(fs.exists(P("a")))
    assert_true(fs.is_file(P("top.al")))
    assert_false(fs.is_file(P("a")))
    assert_true(fs.is_dir(P("a")))
    assert_false(fs.is_dir(P("top.al")))
    assert_false(fs.exists(P("absent")))
    assert_raises(() => fs.kind_of(5), "TypeError")
    assert_raises(() => fs.exists(null), "TypeError")

testing.test("kind_of / exists / is_file / is_dir", t_kind)

func t_links():
    if not has_symlinks():
        return null
    build_tree()
    make_link(P("top.al"), P("lnk"))
    make_link(P("absent"), P("broken"))
    assert_eq(fs.kind_of(P("lnk")), "symlink")
    assert_eq(fs.kind_of(P("broken")), "symlink")
    assert_true(fs.is_link(P("broken")))
    assert_false(fs.exists(P("broken")))
    assert_true(fs.is_file(P("lnk")))
    assert_false(fs.is_link(P("top.al")))
    assert_true(fs.same_file(P("lnk"), P("top.al")))
    st := fs.stat(P("broken"))
    assert_eq(st["kind"], "symlink")
    assert_null(st["size"])
    assert_null(st["mtime"])

testing.test("liens symboliques", t_links)

func t_access():
    build_tree()
    assert_true(fs.is_readable(P("top.al")))
    assert_true(fs.is_writable(P("top.al")))
    assert_false(fs.is_readable(P("absent")))
    assert_false(fs.is_executable(P("absent")))
    assert_raises(() => fs.is_readable(1), "TypeError")

testing.test("is_readable / is_writable / is_executable", t_access)

func t_same_inside():
    build_tree()
    assert_true(fs.same_file(P("a/../top.al"), P("top.al")))
    assert_false(fs.same_file(P("top.al"), P("a/one.txt")))
    assert_false(fs.same_file(P("top.al"), P("absent")))
    assert_true(fs.is_inside(P("a/b/two.al"), P("a")))
    assert_true(fs.is_inside(P("a/b"), _ctx["dir"]))
    assert_false(fs.is_inside(P("a"), P("a")))
    assert_false(fs.is_inside(P("a"), P("a/b")))
    # préfixe de nom : "a2" n'est pas dans "a"
    fs.ensure_dir(P("a2"))
    assert_false(fs.is_inside(P("a2"), P("a")))

testing.test("same_file / is_inside", t_same_inside)

func t_stat():
    build_tree()
    file.write(P("data.txt"), "12345")
    st := fs.stat(P("data.txt"))
    assert_eq(st["kind"], "file")
    assert_eq(st["size"], 5)
    assert_eq(st["name"], "data.txt")
    assert_eq(st["path"], P("data.txt"))
    assert_true(st["mtime"] > 0)
    assert_true(st["mode"] != null)
    d := fs.stat(P("a"))
    assert_eq(d["kind"], "dir")
    assert_null(d["size"])
    assert_raises(() => fs.stat(P("absent")), "IoError", "introuvable")

testing.test("stat", t_stat)

func t_empty_size():
    build_tree()
    assert_true(fs.is_empty(P("top.al")))
    assert_true(fs.is_empty(P("a/x")))
    assert_false(fs.is_empty(P("a")))
    file.write(P("top.al"), "abc")
    assert_false(fs.is_empty(P("top.al")))
    file.write(P("a/b/two.al"), "12")
    assert_eq(fs.tree_size(P("a")), 2)
    assert_eq(fs.tree_size(_ctx["dir"]), 5)
    assert_eq(fs.tree_size(P("top.al")), 3)
    assert_raises(() => fs.is_empty(P("absent")), "IoError")
    assert_raises(() => fs.tree_size(P("absent")), "IoError")

testing.test("is_empty / tree_size", t_empty_size)

func t_tree_size_links():
    if not has_symlinks():
        return null
    build_tree()
    file.write(P("top.al"), "abcd")
    make_link(P("top.al"), P("a/lnk"))
    make_link(P("a"), P("a/loop"))
    assert_eq(fs.tree_size(P("a")), 0)
    assert_eq(fs.tree_size(_ctx["dir"]), 4)

testing.test("tree_size ignore les liens (pas de cycle)", t_tree_size_links)

func t_list():
    build_tree()
    assert_eq(fs.list_dir(P("a")), ["b", "one.txt", "x"])
    assert_eq(fs.list_dir(P("a"), true), [P("a/b"), P("a/one.txt"), P("a/x")])
    assert_eq(fs.list_files(P("a")), ["one.txt"])
    assert_eq(fs.list_dirs(P("a")), ["b", "x"])
    assert_eq(fs.list_dirs(P("a"), true), [P("a/b"), P("a/x")])
    assert_eq(fs.list_files(P("a/x")), [])
    assert_raises(() => fs.list_dir(P("absent")), "IoError")
    assert_raises(() => fs.list_files(3), "TypeError")

testing.test("list_dir / list_files / list_dirs", t_list)

func t_walk():
    build_tree()
    w := fs.walk(P("a"))
    assert_eq(len(w), 4)
    assert_eq(w[0], [P("a"), ["b", "x"], ["one.txt"]])
    assert_eq(w[1], [P("a/b"), ["c"], ["two.al"]])
    assert_eq(w[2], [P("a/b/c"), [], ["three.al"]])
    assert_eq(w[3], [P("a/x"), [], []])
    assert_raises(() => fs.walk(P("top.al")), "IoError", "pas un dossier")

testing.test("walk", t_walk)

func t_walk_links():
    if not has_symlinks():
        return null
    build_tree()
    make_link(P("a"), P("a/b/loop"))
    plain := fs.walk(P("a"))
    assert_eq(len(plain), 4)
    assert_contains(plain[1][1], "loop")
    followed := fs.walk(P("a"), true)
    # chaque dossier réel n'est visité qu'une fois : le lien vers "a" est ignoré
    assert_eq(len(followed), 4)

testing.test("walk : liens et cycles", t_walk_links)

func t_find():
    build_tree()
    assert_eq(fs.find(P("a"), "*.al"), [P("a/b/c/three.al"), P("a/b/two.al")])
    assert_eq(fs.find(P("a"), null, "dir"), [P("a/b"), P("a/b/c"), P("a/x")])
    assert_eq(fs.find(P("a"), null, "file", 1), [P("a/one.txt")])
    assert_eq(fs.find(P("a"), "t*", "file"), [P("a/b/c/three.al"), P("a/b/two.al")])
    assert_eq(fs.find(P("a"), "*", null, 1), [P("a/b"), P("a/one.txt"), P("a/x")])
    assert_eq(fs.find(P("a"), "zzz"), [])
    assert_eq(len(fs.find(_ctx["dir"])), 8)
    assert_raises(() => fs.find(P("top.al")), "IoError")
    assert_raises(() => fs.find(P("a"), null, "bizarre"), "ValueError")
    assert_raises(() => fs.find(P("a"), null, null, 0), "ValueError")
    assert_raises(() => fs.find(P("a"), 5), "TypeError")

testing.test("find", t_find)

func t_find_links():
    if not has_symlinks():
        return null
    build_tree()
    make_link(P("a"), P("a/b/loop"))
    make_link(P("top.al"), P("a/lnk"))
    found := fs.find(P("a"), null, "symlink")
    assert_eq(found, [P("a/b/loop"), P("a/lnk")])
    # le lien vers un dossier n'est pas descendu : pas de boucle infinie
    assert_eq(len(fs.find(P("a"))), 8)

testing.test("find : liens symboliques non suivis", t_find_links)

func t_glob():
    build_tree()
    assert_eq(fs.glob(P("a"), "*.txt"), [P("a/one.txt")])
    assert_eq(fs.glob(P("a"), "*/two.al"), [P("a/b/two.al")])
    assert_eq(fs.glob(P("a"), "b/*.al"), [P("a/b/two.al")])
    assert_eq(fs.glob(P("a"), "**/*.al"), [P("a/b/two.al"), P("a/b/c/three.al")])
    assert_eq(fs.glob(_ctx["dir"], "**/*.al"), [P("top.al"), P("a/b/two.al"), P("a/b/c/three.al")])
    assert_eq(fs.glob(P("a"), "b/**/three.al"), [P("a/b/c/three.al")])
    assert_eq(fs.glob(P("a"), "**", "dir"), [P("a/b"), P("a/b/c"), P("a/x")])
    assert_eq(len(fs.glob(P("a"), "**")), 6)
    assert_eq(fs.glob(P("a"), "**/**/three.al"), [P("a/b/c/three.al")])
    assert_eq(fs.glob(P("a"), "?/two.al"), [P("a/b/two.al")])
    assert_eq(fs.glob(P("a"), "[bx]", "dir"), [P("a/b"), P("a/x")])
    assert_eq(fs.glob(P("a"), "nope/*"), [])
    assert_eq(fs.glob(P("a"), "/*.txt/"), [P("a/one.txt")])
    assert_raises(() => fs.glob(P("a"), ""), "ValueError", "vide")
    assert_raises(() => fs.glob(P("a"), "/"), "ValueError", "vide")
    assert_raises(() => fs.glob(P("top.al"), "*"), "IoError")
    assert_raises(() => fs.glob(P("a"), 1), "TypeError")

testing.test("glob", t_glob)

func t_ensure():
    assert_eq(fs.ensure_dir(P("x/y/z")), P("x/y/z"))
    assert_true(fs.is_dir(P("x/y/z")))
    fs.ensure_dir(P("x/y/z"))
    file.write(P("f"), "")
    assert_raises(() => fs.ensure_dir(P("f")), "IoError")
    assert_eq(fs.ensure_parent(P("p/q/file.txt")), P("p/q/file.txt"))
    assert_true(fs.is_dir(P("p/q")))
    assert_false(fs.exists(P("p/q/file.txt")))
    fs.ensure_parent("relatif.txt")
    assert_eq(fs.ensure_file(P("n.txt")), P("n.txt"))
    assert_true(fs.is_file(P("n.txt")))
    file.write(P("n.txt"), "garde")
    fs.ensure_file(P("n.txt"))
    assert_eq(file.read(P("n.txt")), "garde")
    assert_raises(() => fs.ensure_file(P("x")), "IoError", "dossier")
    assert_raises(() => fs.ensure_file(P("no/parent.txt")), "IoError")

testing.test("ensure_dir / ensure_parent / ensure_file", t_ensure)

func t_remove():
    build_tree()
    assert_true(fs.remove(P("top.al")))
    assert_false(fs.exists(P("top.al")))
    assert_false(fs.remove(P("top.al"), true))
    assert_raises(() => fs.remove(P("top.al")), "IoError", "introuvable")
    assert_raises(() => fs.remove(P("a")), "IoError", "remove_tree")
    assert_true(fs.is_dir(P("a")))

testing.test("remove", t_remove)

func t_remove_links():
    if not has_symlinks():
        return null
    build_tree()
    make_link(P("top.al"), P("lnk"))
    make_link(P("a"), P("dirlnk"))
    make_link(P("absent"), P("broken"))
    assert_true(fs.remove(P("lnk")))
    assert_true(fs.exists(P("top.al")))
    assert_true(fs.remove_tree(P("dirlnk")))
    assert_true(fs.exists(P("a/one.txt")))
    assert_true(fs.remove(P("broken")))
    assert_false(fs.is_link(P("broken")))

testing.test("remove / remove_tree : le lien est retiré, jamais sa cible", t_remove_links)

func t_remove_tree():
    build_tree()
    assert_true(fs.remove_tree(P("a")))
    assert_false(fs.exists(P("a")))
    assert_true(fs.exists(P("top.al")))
    assert_false(fs.remove_tree(P("a"), true))
    assert_raises(() => fs.remove_tree(P("a")), "IoError", "introuvable")
    assert_true(fs.remove_tree(P("top.al")))
    assert_false(fs.exists(P("top.al")))

testing.test("remove_tree", t_remove_tree)

# _refuse_unsafe ne supprime jamais rien : on peut l'interroger sur "/", le dossier personnel, etc.
func t_guard_lexical():
    assert_raises(() => fs._refuse_unsafe("t", ""), "ValueError", "vide")
    assert_raises(() => fs._refuse_unsafe("t", "."), "ValueError", "refusée")
    assert_raises(() => fs._refuse_unsafe("t", ".."), "ValueError", "refusée")
    assert_raises(() => fs._refuse_unsafe("t", P("a/.")), "ValueError", "refusée")
    assert_raises(() => fs._refuse_unsafe("t", P("a/..")), "ValueError", "refusée")
    assert_raises(() => fs._refuse_unsafe("t", os.dirname(os.cwd()) + "/."), "ValueError", "refusée")
    if os.platform() == "windows":
        assert_raises(() => fs._refuse_unsafe("t", "C:\\"), "ValueError")
    else:
        assert_raises(() => fs._refuse_unsafe("t", "/"), "ValueError", "refusée")
        assert_raises(() => fs._refuse_unsafe("t", "//"), "ValueError", "refusée")
    build_tree()
    assert_null(fs._refuse_unsafe("t", P("a")))
    assert_null(fs._refuse_unsafe("t", P("a/")))
    assert_null(fs._refuse_unsafe("t", P("absent")))

testing.test("garde-fou : formes lexicales et racine", t_guard_lexical)

func t_guard_context():
    # dossier courant, ses ancêtres, dossier personnel et ses ancêtres
    assert_raises(() => fs._refuse_unsafe("t", os.cwd()), "ValueError", "courant")
    assert_raises(() => fs._refuse_unsafe("t", os.dirname(os.cwd())), "ValueError")
    home := os.home()
    if home != null and fs.is_dir(home):
        assert_raises(() => fs._refuse_unsafe("t", home), "ValueError", "personnel")
        assert_raises(() => fs._refuse_unsafe("t", os.dirname(home)), "ValueError")
    # le dossier de travail est déplacé dans le bac à sable
    build_tree()
    os.chdir(P("a/b"))
    assert_raises(() => fs._refuse_unsafe("t", P("a")), "ValueError", "courant")
    assert_raises(() => fs._refuse_unsafe("t", P("a/b")), "ValueError", "courant")
    assert_raises(() => fs._refuse_unsafe("t", P("a/b/..")), "ValueError")
    assert_null(fs._refuse_unsafe("t", P("a/x")))
    assert_null(fs._refuse_unsafe("t", P("a/b/c")))

testing.test("garde-fou : dossier courant et dossier personnel", t_guard_context)

func t_guard_wiring():
    build_tree()
    # les fonctions publiques appliquent bien le garde-fou (les cibles refusées restent intactes)
    assert_raises(() => fs.remove_tree(P("a/.")), "ValueError", "refusée")
    assert_raises(() => fs.clear_dir(P("a/.")), "ValueError", "refusée")
    assert_raises(() => fs.remove_tree(""), "ValueError", "vide")
    assert_raises(() => fs.clear_dir(""), "ValueError", "vide")
    assert_true(fs.exists(P("a/b/two.al")))
    assert_true(fs.exists(P("top.al")))
    # un dossier qui contient le dossier courant ne se supprime pas ; il redevient supprimable ensuite
    os.chdir(P("a/b"))
    assert_raises(() => fs.remove_tree(P("a")), "ValueError", "courant")
    assert_raises(() => fs.clear_dir(P("a")), "ValueError", "courant")
    assert_true(fs.exists(P("a/b/two.al")))
    os.chdir(_ctx["cwd"])
    assert_true(fs.remove_tree(P("a")))
    assert_raises(() => fs.remove_tree(7), "TypeError")
    assert_raises(() => fs.clear_dir(7), "TypeError")

testing.test("remove_tree / clear_dir appliquent le garde-fou", t_guard_wiring)

func t_clear_dir():
    build_tree()
    assert_eq(fs.clear_dir(P("a")), 3)
    assert_true(fs.is_dir(P("a")))
    assert_eq(fs.list_dir(P("a")), [])
    assert_true(fs.exists(P("top.al")))
    assert_eq(fs.clear_dir(P("a")), 0)
    assert_raises(() => fs.clear_dir(P("top.al")), "IoError", "pas un dossier")
    assert_raises(() => fs.clear_dir(P("absent")), "IoError")

testing.test("clear_dir", t_clear_dir)

func t_copy():
    build_tree()
    file.write(P("top.al"), "contenu")
    assert_eq(fs.copy(P("top.al"), P("copie.al")), P("copie.al"))
    assert_eq(file.read(P("copie.al")), "contenu")
    file.write(P("copie.al"), "autre")
    assert_raises(() => fs.copy(P("top.al"), P("copie.al"), false), "IoError", "existe déjà")
    assert_eq(file.read(P("copie.al")), "autre")
    fs.copy(P("top.al"), P("copie.al"))
    assert_eq(file.read(P("copie.al")), "contenu")
    # destination = dossier existant : copie DANS le dossier
    assert_eq(fs.copy(P("top.al"), P("a")), P("a/top.al"))
    assert_raises(() => fs.copy(P("top.al"), P("a"), false), "IoError", "existe déjà")
    # dossier
    assert_eq(fs.copy(P("a"), P("a2")), P("a2"))
    assert_eq(fs.find(P("a2"), "*.al", "file"), [P("a2/b/c/three.al"), P("a2/b/two.al"), P("a2/top.al")])
    # a2 existe désormais : copie DANS a2 (a2/a), puis refus d'écraser
    assert_eq(fs.copy(P("a"), P("a2"), false), P("a2/a"))
    assert_raises(() => fs.copy(P("a"), P("a2"), false), "IoError", "existe déjà")
    assert_raises(() => fs.copy(P("absent"), P("z")), "IoError", "introuvable")
    assert_raises(() => fs.copy(P("a"), P("a/b/dans-soi")), "IoError")

testing.test("copy", t_copy)

func t_move():
    build_tree()
    file.write(P("top.al"), "v1")
    assert_eq(fs.move(P("top.al"), P("moved.al")), P("moved.al"))
    assert_false(fs.exists(P("top.al")))
    assert_eq(file.read(P("moved.al")), "v1")
    file.write(P("other.al"), "v2")
    assert_raises(() => fs.move(P("other.al"), P("moved.al"), false), "IoError", "existe déjà")
    assert_true(fs.exists(P("other.al")))
    assert_eq(file.read(P("moved.al")), "v1")
    fs.move(P("other.al"), P("moved.al"))
    assert_eq(file.read(P("moved.al")), "v2")
    assert_eq(fs.move(P("moved.al"), P("a")), P("a/moved.al"))
    assert_eq(fs.move(P("a/b"), P("x")), P("x"))
    assert_true(fs.exists(P("x/c/three.al")))
    assert_false(fs.exists(P("a/b")))
    assert_raises(() => fs.move(P("absent"), P("z")), "IoError", "introuvable")

testing.test("move", t_move)

func t_temp():
    d := fs.make_temp_dir()
    assert_true(fs.is_dir(d))
    assert_true(fs.is_empty(d))
    assert_true(fs.is_inside(d, os.tmp_dir()))
    assert_true(_s.starts_with(os.basename(d), "alex_"))
    e := fs.make_temp_dir("zz_", _ctx["dir"])
    assert_true(fs.is_inside(e, _ctx["dir"]))
    assert_true(d != e)
    assert_true(fs.make_temp_dir("zz_", _ctx["dir"]) != e)
    assert_raises(() => fs.make_temp_dir("p", P("absent")), "IoError")
    assert_raises(() => fs.make_temp_dir(5), "TypeError")
    fs.remove_tree(d)
    if os.platform() != "windows":
        assert_eq(os.permissions(e) % 512, 448)

testing.test("make_temp_dir", t_temp)

func t_with_temp():
    seen := {"dir": null}
    func body(d):
        seen["dir"] = d
        file.write(os.join(d, "x.txt"), "hello")
        return file.read(os.join(d, "x.txt"))
    assert_eq(fs.with_temp_dir(body), "hello")
    assert_false(fs.exists(seen["dir"]))
    func boom(d):
        seen["dir"] = d
        raise("CustomError", "échec voulu")
    assert_raises(() => fs.with_temp_dir(boom), "CustomError", "échec voulu")
    assert_false(fs.exists(seen["dir"]))

testing.test("with_temp_dir : nettoyage en cas de succès et d'erreur", t_with_temp)

func t_touch():
    assert_eq(fs.touch(P("t")), P("t"))
    assert_true(fs.is_file(P("t")))
    os.set_times(P("t"), 1000, 2000.5)
    assert_eq(os.atime(P("t")), 1000.0)
    assert_eq(os.mtime(P("t")), 2000.5)
    # null = date inchangée
    os.set_times(P("t"), null, 3000)
    assert_eq(os.atime(P("t")), 1000.0)
    assert_eq(os.mtime(P("t")), 3000.0)
    # touch sur un fichier existant : dates à « maintenant », contenu intact
    file.write(P("t"), "contenu")
    os.set_times(P("t"), 1000, 2000)
    fs.touch(P("t"))
    assert_true(os.mtime(P("t")) > 1700000000)
    assert_true(os.atime(P("t")) > 1700000000)
    assert_eq(file.read(P("t")), "contenu")
    # un dossier aussi
    fs.ensure_dir(P("d"))
    os.set_times(P("d"), 5, 6)
    fs.touch(P("d"))
    assert_true(os.mtime(P("d")) > 1700000000)
    # os.set_times sans date : maintenant
    os.set_times(P("t"), 1, 1)
    os.set_times(P("t"))
    assert_true(os.mtime(P("t")) > 1700000000)
    assert_raises(() => fs.touch(P("no/parent")), "IoError")
    assert_raises(() => fs.touch(3), "TypeError")
    assert_raises(() => os.set_times(P("absent"), 1, 1), "IoError")
    assert_raises(() => os.set_times(P("t"), "x", 1), "TypeError")
    assert_raises(() => os.set_times(5), "TypeError")

testing.test("touch / os.set_times", t_touch)

func t_ensure_file_atomic():
    fs.ensure_file(P("e"))
    file.write(P("e"), "x")
    os.set_times(P("e"), 1000, 2000)
    fs.ensure_file(P("e"))
    # un fichier existant n'est modifié ni en contenu ni en date
    assert_eq(file.read(P("e")), "x")
    assert_eq(os.mtime(P("e")), 2000.0)
    if has_symlinks():
        make_link(P("absent"), P("broken"))
        assert_raises(() => fs.ensure_file(P("broken")), "IoError")
        assert_false(fs.exists(P("absent")))

testing.test("ensure_file : création atomique, rien de modifié si présent", t_ensure_file_atomic)

func t_temp_file():
    a := fs.make_temp_file()
    assert_true(fs.is_file(a))
    assert_eq(file.size(a), 0)
    assert_true(fs.is_inside(a, os.tmp_dir()))
    assert_true(_s.starts_with(os.basename(a), "alex_"))
    b := fs.make_temp_file("zz_", ".log", _ctx["dir"])
    assert_true(fs.is_inside(b, _ctx["dir"]))
    assert_true(_s.starts_with(os.basename(b), "zz_"))
    assert_true(_s.ends_with(os.basename(b), ".log"))
    assert_true(a != b)
    c := fs.make_temp_file("zz_", ".log", _ctx["dir"])
    assert_true(b != c)
    if has_symlinks():
        assert_eq(os.permissions(b) % 512, 384)
    assert_raises(() => fs.make_temp_file("p", "", P("absent")), "IoError")
    assert_raises(() => fs.make_temp_file(5), "TypeError")
    assert_raises(() => fs.make_temp_file("p", 7), "TypeError")
    fs.remove(a)

testing.test("make_temp_file", t_temp_file)

func t_with_temp_file():
    seen := {"p": null}
    func body(p):
        seen["p"] = p
        file.write(p, "x")
        return file.read(p)
    assert_eq(fs.with_temp_file(body, "alex_", ".txt", _ctx["dir"]), "x")
    assert_false(fs.exists(seen["p"]))
    func boom(p):
        seen["p"] = p
        raise("CustomError", "échec voulu")
    assert_raises(() => fs.with_temp_file(boom, "alex_", "", _ctx["dir"]), "CustomError", "échec voulu")
    assert_false(fs.exists(seen["p"]))

testing.test("with_temp_file : nettoyage en cas de succès et d'erreur", t_with_temp_file)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) filesystem en échec")
print("FILESYSTEM: OK")
