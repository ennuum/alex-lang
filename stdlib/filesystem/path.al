# ALEX STANDARD LIBRARY — filesystem.path
#
# Path : un chemin comme OBJET (à la pathlib de Python). Calculs lexicaux par le module path, accès au disque
# par os / file / filesystem : on enchaîne au lieu d'imbriquer des appels.
#
#   use filesystem.path as fp
#   p := fp.Path("data") / "2026" / "ventes.csv"     # opérateur / : jointure
#   print(p.name, p.stem, p.suffix, p.parent())       # ventes.csv ventes .csv data/2026
#   if not p.parent().exists():
#       p.parent().mkdir()
#   p.write_text("a;b\n")
#   print(p.read_text(), p.size(), p.is_file())
#   for f in fp.Path("src").glob("**/*.al"):
#       print(f.relative_to("src"))
#   print(fp.home() / ".config", fp.cwd())
#   q := p.with_suffix(".bak")                        # data/2026/ventes.bak
#
# Les Path s'égalent par leur forme normalisée ; str(p) donne le texte du chemin.
# Erreurs : celles de filesystem / file (IoError, FileNotFoundError...), TypeError.

from core use len, type, hash
from collections use append
use path as _p
use os as _os
use file as _file
use filesystem as _fs
use filesystem.metadata as _md

func _text(x):
    if isinstance(x, Path):
        return x.text
    if type(x) != "str":
        raise("TypeError", "Path : str ou Path attendu (obtenu '" + type(x) + "')")
    return x

class Path:
    func init(text="."):
        t := _text(text)
        if t == "":
            t = "."
        self.text = t
        self.name = _p.basename(t)
        self.stem = _p.stem(t)
        self.suffix = _p.extension(t)

    func __truediv__(other):
        return Path(_p.join(self.text, _text(other)))

    func join(*others):
        out := self.text
        for o in others:
            out = _p.join(out, _text(o))
        return Path(out)

    func parent():
        d := _p.dirname(self.text)
        if d == "":
            return Path(".")
        return Path(d)

    func parents():
        out := []
        cur := self.parent()
        guard := 0
        while guard < 256:
            append(out, cur)
            nxt := cur.parent()
            if nxt.text == cur.text:
                break
            cur = nxt
            guard += 1
        return out

    func parts():
        return _p.parts(self.text)

    func normalize():
        return Path(_p.normalize(self.text))

    func absolute():
        return Path(_os.absolute(self.text))

    func resolve():
        return Path(_os.realpath(self.text))

    func is_absolute():
        return _p.is_absolute(self.text)

    func with_name(name):
        return Path(_p.with_name(self.text, name))

    func with_suffix(suffix):
        return Path(_p.with_extension(self.text, suffix))

    func relative_to(base):
        return Path(_p.relative_to(self.text, _text(base)))

    func is_relative_to(base):
        return _p.is_subpath(self.text, _text(base))

    func matches(pattern):
        return _p.glob_match(pattern, self.name)

    # ------------------------------------------------------------ disque
    func exists():
        return _os.exists(self.text)

    func is_file():
        return _os.isfile(self.text)

    func is_dir():
        return _os.isdir(self.text)

    func is_link():
        return _os.islink(self.text)

    func size():
        return _os.size(self.text)

    func metadata():
        return _md.of(self.text)

    func read_text():
        return _file.read(self.text)

    func read_lines():
        return _file.read_lines(self.text)

    func write_text(text):
        _file.write(self.text, text)
        return self

    func append_text(text):
        _file.append(self.text, text)
        return self

    func read_bytes():
        return _file.read_bytes(self.text)

    func write_bytes(data):
        _file.write_bytes(self.text, data)
        return self

    func touch():
        _fs.touch(self.text)
        return self

    func mkdir(parents=true):
        if parents:
            _fs.ensure_dir(self.text)
        else:
            _os.mkdir(self.text)
        return self

    func unlink(missing_ok=false):
        _fs.remove(self.text, missing_ok)

    func rmtree():
        _fs.remove_tree(self.text, true)

    func rename(target):
        _fs.move(self.text, _text(target))
        return Path(_text(target))

    func copy_to(target, overwrite=true):
        _fs.copy(self.text, _text(target), overwrite)
        return Path(_text(target))

    func iterdir():
        return [self / n for n in _fs.list_dir(self.text)]

    func glob(pattern):
        return [Path(x) for x in _fs.glob(self.text, pattern)]

    func walk():
        return [Path(x) for x in _fs.find(self.text)]

    func __eq__(other):
        if isinstance(other, Path):
            return _p.normalize(other.text) == _p.normalize(self.text)
        if type(other) == "str":
            return _p.normalize(other) == _p.normalize(self.text)
        return false

    func __lt__(other):
        return self.text < _text(other)

    func hash_code():
        return hash(_p.normalize(self.text))

    func __str__():
        return self.text

func path(text="."):
    return Path(text)

func cwd():
    return Path(_os.cwd())

func home():
    return Path(_os.home())

func temp_dir():
    return Path(_os.tmp_dir())
