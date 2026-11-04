# ALEX STANDARD LIBRARY — ui.view.wcode (interne)
#
# Éditeur de code (v.code_editor) : texte en lignes, police à chasse fixe, numéros de ligne, coloration
# syntaxique (ui.view.syntax), ligne courante, sélection (Maj+flèches, souris, double clic), presse-papiers,
# annuler / rétablir, indentation automatique, Tab / Maj+Tab (indenter / désindenter), commentaire (Ctrl+/),
# déplacement et duplication de lignes, crochets appariés, recherche (Ctrl+F, F3) et saut à une ligne
# (Ctrl+G), marques d'erreur dans la marge avec leur message en fin de ligne.
#
# Chaînes à triples guillemets (Python) et commentaires /* */ (Alex) sur plusieurs lignes : l'état « encore
# dans » est propagé d'une ligne à la suivante (cache invalidé à la première ligne modifiée).
# Pliage : un bloc (ligne suivie de lignes plus indentées) se replie sur son en-tête ; F4 bascule, Maj+F4 plie
# tout, Ctrl+F4 déplie tout, Ctrl+Maj+[ et Ctrl+Maj+] (fenêtre) plient / déplient ; ▾ / ▸ dans la marge.
# Complétion : mots-clés du langage et identifiants du texte ; s'ouvre en tapant (2 caractères) ou par
# Ctrl+Espace ; ↑ ↓ choisissent, Entrée ou Tab valident, Échap ferme. Paramètre completion=false pour la couper.
#
# Tab indente : pour quitter l'éditeur au clavier, Échap puis Tab.

from core use len, type, to_int
from collections use append, insert, pop, contains_key, keys, remove, sort
use string as _s
use os as _os
use ui.view.util as _u
use ui.view.wbase as _b
use ui.view.syntax as _syn
from ui.view.wbase use Widget

func _sl(t, a, b=null):
    if b == null:
        return _s.slice(t, a)
    return _s.slice(t, a, b)

func _before(a, b):
    return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1])

func _indent_of(line):
    k := 0
    while k < len(line) and line[k] == ' ':
        k += 1
    return k

func _is_word_char(c):
    o := _s.ord(c)
    return (o >= 97 and o <= 122) or (o >= 65 and o <= 90) or (o >= 48 and o <= 57) or o == 95 or o >= 192

const _OPEN := "([{"
const _CLOSE := ")]}"
const _COMP_ROWS := 8
_WORDS := {}

# ---------------------------------------------------------------- coloration sur plusieurs lignes
# st["syn"] : {"lang", "src" (lignes déjà passées), "starts" (état au début de chaque ligne, len(src) + 1)}.

func syn_refresh(st, lang):
    c := st["syn"]
    st["syn_dirty"] = false
    if c["lang"] != lang:
        c["lang"] = lang
        c["src"] = []
        c["starts"] = [""]
        return null
    lines := st["lines"]
    src := c["src"]
    d := 0
    m := _u.imin(len(src), len(lines))
    while d < m and src[d] == lines[d]:
        d += 1
    while len(src) > d:
        pop(src)
    while len(c["starts"]) > d + 1:
        pop(c["starts"])

# État (voir ui.view.syntax) au début de la ligne ln.
func syn_state(st, lang, ln):
    if lang != "python" and lang != "alex":
        return ""
    c := st["syn"]
    if c["lang"] != lang or st["syn_dirty"]:
        syn_refresh(st, lang)
    lines := st["lines"]
    starts := c["starts"]
    src := c["src"]
    while len(starts) <= ln:
        i := len(starts) - 1
        text := lines[i]
        prev := starts[i]
        nxt := prev
        if prev != "":
            nxt = _syn.tokens_from(text, lang, prev)[1]
        elif lang == "python":
            if _s.contains(text, "\"\"\"") or _s.contains(text, "'''"):
                nxt = _syn.tokens_from(text, lang, prev)[1]
        elif _s.contains(text, "/*"):
            nxt = _syn.tokens_from(text, lang, prev)[1]
        append(src, text)
        append(starts, nxt)
    return starts[ln]

# ---------------------------------------------------------------- pliage
# st["folds"] : {ligne d'en-tête: texte de l'en-tête} ; st["vis"] : lignes visibles (cache, null = à refaire) ;
# st["prev"] : copie des lignes à la dernière modification (pour recaler les blocs repliés).

func line_indent(line):
    k := _indent_of(line)
    if k >= len(line):
        return -1
    return k

# La ligne s ouvre-t-elle un bloc (la première ligne non vide qui suit est plus indentée) ?
func foldable(lines, s):
    base := line_indent(lines[s])
    if base < 0:
        return false
    k := s + 1
    while k < len(lines):
        ind := line_indent(lines[k])
        if ind >= 0:
            return ind > base
        k += 1
    return false

# Dernière ligne du bloc ouvert en s (lignes suivantes plus indentées, lignes vides finales exclues), ou -1.
func fold_end(lines, s):
    base := line_indent(lines[s])
    if base < 0:
        return -1
    last := -1
    k := s + 1
    while k < len(lines):
        ind := line_indent(lines[k])
        if ind >= 0:
            if ind <= base:
                break
            last = k
        k += 1
    return last

# Lignes visibles (indices croissants), ou null quand rien n'est replié.
func visible_lines(st):
    folds := st["folds"]
    if len(keys(folds)) == 0:
        return null
    v := st["vis"]
    if v != null:
        return v
    lines := st["lines"]
    n := len(lines)
    out := []
    i := 0
    while i < n:
        append(out, i)
        if contains_key(folds, i):
            e := fold_end(lines, i)
            if e > i:
                i = e + 1
                continue
        i += 1
    st["vis"] = out
    return out

# Rang, parmi les lignes visibles, de la plus grande ligne visible <= ln.
func vis_index(vis, ln):
    lo := 0
    hi := len(vis) - 1
    while lo < hi:
        mid := (lo + hi + 1) // 2
        if vis[mid] <= ln:
            lo = mid
        else:
            hi = mid - 1
    return lo

func vpos(st, ln):
    vis := visible_lines(st)
    if vis == null:
        return ln
    return vis_index(vis, ln)

func vline(st, vi):
    vis := visible_lines(st)
    if vis == null:
        return _u.clamp(vi, 0, len(st["lines"]) - 1)
    return vis[_u.clamp(vi, 0, len(vis) - 1)]

func vcount(st):
    vis := visible_lines(st)
    if vis == null:
        return len(st["lines"])
    return len(vis)

func is_hidden(st, ln):
    vis := visible_lines(st)
    if vis == null:
        return false
    return vis[vis_index(vis, ln)] != ln

# Le curseur et l'ancre d'une sélection ne restent jamais sur une ligne masquée (retour à l'en-tête).
func clamp_visible(st):
    vis := visible_lines(st)
    if vis == null:
        return null
    for name in ["cur", "anchor"]:
        p := st[name]
        if p != null:
            k := vis_index(vis, p[0])
            if vis[k] != p[0]:
                st[name] = [vis[k], len(st["lines"][vis[k]])]

func _folds_changed(st):
    st["vis"] = null
    st["prev"] = [x for x in st["lines"]] if len(keys(st["folds"])) > 0 else []
    st["top"] = vline(st, vpos(st, _b.st_get(st, "top", 0)))
    clamp_visible(st)

func fold_at(st, s):
    lines := st["lines"]
    if s < 0 or s >= len(lines) or contains_key(st["folds"], s):
        return false
    if fold_end(lines, s) <= s:
        return false
    st["folds"][s] = lines[s]
    _folds_changed(st)
    return true

func unfold_at(st, s):
    if not contains_key(st["folds"], s):
        return false
    remove(st["folds"], s)
    _folds_changed(st)
    return true

# Déplie les blocs repliés qui masquent la ligne ln.
func unfold_containing(st, ln):
    changed := false
    lines := st["lines"]
    for s in keys(st["folds"]):
        if s < ln and fold_end(lines, s) >= ln:
            remove(st["folds"], s)
            changed = true
    if changed:
        _folds_changed(st)
    return changed

# Déplie les blocs repliés qui touchent les lignes a..b (en-tête ou corps, une ligne de marge de chaque côté).
func unfold_near(st, a, b):
    changed := false
    lines := st["lines"]
    for s in keys(st["folds"]):
        e := fold_end(lines, s)
        if e < s:
            e = s
        if s <= b + 1 and e >= a - 1:
            remove(st["folds"], s)
            changed = true
    if changed:
        _folds_changed(st)
    return changed

# En-tête du bloc le plus proche contenant la ligne ln (ln elle-même si elle ouvre un bloc), ou -1.
func fold_header_for(st, ln):
    lines := st["lines"]
    if foldable(lines, ln):
        return ln
    ind := line_indent(lines[ln])
    k := ln - 1
    while k >= 0:
        ik := line_indent(lines[k])
        if ik >= 0 and (ind < 0 or ik < ind):
            if fold_end(lines, k) >= ln:
                return k
            ind = ik
        k -= 1
    return -1

