# ALEX — commands.bundle
#
# SDK embarqué dans l'exécutable alexc : stdlib/, runtime/, templates/ et la machine virtuelle, ajoutés à la fin de
# l'exécutable (après sa dernière section : ni le chargeur de Windows ni celui de Linux ne les lisent). Un alexc
# copié seul, sans dossier stdlib ni runtime à côté, extrait ce SDK une fois dans un cache par version et s'en sert
# ensuite comme d'une installation ordinaire (compilation, cache des modules, `run`, `new`, `doc`...).
#
#   use commands.bundle as sdk
#   sdk.pack(exe, "D:/alex", "D:/alex/build/alexvm.exe", "alexc-portable.exe")   # exe + SDK -> nouvel exécutable
#   dir := sdk.extract(exe)        # dossier du SDK extrait (stdlib/, runtime/, templates/, alexvm), "" sans SDK
#
# Format, à la fin du fichier : les données (fichiers concaténés), l'index (lignes « chemin\tdécalage\ttaille\n »,
# chemins relatifs en « / », décalages depuis le début des données), puis un en-queue de 32 octets : « ALEXSDK1 »,
# taille des données, taille de l'index, taille de l'exécutable d'origine (entiers de 64 bits, petit-boutiens).
# Contenu déterministe (fichiers dans l'ordre trié de list_dir, sans date) : deux paquetages identiques en entrée
# donnent les mêmes octets. Les caches de compilation (*.albc, *.meta) et les dossiers cachés ne sont pas embarqués.
#
# Erreurs : celles d'io et d'os (pack) ; extract renvoie "" plutôt que d'échouer.

from core use len, to_int
from collections use append
use string as _s
use os as _os
use io as _io

const MAGIC := "ALEXSDK1"
const TRAILER := 32
const DIRS := ["stdlib", "runtime", "templates"]
# Fichier écrit en dernier dans un SDK extrait : sa présence garantit une extraction complète.
const MARKER := ".alex-sdk"

func _keep(name):
    return not (_s.ends_with(name, ".albc") or _s.ends_with(name, ".meta"))

# Chemins relatifs (en « / ») des fichiers à embarquer sous root/rel, récursivement, dans l'ordre trié.
func _files(root, rel, out):
    for n in _os.list_dir(_os.join(root, rel)):
        r := rel + "/" + n
        p := _os.join(root, r)
        if _os.isdir(p):
            if len(n) > 0 and n[0] != '.':
                _files(root, r, out)
        elif _keep(n):
            append(out, r)

func _u64_bytes(v):
    out := []
    k := 0
    while k < 8:
        append(out, (v >> (8 * k)) & 255)
        k += 1
    return _s.byte_pack(out)

func _u64(b, i):
    v := 0
    k := 7
    while k >= 0:
        v = (v << 8) | b[i + k]
        k -= 1
    return v

func _u32(b, i):
    return b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24)

# Entrée « sécurité » (signature Authenticode) d'un exécutable PE : [position de l'entrée dans le fichier, décalage
# de la table des certificats, sa taille], ou null (pas un PE, ou PE non signé).
func _securite_pe(exe, n):
    if n < 0x40:
        return null
    h := _io.read_bytes(exe, 0, 0x40)
    if h[0] != 77 or h[1] != 90:
        return null
    pe := _u32(h, 0x3C)
    if pe <= 0 or pe + 24 + 152 > n:
        return null
    o := _io.read_bytes(exe, pe, 24 + 152)
    if o[0] != 80 or o[1] != 69 or o[2] != 0 or o[3] != 0:
        return null
    magic := o[24] | (o[25] << 8)
    # répertoires de données : à 96 (PE32) ou 112 (PE32+) octets de l'en-tête optionnel ; « sécurité » = n° 4
    dd := 112 if magic == 0x20B else 96
    pos := 24 + dd + 4 * 8
    off := _u32(o, pos)
    taille := _u32(o, pos + 4)
    if off <= 0 or taille <= 0:
        return null
    return [pe + pos, off, taille]

# [fin du SDK dans le fichier, taille des données, taille de l'index, taille de l'exécutable d'origine], ou null si
# `exe` ne porte pas de SDK. Un exécutable Windows signé après l'ajout du SDK (Authenticode) porte, après l'en-queue,
# quelques octets d'alignement (0 à 7) puis la table des certificats : le SDK se termine alors avant elle.
func trailer(exe):
    try:
        n := _os.size(exe)
        fin := n
        sec := _securite_pe(exe, n)
        if sec != null and sec[1] + sec[2] == n:
            fin = sec[1]
        pad := 0
        while pad < 8:
            e := fin - pad
            if e < TRAILER:
                return null
            t := _io.read_bytes(exe, e - TRAILER, TRAILER)
            if _s.byte_pack(t[0:8]) == MAGIC:
                d := _u64(t, 8)
                x := _u64(t, 16)
                b := _u64(t, 24)
                if b < 0 or d < 0 or x < 0 or b + d + x + TRAILER != e:
                    return null
                return [e, d, x, b]
            if fin == n:
                return null
            pad += 1
        return null
    catch e:
        return null

