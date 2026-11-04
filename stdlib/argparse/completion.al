# ALEX STANDARD LIBRARY — argparse.completion
#
# Génère des scripts de complétion à partir d'un ArgumentParser (et de ses sous-commandes
# imbriquées) :  parser.completion("bash" | "zsh" | "powershell").
#
#   Bash        source <(prog completion bash)     ou   fichier dans bash_completion.d/
#   Zsh         fichier _prog dans un dossier de $fpath  (ou  source <(...)  puis compdef)
#   PowerShell  prog completion powershell | Out-String | Invoke-Expression
#
# Ce que complètent les scripts : sous-commandes (et leurs alias), options longues/courtes
# de la commande en cours, valeurs d'options à `choices`, fichiers (type "path"/"file"),
# dossiers (type "dir"), mots fixes (complete=[...]), choix des positionnels. L'option
# `complete` d'add_argument ("file", "dir", "none" ou une liste de mots) prime sur le type.
#
# Limites : les positionnels sont complétés « en bloc » (tous les choix de la commande,
# sans compter les positionnels déjà donnés) ; les options à plusieurs valeurs (nargs > 1)
# ne complètent que la première valeur ; la forme collée -nVALEUR n'est pas reconnue pour
# repérer les sous-commandes. Bash et Zsh sont testés, PowerShell est généré mais non
# exécuté ici (voir docs/ARGPARSE.md).
#
# Erreurs : ArgumentError (shell inconnu).

from core use len, type
from collections use append, contains
use argparse.text as _t
use argparse.help as _h

# ---------------------------------------------------------------------
# Arbre des commandes
# ---------------------------------------------------------------------

# Programme racine : premier mot de parser.prog (ou `prog` fourni).
func _root_name(parser, prog):
    if prog != null:
        return prog
    w := _t.words(parser.prog)
    if len(w) == 0:
        return "prog"
    return w[0]

# Liste de nœuds {"path": [noms], "parser": p, "key": "prog sous sous"} en profondeur d'abord.
func nodes(parser, root):
    out := []
    _walk(parser, [], root, out)
    return out

func _walk(parser, path, root, out):
    key := root
    if len(path) > 0:
        key = root + " " + _t.join(" ", path)
    append(out, {"path": path, "parser": parser, "key": key})
    if parser.sub != null:
        for c in parser.sub.commands:
            if c.hidden:
                continue
            sub_path := []
            for x in path:
                append(sub_path, x)
            append(sub_path, c.name)
            _walk(c, sub_path, root, out)

# Indice de complétion d'un argument : {"kind": "words"|"file"|"dir"|"none", "words": [...]}.
func hint_of(arg):
    c := arg.complete
    if c != null:
        if type(c) == "list":
            return {"kind": "words", "words": _t.stringify(c)}
        return {"kind": str(c), "words": []}
    if arg.choices != null:
        return {"kind": "words", "words": _t.stringify(arg.choices)}
    if arg.type == "path" or arg.type == "file":
        return {"kind": "file", "words": []}
    if arg.type == "dir":
        return {"kind": "dir", "words": []}
    return {"kind": "none", "words": []}

# Options visibles d'un parseur (Arguments non positionnels).
func options_of(parser):
    out := []
    for a in parser.args:
        if a.positional or a.hidden:
            continue
        append(out, a)
    return out

func positionals_of(parser):
    out := []
    for a in parser.args:
        if a.positional and not a.hidden and a.action != "parser":
            append(out, a)
    return out

# [[nom_ou_alias, nom_canonique, aide], ...] des sous-commandes visibles.
func subcommands_of(parser):
    out := []
    if parser.sub == null:
        return out
    for c in parser.sub.commands:
        if c.hidden:
            continue
        h := c.help_text
        if h == null:
            h = ""
        append(out, [c.name, c.name, h])
        for al in c.aliases:
            append(out, [al, c.name, h])
    return out

func _takes_value(arg):
    return _h.takes_value(arg)