# mode : "toggle", "fold" ou "unfold" ; agit sur le bloc de la ligne ln.
func fold_command(st, ln, mode):
    if contains_key(st["folds"], ln):
        if mode == "fold":
            return false
        return unfold_at(st, ln)
    if mode == "unfold":
        return false
    h := fold_header_for(st, ln)
    if h < 0 or contains_key(st["folds"], h):
        return false
    return fold_at(st, h)

func fold_all(st):
    lines := st["lines"]
    folds := {}
    i := 0
    while i < len(lines):
        if foldable(lines, i) and fold_end(lines, i) > i:
            folds[i] = lines[i]
        i += 1
    st["folds"] = folds
    _folds_changed(st)

func unfold_all(st):
    st["folds"] = {}
    _folds_changed(st)

# Après un déplacement : si pos tombe sur une ligne masquée, aller à la ligne visible suivante (forward) ou à
# l'en-tête du bloc.
func skip_hidden(st, pos, forward):
    vis := visible_lines(st)
    if vis == null:
        return pos
    k := vis_index(vis, pos[0])
    if vis[k] == pos[0]:
        return pos
    if forward and k + 1 < len(vis):
        return [vis[k + 1], 0]
    return [vis[k], len(st["lines"][vis[k]])]

# À appeler après toute modification du texte : invalide la coloration et recale les blocs repliés.
func after_edit(st):
    st["syn_dirty"] = true
    st["vis"] = null
    folds := st["folds"]
    if len(keys(folds)) == 0:
        return null
    lines := st["lines"]
    prev := st["prev"]
    old_n := len(prev)
    new_n := len(lines)
    delta := new_n - old_n
    d := 0
    m := _u.imin(old_n, new_n)
    while d < m and prev[d] == lines[d]:
        d += 1
    out := {}
    for s in keys(folds):
        header := folds[s]
        chosen := -1
        if s < d:
            if s < new_n and fold_end(lines, s) > s:
                chosen = s
        else:
            for cand in [s + delta, s]:
                if chosen < 0 and cand >= 0 and cand < new_n and lines[cand] == header and fold_end(lines, cand) > cand:
                    chosen = cand
            if chosen < 0 and delta == 0 and s < new_n and fold_end(lines, s) > s:
                chosen = s
        if chosen >= 0 and not contains_key(out, chosen):
            out[chosen] = lines[chosen]
    st["folds"] = out
    st["prev"] = [x for x in lines] if len(keys(out)) > 0 else []
    st["top"] = vline(st, vpos(st, _b.st_get(st, "top", 0)))
    clamp_visible(st)

# ---------------------------------------------------------------- complétion
func _is_digit_char(c):
    o := _s.ord(c)
    return o >= 48 and o <= 57

func _ident_start(line, c):
    k := c
    while k > 0 and _is_word_char(line[k - 1]):
        k -= 1
    return k

# Identifiants de line (2 caractères au moins, pas de chiffre en tête), sauf ceux qui chevauchent [skip_a, skip_b).
func _collect_words(line, d, skip_a, skip_b):
    n := len(line)
    i := 0
    while i < n:
        if _is_word_char(line[i]):
            j := i
            while j < n and _is_word_char(line[j]):
                j += 1
            if j - i >= 2 and not _is_digit_char(line[i]) and not (i < skip_b and j > skip_a):
                d[_sl(line, i, j)] = true
            i = j
        else:
            i += 1

# Identifiants du texte (rafraîchis au plus toutes les 2 s, sauf ceux de la ligne du curseur).
func buffer_words(st):
    now := _os.monotonic_time()
    c := st["words"]
    cur := st["cur"]
    if c["set"] == null or now - c["at"] > 2.0:
        d := {}
        lines := st["lines"]
        n := _u.imin(len(lines), 5000)
        i := 0
        while i < n:
            if i == cur[0]:
                _collect_words(lines[i], d, _ident_start(lines[i], cur[1]), cur[1])
            else:
                _collect_words(lines[i], d, 0, 0)
            i += 1
        c["set"] = d
        c["at"] = now
    out := {}
    for w in keys(c["set"]):
        out[w] = true
    line := st["lines"][cur[0]]
    _collect_words(line, out, _ident_start(line, cur[1]), cur[1])
    return out

func language_words(lang):
    if not contains_key(_WORDS, lang):
        _WORDS[lang] = _syn.words(lang)
    return _WORDS[lang]

# Propositions pour le préfixe prefix : celles qui respectent la casse d'abord, puis le reste ; ordre alphabétique.
func completion_items(st, lang, prefix, member):
    pl := len(prefix)
    lp := _s.lower(prefix)
    seen := {}
    exact := []
    loose := []
    pools := []
    if not member:
        pools = [language_words(lang), keys(buffer_words(st))]
    else:
        pools = [keys(buffer_words(st))]
    for pool in pools:
        for w in pool:
            if len(w) > pl and not contains_key(seen, w):
                if pl == 0:
                    seen[w] = true
                    append(exact, w)
                elif _s.starts_with(w, prefix):
                    seen[w] = true
                    append(exact, w)
                elif _s.starts_with(_s.lower(w), lp):
                    seen[w] = true
                    append(loose, w)
    sort(exact)
    sort(loose)
    out := exact
    for w in loose:
        append(out, w)
    if len(out) > 200:
        cut := []
        k := 0
        while k < 200:
            append(cut, out[k])
            k += 1
        out = cut
    return out

# Le caractère juste avant la colonne col est-il dans un commentaire ou une chaîne ?
func in_string_or_comment(st, lang, ln, col):
    if col <= 0 or lang == "text":
        return false
    line := st["lines"][ln]
    toks := _syn.tokens_from(line, lang, syn_state(st, lang, ln))[0]
    for t in toks:
        if t[0] <= col - 1 and col - 1 < t[1]:
            return t[2] == "syn_comment" or t[2] == "syn_string"
    return false

# Propositions d'un fournisseur externe (serveur de langage) : str ou dict {label, detail, insert, kind}.
func _provider_items(app, provider, st, prefix, member):
    cur := st["cur"]
    got := app.call(provider, [cur[0] + 1, cur[1] + 1, prefix, member])
    if got == null:
        return null
    labels := []
    details := []
    inserts := []
    lp := _s.lower(prefix)
    for it in got:
        if type(it) == "str":
            it = {"label": it}
        lab := str(it["label"])
        if prefix != "" and not _s.starts_with(_s.lower(lab), lp):
            continue
        append(labels, lab)
        append(details, str(it["detail"]) if contains_key(it, "detail") and it["detail"] != null else "")
        append(inserts, str(it["insert"]) if contains_key(it, "insert") and it["insert"] != null else lab)
        if len(labels) >= 300:
            break
    return [labels, details, inserts]

# Ouvre (ou met à jour) la liste de complétion au curseur ; manual : demandée au clavier (préfixe vide permis).
# provider (fonction (ligne, colonne, préfixe, membre) -> propositions) remplace les mots du tampon.
func comp_open(st, lang, manual, provider=null, app=null):
    st["comp"] = null
    cur := st["cur"]
    line := st["lines"][cur[0]]
    start := _ident_start(line, cur[1])
    prefix := _sl(line, start, cur[1])
    if prefix != "" and _is_digit_char(prefix[0]):
        return false
    if not manual:
        if len(prefix) < 2 or in_string_or_comment(st, lang, cur[0], start):
            return false
    member := start > 0 and line[start - 1] == '.'
    if provider != null and app != null:
        got := _provider_items(app, provider, st, prefix, member)
        if got != null:
            if len(got[0]) == 0:
                return false
            st["comp"] = {"items": got[0], "details": got[1], "inserts": got[2], "sel": 0, "top": 0, "start": start, "line": cur[0]}
            return true
    items := completion_items(st, lang, prefix, member)
    if len(items) == 0:
        return false
    st["comp"] = {"items": items, "sel": 0, "top": 0, "start": start, "line": cur[0]}
    return true

# Texte d'insertion d'un extrait (« ${1:nom} », « $0 ») : [texte sans marqueurs, position du 1er marqueur ou -1].
func expand_snippet(text):
    out := ""
    first := -1
    i := 0
    n := len(text)
    while i < n:
        c := text[i]
        if c == '$' and i + 1 < n and text[i + 1] == '{':
            j := i + 2
            while j < n and text[j] != ':' and text[j] != '}':
                j += 1
            if first < 0:
                first = len(out)
            if j < n and text[j] == ':':
                k := j + 1
                while k < n and text[k] != '}':
                    out = out + str(text[k])
                    k += 1
                i = k + 1
            else:
                i = j + 1
            continue
        if c == '$' and i + 1 < n and _is_digit_char(text[i + 1]):
            if first < 0:
                first = len(out)
            i += 2
            continue
        out = out + str(c)
        i += 1
    return [out, first]

