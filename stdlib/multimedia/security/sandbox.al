# ALEX STANDARD LIBRARY — multimedia.security.sandbox
#
# Analyse d'un fichier NON FIABLE dans un PROCESSUS ISOLÉ (security.sandbox : limites du noyau sur le temps
# processeur, la mémoire, la taille des fichiers, délai réel, environnement vidé, dossier jetable, sans réseau
# quand le noyau le permet). Si le décodeur plante, boucle ou épuise la mémoire, seul le processus fils meurt ;
# le résultat le dit. À utiliser avant d'ouvrir un fichier reçu d'un tiers dans le processus principal.
#
#   use multimedia.security.sandbox as msb
#   r := msb.isolated_probe("piece_jointe.flac")
#   if r["ok"]:
#       print(r["info"]["container"], r["info"]["streams"])
#   v := msb.isolated_check("photo.png")        # décode entièrement : {"ok", "kind", "summary" | "error_type", ...}
#   print(v["enforced"])                         # protections réellement appliquées
#
# Le processus fils compile un petit programme ALEX : prévoir ~4 Gio de limite mémoire (memory_mb).
# Erreurs : aucune levée pour un fichier hostile (le résultat porte l'échec) ; MediaError si le fichier manque.

from core use len
from collections use keys
use os as _os
use json as _json
use string as _s
use security.sandbox as _sb
use multimedia.core.errors as merr

const PROBE_SRC := "use multimedia.container.probe as p\nuse json\ntry:\n    print(\"@@\" + json.stringify({\"ok\": true, \"info\": p.probe(ARG).to_dict()}))\ncatch e:\n    print(\"@@\" + json.stringify({\"ok\": false, \"error_type\": e.type, \"error\": e.message}))\n"

const CHECK_SRC := "use multimedia.container.probe as p\nuse multimedia.container.demux as d\nuse multimedia.image.decode as img\nuse json\nuse crypto\ntry:\n    i := p.probe(ARG)\n    s := {}\n    if i.has(\"image\"):\n        m := img.load(ARG)\n        s = {\"kind\": \"image\", \"width\": m.width, \"height\": m.height, \"mode\": m.mode, \"md5\": crypto.md5(m.pixels)}\n    elif i.has(\"audio\"):\n        x := d.open(ARG)\n        a := x.read_all()\n        s = {\"kind\": \"audio\", \"frames\": len(a) // x.format.channels, \"rate\": x.format.rate, \"channels\": x.format.channels}\n    else:\n        s = {\"kind\": \"autre\"}\n    print(\"@@\" + json.stringify({\"ok\": true, \"summary\": s, \"warnings\": i.warnings}))\ncatch e:\n    print(\"@@\" + json.stringify({\"ok\": false, \"error_type\": e.type, \"error\": e.message}))\n"

func _abs(path):
    if _os.is_absolute(path):
        return path
    return _os.join(_os.cwd(), path)

func _quote(text):
    return "\"" + _s.replace(_s.replace(text, "\\", "\\\\"), "\"", "\\\"") + "\""

func _run(template, path, cpu_seconds, memory_mb, timeout):
    if not _os.isfile(path):
        merr.fail(merr.MEDIA, "fichier introuvable : " + str(path))
    s := _sb.Sandbox()
    s.cpu_seconds = cpu_seconds
    s.memory_mb = memory_mb
    s.timeout = timeout
    s.network = false
    src := "ARG := " + _quote(_abs(path)) + "\n" + template
    r := s.run_source(src)
    out := {"ok": false, "enforced": r.enforced, "timed_out": false}
    try:
        out["timed_out"] = r.timed_out
    catch e:
        out["timed_out"] = false
    for line in _s.split(r.stdout, "\n"):
        if _s.starts_with(line, "@@"):
            res := _json.parse(_s.substring(line, 2, len(line)))
            for k in keys(res):
                out[k] = res[k]
            return out
    out["error_type"] = "SandboxFailure"
    err := _s.trim(r.stderr)
    out["error"] = "le processus isolé n'a pas rendu de résultat" + (" (délai dépassé)" if out["timed_out"] else "") + (" : " + err if len(err) > 0 else "")
    return out

func isolated_probe(path, cpu_seconds=60, memory_mb=4096, timeout=90.0):
    return _run(PROBE_SRC, path, cpu_seconds, memory_mb, timeout)

func isolated_check(path, cpu_seconds=120, memory_mb=4096, timeout=180.0):
    return _run(CHECK_SRC, path, cpu_seconds, memory_mb, timeout)