func _ident(text):
    out := ""
    i := 0
    while i < len(text):
        c := _t.char_at(text, i)
        code := _ord(c)
        ok := (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code == 95
        if ok:
            out = out + c
        else:
            out = out + "_"
        i = i + 1
    return out

use string as _str

func _ord(c):
    return _str.ord(c)

# ---------------------------------------------------------------------
# Bash
# ---------------------------------------------------------------------

func _sq(text):
    return "'" + _t.replace_all(text, "'", "'\\''") + "'"

func _words_arg(words):
    return _sq(_t.join(" ", words))

func bash(parser, prog):
    root := _root_name(parser, prog)
    fn := "_" + _ident(root) + "_complete"
    ns := nodes(parser, root)
    L := []
    append(L, "# Complétion Bash pour " + root + " (générée par argparse)")
    append(L, fn + "() {")
    append(L, "    local cur prev cmd=" + _sq(root) + " i w")
    append(L, "    cur=\"${COMP_WORDS[COMP_CWORD]}\"")
    append(L, "    prev=\"${COMP_WORDS[COMP_CWORD-1]}\"")
    append(L, "    # bash découpe --opt=valeur en trois mots : --opt, =, valeur")
    append(L, "    if [[ \"$cur\" == \"=\" ]]; then cur=\"\"")
    append(L, "    elif [[ \"$prev\" == \"=\" ]]; then prev=\"${COMP_WORDS[COMP_CWORD-2]}\"; fi")
    append(L, "    # repère la commande courante en sautant les valeurs d'options")
    append(L, "    i=1")
    append(L, "    while (( i < COMP_CWORD )); do")
    append(L, "        w=\"${COMP_WORDS[i]}\"")
    append(L, "        case \"$cmd|$w\" in")
    for n in ns:
        p := n["parser"]
        vals := []
        for a in options_of(p):
            if _takes_value(a):
                for nm in a.names:
                    append(vals, _sq(n["key"] + "|" + nm))
        if len(vals) > 0:
            append(L, "            " + _t.join("|", vals) + ")")
            append(L, "                if [[ \"${COMP_WORDS[i+1]}\" == \"=\" ]]; then i=$((i+2)); else i=$((i+1)); fi ;;")
        for s in subcommands_of(p):
            append(L, "            " + _sq(n["key"] + "|" + s[0]) + ") cmd=" + _sq(n["key"] + " " + s[1]) + " ;;")
    append(L, "        esac")
    append(L, "        i=$((i+1))")
    append(L, "    done")
    append(L, "    # valeur d'une option")
    append(L, "    case \"$cmd|$prev\" in")
    for n in ns:
        for a in options_of(n["parser"]):
            if not _takes_value(a):
                continue
            h := hint_of(a)
            keys := []
            for nm in a.names:
                append(keys, _sq(n["key"] + "|" + nm))
            body := "return 0"
            if h["kind"] == "words":
                body = "COMPREPLY=( $(compgen -W " + _words_arg(h["words"]) + " -- \"$cur\") ); return 0"
            elif h["kind"] == "file":
                body = "COMPREPLY=( $(compgen -f -- \"$cur\") ); return 0"
            elif h["kind"] == "dir":
                body = "COMPREPLY=( $(compgen -d -- \"$cur\") ); return 0"
            append(L, "        " + _t.join("|", keys) + ") " + body + " ;;")
    append(L, "    esac")
    append(L, "    local opts=\"\" subs=\"\" posw=\"\" posfile=0")
    append(L, "    case \"$cmd\" in")
    for n in ns:
        p := n["parser"]
        opt_words := []
        for a in options_of(p):
            for nm in a.names:
                append(opt_words, nm)
        sub_words := []
        for s in subcommands_of(p):
            append(sub_words, s[0])
        pos_words := []
        posfile := 0
        for a in positionals_of(p):
            h := hint_of(a)
            if h["kind"] == "words":
                for w in h["words"]:
                    append(pos_words, w)
            elif h["kind"] == "file" or h["kind"] == "dir":
                posfile = 1
        append(L, "        " + _sq(n["key"]) + ")")
        append(L, "            opts=" + _words_arg(opt_words))
        append(L, "            subs=" + _words_arg(sub_words))
        append(L, "            posw=" + _words_arg(pos_words))
        append(L, "            posfile=" + str(posfile) + " ;;")
    append(L, "    esac")
    append(L, "    if [[ \"$cur\" == -* ]]; then")
    append(L, "        COMPREPLY=( $(compgen -W \"$opts\" -- \"$cur\") )")
    append(L, "    else")
    append(L, "        COMPREPLY=( $(compgen -W \"$subs $posw\" -- \"$cur\") )")
    append(L, "        if (( posfile )); then COMPREPLY+=( $(compgen -f -- \"$cur\") ); fi")
    append(L, "    fi")
    append(L, "    return 0")
    append(L, "}")
    append(L, "complete -F " + fn + " " + _sq(root))
    return _t.lines_text(L) + "\n"

# ---------------------------------------------------------------------
# Zsh
# ---------------------------------------------------------------------

# Dans une description de _arguments : [ ] ' \ ne doivent pas casser la spécification.
func _zdesc(text):
    t := _t.replace_all(text, "\\", "\\\\")
    t = _t.replace_all(t, "[", "(")
    t = _t.replace_all(t, "]", ")")
    t = _t.replace_all(t, "'", "'\\''")
    t = _t.replace_all(t, "\n", " ")
    return t

# Dans une entrée de _describe « nom:description » : « : » du nom échappé.
func _zname(text):
    return _t.replace_all(_zdesc(text), ":", "\\:")

func _zaction(hint, optional_value):
    kind := hint["kind"]
    if kind == "words":
        return "(" + _t.join(" ", hint["words"]) + ")"
    if kind == "file":
        return "_files"
    if kind == "dir":
        return "_files -/"
    return " "

func _zmetavar(arg):
    m := arg.dest
    if type(arg.metavar) == "str":
        m = arg.metavar
    elif not arg.positional:
        m = _t.upper(arg.dest)
    m = _t.replace_all(m, ":", " ")
    m = _t.replace_all(m, "'", "")
    return m

func _zsh_spec_for(arg):
    h := hint_of(arg)
    desc := ""
    if arg.help != null:
        desc = arg.help
    names := arg.names
    value := ""
    if _takes_value(arg):
        n := arg.nargs
        mv := _zmetavar(arg)
        if n == "?":
            value = "::" + mv + ":" + _zaction(h, true)
        elif _kind_of(n) == "int" and n > 1:
            i := 0
            while i < n:
                value = value + ":" + mv + ":" + _zaction(h, false)
                i = i + 1
        else:
            value = ":" + mv + ":" + _zaction(h, false)
    text := value
    if desc != "":
        text = "[" + _zdesc(desc) + "]" + value
    if len(names) == 1:
        nm := names[0]
        if _takes_value(arg) and _t.starts_with(nm, "--"):
            nm = nm + "="
        return "'" + nm + text + "'"
    excl := "'(" + _t.join(" ", names) + ")'"
    forms := []
    for nm in names:
        if _takes_value(arg):
            if _t.starts_with(nm, "--"):
                append(forms, nm + "=")
            else:
                append(forms, nm + "+")
        else:
            append(forms, nm)
    return excl + "{" + _t.join(",", forms) + "}'" + text + "'"

func _kind_of(v):
    return type(v)

func _zsh_node(node, root, L, is_root):
    p := node["parser"]
    key := node["key"]
    fn := "_" + _ident(key)
    append(L, fn + "() {")
    append(L, "    local curcontext=\"$curcontext\" state state_descr line ret=1")
    append(L, "    typeset -A opt_args")
    specs := []
    for a in options_of(p):
        append(specs, _zsh_spec_for(a))
    idx := 1
    for a in positionals_of(p):
        h := hint_of(a)
        mv := _zmetavar(a)
        act := _zaction(h, false)
        n := a.nargs
        if n == "?":
            append(specs, "'" + str(idx) + "::" + mv + ":" + act + "'")
            idx = idx + 1
        elif n == "*" or n == "+":
            append(specs, "'*:" + mv + ":" + act + "'")
        elif _kind_of(n) == "int":
            j := 0
            while j < n:
                append(specs, "'" + str(idx) + ":" + mv + ":" + act + "'")
                idx = idx + 1
                j = j + 1
        elif n == "remainder":
            append(specs, "'*:" + mv + ":" + act + "'")
        else:
            append(specs, "'" + str(idx) + ":" + mv + ":" + act + "'")
            idx = idx + 1
    subs := subcommands_of(p)
    has_subs := len(subs) > 0
    if has_subs:
        append(specs, "'" + str(idx) + ": :->cmds'")
        append(specs, "'*:: :->args'")
    if len(specs) == 0:
        append(L, "    _message 'aucun argument'")
        append(L, "    return ret")
    else:
        append(L, "    _arguments -C \\")
        i := 0
        while i < len(specs):
            tail := " \\"
            if i == len(specs) - 1:
                tail = " && ret=0"
            append(L, "        " + specs[i] + tail)
            i = i + 1
        if has_subs:
            append(L, "    case $state in")
            append(L, "        cmds)")
            append(L, "            local -a subcmds")
            entries := []
            for s in subs:
                append(entries, "'" + _zname(s[0]) + ":" + _zdesc(s[2]) + "'")
            append(L, "            subcmds=(" + _t.join(" ", entries) + ")")
            append(L, "            _describe -t commands 'commandes' subcmds && ret=0 ;;")
            append(L, "        args)")
            append(L, "            case ${line[1]} in")
            for s in subs:
                child_key := key + " " + s[1]
                append(L, "                " + _sq(s[0]) + ") " + "_" + _ident(child_key) + " ;;")
            append(L, "            esac ;;")
            append(L, "    esac")
        append(L, "    return ret")
    append(L, "}")
    append(L, "")

func zsh(parser, prog):
    root := _root_name(parser, prog)
    ns := nodes(parser, root)
    L := []
    append(L, "#compdef " + root)
    append(L, "# Complétion Zsh pour " + root + " (générée par argparse)")
    append(L, "")
    for n in ns:
        _zsh_node(n, root, L, len(n["path"]) == 0)
    rootfn := "_" + _ident(root)
    append(L, "if [ \"$funcstack[1]\" = \"" + rootfn + "\" ]; then")
    append(L, "    " + rootfn + " \"$@\"")
    append(L, "else")
    append(L, "    compdef " + rootfn + " " + _sq(root))
    append(L, "fi")
    return _t.lines_text(L) + "\n"

# ---------------------------------------------------------------------
# PowerShell
# ---------------------------------------------------------------------

func _ps(text):
    return "'" + _t.replace_all(_t.replace_all(text, "'", "''"), "\n", " ") + "'"

func _ps_list(words):
    items := []
    for w in words:
        append(items, _ps(w))
    if len(items) == 0:
        return "@()"
    return "@(" + _t.join(", ", items) + ")"

func _ps_entries(pairs):
    items := []
    for pr in pairs:
        append(items, "[pscustomobject]@{ N = " + _ps(pr[0]) + "; T = " + _ps(pr[1]) + " }")
    if len(items) == 0:
        return "@()"
    return "@(" + _t.join(", ", items) + ")"

func powershell(parser, prog):
    root := _root_name(parser, prog)
    ns := nodes(parser, root)
    L := []
    append(L, "# Complétion PowerShell pour " + root + " (générée par argparse)")
    append(L, "$script:__valueOpts = @{")
    for n in ns:
        vals := []
        for a in options_of(n["parser"]):
            if _takes_value(a):
                for nm in a.names:
                    append(vals, nm)
        append(L, "    " + _ps(n["key"]) + " = " + _ps_list(vals))
    append(L, "}")
    append(L, "$script:__subMap = @{")
    for n in ns:
        for s in subcommands_of(n["parser"]):
            append(L, "    " + _ps(n["key"] + "|" + s[0]) + " = " + _ps(n["key"] + " " + s[1]))
    append(L, "}")
    append(L, "$script:__choices = @{")
    for n in ns:
        for a in options_of(n["parser"]):
            if not _takes_value(a):
                continue
            h := hint_of(a)
            for nm in a.names:
                if h["kind"] == "words":
                    append(L, "    " + _ps(n["key"] + "|" + nm) + " = " + _ps_list(h["words"]))
                elif h["kind"] == "file" or h["kind"] == "dir":
                    append(L, "    " + _ps(n["key"] + "|" + nm) + " = " + _ps("@" + h["kind"]))
    append(L, "}")
    append(L, "$script:__options = @{")
    for n in ns:
        pairs := []
        for a in options_of(n["parser"]):
            tip := a.help
            if tip == null:
                tip = a.names[0]
            for nm in a.names:
                append(pairs, [nm, tip])
        append(L, "    " + _ps(n["key"]) + " = " + _ps_entries(pairs))
    append(L, "}")
    append(L, "$script:__subs = @{")
    for n in ns:
        pairs2 := []
        for s in subcommands_of(n["parser"]):
            tip2 := s[2]
            if tip2 == "":
                tip2 = s[0]
            append(pairs2, [s[0], tip2])
        for a in positionals_of(n["parser"]):
            h := hint_of(a)
            if h["kind"] == "words":
                for w in h["words"]:
                    append(pairs2, [w, w])
        append(L, "    " + _ps(n["key"]) + " = " + _ps_entries(pairs2))
    append(L, "}")
    append(L, "Register-ArgumentCompleter -Native -CommandName " + _ps(root) + " -ScriptBlock {")
    append(L, "    param($wordToComplete, $commandAst, $cursorPosition)")
    append(L, "    $elements = @($commandAst.CommandElements | ForEach-Object { $_.ToString() })")
    append(L, "    $cmd = " + _ps(root))
    append(L, "    $limit = $elements.Count")
    append(L, "    if ($wordToComplete -ne '') { $limit = $elements.Count - 1 }")
    append(L, "    $i = 1")
    append(L, "    while ($i -lt $limit) {")
    append(L, "        $w = $elements[$i]")
    append(L, "        if ($script:__valueOpts.ContainsKey($cmd) -and ($script:__valueOpts[$cmd] -contains $w)) { $i += 2; continue }")
    append(L, "        $k = \"$cmd|$w\"")
    append(L, "        if ($script:__subMap.ContainsKey($k)) { $cmd = $script:__subMap[$k] }")
    append(L, "        $i++")
    append(L, "    }")
    append(L, "    $prev = ''")
    append(L, "    if ($limit -ge 1) { $prev = $elements[$limit - 1] }")
    append(L, "    if ($script:__valueOpts.ContainsKey($cmd) -and ($script:__valueOpts[$cmd] -contains $prev)) {")
    append(L, "        $ck = \"$cmd|$prev\"")
    append(L, "        if ($script:__choices.ContainsKey($ck)) {")
    append(L, "            $vals = $script:__choices[$ck]")
    append(L, "            if ($vals.Count -eq 1 -and $vals[0] -like '@*') { return }")
    append(L, "            $vals | Where-Object { $_ -like \"$wordToComplete*\" } | ForEach-Object {")
    append(L, "                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)")
    append(L, "            }")
    append(L, "        }")
    append(L, "        return")
    append(L, "    }")
    append(L, "    if ($wordToComplete -like '-*') { $cands = $script:__options[$cmd]; $kind = 'ParameterName' }")
    append(L, "    else { $cands = $script:__subs[$cmd]; $kind = 'ParameterValue' }")
    append(L, "    $cands | Where-Object { $_.N -like \"$wordToComplete*\" } | ForEach-Object {")
    append(L, "        [System.Management.Automation.CompletionResult]::new($_.N, $_.N, $kind, $_.T)")
    append(L, "    }")
    append(L, "}")
    return _t.lines_text(L) + "\n"

# ---------------------------------------------------------------------
# Point d'entrée
# ---------------------------------------------------------------------

func generate(parser, shell, prog):
    s := _t.lower(str(shell))
    if s == "bash":
        return bash(parser, prog)
    if s == "zsh":
        return zsh(parser, prog)
    if s == "powershell" or s == "pwsh":
        return powershell(parser, prog)
    raise("ArgumentError", "argparse.completion : shell inconnu '" + str(shell) + "' (bash, zsh, powershell)")
