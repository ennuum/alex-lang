# ALEX STANDARD LIBRARY — file
# Contenu des fichiers, texte et binaire, en ALEX pur au-dessus des primitives de `io` (lecture / écriture à une
# POSITION, création exclusive) et de `os`. Pour l'arborescence (lister, copier, supprimer, dossiers et fichiers
# temporaires), voir `filesystem`.
#
#   use file
#   file.write("notes.txt", "a\nb\n")
#   file.read_lines("notes.txt")                  # ["a", "b"]
#   file.write_atomic("conf.json", texte)         # jamais de fichier à moitié écrit
#   file.create("verrou", "pid 42")               # échoue si le fichier existe déjà (atomique)
#   f := file.open("data.bin", "r+b")             # lecture + écriture, binaire
#   f.seek(16); f.write([1, 2, 3]); f.close()
#   n := file.with_open("notes.txt", (f) => len(f.read_lines()))      # fermeture garantie
#
# FONCTIONS (fichier entier)
#   read(p)  read_or(p, fallback)  read_lines(p, keep_ends=false)  line_count(p)  head(p, n=10)  tail(p, n=10)
#   write(p, texte)  append(p, texte)  write_lines(p, lignes, newline="\n")  append_lines(p, lignes, newline="\n")
#   read_bytes(p)  write_bytes(p, octets)  append_bytes(p, octets)
#   write_atomic(p, texte_ou_octets)   create(p, texte="")   exists(p)  size(p)  delete(p, missing_ok=false)
#   open(p, mode="r") -> File          with_open(p, fn, mode="r")
# OBJET File — modes comme ceux de Python : r (lecture, le fichier doit exister), w (crée / vide), a (crée / ajoute
#   toujours à la fin), x (crée, ÉCHOUE si le fichier existe : création exclusive atomique) ; suffixe + (lecture ET
#   écriture) et/ou b (binaire), dans n'importe quel ordre : "r+", "wb", "ab+", "x+b"...
#   position : seek(offset, whence=0)  tell()  rewind()  size()  eof()          whence : 0 début, 1 courant, 2 fin
#   lecture  : read(size=null)  read_line()  read_lines(keep_ends=false)         (si le mode le permet)
#   écriture : write(donnée)  write_line(texte="")  write_lines(lignes)  truncate(size=null)  flush()
#   commun   : close()  is_closed()      champs en lecture : path, mode, binary, readable, writable
#
# Conventions
#   - TEXTE (mode sans b) : UTF-8 lu et écrit tel quel (aucun décodage, BOM et NUL conservés, aucune conversion de
#     fins de ligne à l'écriture). À la LECTURE par File ou par read_lines / head / tail / line_count, "\n", "\r\n" et
#     "\r" sont tous rendus "\n" (comme le mode texte de Python) ; file.read(p) et write rendent le contenu exact.
#     Un fichier terminé par une fin de ligne n'a pas de dernière ligne vide ; "" n'a aucune ligne.
#   - BINAIRE (mode avec b, read_bytes...) : les octets sont des listes d'int 0..255 (comme dans crypto).
#   - POSITIONS : seek / tell comptent des OCTETS, en texte comme en binaire. read(size) en texte compte des
#     caractères (points de code). Se placer au milieu d'un caractère UTF-8 est permis (l'octet orphelin est lu
#     comme un caractère à part) : utiliser de préférence 0, la fin, ou une valeur rendue par tell().
#   - File lit PAR FLUX : rien n'est chargé à l'ouverture ni gardé en mémoire ; chaque lecture ou écriture ouvre le
#     fichier, agit à la position courante puis le referme. Les écritures sont donc immédiates (flush ne fait
#     rien), et un fichier modifié par un autre processus est vu tel qu'il est au moment de l'appel.
#   - Mode a : toute écriture va à la fin, quelle que soit la position (la position suit ensuite la fin).
#   - Écrire au-delà de la fin prolonge le fichier avec des zéros ; lire au-delà de la fin rend "" ou [].
#   - Les noms commençant par `_` sont des détails d'implémentation.
# Erreurs : TypeError (argument de mauvais type), ValueError (mode invalide, position ou taille invalide, fichier
# fermé, opération texte sur un fichier binaire), IoError (fichier introuvable ou déjà existant, droits, opération
# interdite par le mode d'ouverture).

