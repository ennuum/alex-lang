# ALEX STANDARD LIBRARY — web.browser.file
#
# File : un Blob nommé, avec date de dernière modification — créé depuis des données ou lu depuis un fichier
# local (comme un choix dans <input type="file">) ; FileList pour les champs de fichiers ; type MIME deviné
# d'après l'extension.
#
#   use web.browser.file as fl
#   f := fl.File(["a,b\n1,2"], "donnees.csv", {"type": "text/csv"})
#   f.name, f.size, f.type, f.last_modified      # donnees.csv 7 text/csv …
#   g := fl.from_path("/tmp/photo.png")           # contenu, nom et type depuis le disque
#   fl.set_input_files(champ, [f, g])             # simule le choix de fichiers (événements input / change)
#   champ.files.length(), champ.files.item(0).name
#
# Erreurs : TypeError (nom manquant), NotFoundError (fichier local absent).

from core use len, type, to_int
from collections use append
use string as _s
use io as _io
use os as _os
use time as _time
use web.browser.browser_errors as _err
use web.http.content_type as _ct
use web.dom.event as _ev
use web.dom.event_target as _et
from web.browser.blob use Blob

class File extends Blob:
    func init(parts, name, options=null):
        if name == null:
            _err.type_error("File", "nom de fichier requis")
        super.init(parts, options)
        o := options if options != null else {}
        self.name = _s.replace(str(name), "/", ":")
        self.last_modified = o["last_modified"] if "last_modified" in o else to_int(_time.time() * 1000)
        self.webkit_relative_path = ""
        if self.type == "" and not ("type" in o):
            self.type = guess_type(self.name)

    func __str__():
        return "File(" + self.name + ", " + str(self.size) + " octets)"

# Type MIME d'après l'extension (application/octet-stream si inconnue).
func guess_type(name):
    return str(_ct.guess(name))

# File depuis un chemin local (contenu lu entièrement).
func from_path(path, content_type=null):
    if not _os.exists(path) or not _os.isfile(path):
        _err.not_found("file.from_path", "fichier introuvable « " + str(path) + " »")
    n := _os.size(path)
    data := _io.read_bytes(path, 0, n) if n > 0 else []
    parts := _s.split(_s.replace(path, "\\", "/"), "/")
    name := parts[len(parts) - 1]
    o := {"last_modified": to_int(_os.mtime(path) * 1000)}
    if content_type != null:
        o["type"] = content_type
    return File([data], name, o)

class FileList:
    func init(files=null):
        self.files = files if files != null else []

    func length():
        return len(self.files)

    func __len__():
        return len(self.files)

    func item(i):
        if i < 0 or i >= len(self.files):
            return null
        return self.files[i]

    func __getitem__(i):
        return self.files[i]

# Simule le choix de fichiers pour un <input type="file"> : element.files, puis input et change.
func set_input_files(element, files):
    if element.local_name != "input" or element.input_type() != "file":
        _err.type_error("set_input_files", "<input type=\"file\"> attendu")
    lst := files if type(files) == "list" else [files]
    if len(lst) > 1 and not element.has_attribute("multiple"):
        _err.invalid_state("set_input_files", "le champ n'accepte qu'un seul fichier (attribut multiple absent)")
    element.files = FileList(lst)
    names := []
    for f in lst:
        append(names, f.name)
    element._value = ("C:\\fakepath\\" + names[0]) if len(names) > 0 else ""
    _et.dispatch(element, _ev.Event("input", true, false, true), true)
    _et.dispatch(element, _ev.Event("change", true, false), true)
    return element.files
