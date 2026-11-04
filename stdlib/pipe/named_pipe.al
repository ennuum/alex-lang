# ALEX STANDARD LIBRARY — pipe.named_pipe
#
# Tubes nommés (FIFO) : un chemin du système de fichiers que deux processus SANS lien de parenté ouvrent pour se
# parler, l'un en lecture, l'autre en écriture.
#
#   use pipe.named_pipe as np
#   f := np.NamedPipe("/tmp/commandes")
#   f.create()                                  # mkfifo (droits 0600)
#   # processus A                               # processus B
#   r := f.open_reader()                        w := np.NamedPipe("/tmp/commandes").open_writer(5)
#   print(r.read_line(10))                      w.write_line("stop")
#   f.unlink()
#
#   np.with_temporary((tube) => ...)            # tube temporaire unique, supprimé ensuite
#
# Règles du système : open_writer attend qu'un lecteur ait ouvert le tube (au plus timeout secondes, sinon
# TimeoutError) ; le lecteur voit la fin du flux quand le dernier écrivain ferme. Un tube nommé ne garde rien :
# ce qui est écrit sans lecteur n'existe pas.
#
# Erreurs : IoError (système, chemin qui n'est pas un tube), TimeoutError, TypeError.

from core use type
use os as _os
use io.pipe as _iop
use _native_fd as _f
use _native_net as _n

func _need_path(fn, path):
    if type(path) != "str" or path == "":
        raise("TypeError", "named_pipe." + fn + " : chemin (str non vide) attendu")

func is_fifo(path):
    return _f.file_kind(path, true) == "fifo"

class NamedPipe:
    func init(path):
        _need_path("NamedPipe", path)
        self.path = path

    func exists():
        return is_fifo(self.path)

    # Crée le tube (mode : droits). exist_ok : ne rien faire si un tube existe déjà à ce chemin.
    func create(mode=384, exist_ok=true):
        kind := _f.file_kind(self.path, false)
        if kind == "fifo" and exist_ok:
            return self
        if kind != null:
            raise("IoError", "named_pipe.create : '" + self.path + "' existe déjà (" + kind + ")")
        _iop.create_fifo(self.path, mode)
        return self

    # Lecteur (io.stream) : s'ouvre tout de suite.
    func open_reader():
        return _iop.open_fifo_reader(self.path)

    # Écrivain (io.stream) : attend un lecteur au plus timeout secondes (null : sans limite).
    func open_writer(timeout=null):
        return _iop.open_fifo_writer(self.path, timeout)

    # Ouvre, écrit text, referme : un message complet pour le lecteur.
    func send(text, timeout=null):
        w := self.open_writer(timeout)
        try:
            w.write(text)
        finally:
            w.close()

    func send_line(text, timeout=null):
        self.send(str(text) + "\n", timeout)

    # Ouvre, lit tout jusqu'à la fin du flux (le dernier écrivain ferme), referme.
    func receive_all(timeout=null):
        r := self.open_reader()
        try:
            return r.read_all(timeout)
        finally:
            r.close()

    # Supprime le tube (rien s'il n'existe pas).
    func unlink():
        if _f.file_kind(self.path, false) != null:
            _os.remove(self.path)

    func to_string():
        return "NamedPipe(" + self.path + ")"

func create(path, mode=384):
    return NamedPipe(path).create(mode, true)

# Tube nommé neuf dans le dossier temporaire (nom unique).
func temporary(prefix="alex-fifo-"):
    base := _os.tmp_dir()
    rnd := _n.to_bytes(_n.random_bytes(6))
    hex := "0123456789abcdef"
    name := prefix + str(_os.pid()) + "-"
    for b in rnd:
        name = name + str(hex[b >> 4]) + str(hex[b & 15])
    return NamedPipe(_os.join(base, name)).create(384, false)

# Appelle fn(tube) avec un tube temporaire, puis le supprime (même en cas d'erreur).
func with_temporary(fn):
    t := temporary()
    try:
        return fn(t)
    finally:
        t.unlink()