# Empreinte FNV-1a 64 bits, en 16 chiffres hexadécimaux.
func _hash(text):
    h := 1469598103934665603
    for c in _s.byte_unpack(text):
        h = h ^ c
        h = h * 1099511628211
    hexd := "0123456789abcdef"
    digits := ""
    i := 15
    while i >= 0:
        digits += str(hexd[(h >> (i * 4)) & 0xF])
        i -= 1
    return digits

# Écrit `out` : l'exécutable `exe` (débarrassé d'un SDK déjà embarqué) suivi du SDK pris sous sdk_root (stdlib/,
# runtime/, templates/) et de la machine virtuelle `vm` ("" : sans VM). Renvoie [nombre de fichiers, octets du SDK].
func pack(exe, sdk_root, vm, out):
    base := _io.read_file(exe)
    t := trailer(exe)
    if t != null:
        base = _s.byte_slice(base, 0, t[3])
    # exécutable signé : la signature ne vaudrait plus après l'ajout du SDK ; on la retire (table des certificats
    # en fin de fichier, entrée « sécurité » remise à zéro) — signer l'exécutable final, après le paquetage
    sec := _securite_pe(exe, _os.size(exe))
    if sec != null:
        lb := _s.byte_len(base)
        coupe := sec[1] if sec[1] < lb and sec[1] + sec[2] <= lb else lb
        zero := _s.byte_pack([0, 0, 0, 0, 0, 0, 0, 0])
        base = _s.byte_slice(base, 0, sec[0]) + zero + _s.byte_slice(base, sec[0] + 8, coupe)
    files := []
    for d in DIRS:
        if _os.isdir(_os.join(sdk_root, d)):
            _files(sdk_root, d, files)
    if not ("stdlib/core/core.al" in files):
        raise("IoError", "bundle : pas de bibliothèque standard sous '" + sdk_root + "' (stdlib/core/core.al)")
    parts := []
    index := []
    off := 0
    for r in files:
        data := _io.read_file(_os.join(sdk_root, r))
        append(parts, data)
        append(index, r + "\t" + str(off) + "\t" + str(_s.byte_len(data)) + "\n")
        off += _s.byte_len(data)
    if vm != "":
        data := _io.read_file(vm)
        append(parts, data)
        append(index, _os.basename(vm) + "\t" + str(off) + "\t" + str(_s.byte_len(data)) + "\n")
        off += _s.byte_len(data)
    idx := _s.join("", index)
    tail := MAGIC + _u64_bytes(off) + _u64_bytes(_s.byte_len(idx)) + _u64_bytes(_s.byte_len(base))
    _io.write_file(out, base + _s.join("", parts) + idx + tail)
    return [len(index), off]

# Cache des SDK extraits : %LOCALAPPDATA%\alex\sdk sous Windows, $XDG_CACHE_HOME/alex/sdk ou ~/.cache/alex/sdk
# ailleurs, en dernier recours le dossier temporaire.
func cache_root():
    v := _os.getenv("LOCALAPPDATA") if _os.platform() == "windows" else _os.getenv("XDG_CACHE_HOME")
    if v != null and v != "":
        return _os.join(_os.join(v, "alex"), "sdk")
    h := _os.home()
    if h != null and h != "":
        return _os.join(_os.join(_os.join(h, ".cache"), "alex"), "sdk")
    return _os.join(_os.tmp_dir(), "alex-sdk")

# Hors Windows, la machine virtuelle extraite doit être exécutable (io.write_file crée les fichiers en 0644) ;
# corrige aussi un cache extrait par une version antérieure.
func _executable_vm(dir):
    if _os.platform() == "windows":
        return null
    vm := _os.join(dir, "alexvm")
    if _os.isfile(vm):
        _os.chmod(vm, "755")

# Dossier du SDK embarqué dans `exe`, extrait au premier appel (dossier temporaire puis renommage : jamais de SDK
# à moitié écrit, même avec plusieurs alexc lancés en même temps). "" si `exe` n'en porte pas ou si l'extraction
# échoue (disque plein, droits...).
func extract(exe):
    t := trailer(exe)
    if t == null:
        return ""
    d := t[1]
    b := t[3]
    try:
        idx := _s.byte_pack(_io.read_bytes(exe, b + d, t[2]))
        key := _os.alex_build()["version"] + "-" + _hash(idx + "\n" + str(d))
        root := cache_root()
        dir := _os.join(root, key)
        if _os.isfile(_os.join(dir, MARKER)):
            _executable_vm(dir)
            return dir
        tmp := dir + ".tmp-" + str(_os.pid())
        if _os.isdir(tmp):
            _os.rmdir(tmp, true)
        all := _io.read_file(exe)
        for line in _s.split(idx, "\n"):
            if line == "":
                continue
            f := _s.split(line, "\t")
            p := _os.join(tmp, f[0])
            _os.mkdir_all(_os.dirname(p))
            o := b + to_int(f[1])
            _io.write_file(p, _s.byte_slice(all, o, o + to_int(f[2])))
        _executable_vm(tmp)
        _io.write_file(_os.join(tmp, MARKER), key + "\n")
        if _os.isdir(dir) and not _os.isfile(_os.join(dir, MARKER)):
            _os.rmdir(dir, true)
        if _os.isdir(dir):
            _os.rmdir(tmp, true)
        else:
            _os.move(tmp, dir)
        return dir if _os.isfile(_os.join(dir, MARKER)) else ""
    catch e:
        return ""
