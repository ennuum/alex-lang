# ALEX STANDARD LIBRARY — web.server.directory_listing
#
# Liste HTML du contenu d'un dossier servi par web.server.static_files (quand aucun fichier d'index n'existe et
# que la liste est autorisée). Page accessible produite avec web.html : noms échappés et liens encodés, dossiers
# d'abord, taille et date de modification, lien vers le dossier parent. Les fichiers cachés (« . ») sont omis
# sauf si show_hidden.
#
#   use web.server.directory_listing as dl
#   r := dl.render("/srv/www/docs", "/docs/")          # web.http.response.Response (text/html)
#   dl.entries("/srv/www/docs")                        # [{"name", "is_dir", "size", "mtime"}], dossiers d'abord
#   dl.format_size(1536)                               # 1.5 Kio
#
# Erreurs : IoError (dossier illisible).

from core use len, type, to_int
from collections use append
use string as _s
use os as _os
use web.http.response as _response
use web.http.date_header as _date
use web.html.document as _document
use web.html.element as _el
use web.html.tables as _tables
use web.url.path_segment as _seg

# Taille lisible (o, Kio, Mio, Gio).
func format_size(n):
    if n < 1024:
        return str(n) + " o"
    units := ["Kio", "Mio", "Gio", "Tio"]
    v := n / 1024.0
    i := 0
    while v >= 1024.0 and i < len(units) - 1:
        v = v / 1024.0
        i += 1
    whole := to_int(v * 10 + 0.5)
    return str(whole // 10) + "." + str(whole % 10) + " " + units[i]

# Entrées du dossier : dict name, is_dir, size, mtime ; dossiers d'abord puis ordre alphabétique (sans casse).
func entries(directory, show_hidden=false):
    out := []
    for name in _os.list_dir(directory):
        if not show_hidden and _s.starts_with(name, "."):
            continue
        full := _os.join(directory, name)
        is_dir := _os.isdir(full)
        size := 0
        mtime := 0
        try:
            size = 0 if is_dir else _os.size(full)
            mtime = to_int(_os.mtime(full))
        catch e:
            size = 0
        append(out, {"name": name, "is_dir": is_dir, "size": size, "mtime": mtime})
    n := len(out)
    i := 1
    while i < n:
        cur := out[i]
        j := i - 1
        while j >= 0 and _after(out[j], cur):
            out[j + 1] = out[j]
            j -= 1
        out[j + 1] = cur
        i += 1
    return out

func _after(a, b):
    if a["is_dir"] != b["is_dir"]:
        return b["is_dir"]
    return _s.lower(a["name"]) > _s.lower(b["name"])

# Page HTML de la liste ; url_path : chemin de l'URL du dossier (terminé par « / »).
func render(directory, url_path, show_hidden=false, title_prefix="Index de "):
    title := title_prefix + url_path
    doc := _document.Document(title, "fr")
    style := "body{font-family:system-ui,sans-serif;margin:2rem}table{border-collapse:collapse}td,th{padding:.25rem 1rem;text-align:left}td.size{text-align:right}"
    doc.head().append(_el.Element("style", null, [style]))
    rows := []
    if url_path != "/":
        append(rows, [_el.Element("a", {"href": "../"}, "../"), "", ""])
    for e in entries(directory, show_hidden):
        href := _seg.encode(e["name"]) + ("/" if e["is_dir"] else "")
        label := e["name"] + ("/" if e["is_dir"] else "")
        size_cell := "—" if e["is_dir"] else {"content": format_size(e["size"]), "class": "size"}
        append(rows, [_el.Element("a", {"href": href}, label), size_cell, _date.format(e["mtime"]) if e["mtime"] > 0 else ""])
    table := _tables.table(rows, ["Nom", "Taille", "Modifié"], null)
    main := _el.Element("main", {"id": "contenu"}, [_el.Element("h1", null, title), table])
    doc.body().append(main)
    r := _response.html(doc.to_html())
    r.headers.set("Cache-Control", "no-cache")
    return r