from core use len, type
use collections as _c
use string as _s
use os as _os
use io as _io

_state := {"tmp": 0}

# ---------------------------------------------------------------------
# Outils internes
# ---------------------------------------------------------------------

func _need_str(fn, value, label="le chemin"):
    if type(value) != "str":
        raise("TypeError", "file." + fn + "() : " + label + " doit être une str (obtenu '" + type(value) + "')")

func _need_lines(fn, lines):
    t := type(lines)
    if t != "list" and t != "tuple":
        raise("TypeError", "file." + fn + "() : les lignes doivent former une list de str (obtenu '" + t + "')")
    for line in lines:
        if type(line) != "str":
            raise("TypeError", "file." + fn + "() : chaque ligne doit être une str (obtenu '" + type(line) + "')")

func _need_bytes(fn, data):
    t := type(data)
    if t != "list" and t != "tuple":
        raise("TypeError", "file." + fn + "() : les octets doivent former une list d'int 0..255 (obtenu '" + t + "')")

func _need_count(fn, n):
    if type(n) != "int" or n < 0:
        raise("ValueError", "file." + fn + "() : le nombre doit être un entier >= 0")

# Fins de ligne "\r\n" et "\r" ramenées à "\n".
func _unify_newlines(text):
    if _s.contains(text, "\r"):
        text = _s.replace(text, "\r\n", "\n")
        text = _s.replace(text, "\r", "\n")
    return text

# Découpe en lignes. keep_ends : chaque ligne garde son "\n" (sauf une dernière ligne non terminée).
func _split_lines(text, keep_ends):
    text = _unify_newlines(text)
    if text == "":
        return []
    parts := _s.split(text, "\n")
    terminated := parts[len(parts) - 1] == ""
    if terminated:
        _c.pop(parts)
    if not keep_ends:
        return parts
    out := []
    i := 0
    while i < len(parts):
        if terminated or i < len(parts) - 1:
            _c.append(out, parts[i] + "\n")
        else:
            _c.append(out, parts[i])
        i += 1
    return out

# Éléments [a, b) d'une liste (string.slice ne travaille que sur des str).
func _sub(items, a, b):
    out := []
    i := a
    while i < b:
        _c.append(out, items[i])
        i += 1
    return out

func _join_lines(lines, newline):
    out := []
    for line in lines:
        _c.append(out, line + newline)
    return _s.join("", out)

func _attempt_delete(p):
    try:
        if _os.exists(p):
            _os.remove(p)
    catch e:
        return false
    return true

# ---------------------------------------------------------------------
# Fichier entier
# ---------------------------------------------------------------------

# Vrai pour un fichier régulier (pas un dossier : voir filesystem.exists).
func exists(p):
    _need_str("exists", p)
    return _io.file_exists(p)

# Taille en octets (IoError si absent ou si c'est un dossier).
func size(p):
    _need_str("size", p)
    return _os.size(p)

# Contenu intégral, tel quel.
func read(p):
    _need_str("read", p)
    return _io.read_file(p)

# Contenu, ou `fallback` si le fichier n'existe pas (les autres erreurs, comme un refus d'accès, sont propagées).
func read_or(p, fallback=null):
    _need_str("read_or", p)
    if not _io.file_exists(p):
        return fallback
    return _io.read_file(p)

func read_lines(p, keep_ends=false):
    _need_str("read_lines", p)
    return _split_lines(_io.read_file(p), keep_ends)

func line_count(p):
    _need_str("line_count", p)
    return len(_split_lines(_io.read_file(p), false))

# Les n premières lignes (moins si le fichier est plus court).
func head(p, n=10):
    _need_str("head", p)
    _need_count("head", n)
    lines := _split_lines(_io.read_file(p), false)
    if n >= len(lines):
        return lines
    return _sub(lines, 0, n)

