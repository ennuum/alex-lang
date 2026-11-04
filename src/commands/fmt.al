# ALEX — commands.fmt
#
# `alexc fmt [--check] [fichiers|dossiers...]` (défaut : dossier courant) : mise en forme comme
# LanguageService::format du C++ — tabulations de tête remplacées par des espaces (tabulation de 4), espaces de fin
# de ligne retirés, au plus deux lignes vides consécutives, lignes vides finales retirées, un « \n » final.
#
#   use commands.fmt as cf
#   cf.format_text("x := 1   \n\n\n\n")     # "x := 1\n\n\n"
#   code := cf.run(["--check", "src"])
#
# Erreurs : celles d'io (fichier illisible).

from core use len
from collections use append
use string as _s
use os as _os
use io as _io
use commands.common as cc

# Texte mis en forme (identique à `text` s'il n'y a rien à changer).
func format_text(text, tab_size=4):
    out := []
    blank := 0
    for line in cc.split_lines(text):
        lead := ""
        k := 0
        n := len(line)
        while k < n and (line[k] == ' ' or line[k] == '\t'):
            if line[k] == '\t':
                lead += _s.repeat(" ", tab_size - len(lead) % tab_size)
            else:
                lead += " "
            k += 1
        line = lead + _s.substring(line, k, n)
        e := len(line)
        while e > 0 and (line[e - 1] == ' ' or line[e - 1] == '\t'):
            e -= 1
        line = _s.substring(line, 0, e)
        if line == "":
            blank += 1
            if blank > 2:
                continue
        else:
            blank = 0
        append(out, line)
    while len(out) > 1 and out[len(out) - 1] == "":
        out = out[0:len(out) - 1]
    return _s.join("", [l + "\n" for l in out])

func _is_al(n):
    return cc.ends_with(n, ".al") and len(n) > 3

func run(args):
    check := false
    targets := []
    for a in args:
        if a == "--check":
            check = true
        else:
            append(targets, a)
    if len(targets) == 0:
        append(targets, ".")
    files := []
    for t in targets:
        if _os.isfile(t):
            append(files, t)
        elif _os.isdir(t):
            for f in cc.walk_files(t, _is_al):
                append(files, f)
    changed := 0
    for f in files:
        text := _io.read_file(f)
        nt := format_text(text)
        if nt == text:
            continue
        changed += 1
        if check:
            print("à mettre en forme : " + f)
        else:
            _io.write_file(f, nt)
            print("mis en forme : " + f)
    if check and changed > 0:
        return 1
    cc.err(str(len(files)) + " fichier(s), " + str(changed) + (" à mettre en forme\n" if check else " modifié(s)\n"))
    return 0