# Remplace le préfixe par la proposition choisie.
func comp_accept(st):
    c := st["comp"]
    st["comp"] = null
    if c == null:
        return false
    cur := st["cur"]
    if c["line"] != cur[0] or c["start"] > cur[1]:
        return false
    item := c["items"][c["sel"]]
    caret := -1
    if contains_key(c, "inserts"):
        ex := expand_snippet(c["inserts"][c["sel"]])
        item = ex[0]
        caret = ex[1]
    push_undo(st, "complete")
    if _s.contains(item, "\n"):
        # extrait sur plusieurs lignes : indenté comme la ligne courante
        ind := _indent_of(st["lines"][cur[0]])
        parts := _s.split(item, "\n")
        text := parts[0]
        k := 1
        while k < len(parts):
            text = text + "\n" + ind + parts[k]
            k += 1
        base_line := cur[0]
        st["cur"] = [cur[0], c["start"]]
        st["anchor"] = [cur[0], cur[1]]
        delete_selection(st)
        insert_text(st, text)
        if caret >= 0:
            # position du marqueur : lignes de l'extrait avant lui (les suivantes sont indentées de ind)
            pre := _s.split(_sl(item, 0, caret), "\n")
            if len(pre) == 1:
                st["cur"] = [base_line, c["start"] + len(pre[0])]
            else:
                st["cur"] = [base_line + len(pre) - 1, len(ind) + len(pre[len(pre) - 1])]
        st["anchor"] = null
        return true
    lines := st["lines"]
    line := lines[cur[0]]
    lines[cur[0]] = _sl(line, 0, c["start"]) + item + _sl(line, cur[1])
    st["cur"] = [cur[0], c["start"] + (caret if caret >= 0 else len(item))]
    st["anchor"] = null
    return true

# ---------------------------------------------------------------- modèle (état du composant)
# st : lines (list de str), cur [ligne, colonne], anchor (début de sélection ou null), top, left (défilement),
# undo / redo (instantanés), find {open, mode, text, origin}.

func sync(n):
    st := n.st
    value := str(n.get("value", ""))
    if not contains_key(st, "lines"):
        st["__seen"] = value
        st["__own"] = null
        st["lines"] = _s.split(value, "\n")
        if len(st["lines"]) == 0:
            st["lines"] = [""]
        st["cur"] = [0, 0]
        st["anchor"] = null
        st["top"] = 0
        st["left"] = 0
        st["undo"] = []
        st["redo"] = []
        st["find"] = {"open": false, "mode": "find", "text": "", "origin": [0, 0]}
        st["last_edit"] = ["", 0.0, -1]
        st["esc"] = false
        st["folds"] = {}
        st["vis"] = null
        st["prev"] = []
        st["syn"] = {"lang": null, "src": [], "starts": [""]}
        st["syn_dirty"] = false
        st["comp"] = null
        st["words"] = {"at": 0.0, "set": null}
    elif value != st["__seen"]:
        # nouvelle valeur du programme : l'écho de nos propres modifications, ou un autre texte
        st["__seen"] = value
        if value != st["__own"]:
            st["lines"] = _s.split(value, "\n")
            if len(st["lines"]) == 0:
                st["lines"] = [""]
            st["undo"] = []
            st["redo"] = []
            st["anchor"] = null
            st["folds"] = {}
            st["vis"] = null
            st["prev"] = []
            st["syn_dirty"] = true
            st["comp"] = null
            st["words"] = {"at": 0.0, "set": null}
            clamp_cursor(st)
    return st

func clamp_cursor(st):
    lines := st["lines"]
    l := _u.clamp(st["cur"][0], 0, len(lines) - 1)
    st["cur"] = [l, _u.clamp(st["cur"][1], 0, len(lines[l]))]
    a := st["anchor"]
    if a != null:
        al := _u.clamp(a[0], 0, len(lines) - 1)
        st["anchor"] = [al, _u.clamp(a[1], 0, len(lines[al]))]

func text_of_st(st):
    return _s.join("\n", st["lines"])

func selection(st):
    a := st["anchor"]
    if a == null:
        return null
    c := st["cur"]
    if a[0] == c[0] and a[1] == c[1]:
        return null
    if _before(a, c):
        return [a, c]
    return [c, a]

func selected_text(st):
    r := selection(st)
    if r == null:
        return ""
    return range_text(st, r[0], r[1])

func range_text(st, a, b):
    lines := st["lines"]
    if a[0] == b[0]:
        return _sl(lines[a[0]], a[1], b[1])
    parts := [_sl(lines[a[0]], a[1])]
    l := a[0] + 1
    while l < b[0]:
        append(parts, lines[l])
        l += 1
    append(parts, _sl(lines[b[0]], 0, b[1]))
    return _s.join("\n", parts)

func snapshot(st):
    return {"lines": [x for x in st["lines"]], "cur": [st["cur"][0], st["cur"][1]], "anchor": st["anchor"]}

# Mémorise l'état avant une modification ; kind « type » regroupe la frappe continue sur une ligne.
func push_undo(st, kind):
    now := _os.monotonic_time()
    last := st["last_edit"]
    if kind == "type" and last[0] == "type" and now - last[1] < 1.0 and last[2] == st["cur"][0]:
        st["last_edit"] = [kind, now, st["cur"][0]]
        return null
    append(st["undo"], snapshot(st))
    if len(st["undo"]) > 300:
        pop(st["undo"], 0)
    st["redo"] = []
    st["last_edit"] = [kind, now, st["cur"][0]]

func restore(st, snap):
    st["lines"] = snap["lines"]
    st["cur"] = snap["cur"]
    st["anchor"] = snap["anchor"]

func delete_range(st, a, b):
    lines := st["lines"]
    if a[0] == b[0]:
        line := lines[a[0]]
        lines[a[0]] = _sl(line, 0, a[1]) + _sl(line, b[1])
    else:
        lines[a[0]] = _sl(lines[a[0]], 0, a[1]) + _sl(lines[b[0]], b[1])
        k := b[0] - a[0]
        while k > 0:
            pop(lines, a[0] + 1)
            k -= 1
    st["cur"] = [a[0], a[1]]
    st["anchor"] = null

func delete_selection(st):
    r := selection(st)
    if r == null:
        st["anchor"] = null
        return false
    delete_range(st, r[0], r[1])
    return true

func insert_text(st, text):
    delete_selection(st)
    lines := st["lines"]
    l := st["cur"][0]
    c := st["cur"][1]
    line := lines[l]
    before := _sl(line, 0, c)
    after := _sl(line, c)
    parts := _s.split(text, "\n")
    if len(parts) == 1:
        lines[l] = before + text + after
        st["cur"] = [l, c + len(text)]
        return null
    lines[l] = before + parts[0]
    k := 1
    while k < len(parts) - 1:
        insert(lines, l + k, parts[k])
        k += 1
    last := parts[len(parts) - 1]
    insert(lines, l + len(parts) - 1, last + after)
    st["cur"] = [l + len(parts) - 1, len(last)]

func _clean(text):
    out := _s.replace(_s.replace(text, "\r\n", "\n"), "\r", "\n")
    return _s.replace(out, "\t", "    ")

# Lignes touchées par la sélection (ou la ligne du curseur) : [première, dernière].
func line_span(st):
    r := selection(st)
    if r == null:
        return [st["cur"][0], st["cur"][0]]
    last := r[1][0]
    if r[1][1] == 0 and last > r[0][0]:
        last -= 1
    return [r[0][0], last]

func find_in(line, q, start):
    if start > len(line):
        return -1
    k := _s.find(_s.lower(_sl(line, start)), _s.lower(q))
    if k < 0:
        return -1
    return start + k

func find_from(st, q, pos, forward=true):
    lines := st["lines"]
    n := len(lines)
    if q == "" or n == 0:
        return null
    if forward:
        i := 0
        while i <= n:
            l := (pos[0] + i) % n
            start := pos[1] if i == 0 else 0
            k := find_in(lines[l], q, start)
            if k >= 0:
                return [l, k]
            i += 1
        return null
    i := 0
    while i <= n:
        l := (pos[0] - i + n) % n
        line := lines[l]
        limit := pos[1] if i == 0 else len(line) + 1
        best := -1
        k := find_in(line, q, 0)
        while k >= 0 and k < limit:
            best = k
            k = find_in(line, q, k + 1)
        if best >= 0:
            return [l, best]
        i += 1
    return null

func count_matches(st, q):
    if q == "":
        return 0
    total := 0
    for line in st["lines"]:
        k := find_in(line, q, 0)
        while k >= 0:
            total += 1
            k = find_in(line, q, k + len(q))
    return total

# Position du crochet apparié à celui sous / avant le curseur, ou null : [[l, c], [l2, c2]].
func bracket_pair(st):
    lines := st["lines"]
    cur := st["cur"]
    line := lines[cur[0]]
    for c in [cur[1], cur[1] - 1]:
        if c >= 0 and c < len(line):
            ch := str(line[c])
            oi := _s.find(_OPEN, ch)
            ci := _s.find(_CLOSE, ch)
            if oi >= 0:
                m := _scan(lines, [cur[0], c], ch, str(_CLOSE[oi]), 1)
                if m != null:
                    return [[cur[0], c], m]
            if ci >= 0:
                m := _scan(lines, [cur[0], c], ch, str(_OPEN[ci]), -1)
                if m != null:
                    return [[cur[0], c], m]
    return null