# Les n dernières lignes, dans l'ordre du fichier.
func tail(p, n=10):
    _need_str("tail", p)
    _need_count("tail", n)
    lines := _split_lines(_io.read_file(p), false)
    if n >= len(lines):
        return lines
    return _sub(lines, len(lines) - n, len(lines))

# Contenu intégral en octets : liste d'int 0..255.
func read_bytes(p):
    _need_str("read_bytes", p)
    return _io.read_bytes(p, 0, -1)

# Écrase (ou crée) le fichier avec ces octets.
func write_bytes(p, data):
    _need_str("write_bytes", p)
    _need_bytes("write_bytes", data)
    _io.write_bytes(p, data)
    return null

# Ajoute ces octets à la fin (crée le fichier si besoin).
func append_bytes(p, data):
    _need_str("append_bytes", p)
    _need_bytes("append_bytes", data)
    _io.write_bytes_at(p, data, null)
    return null

# Crée un fichier NEUF avec ce contenu : IoError s'il existe déjà, même créé à l'instant par un autre processus
# (création exclusive atomique, base d'un verrou). Si l'écriture du contenu échoue, le fichier vide est retiré.
func create(p, text=""):
    _need_str("create", p)
    _need_str("create", text, "le texte")
    _io.create_file(p)
    if text != "":
        try:
            _io.write_file(p, text)
        catch e:
            _attempt_delete(p)
            raise(e.type, e.message)
    return null

# Écrase (ou crée) le fichier. Le dossier parent doit exister (voir filesystem.ensure_parent).
func write(p, text):
    _need_str("write", p)
    _need_str("write", text, "le texte")
    _io.write_file(p, text)
    return null

# Ajoute à la fin (crée le fichier si besoin).
func append(p, text):
    _need_str("append", p)
    _need_str("append", text, "le texte")
    _io.append_file(p, text)
    return null

# Écrit une ligne par élément, chacune terminée par `newline` (donc le fichier se termine par une fin de ligne ;
# liste vide = fichier vide).
func write_lines(p, lines, newline="\n"):
    _need_str("write_lines", p)
    _need_lines("write_lines", lines)
    _need_str("write_lines", newline, "newline")
    _io.write_file(p, _join_lines(lines, newline))
    return null

func append_lines(p, lines, newline="\n"):
    _need_str("append_lines", p)
    _need_lines("append_lines", lines)
    _need_str("append_lines", newline, "newline")
    _io.append_file(p, _join_lines(lines, newline))
    return null

# Écrit dans un fichier temporaire voisin puis le renomme sur `p` : un lecteur (ou un crash) ne voit jamais un
# fichier à moitié écrit. `data` : texte (str) ou octets (list d'int). Les droits d'un fichier existant sont
# conservés quand l'OS le permet. En cas d'échec le fichier temporaire est supprimé et `p` reste intact.
# Dossier : IoError.
func write_atomic(p, data):
    _need_str("write_atomic", p)
    is_text := type(data) == "str"
    if not is_text:
        _need_bytes("write_atomic", data)
    if _os.isdir(p):
        raise("IoError", "file.write_atomic('" + p + "') : est un dossier")
    _state["tmp"] = _state["tmp"] + 1
    tmp := p + ".tmp" + str(_os.pid()) + "_" + str(_state["tmp"])
    try:
        if is_text:
            _io.write_file(tmp, data)
        else:
            _io.write_bytes(tmp, data)
        if _os.exists(p):
            _copy_mode(p, tmp)
        _os.move(tmp, p)
    catch e:
        _attempt_delete(tmp)
        raise(e.type, e.message)
    return null

func _copy_mode(src, dst):
    try:
        _os.chmod(dst, _os.permissions(src))
    catch e:
        return false
    return true

# Supprime un fichier régulier (ou un lien : jamais sa cible). Absent : IoError, sauf missing_ok (retourne false).
# Retourne true si le fichier a été supprimé.
func delete(p, missing_ok=false):
    _need_str("delete", p)
    if not _io.file_exists(p):
        if missing_ok:
            return false
        raise("IoError", "file.delete('" + p + "') : fichier introuvable")
    _io.delete_file(p)
    return true

