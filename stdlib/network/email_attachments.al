# ALEX STANDARD LIBRARY — network.email_attachments
#
# Pièces jointes des courriels : création (fichier, octets, image intégrée « cid: »), extraction depuis un message
# reçu, enregistrement sûr sur le disque (noms nettoyés, pas d'écrasement, pas de sortie du dossier).
#
#   Attachment(nom, données, type, disposition, content_id)
#   from_file(chemin) / from_bytes(octets, nom) / inline_image(chemin, cid)
#   a.to_part() -> network.mime.MimePart           a.save(dossier) -> chemin écrit
#   extract(message_ou_partie) -> list[Attachment]  save_all(message, dossier) -> list de chemins
#
# Exemple
#   use network.email_attachments as att
#   m.attach(att.from_file("rapport.pdf"))
#   for a in att.extract(message_reçu):
#       print(a.filename, a.content_type, a.size())
#       a.save("/tmp/pj")

from core use len, type
from collections use append
use string as _s
use _native_net as _n
use io as _io
use os as _os
use network.mime as _mime
use network.http_multipart as _mp
use network.encoding as _enc
use network.http_headers as _hh

const DEFAULT_MAX_SIZE := 52428800

class Attachment:
    func init(filename, data, content_type=null, disposition="attachment", content_id=null):
        self.filename = filename
        self.data = data
        if type(data) == "list":
            self.data = _n.from_bytes(data)
        if self.data == null:
            self.data = ""
        self.content_type = content_type
        if content_type == null:
            if filename != null:
                self.content_type = _mime.guess_type(filename)
            else:
                self.content_type = _mime.DEFAULT_TYPE
        self.disposition = disposition      # "attachment" ou "inline"
        self.content_id = content_id        # sans chevrons (« logo@exemple »), pour <img src="cid:...">

    func size():
        return _n.blen(self.data)

    func bytes():
        return _n.to_bytes(self.data)

    func is_inline():
        return self.disposition == "inline"

    # Texte (pour une pièce jointe textuelle), selon le charset du type de contenu.
    func text():
        return _enc.decode_charset(self.data, _charset(self.content_type), "replace")

    # Partie MIME correspondante (base64).
    func to_part():
        return _mime.leaf(self.data, self.content_type, "base64", self.filename, self.disposition, self.content_id)

    # Enregistre dans `target` : un dossier (nom de fichier nettoyé, sans écraser un fichier existant) ou un chemin
    # complet. Rend le chemin écrit.
    func save(target, overwrite=false):
        path := target
        if _os.isdir(target):
            path = unique_path(target, safe_name(self.filename), overwrite)
        _io.write_bytes(path, _n.to_bytes(self.data))
        return path

    func str():
        return "Attachment(" + str(self.filename) + ", " + self.content_type + ", " + str(self.size()) + " octets)"

func _charset(content_type):
    p := _hh.parse_value(content_type)[1]
    if "charset" in p:
        return p["charset"]
    return "utf-8"

# Pièce jointe lue sur le disque (nom d'envoi : celui du fichier, sauf `filename`).
func from_file(path, content_type=null, filename=null, max_size=DEFAULT_MAX_SIZE):
    if not _os.isfile(path):
        raise("IoError", "email_attachments : fichier introuvable « " + path + " »")
    if max_size != null and _os.size(path) > max_size:
        raise("EmailError", "email_attachments : « " + path + " » dépasse " + str(max_size) + " octets")
    name := filename
    if name == null:
        name = _os.basename(path)
    return Attachment(name, _n.from_bytes(_io.read_bytes(path)), content_type)

func from_bytes(data, filename, content_type=null):
    return Attachment(filename, data, content_type)

# Image intégrée au HTML (référencée par <img src="cid:CID">).
func inline_image(path, cid, content_type=null):
    a := from_file(path, content_type)
    a.disposition = "inline"
    a.content_id = cid
    return a

# Nom de fichier sûr (sans chemin, sans caractère réservé) ; « piece_jointe » s'il ne reste rien.
func safe_name(name, default="piece_jointe"):
    return _mp.safe_filename(name, default)

# Chemin libre dans `directory` pour `name` : « nom.ext », puis « nom (1).ext », « nom (2).ext »...
func unique_path(directory, name, overwrite=false):
    p := _os.join(directory, name)
    if overwrite or not _os.exists(p):
        return p
    stem := name
    ext := ""
    k := len(name) - 1
    while k > 0 and name[k] != '.':
        k -= 1
    if k > 0:
        stem = _s.substring(name, 0, k)
        ext = _s.substring(name, k, len(name))
    i := 1
    while true:
        cand := _os.join(directory, stem + " (" + str(i) + ")" + ext)
        if not _os.exists(cand):
            return cand
        i += 1

# Pièces jointes d'un message (network.email.EmailMessage ou network.mime.MimePart). inline=true : inclut les
# parties intégrées (images « cid: ») qui portent un nom ou un identifiant.
func extract(message, inline=true):
    root := message
    if not isinstance(message, _mime.MimePart):
        root = message.mime
        if root == null:
            out := []
            for a in message.attachments:
                append(out, a)
            return out
    out := []
    for p in root.leaves():
        d := p.disposition()
        name := p.filename()
        if d == "attachment" or (d == null and name != null and not _s.starts_with(p.content_type(), "text/")):
            append(out, Attachment(name, p.body, p.headers.get("content-type", p.content_type()), "attachment", p.content_id()))
        elif inline and (d == "inline" or p.content_id() != null) and (name != null or p.content_id() != null) and not _s.starts_with(p.content_type(), "text/"):
            append(out, Attachment(name, p.body, p.headers.get("content-type", p.content_type()), "inline", p.content_id()))
    return out

# Enregistre toutes les pièces jointes dans un dossier (créé au besoin) ; rend les chemins écrits.
func save_all(message, directory, inline=false):
    _os.mkdir_all(directory)
    paths := []
    for a in extract(message, inline):
        append(paths, a.save(directory))
    return paths