func _scan(lines, pos, me, other, step):
    depth := 0
    l := pos[0]
    c := pos[1]
    budget := 20000
    while budget > 0 and l >= 0 and l < len(lines):
        line := lines[l]
        while c >= 0 and c < len(line):
            ch := str(line[c])
            if ch == me:
                depth += 1
            elif ch == other:
                depth -= 1
                if depth == 0:
                    return [l, c]
            c += step
            budget -= 1
        l += step
        if l >= 0 and l < len(lines):
            c = 0 if step > 0 else len(lines[l]) - 1
    return null

# ---------------------------------------------------------------- composant
class CodeEditor extends Widget:
    func init():
        super.init()
        self.stretch_w = true
        self.stretch_h = true
        self.grow = 1

    func focusable(app, n):
        return true

    func _cw(app):
        return app.s.text_width("M", "mono")

    func _lh(app):
        return app.s.line_height("mono")

    func width_for(app, n, chars):
        return chars * self._cw(app) + self._gutter(app, n, 999) + 2 * app.s.lb + app.s.sbw + 2

    func height_for(app, n, lines):
        return lines * self._lh(app) + 2 * app.s.lb + 2 * self._pad_y(app)

    func measure(app, n, max_w):
        return [self.width_for(app, n, 60), self.height_for(app, n, 15)]

    func _pad_y(app):
        return 0 if app.s.cell else 4

    func _gutter(app, n, count):
        bp := self._bpw(app, n)
        if not n.get("line_numbers", true):
            return bp + (0 if app.s.cell else 6)
        digits := len(str(_u.imax(count, 99)))
        return bp + (digits + 2) * self._cw(app)

    # Colonne des points d'arrêt (si la propriété breakpoints est donnée).
    func _bpw(app, n):
        if n.get("breakpoints", null) == null and n.get("exec_line", null) == null:
            return 0
        return 2 if app.s.cell else 2 * self._cw(app) + 2

    # Zone du texte [x, y, largeur, hauteur], nombre de lignes visibles, marge.
    func _geom(app, n, st):
        s := app.s
        lh := self._lh(app)
        gw := self._gutter(app, n, len(st["lines"]))
        fb := lh if st["find"]["open"] else 0
        x := n.x + s.lb + gw
        y := n.y + s.lb + self._pad_y(app)
        h := _u.imax(0, n.h - 2 * s.lb - 2 * self._pad_y(app) - fb)
        w := _u.imax(0, n.w - 2 * s.lb - gw - s.sbw)
        rows := _u.imax(1, h // lh)
        return [x, y, w, h, rows, gw]

    func _cursor_changed(app, n, st):
        c := st["cur"]
        key := str(c[0]) + ":" + str(c[1])
        if _b.st_get(st, "__cur_sent", "") != key:
            st["__cur_sent"] = key
            app.call(n.get("on_cursor"), [c[0] + 1, c[1] + 1])

    func _emit(app, n, st):
        after_edit(st)
        text := text_of_st(st)
        st["__own"] = text
        app.call(n.get("on_change"), [text])

    # Garde le curseur visible (défilement vertical et horizontal).
    func _reveal(app, n, st):
        g := self._geom(app, n, st)
        rows := g[4]
        cur := st["cur"]
        vtop := _b.keep_visible(vpos(st, _b.st_get(st, "top", 0)), vpos(st, cur[0]), rows)
        st["top"] = vline(st, _u.clamp(vtop, 0, _u.imax(0, vcount(st) - 1)))
        line := st["lines"][cur[0]]
        left := _b.st_get(st, "left", 0)
        if cur[1] < left:
            left = _u.imax(0, cur[1] - 4)
        s := app.s
        while left < cur[1] and s.text_width(_sl(line, left, cur[1]), "mono") > g[2] - 2 * self._cw(app):
            left += 1
        st["left"] = left

    # Fenêtre de complétion [x, y, largeur, hauteur, nombre de lignes], ou null.
    func _comp_rect(app, n, st):
        comp := st["comp"]
        if comp == null:
            return null
        g := self._geom(app, n, st)
        s := app.s
        lh := self._lh(app)
        cw := self._cw(app)
        cur := st["cur"]
        row := vpos(st, cur[0]) - vpos(st, _b.st_get(st, "top", 0))
        if row < 0 or row >= g[4]:
            return null
        count := _u.imin(len(comp["items"]), _COMP_ROWS)
        widest := 0
        k := 0
        for it in comp["items"]:
            wd := len(it)
            if contains_key(comp, "details") and comp["details"][k] != "":
                wd = wd + 3 + _u.imin(len(comp["details"][k]), 36)
            widest = _u.imax(widest, wd)
            k += 1
        pw := (_u.imin(widest, 72) + 2) * cw
        ph := count * lh
        left := _b.st_get(st, "left", 0)
        px := g[0] + self._x_of(app, st["lines"][cur[0]], left, comp["start"]) - cw
        limit := n.x + n.w - s.lb - s.sbw
        if px + pw > limit:
            px = limit - pw
        if px < n.x + s.lb:
            px = n.x + s.lb
        py := g[1] + (row + 1) * lh
        if py + ph > n.y + n.h - s.lb:
            py = g[1] + row * lh - ph
        if py < n.y:
            py = n.y
        return [px, py, pw, ph, count]

    func _paint_comp(app, n, st):
        r := self._comp_rect(app, n, st)
        if r == null:
            return null
        s := app.s
        comp := st["comp"]
        lh := self._lh(app)
        cw := self._cw(app)
        comp["top"] = _b.keep_visible(comp["top"], comp["sel"], r[4])
        s.fill(r[0], r[1], r[2], r[3], "surface")
        k := 0
        while k < r[4]:
            idx := comp["top"] + k
            y := r[1] + k * lh
            if idx == comp["sel"]:
                s.fill(r[0], y, r[2], lh, "selection_focus")
            role := "selection_focus_text" if idx == comp["sel"] else "text"
            s.text(r[0] + cw, y, _u.fit(s, comp["items"][idx], r[2] - 2 * cw), role, "mono")
            if contains_key(comp, "details") and comp["details"][idx] != "":
                d := comp["details"][idx]
                lw := s.text_width(comp["items"][idx], "mono") + 3 * cw
                if lw < r[2] - 6 * cw:
                    d = _u.fit(s, d, r[2] - lw - cw)
                    s.text(r[0] + r[2] - cw - s.text_width(d, "mono"), y, d, role if idx == comp["sel"] else "muted", "mono")
            k += 1
        if not s.cell:
            s.frame(r[0], r[1], r[2], r[3], "border", 0, false)

    func arrange(app, n):
        st := sync(n)
        g := n.get("goto", null)
        if g != null and _b.st_get(st, "__goto", null) != g[2]:
            # aller à [ligne, colonne, jeton] (1-based) : centré, sélection effacée
            st["__goto"] = g[2]
            l := _u.clamp(g[0] - 1, 0, len(st["lines"]) - 1)
            st["cur"] = [l, _u.clamp(g[1] - 1, 0, len(st["lines"][l]))]
            st["anchor"] = null
            st["comp"] = null
            unfold_containing(st, l)
            clamp_visible(st)
            rows := self._geom(app, n, st)[4]
            st["top"] = vline(st, _u.clamp(vpos(st, l) - rows // 3, 0, _u.imax(0, vcount(st) - 1)))
            self._cursor_changed(app, n, st)
            return null
        e := n.get("exec_line", null)
        if e != null and _b.st_get(st, "__exec", null) != e:
            # ligne d'exécution du débogueur : la rendre visible
            st["__exec"] = e
            l := _u.clamp(e - 1, 0, len(st["lines"]) - 1)
            unfold_containing(st, l)
            clamp_visible(st)
            rows := self._geom(app, n, st)[4]
            vt := vpos(st, _b.st_get(st, "top", 0))
            if vpos(st, l) < vt or vpos(st, l) >= vt + rows:
                st["top"] = vline(st, _u.clamp(vpos(st, l) - rows // 3, 0, _u.imax(0, vcount(st) - 1)))
            return null
        if app.is_focused(n):
            self._reveal(app, n, st)

    func _paint_bp(app, x, y, w, lh, bp, here):
        s := app.s
        if s.cell:
            if here:
                s.text(x, y, "▶", "exec_arrow")
            elif bp != null:
                mark := "●"
                if _b.st_get(bp, "log", null) != null:
                    mark = "◆"
                elif _b.st_get(bp, "enabled", true) == false:
                    mark = "○"
                s.text(x, y, mark, "breakpoint")
            return null
        cx := x + w / 2
        cy := y + lh / 2
        r := _u.imin(w, lh) / 2 - 3
        if bp != null:
            enabled := _b.st_get(bp, "enabled", true) != false
            if _b.st_get(bp, "log", null) != null:
                s.fill(cx - r * 0.75, cy - r * 0.75, r * 1.5, r * 1.5, "breakpoint", 2)
            elif not enabled:
                s.circle(cx, cy, r, "breakpoint", false, 1.5)
            else:
                s.circle(cx, cy, r, "breakpoint", true)
                if _b.st_get(bp, "condition", null) != null or _b.st_get(bp, "hit", null) != null:
                    s.fill(cx - r * 0.5, cy - 1, r, 2, "code_bg")
        if here:
            # flèche d'exécution
            s.line(x + 2, cy, x + w - 3, cy, "exec_arrow", 2.5)
            s.line(x + w - 7, cy - 4, x + w - 3, cy, "exec_arrow", 2.5)
            s.line(x + w - 7, cy + 4, x + w - 3, cy, "exec_arrow", 2.5)

    func _squiggle(s, xa, xb, y, role, dotted):
        x := xa
        up := true
        while x < xb:
            nx := _u.imin(xb, x + 3)
            if dotted:
                s.line(x, y + 1, nx - 1, y + 1, role, 1.0)
                x = nx + 2
                continue
            s.line(x, y + (0 if up else 2), nx, y + (2 if up else 0), role, 1.0)
            up = not up
            x = nx

    # Bulle de survol : demandée à on_hover(ligne, colonne) après 0,45 s d'immobilité de la souris.
    func _paint_hover(app, n, st, g):
        hp := _b.st_get(st, "hover_pos", null)
        if hp == null or n.get("on_hover", null) == null or not app.is_hovered(n) or st["comp"] != null:
            return null
        if app.now - st["hover_t"] < 0.45:
            return null
        if not st["hover_asked"]:
            st["hover_asked"] = true
            st["hover_text"] = app.call(n.get("on_hover"), [hp[0] + 1, hp[1] + 1])
        text := st["hover_text"]
        if text == null or text == "":
            return null
        s := app.s
        lh := self._lh(app)
        cw := self._cw(app)
        rows := []
        code := false
        for raw in _s.split(str(text), "\n"):
            if _s.starts_with(_s.trim(raw), "```"):
                code = not code
                continue
            line := raw
            # retour à la ligne des longues lignes
            while len(line) > 90:
                append(rows, [_sl(line, 0, 90), code])
                line = _sl(line, 90)
            append(rows, [line, code])
            if len(rows) >= 14:
                break
        while len(rows) > 0 and _s.trim(rows[len(rows) - 1][0]) == "":
            pop(rows)
        if len(rows) == 0:
            return null
        widest := 0
        for r in rows:
            widest = _u.imax(widest, s.text_width(r[0], "mono" if r[1] else "normal"))
        pad := 0 if s.cell else 8
        bw := _u.imin(widest + 2 * pad + 2, n.w - 2 * s.lb)
        bh := len(rows) * lh + 2 * pad
        vrow := vpos(st, hp[0]) - vpos(st, _b.st_get(st, "top", 0))
        line := st["lines"][hp[0]]
        bx := g[0] + self._x_of(app, line, _b.st_get(st, "left", 0), hp[1])
        by := g[1] + (vrow + 1) * lh + 2
        if by + bh > n.y + n.h:
            by = g[1] + vrow * lh - bh - 2
        if bx + bw > n.x + n.w - s.lb:
            bx = n.x + n.w - s.lb - bw
        if bx < n.x + s.lb:
            bx = n.x + s.lb
        if not s.cell:
            s.shadow(bx, by, bw, bh)
        s.fill(bx, by, bw, bh, "tooltip", 0 if s.cell else 6)
        if not s.cell:
            s.frame(bx, by, bw, bh, "border", 6, false)
        k := 0
        for r in rows:
            s.text(bx + pad + 1, by + pad + k * lh, _u.fit(s, r[0], bw - 2 * pad), "syn_function" if r[1] else "text", "mono" if r[1] else "normal")
            k += 1

    func _x_of(app, line, left, col):
        if col <= left:
            return 0
        return app.s.text_width(_sl(line, left, col), "mono")

    func paint(app, n):
        s := app.s
        st := sync(n)
        focused := app.is_focused(n)
        lang := n.get("language", "alex")
        g := self._geom(app, n, st)
        x0 := g[0]
        y0 := g[1]
        tw := g[2]
        rows := g[4]
        gw := g[5]
        lh := self._lh(app)
        cw := self._cw(app)
        lines := st["lines"]
        top := _u.clamp(_b.st_get(st, "top", 0), 0, _u.imax(0, len(lines) - 1))
        vtop := vpos(st, top)
        top = vline(st, vtop)
        st["top"] = top
        vis := visible_lines(st)
        total := vcount(st)
        left := _b.st_get(st, "left", 0)
        bordure := n.get("border", true)
        s.fill(n.x, n.y, n.w, n.h, "code_bg", s.radius if bordure else 0)
        if gw > 0:
            s.fill(n.x + s.lb, n.y + s.lb, gw, n.h - 2 * s.lb, "gutter", 0)
        markers := {}
        squiggles := {}
        for m in n.get("markers", []):
            ln := m["line"] if contains_key(m, "line") else 0
            kind := _b.st_get(m, "kind", "error")
            if contains_key(m, "col") and m["col"] != null:
                if not contains_key(squiggles, ln - 1):
                    squiggles[ln - 1] = []
                append(squiggles[ln - 1], m)
            if kind == "hint" or kind == "info":
                continue
            # une marque par ligne : l'erreur l'emporte sur l'avertissement
            if not contains_key(markers, ln - 1) or (kind == "error" and _b.st_get(markers[ln - 1], "kind", "error") != "error"):
                markers[ln - 1] = m
        bpw := self._bpw(app, n)
        bps := {}
        if n.get("breakpoints", null) != null:
            for b in n.get("breakpoints", []):
                if type(b) == "int":
                    bps[b - 1] = {"line": b}
                else:
                    bps[b["line"] - 1] = b
        exec_ln := n.get("exec_line", null)
        if exec_ln != null:
            exec_ln = exec_ln - 1
        hl := {}
        for h in n.get("highlights", []):
            if not contains_key(hl, h[0] - 1):
                hl[h[0] - 1] = []
            append(hl[h[0] - 1], h)
        sel := selection(st)
        q := st["find"]["text"] if st["find"]["open"] and st["find"]["mode"] == "find" else ""
        pair := bracket_pair(st) if focused else null
        cur := st["cur"]
        i := 0
        while i < rows and vtop + i < total:
            ln := vtop + i if vis == null else vis[vtop + i]
            line := lines[ln]
            y := y0 + i * lh
            folded_end := -1
            hidden_error := false
            if vis != null and contains_key(st["folds"], ln):
                folded_end = fold_end(lines, ln)
                for mk in keys(markers):
                    if mk > ln and mk <= folded_end:
                        hidden_error = true
            # fond de ligne : exécution (débogueur), erreur, ligne courante
            if ln == exec_ln:
                s.fill(x0 - 2 if not s.cell else x0, y, tw + 2, lh, "exec_line")
            elif hidden_error:
                s.fill(x0 - 2 if not s.cell else x0, y, tw + 2, lh, "error_line")
            elif contains_key(markers, ln):
                kind := _b.st_get(markers[ln], "kind", "error")
                s.fill(x0 - 2 if not s.cell else x0, y, tw + 2, lh, "warning_line" if kind == "warning" else "error_line")
            elif ln == cur[0] and sel == null:
                s.fill(x0 - 2 if not s.cell else x0, y, tw + 2, lh, "line_highlight")
            # numéro de ligne
            if n.get("line_numbers", true):
                num := str(ln + 1)
                role := "gutter_current" if ln == cur[0] else "gutter_text"
                if contains_key(markers, ln):
                    role = "warning" if _b.st_get(markers[ln], "kind", "error") == "warning" else "danger"
                s.text(n.x + s.lb + gw - cw - s.text_width(num, "mono"), y, num, role, "mono")
                if contains_key(st["folds"], ln):
                    s.text(n.x + s.lb + bpw, y, "▸", "gutter_current", "mono")
                elif foldable(lines, ln):
                    s.text(n.x + s.lb + bpw, y, "▾", "gutter_text", "mono")
            # point d'arrêt, flèche d'exécution
            if bpw > 0:
                self._paint_bp(app, n.x + s.lb, y, bpw, lh, bps[ln] if contains_key(bps, ln) else null, ln == exec_ln)
            s.push_clip(x0, y, tw, lh)
            # sélection
            if sel != null and ln >= sel[0][0] and ln <= sel[1][0]:
                a := sel[0][1] if ln == sel[0][0] else 0
                b := sel[1][1] if ln == sel[1][0] else len(line)
                xa := self._x_of(app, line, left, a)
                xb := self._x_of(app, line, left, b)
                if ln != sel[1][0]:
                    xb += cw // 2 if not s.cell else 1
                if xb > xa:
                    s.fill(x0 + xa, y, xb - xa, lh, "selection")
            # occurrences du symbole sous le curseur (fournies par le programme)
            if contains_key(hl, ln):
                for h in hl[ln]:
                    xa := self._x_of(app, line, left, h[1] - 1)
                    xb := self._x_of(app, line, left, h[2] - 1)
                    if xb > xa:
                        s.fill(x0 + xa, y, xb - xa, lh, "word_highlight")
            # résultats de la recherche
            if q != "":
                k := find_in(line, q, 0)
                while k >= 0:
                    xa := self._x_of(app, line, left, k)
                    xb := self._x_of(app, line, left, k + len(q))
                    if xb > xa:
                        s.fill(x0 + xa, y, xb - xa, lh, "match")
                    k = find_in(line, q, k + len(q))
            # crochets appariés
            if pair != null:
                for p in pair:
                    if p[0] == ln and p[1] >= left:
                        xa := self._x_of(app, line, left, p[1])
                        s.fill(x0 + xa, y, s.text_width(str(line[p[1]]), "mono"), lh, "bracket")
            # texte coloré
            visible_end := left + _u.fit_count(s, _sl(line, left), tw) + 1
            for t in _syn.tokens_from(line, lang, syn_state(st, lang, ln))[0]:
                a := _u.imax(t[0], left)
                b := _u.imin(t[1], visible_end)
                if b > a:
                    role := t[2]
                    if sel != null and ln >= sel[0][0] and ln <= sel[1][0] and s.cell:
                        role = t[2]
                    s.text(x0 + self._x_of(app, line, left, a), y, _sl(line, a, b), role, "mono")
            # soulignement ondulé des diagnostics à colonnes
            if contains_key(squiggles, ln) and not s.cell:
                for m in squiggles[ln]:
                    ca := _u.imax(0, m["col"] - 1)
                    cb := len(line)
                    if contains_key(m, "end_col") and m["end_col"] != null and m["end_col"] - 1 > ca:
                        cb = m["end_col"] - 1
                    if cb <= ca:
                        cb = ca + 1
                    xa := self._x_of(app, line, left, ca)
                    xb := _u.imax(xa + cw, self._x_of(app, line, left, cb))
                    kind := _b.st_get(m, "kind", "error")
                    role := "squiggle_error"
                    if kind == "warning":
                        role = "squiggle_warning"
                    elif kind == "info" or kind == "hint":
                        role = "squiggle_info"
                    self._squiggle(s, x0 + xa, x0 + xb, y + lh - 3, role, kind == "hint")
            # bloc replié : nombre de lignes masquées
            fold_x := 0
            if folded_end > ln:
                label := "… " + str(folded_end - ln) + (" ligne" if folded_end - ln == 1 else " lignes")
                fx0 := self._x_of(app, line, left, len(line)) + 2 * cw
                if fx0 < tw - cw:
                    s.text(x0 + fx0, y, _u.fit(s, label, tw - fx0), "muted", "mono")
                fold_x = (len(label) + 2) * cw
            # message d'erreur en fin de ligne
            if contains_key(markers, ln):
                msg := str(_b.st_get(markers[ln], "message", ""))
                end_x := self._x_of(app, line, left, len(line)) + 3 * cw + fold_x
                if msg != "" and end_x < tw - 4 * cw:
                    kind := _b.st_get(markers[ln], "kind", "error")
                    s.text(x0 + end_x, y, _u.fit(s, "◂ " + msg, tw - end_x), "warning" if kind == "warning" else "danger", "mono")
            s.pop_clip()
            if focused and ln == cur[0] and cur[1] >= left and not st["find"]["open"]:
                s.caret(x0 + self._x_of(app, line, left, cur[1]), y)
            i += 1
        # bulle d'information (survol)
        self._paint_hover(app, n, st, g)
        # barre de défilement
        if total > rows:
            s.scrollbar(n.x + n.w - s.lb - s.sbw, y0, rows * lh, vtop / total, rows / total)
        # liste de complétion
        if focused and st["comp"] != null:
            self._paint_comp(app, n, st)
        # barre de recherche
        if st["find"]["open"]:
            f := st["find"]
            fy := n.y + n.h - s.lb - lh - self._pad_y(app)
            s.fill(n.x + s.lb, fy, n.w - 2 * s.lb, lh + self._pad_y(app), "surface")
            label := "Rechercher : " if f["mode"] == "find" else "Aller à la ligne : "
            s.text(n.x + s.lb + cw, fy, label, "muted", "mono")
            fx := n.x + s.lb + cw + s.text_width(label, "mono")
            s.text(fx, fy, f["text"], "text", "mono")
            if focused:
                s.caret(fx + s.text_width(f["text"], "mono"), fy)
            if f["mode"] == "find" and f["text"] != "":
                info := str(count_matches(st, f["text"])) + " résultat(s)"
                s.text(n.x + n.w - s.lb - s.sbw - cw - s.text_width(info, "mono"), fy, info, "muted", "mono")
        if not s.cell and bordure:
            s.frame(n.x, n.y, n.w, n.h, "accent" if focused else "border", s.radius, focused)

    # ------------------------------------------------------------ clavier
    func _move(st, pos, extend):
        if extend:
            if st["anchor"] == null:
                st["anchor"] = [st["cur"][0], st["cur"][1]]
        else:
            st["anchor"] = null
        st["cur"] = pos

    # Le curseur ne reste pas sur une ligne masquée : déplier le bloc qui la cache (recherche, aller à la ligne).
    func _fix_hidden(st):
        if len(keys(st["folds"])) > 0 and is_hidden(st, st["cur"][0]):
            unfold_containing(st, st["cur"][0])
        clamp_visible(st)

    func _word_left(line, c):
        k := c
        while k > 0 and not _is_word_char(line[k - 1]):
            k -= 1
        while k > 0 and _is_word_char(line[k - 1]):
            k -= 1
        return k

    func _word_right(line, c):
        k := c
        n := len(line)
        while k < n and not _is_word_char(line[k]):
            k += 1
        while k < n and _is_word_char(line[k]):
            k += 1
        return k

    func _find_key(app, n, st, ev, k):
        f := st["find"]
        if k == "escape":
            f["open"] = false
            return true
        if k == "enter" or k == "f3" or k == "shift+enter" or k == "shift+f3":
            if f["mode"] == "goto":
                num := _b.st_get(st, "__dummy", null)
                txt := _s.trim(f["text"])
                ok := txt != ""
                for c in txt:
                    if c < '0' or c > '9':
                        ok = false
                if ok:
                    l := _u.clamp(to_int(txt) - 1, 0, len(st["lines"]) - 1)
                    st["cur"] = [l, _indent_of(st["lines"][l])]
                    st["anchor"] = null
                f["open"] = false
                return true
            forward := not (k == "shift+enter" or k == "shift+f3")
            start := st["cur"]
            if not forward and st["anchor"] != null and _before(st["anchor"], st["cur"]):
                start = st["anchor"]
            m := find_from(st, f["text"], start, forward)
            if m != null:
                st["anchor"] = m
                st["cur"] = [m[0], m[1] + len(f["text"])]
            return true
        if k == "backspace":
            f["text"] = _sl(f["text"], 0, _u.imax(0, len(f["text"]) - 1))
        elif ev["type"] == "paste":
            f["text"] = f["text"] + _s.replace(ev["text"], "\n", " ")
        elif k == "space":
            f["text"] = f["text"] + " "
        elif ev["type"] == "key" and ev["text"] != null and ev["text"] != "":
            f["text"] = f["text"] + ev["text"]
        else:
            return k != "tab" and k != "shift+tab"
        if f["mode"] == "find":
            # recherche au fil de la frappe, depuis la position d'ouverture
            m := find_from(st, f["text"], f["origin"], true)
            if m != null:
                st["anchor"] = m
                st["cur"] = [m[0], m[1] + len(f["text"])]
        return true

    func key(app, n, ev):
        st := sync(n)
        st["hover_pos"] = null
        k := _b.key_of(ev)
        if ev["type"] == "paste":
            k = "paste"
        if st["find"]["open"]:
            st["comp"] = null
            r := self._find_key(app, n, st, ev, k)
            self._fix_hidden(st)
            self._cursor_changed(app, n, st)
            return r
        readonly := n.get("readonly", false)
        lang := n.get("language", "alex")
        comp := st["comp"]
        was_open := comp != null
        if comp != null:
            if k == "up" or k == "down" or k == "page_up" or k == "page_down":
                step := 1 if (k == "up" or k == "down") else _COMP_ROWS
                d := step if (k == "down" or k == "page_down") else -step
                comp["sel"] = _u.clamp(comp["sel"] + d, 0, len(comp["items"]) - 1)
                return true
            if k == "enter" or k == "tab":
                if comp_accept(st):
                    self._emit(app, n, st)
                    self._cursor_changed(app, n, st)
                    return true
            if k == "escape":
                st["comp"] = null
                return true
            st["comp"] = null
        if k == "tab" and st["esc"]:
            st["esc"] = false
            return false
        if k != "escape":
            st["esc"] = false
        lines := st["lines"]
        cur := st["cur"]
        line := lines[cur[0]]
        shift := ev["type"] == "key" and ev["shift"] == true and _s.contains(k, "shift+")
        base := _s.replace(k, "shift+", "")
        rows := self._geom(app, n, st)[4]
        handled := true
        edited := false
        auto := false
        # ---- déplacements
        if base == "left" or base == "right" or base == "up" or base == "down" or base == "home" or base == "end" or base == "page_up" or base == "page_down" or base == "ctrl+left" or base == "ctrl+right" or base == "ctrl+home" or base == "ctrl+end":
            sel := selection(st)
            pos := [cur[0], cur[1]]
            goal := _b.st_get(st, "goal", null)
            if base == "left":
                if sel != null and not shift:
                    pos = sel[0]
                elif cur[1] > 0:
                    pos = [cur[0], cur[1] - 1]
                elif cur[0] > 0:
                    pos = [cur[0] - 1, len(lines[cur[0] - 1])]
            elif base == "right":
                if sel != null and not shift:
                    pos = sel[1]
                elif cur[1] < len(line):
                    pos = [cur[0], cur[1] + 1]
                elif cur[0] + 1 < len(lines):
                    pos = [cur[0] + 1, 0]
            elif base == "ctrl+left":
                if cur[1] == 0 and cur[0] > 0:
                    pos = [cur[0] - 1, len(lines[cur[0] - 1])]
                else:
                    pos = [cur[0], self._word_left(line, cur[1])]
            elif base == "ctrl+right":
                if cur[1] == len(line) and cur[0] + 1 < len(lines):
                    pos = [cur[0] + 1, 0]
                else:
                    pos = [cur[0], self._word_right(line, cur[1])]
            elif base == "home":
                ind := _indent_of(line)
                pos = [cur[0], ind if cur[1] != ind else 0]
            elif base == "end":
                pos = [cur[0], len(line)]
            elif base == "ctrl+home":
                pos = [0, 0]
            elif base == "ctrl+end":
                pos = [len(lines) - 1, len(lines[len(lines) - 1])]
            else:
                step := 1 if (base == "up" or base == "down") else rows - 1
                vi := vpos(st, cur[0])
                vt := vi - step if (base == "up" or base == "page_up") else vi + step
                vt = _u.clamp(vt, 0, vcount(st) - 1)
                target := vline(st, vt)
                if goal == null:
                    goal = cur[1]
                pos = [target, _u.imin(goal, len(lines[target]))]
                if base == "page_up" or base == "page_down":
                    vtop := vpos(st, _b.st_get(st, "top", 0))
                    st["top"] = vline(st, _u.clamp(vtop + (vt - vi), 0, _u.imax(0, vcount(st) - rows)))
                self._move(st, pos, shift)
                st["goal"] = goal
                self._cursor_changed(app, n, st)
                return true
            st["goal"] = null
            pos = skip_hidden(st, pos, base == "right" or base == "ctrl+right")
            self._move(st, pos, shift)
        elif k == "ctrl+a":
            st["anchor"] = [0, 0]
            st["cur"] = [len(lines) - 1, len(lines[len(lines) - 1])]
        elif k == "ctrl+c" or k == "ctrl+insert":
            t := selected_text(st)
            if t == "":
                t = line + "\n"
            app.clipboard_set(t)
        elif k == "ctrl+f":
            st["find"] = {"open": true, "mode": "find", "text": selected_text(st) if selection(st) != null and selection(st)[0][0] == selection(st)[1][0] else st["find"]["text"], "origin": [cur[0], cur[1]]}
        elif k == "ctrl+g" or k == "ctrl+l":
            st["find"] = {"open": true, "mode": "goto", "text": "", "origin": [cur[0], cur[1]]}
        elif k == "f3" or k == "shift+f3":
            if st["find"]["text"] != "":
                st["find"]["open"] = false
                m := find_from(st, st["find"]["text"], cur if k == "f3" else (selection(st)[0] if selection(st) != null else cur), k == "f3")
                if m != null:
                    st["anchor"] = m
                    st["cur"] = [m[0], m[1] + len(st["find"]["text"])]
        elif k == "escape":
            if selection(st) != null:
                st["anchor"] = null
            else:
                st["esc"] = true
                return false
        elif k == "f4" or k == "shift+f4" or k == "ctrl+f4" or k == "ctrl+shift+[" or k == "ctrl+shift+]":
            if k == "shift+f4":
                fold_all(st)
            elif k == "ctrl+f4":
                unfold_all(st)
            else:
                mode := "toggle" if k == "f4" else ("fold" if k == "ctrl+shift+[" else "unfold")
                fold_command(st, cur[0], mode)
            clamp_visible(st)
            st["goal"] = null
        elif readonly:
            handled = false
        elif k == "ctrl+space":
            comp_open(st, lang, true, n.get("completion_provider", null), app)
        # ---- modifications
        elif k == "ctrl+z":
            if len(st["undo"]) > 0:
                append(st["redo"], snapshot(st))
                restore(st, pop(st["undo"]))
                st["last_edit"] = ["", 0.0, -1]
                edited = true
        elif k == "ctrl+y" or k == "ctrl+shift+z":
            if len(st["redo"]) > 0:
                append(st["undo"], snapshot(st))
                restore(st, pop(st["redo"]))
                st["last_edit"] = ["", 0.0, -1]
                edited = true
        elif k == "ctrl+x" or k == "shift+delete":
            if selection(st) == null:
                unfold_near(st, cur[0], cur[0])
            push_undo(st, "cut")
            if selection(st) == null:
                app.clipboard_set(line + "\n")
                if len(lines) > 1:
                    pop(lines, cur[0])
                    l := _u.imin(cur[0], len(lines) - 1)
                    st["cur"] = [l, _u.imin(cur[1], len(lines[l]))]
                else:
                    lines[0] = ""
                    st["cur"] = [0, 0]
            else:
                app.clipboard_set(selected_text(st))
                delete_selection(st)
            edited = true
        elif k == "ctrl+v" or k == "shift+insert" or k == "paste":
            t := ev["text"] if k == "paste" else app.clipboard_get()
            if t != null and t != "":
                push_undo(st, "paste")
                insert_text(st, _clean(t))
                edited = true
        elif k == "enter":
            if contains_key(st["folds"], cur[0]):
                unfold_at(st, cur[0])
            push_undo(st, "enter")
            delete_selection(st)
            cur = st["cur"]
            line = lines[cur[0]]
            ind := _indent_of(line)
            if ind > cur[1]:
                ind = cur[1]
            head := _s.trim(_sl(line, 0, cur[1]))
            if _s.ends_with(head, ":") or _s.ends_with(head, "{") or _s.ends_with(head, "[") or _s.ends_with(head, "("):
                ind += n.get("tab_size", 4)
            insert_text(st, "\n" + _s.repeat(" ", ind))
            edited = true
        elif k == "backspace":
            if cur[1] == 0 and cur[0] > 0 and selection(st) == null and is_hidden(st, cur[0] - 1):
                unfold_containing(st, cur[0] - 1)
            push_undo(st, "type")
            if not delete_selection(st):
                if cur[1] > 0:
                    ts := n.get("tab_size", 4)
                    c := cur[1]
                    if _s.trim(_sl(line, 0, c)) == "":
                        c = ((c - 1) // ts) * ts
                    else:
                        c -= 1
                    delete_range(st, [cur[0], c], cur)
                elif cur[0] > 0:
                    delete_range(st, [cur[0] - 1, len(lines[cur[0] - 1])], cur)
            edited = true
        elif k == "delete":
            if cur[1] == len(line) and contains_key(st["folds"], cur[0]):
                unfold_at(st, cur[0])
            push_undo(st, "type")
            if not delete_selection(st):
                if cur[1] < len(line):
                    delete_range(st, cur, [cur[0], cur[1] + 1])
                elif cur[0] + 1 < len(lines):
                    delete_range(st, cur, [cur[0] + 1, 0])
            edited = true
        elif k == "tab" or k == "shift+tab":
            ts := n.get("tab_size", 4)
            sel := selection(st)
            if k == "tab" and (sel == null or sel[0][0] == sel[1][0]):
                push_undo(st, "type")
                delete_selection(st)
                c := st["cur"][1]
                insert_text(st, _s.repeat(" ", ts - c % ts))
            else:
                push_undo(st, "indent")
                span := line_span(st)
                l := span[0]
                while l <= span[1]:
                    t := lines[l]
                    if k == "tab":
                        if _s.trim(t) != "":
                            lines[l] = _s.repeat(" ", ts) + t
                    else:
                        lines[l] = _sl(t, _u.imin(ts, _indent_of(t)))
                    l += 1
                d := ts if k == "tab" else -ts
                if st["anchor"] != null:
                    st["anchor"] = [st["anchor"][0], _u.imax(0, st["anchor"][1] + d)]
                st["cur"] = [st["cur"][0], _u.imax(0, st["cur"][1] + d)]
                clamp_cursor(st)
            edited = true
        elif k == "ctrl+/" or k == "ctrl+_" or k == "ctrl+7":
            push_undo(st, "comment")
            span := line_span(st)
            all_commented := true
            l := span[0]
            while l <= span[1]:
                t := _s.trim(lines[l])
                if t != "" and not _s.starts_with(t, "#"):
                    all_commented = false
                l += 1
            l = span[0]
            while l <= span[1]:
                t := lines[l]
                ind := _indent_of(t)
                if all_commented:
                    rest := _sl(t, ind)
                    if _s.starts_with(rest, "# "):
                        lines[l] = _sl(t, 0, ind) + _sl(rest, 2)
                    elif _s.starts_with(rest, "#"):
                        lines[l] = _sl(t, 0, ind) + _sl(rest, 1)
                elif _s.trim(t) != "":
                    lines[l] = _sl(t, 0, ind) + "# " + _sl(t, ind)
                l += 1
            clamp_cursor(st)
            edited = true
        elif k == "ctrl+d":
            push_undo(st, "dup")
            span := line_span(st)
            unfold_near(st, span[0], span[1])
            l := span[0]
            count := span[1] - span[0] + 1
            while l <= span[1]:
                insert(lines, l + count, lines[l])
                l += 1
            st["cur"] = [st["cur"][0] + count, st["cur"][1]]
            if st["anchor"] != null:
                st["anchor"] = [st["anchor"][0] + count, st["anchor"][1]]
            edited = true
        elif k == "ctrl+shift+k":
            push_undo(st, "delline")
            span := line_span(st)
            unfold_near(st, span[0], span[1])
            k2 := span[1] - span[0] + 1
            while k2 > 0 and len(lines) > 1:
                pop(lines, span[0])
                k2 -= 1
            if k2 > 0:
                lines[0] = ""
            st["anchor"] = null
            st["cur"] = [_u.imin(span[0], len(lines) - 1), 0]
            edited = true
        elif k == "alt+up" or k == "alt+down":
            span := line_span(st)
            unfold_near(st, span[0] - 1, span[1] + 1)
            up := k == "alt+up"
            if (up and span[0] > 0) or (not up and span[1] + 1 < len(lines)):
                push_undo(st, "move")
                if up:
                    moved := pop(lines, span[0] - 1)
                    insert(lines, span[1], moved)
                else:
                    moved := pop(lines, span[1] + 1)
                    insert(lines, span[0], moved)
                d := -1 if up else 1
                st["cur"] = [st["cur"][0] + d, st["cur"][1]]
                if st["anchor"] != null:
                    st["anchor"] = [st["anchor"][0] + d, st["anchor"][1]]
                edited = true
        else:
            t := null
            if k == "space":
                t = " "
            elif ev["type"] == "key" and ev["text"] != null and ev["text"] != "" and not ev["ctrl"] and not ev["alt"]:
                t = ev["text"]
            if t == null:
                handled = false
            else:
                push_undo(st, "type")
                insert_text(st, t)
                edited = true
                if len(t) == 1 and (_is_word_char(t[0]) or (t == "." and n.get("completion_provider", null) != null)):
                    auto = true
        if edited:
            st["goal"] = null
            self._emit(app, n, st)
            if n.get("completion", true) and not readonly and (auto or (k == "backspace" and was_open)):
                prov := n.get("completion_provider", null)
                line := st["lines"][st["cur"][0]]
                after_dot := st["cur"][1] > 0 and line[st["cur"][1] - 1] == '.'
                if prov != null and after_dot and not in_string_or_comment(st, lang, st["cur"][0], st["cur"][1]):
                    comp_open(st, lang, true, prov, app)
                else:
                    comp_open(st, lang, false, prov, app)
        if handled:
            self._fix_hidden(st)
            self._cursor_changed(app, n, st)
        return handled

    # ------------------------------------------------------------ souris
    func _pos_at(app, n, st, x, y):
        g := self._geom(app, n, st)
        lh := self._lh(app)
        lines := st["lines"]
        l := vline(st, vpos(st, _b.st_get(st, "top", 0)) + _u.imax(0, (y - g[1])) // lh)
        line := lines[l]
        left := _b.st_get(st, "left", 0)
        target := x - g[0]
        c := left
        s := app.s
        while c < len(line):
            w0 := s.text_width(_sl(line, left, c), "mono")
            w1 := s.text_width(_sl(line, left, c + 1), "mono")
            if target < (w0 + w1) / 2:
                break
            c += 1
        return [l, _u.imin(c, len(line))]

    func mouse(app, n, ev):
        st := sync(n)
        a := ev["action"]
        g := self._geom(app, n, st)
        if a == "move":
            # survol du texte : position mémorisée pour la bulle d'information
            if n.get("on_hover", null) == null:
                return false
            inside := ev["x"] >= g[0] and ev["x"] < g[0] + g[2] and ev["y"] >= g[1] and ev["y"] < g[1] + g[3]
            hp := null
            if inside:
                p := self._pos_at(app, n, st, ev["x"], ev["y"])
                line := st["lines"][p[0]]
                if p[1] < len(line) and _is_word_char(line[p[1]]):
                    # début du mot : une seule demande par mot
                    c0 := p[1]
                    while c0 > 0 and _is_word_char(line[c0 - 1]):
                        c0 -= 1
                    hp = [p[0], c0]
            old := _b.st_get(st, "hover_pos", null)
            if hp == old:
                return false
            st["hover_pos"] = hp
            st["hover_t"] = app.now
            st["hover_asked"] = false
            st["hover_text"] = null
            return true
        if a == "down":
            st["hover_pos"] = null
        if a == "down" and self._bpw(app, n) > 0 and ev["x"] < n.x + app.s.lb + self._bpw(app, n) and ev["x"] >= n.x:
            # colonne des points d'arrêt
            p := self._pos_at(app, n, st, g[0], ev["y"])
            app.call(n.get("on_gutter", null), [p[0] + 1])
            return true
        if a == "down" and _b.st_get(ev, "ctrl", false) == true and n.get("on_definition", null) != null and ev["x"] >= g[0]:
            # Ctrl+clic : aller à la définition
            p := self._pos_at(app, n, st, ev["x"], ev["y"])
            st["cur"] = p
            st["anchor"] = null
            self._cursor_changed(app, n, st)
            app.call(n.get("on_definition"), [p[0] + 1, p[1] + 1])
            return true
        if a == "up":
            st["bar_drag"] = false
            return true
        if st["comp"] != null and a == "down":
            r := self._comp_rect(app, n, st)
            if r != null and ev["x"] >= r[0] and ev["x"] < r[0] + r[2] and ev["y"] >= r[1] and ev["y"] < r[1] + r[3]:
                comp := st["comp"]
                comp["sel"] = _u.clamp(comp["top"] + (ev["y"] - r[1]) // self._lh(app), 0, len(comp["items"]) - 1)
                if comp_accept(st):
                    self._emit(app, n, st)
                    self._cursor_changed(app, n, st)
                return true
            st["comp"] = null
        on_bar := ev["x"] >= n.x + n.w - app.s.lb - app.s.sbw and vcount(st) > g[4]
        if a == "down" and on_bar or (a == "drag" and _b.st_get(st, "bar_drag", false)):
            st["bar_drag"] = true
            st["top"] = vline(st, _b.vscroll_click(ev["y"] - g[1], g[3], vcount(st), g[4]))
            return true
        if a != "down" and a != "drag":
            return false
        pos := self._pos_at(app, n, st, ev["x"], ev["y"])
        if a == "drag":
            if st["anchor"] == null:
                st["anchor"] = [st["cur"][0], st["cur"][1]]
            st["cur"] = pos
            self._cursor_changed(app, n, st)
            return true
        st["find"]["open"] = false
        clicks := ev["clicks"] if contains_key(ev, "clicks") else 1
        if ev["x"] < g[0] and n.get("line_numbers", true) and ev["x"] < n.x + app.s.lb + self._bpw(app, n) + self._cw(app) and (contains_key(st["folds"], pos[0]) or foldable(st["lines"], pos[0])):
            # clic sur le triangle de la marge : replier / déplier le bloc
            fold_command(st, pos[0], "toggle")
            clamp_visible(st)
        elif ev["x"] < g[0] and n.get("line_numbers", true):
            # clic dans la marge : sélectionner la ligne
            l := pos[0]
            st["anchor"] = [l, 0]
            st["cur"] = [l + 1, 0] if l + 1 < len(st["lines"]) else [l, len(st["lines"][l])]
        elif clicks >= 3:
            st["anchor"] = [pos[0], 0]
            st["cur"] = [pos[0], len(st["lines"][pos[0]])]
        elif clicks == 2:
            line := st["lines"][pos[0]]
            a0 := pos[1]
            b0 := pos[1]
            while a0 > 0 and _is_word_char(line[a0 - 1]):
                a0 -= 1
            while b0 < len(line) and _is_word_char(line[b0]):
                b0 += 1
            st["anchor"] = [pos[0], a0]
            st["cur"] = [pos[0], b0]
        elif ev["shift"] == true:
            if st["anchor"] == null:
                st["anchor"] = [st["cur"][0], st["cur"][1]]
            st["cur"] = pos
        else:
            st["anchor"] = null
            st["cur"] = pos
        st["goal"] = null
        self._cursor_changed(app, n, st)
        return true

    func wheel(app, n, ev):
        st := sync(n)
        rows := self._geom(app, n, st)[4]
        total := vcount(st)
        if total <= rows:
            return false
        st["comp"] = null
        vtop := _u.clamp(vpos(st, _b.st_get(st, "top", 0)) - ev["dy"] * 3, 0, total - rows)
        st["top"] = vline(st, vtop)
        # garder le curseur dans la vue sans changer le texte
        cur := st["cur"]
        vc := vpos(st, cur[0])
        if vc < vtop:
            l := vline(st, vtop)
            st["cur"] = [l, _u.imin(cur[1], len(st["lines"][l]))]
        elif vc >= vtop + rows:
            l := vline(st, vtop + rows - 1)
            st["cur"] = [l, _u.imin(cur[1], len(st["lines"][l]))]
        st["anchor"] = null
        return true

    func text_of(n):
        return str(n.get("value", ""))