# ---------------------------------------------------------------------
# Objet File
# ---------------------------------------------------------------------

class File:
    path := ""
    mode := "r"
    binary := false
    readable := false
    writable := false
    _kind := "r"
    _closed := false
    _pos := 0

    # Ne pas appeler directement : file.open(path, mode). r : le fichier doit exister. w : crée ou vide, tout de
    # suite (une erreur de droits se voit à l'ouverture). a : crée si besoin, position initiale = fin. x : création
    # exclusive, IoError si le fichier existe.
    func init(path, kind, plus, binary):
        self.path = path
        self._kind = kind
        self.binary = binary
        self.readable = kind == "r" or plus
        self.writable = kind != "r" or plus
        label := kind
        if plus:
            label = label + "+"
        if binary:
            label = label + "b"
        self.mode = label
        if kind == "r":
            if not _io.file_exists(path):
                raise("IoError", "file.open('" + path + "') : fichier introuvable (ou pas un fichier régulier)")
        elif kind == "w":
            _io.write_file(path, "")
        elif kind == "a":
            _io.append_file(path, "")
            self._pos = _os.size(path)
        else:
            _io.create_file(path)

    func _check_open(op):
        if self._closed:
            raise("ValueError", "file.File." + op + "() : fichier fermé ('" + self.path + "')")

    func _check_readable(op):
        self._check_open(op)
        if not self.readable:
            raise("IoError", "file.File." + op + "() : '" + self.path + "' n'est pas ouvert en lecture (mode \"" + self.mode + "\")")

    func _check_writable(op):
        self._check_open(op)
        if not self.writable:
            raise("IoError", "file.File." + op + "() : '" + self.path + "' n'est pas ouvert en écriture (mode \"" + self.mode + "\")")

    func _check_text(op):
        if self.binary:
            raise("ValueError", "file.File." + op + "() : réservé au mode texte (mode \"" + self.mode + "\" binaire)")

    func is_closed():
        return self._closed

    # ---- position ----

    # Position courante, en octets depuis le début.
    func tell():
        self._check_open("tell")
        return self._pos

    # Déplace la position : whence 0 = depuis le début, 1 = depuis la position courante, 2 = depuis la fin. Retourne
    # la nouvelle position. Aller au-delà de la fin est permis (lire rend du vide ; écrire prolonge de zéros) ; une
    # position négative est une ValueError.
    func seek(offset, whence=0):
        self._check_open("seek")
        if type(offset) != "int":
            raise("TypeError", "file.File.seek() : offset doit être un int (obtenu '" + type(offset) + "')")
        base := 0
        if whence == 1:
            base = self._pos
        elif whence == 2:
            base = _os.size(self.path)
        elif whence != 0:
            raise("ValueError", "file.File.seek() : whence doit valoir 0 (début), 1 (courant) ou 2 (fin)")
        target := base + offset
        if target < 0:
            raise("ValueError", "file.File.seek() : position négative (" + str(target) + ")")
        self._pos = target
        return target

    func rewind():
        self.seek(0)
        return null

    # Taille actuelle du fichier sur le disque, en octets.
    func size():
        self._check_open("size")
        return _os.size(self.path)

    # Vrai quand la position est à la fin du fichier (ou au-delà).
    func eof():
        self._check_readable("eof")
        return self._pos >= _os.size(self.path)

    # ---- lecture ----

    # Texte : au plus `size` caractères (null = tout le reste), "" en fin de fichier. Binaire : au plus `size`
    # octets, liste d'int ([] en fin de fichier).
    func read(size=null):
        self._check_readable("read")
        want := -1
        if size != null:
            _need_count("File.read", size)
            want = size
        if self.binary:
            data := _io.read_bytes(self.path, self._pos, want)
            self._pos += len(data)
            return data
        got := _io.read_text(self.path, self._pos, want)
        self._pos += got[1]
        return got[0]

    # Ligne suivante AVEC sa fin de ligne ("\n"), ou "" en fin de fichier (aucune vraie ligne n'est vide : elle
    # contient au moins "\n"). Texte uniquement.
    func read_line():
        self._check_readable("read_line")
        self._check_text("read_line")
        got := _io.read_line(self.path, self._pos)
        self._pos += got[1]
        return got[0]

    # Lignes restantes. Sans keep_ends, la fin de ligne est retirée. Texte uniquement.
    func read_lines(keep_ends=false):
        self._check_readable("read_lines")
        self._check_text("read_lines")
        got := _io.read_text(self.path, self._pos, -1)
        self._pos += got[1]
        return _split_lines(got[0], keep_ends)

    # ---- écriture ----

    # Écrit à la position courante (mode a : toujours à la fin), puis avance. Texte : une str, retourne le nombre
    # de caractères ; binaire : une list d'octets, retourne le nombre d'octets.
    func write(data):
        self._check_writable("write")
        count := 0
        if self.binary:
            _need_bytes("File.write", data)
            count = len(data)
            if count == 0:
                return 0
            if self._kind == "a":
                _io.write_bytes_at(self.path, data, null)
                self._pos = _os.size(self.path)
            else:
                self._pos += _io.write_bytes_at(self.path, data, self._pos)
            return count
        _need_str("File.write", data, "le texte")
        count = len(data)
        if count == 0:
            return 0
        if self._kind == "a":
            _io.write_at(self.path, data, null)
            self._pos = _os.size(self.path)
        else:
            self._pos += _io.write_at(self.path, data, self._pos)
        return count

    func write_line(text=""):
        self._check_writable("write_line")
        self._check_text("write_line")
        _need_str("File.write_line", text, "le texte")
        return self.write(text + "\n")

    # Une ligne par élément, en une seule écriture (validés avant toute écriture : tout ou rien).
    func write_lines(lines):
        self._check_writable("write_lines")
        self._check_text("write_lines")
        _need_lines("File.write_lines", lines)
        return self.write(_join_lines(lines, "\n"))

    # Fixe la taille du fichier à `size` octets (null = la position courante) : raccourcit, ou prolonge de zéros.
    # La position ne change pas. Retourne la taille.
    func truncate(size=null):
        self._check_writable("truncate")
        target := self._pos
        if size != null:
            _need_count("File.truncate", size)
            target = size
        _io.truncate(self.path, target)
        return target

    # Les écritures sont immédiates : ne fait rien (conservé pour la compatibilité avec le code habitué à flush).
    func flush():
        self._check_open("flush")
        return null

    # Ferme. Idempotent. Toute opération ultérieure lève ValueError.
    func close():
        self._closed = true
        return null

# Ouvre un fichier. mode : r, w, a ou x (voir l'en-tête), suivi de + et / ou b dans n'importe quel ordre.
# Penser à close(), ou préférer with_open.
func open(p, mode="r"):
    _need_str("open", p)
    _need_str("open", mode, "le mode")
    kind := ""
    plus := false
    binary := false
    for ch in mode:
        c := str(ch)
        if (c == "r" or c == "w" or c == "a" or c == "x") and kind == "":
            kind = c
        elif c == "+" and not plus:
            plus = true
        elif c == "b" and not binary:
            binary = true
        else:
            kind = ""
            break
    if kind == "":
        raise("ValueError", "file.open() : mode invalide '" + mode + "' (attendu : r, w, a ou x, suivi de + et/ou b)")
    return File(p, kind, plus, binary)

func _attempt_close(f):
    try:
        f.close()
    catch e:
        return false
    return true

# Ouvre, appelle fn(fichier), ferme (même si fn lève : l'exception est relancée à l'identique) et retourne la
# valeur de fn.
func with_open(p, fn, mode="r"):
    f := open(p, mode)
    result := null
    try:
        result = fn(f)
    catch e:
        _attempt_close(f)
        raise(e.type, e.message)
    f.close()
    return result
