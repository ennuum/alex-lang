# ALEX STANDARD LIBRARY — web.browser.form_data
#
# FormData : paires nom -> valeur (texte, Blob ou File) d'un formulaire — construites à la main ou depuis un
# <form> web.dom (contrôles « réussis », bouton d'envoi compris, fichiers des champs file) ; encodage en
# corps de requête multipart/form-data (avec frontière) ou application/x-www-form-urlencoded.
#
#   use web.browser.form_data as fd
#   d := fd.FormData()
#   d.append("nom", "Ada")
#   d.append("cv", file.File(["…"], "cv.txt"))
#   d.get("nom"), d.get_all("nom"), d.has("cv")
#   body := d.to_multipart()          # (corps texte, type « multipart/form-data; boundary=… »)
#   d2 := fd.from_form(formulaire)    # depuis un élément <form>
#   d2.to_urlencoded()                # nom=Ada&…
#
# Erreurs : TypeError (élément qui n'est pas un formulaire).

from core use len, type
from collections use append
use string as _s
use random as _random
use web.url.form_url_encoding as _form
use web.browser.browser_errors as _err
use web.browser.blob as _blob
use web.browser.file as _file

func _value(v, filename=null):
    if isinstance(v, _blob.Blob):
        if isinstance(v, _file.File):
            if filename != null:
                return _file.File([v], filename, {"type": v.type, "last_modified": v.last_modified})
            return v
        return _file.File([v], filename if filename != null else "blob", {"type": v.type})
    if v == true:
        return "true"
    if v == false:
        return "false"
    return str(v) if v != null else "null"

class FormData:
    func init(form=null, submitter=null):
        self.entries_list = []
        if form != null:
            if form.local_name != "form":
                _err.type_error("FormData", "élément <form> attendu")
            for p in form.form_entries(submitter):
                append(self.entries_list, (p[0], p[1]))
            for c in form.elements():
                if c.local_name == "input" and c.input_type() == "file" and c.get_attribute("name") != null and not c.disabled():
                    files := null
                    try:
                        files = c.files
                    catch e:
                        files = null
                    if files != null and files.length() > 0:
                        for f in files.files:
                            append(self.entries_list, (c.get_attribute("name"), f))
                    else:
                        append(self.entries_list, (c.get_attribute("name"), _file.File([], "", {"type": "application/octet-stream"})))

    func append(name, value, filename=null):
        append(self.entries_list, (str(name), _value(value, filename)))

    func delete(name):
        kept := []
        for e in self.entries_list:
            if e[0] != name:
                append(kept, e)
        self.entries_list = kept

    func get(name):
        for e in self.entries_list:
            if e[0] == name:
                return e[1]
        return null

    func get_all(name):
        out := []
        for e in self.entries_list:
            if e[0] == name:
                append(out, e[1])
        return out

    func has(name):
        return self.get(name) != null

    func set(name, value, filename=null):
        out := []
        done := false
        v := _value(value, filename)
        for e in self.entries_list:
            if e[0] == name:
                if not done:
                    append(out, (name, v))
                    done = true
                continue
            append(out, e)
        if not done:
            append(out, (name, v))
        self.entries_list = out

    func entries():
        return self.entries_list

    func keys():
        out := []
        for e in self.entries_list:
            append(out, e[0])
        return out

    func values():
        out := []
        for e in self.entries_list:
            append(out, e[1])
        return out

    func size():
        return len(self.entries_list)

    func has_files():
        for e in self.entries_list:
            if isinstance(e[1], _blob.Blob):
                return true
        return false

    # Corps application/x-www-form-urlencoded (fichiers remplacés par leur nom).
    func to_urlencoded():
        pairs := []
        for e in self.entries_list:
            v := e[1]
            append(pairs, (e[0], v.name if isinstance(v, _file.File) else v))
        return _form.encode(pairs)

    # (corps, type de contenu) multipart/form-data ; boundary : frontière imposée (sinon aléatoire).
    func to_multipart(boundary=null):
        b := boundary if boundary != null else "----AlexFormBoundary" + str(_random.getrandbits(48))
        parts := []
        for e in self.entries_list:
            name := _s.replace(_s.replace(_s.replace(e[0], "\"", "%22"), "\r", "%0D"), "\n", "%0A")
            v := e[1]
            if isinstance(v, _file.File):
                fname := _s.replace(v.name, "\"", "%22")
                ctype := v.type if v.type != "" else "application/octet-stream"
                append(parts, "--" + b + "\r\nContent-Disposition: form-data; name=\"" + name + "\"; filename=\"" + fname + "\"\r\nContent-Type: " + ctype + "\r\n\r\n" + v.text_now() + "\r\n")
            else:
                append(parts, "--" + b + "\r\nContent-Disposition: form-data; name=\"" + name + "\"\r\n\r\n" + _s.replace(_s.replace(str(v), "\r\n", "\n"), "\n", "\r\n") + "\r\n")
        append(parts, "--" + b + "--\r\n")
        return (_s.join("", parts), "multipart/form-data; boundary=" + b)

func from_form(form, submitter=null):
    return FormData(form, submitter)
