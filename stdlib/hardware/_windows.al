# ALEX STANDARD LIBRARY — hardware._windows (privé)
#
# Périphériques multimédias de Windows, communs à hardware.audio, hardware.microphone, hardware.camera, audio et
# camera :
#   - caméras et entrées audio DirectShow, telles que ffmpeg les voit (`ffmpeg -list_devices true -f dshow`) ;
#   - cartes son (WMI, Win32_SoundDevice, par PowerShell).
# Chaque périphérique DirectShow est un dict {"name", "kind" ("video" | "audio"), "alt"} ; « alt » est le nom
# interne (« @device_pnp_... »), en ASCII, que ffmpeg accepte aussi : c'est lui qui est passé à ffmpeg, pour ne pas
# dépendre de l'encodage du nom affiché (« Réseau de microphones (... Intel® ...) »).
#
#   use hardware._windows as win
#   print(win.dshow_devices())          # [{"name": "HP HD Camera", "kind": "video", "alt": "@device_pnp_..."}, ...]
#   print(win.input_args(win.dshow_audio()[0]))      # ["-f", "dshow", "-i", "audio=@device_cm_..."]
#
# Hors Windows (ou sans ffmpeg) : listes vides. Les résultats sont mis en cache (reset() les oublie).

from core use len, type
from collections use append
use string as _s
use os as _os
use process as _proc

_cache := [{}]

func is_windows():
    return _os.platform() == "windows"

func reset():
    _cache[0] = {}

# Analyse la sortie de `ffmpeg -list_devices true -f dshow -i dummy` (ffmpeg 4.3 et plus : « "Nom" (video) » ;
# plus ancien : sections « DirectShow video devices » / « DirectShow audio devices »).
func parse_dshow(text):
    out := []
    section := null
    for raw in _s.split(text, "\n"):
        line := _s.trim(raw)
        if _s.contains(line, "DirectShow video devices"):
            section = "video"
            continue
        if _s.contains(line, "DirectShow audio devices"):
            section = "audio"
            continue
        a := _s.find(line, "\"")
        if a < 0:
            continue
        b0 := _s.find(_s.slice(line, a + 1), "\"")
        if b0 < 0:
            continue
        b := a + 1 + b0
        value := _s.slice(line, a + 1, b)
        if _s.contains(line, "Alternative name"):
            if len(out) > 0:
                out[len(out) - 1]["alt"] = value
            continue
        rest := _s.slice(line, b + 1)
        kind := section
        if _s.contains(rest, "(video)"):
            kind = "video"
        elif _s.contains(rest, "(audio)"):
            kind = "audio"
        elif _s.contains(rest, "(none)"):
            kind = null
        if kind == null or value == "dummy":
            continue
        append(out, {"name": value, "kind": kind, "alt": null})
    return out

func dshow_devices():
    if "dshow" in _cache[0]:
        return _cache[0]["dshow"]
    out := []
    if is_windows() and _proc.which("ffmpeg") != null:
        try:
            r := _proc.run("ffmpeg", ["-hide_banner", "-list_devices", "true", "-f", "dshow", "-i", "dummy"], null, 20)
            out = parse_dshow(r.stderr + "\n" + r.stdout)
        catch e:
            out = []
    _cache[0]["dshow"] = out
    return out

func dshow_video():
    return [d for d in dshow_devices() if d["kind"] == "video"]

func dshow_audio():
    return [d for d in dshow_devices() if d["kind"] == "audio"]

# Identifiant à passer à ffmpeg : « video=... » / « audio=... » (nom interne s'il est connu).
func source(device):
    return device["kind"] + "=" + (device["alt"] if device["alt"] != null else device["name"])

# Désignation acceptée partout où un périphérique est attendu : dict DirectShow, « video=... » / « audio=... »,
# nom affiché ou nom interne d'un périphérique de ce genre.
func resolve(device, kind):
    if device == null:
        ds := dshow_video() if kind == "video" else dshow_audio()
        if len(ds) == 0:
            return null
        return source(ds[0])
    if type(device) == "dict":
        return source(device)
    if _s.starts_with(device, kind + "="):
        return device
    for d in dshow_devices():
        if d["kind"] == kind and (d["name"] == device or d["alt"] == device):
            return source(d)
    return kind + "=" + device

# Arguments d'entrée de ffmpeg pour un périphérique DirectShow (dict ou identifiant « video=... »).
func input_args(device, kind=null):
    k := kind
    if k == null:
        k = device["kind"] if type(device) == "dict" else ("video" if _s.starts_with(device, "video=") else "audio")
    src := resolve(device, k)
    if src == null:
        return null
    return ["-f", "dshow", "-i", src]

# Cartes son (noms WMI), [] hors Windows.
func sound_cards():
    if "cards" in _cache[0]:
        return _cache[0]["cards"]
    out := []
    if is_windows():
        try:
            cmd := "[Console]::OutputEncoding = [Text.Encoding]::UTF8; Get-CimInstance Win32_SoundDevice | Where-Object { $_.Status -eq 'OK' } | ForEach-Object { $_.Name }"
            r := _proc.run("powershell", ["-NoProfile", "-NonInteractive", "-Command", cmd], null, 30)
            if r.code == 0:
                for line in _s.split(r.stdout, "\n"):
                    t := _s.trim(line)
                    if t != "":
                        append(out, t)
        catch e:
            out = []
    _cache[0]["cards"] = out
    return out
