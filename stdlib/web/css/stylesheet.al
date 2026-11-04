# ALEX STANDARD LIBRARY — web.css.stylesheet
#
# Feuille de style (règles, at-rules, @keyframes) et CASCADE : calcul du style d'un élément (web.html ou
# web.dom) selon les règles applicables dans un environnement (web.css.media_query.Environment), avec
# origines (user-agent, user, author), !important, couches @layer, spécificité, ordre, attribut style,
# @media / @supports / @container / @scope, héritage, inherit / initial / unset / revert, raccourcis développés,
# propriétés personnalisées et var(), et taille de police calculée en px.
#
#   use web.css.stylesheet as ss
#   sh := ss.Stylesheet()
#   sh.rule("p", {"color": "#333", "margin": "0 0 1em"})
#   sh.rule("p.note", {"color": "teal"})
#   sh.media("(max-width: 600px)").add(css_rule.StyleRule("p", {"font-size": "14px"}))
#   st := sh.compute(element, media_query.Environment(400, 800))
#   st.get("color")                  # teal  (spécificité)
#   st.get("margin-bottom")          # 1em   (raccourci développé)
#   st.font_size_px                  # 14.0
#   ss.compute(element, [ss.default_stylesheet(), sh], env)   # plusieurs feuilles (agent utilisateur + auteur)
#   sh.matching_rules(element, env)  # règles appliquées, de la plus faible à la plus forte
#
# Erreurs : CssError ; les sélecteurs invalides d'une règle sont ignorés par la cascade (comme un navigateur).

from core use len, type, to_float
from collections use append, keys
use string as _s
use web.css.css_errors as _err
use web.css.css_rule as _rule
use web.css.at_rule as _at
use web.css.keyframes as _kf
use web.css.declaration as _decl
use web.css.property as _prop
use web.css.selector as _sel
use web.css.selector_parser as _sp
use web.css.media_query as _mq
use web.css.supports_query as _sq
use web.css.container_query as _cq
use web.css.variables as _vars
use web.css.functions as _fn
use web.css.units as _units

const ORIGINS := {"user-agent": 0, "user": 1, "author": 2}
const _UNLAYERED := 1000000

class Stylesheet:
    func init(rules=null, origin="author", href=null, media=null, title=null):
        if not (origin in ORIGINS):
            _err.css_error("Stylesheet", "origine inconnue « " + str(origin) + " »")
        self.rules = []
        self.origin = origin
        self.href = href
        self.media_text = media          # attribut media de la feuille (null : toujours)
        self.title = title
        self.disabled = false
        self._entries = null
        if rules != null:
            for r in rules:
                self.add(r)

    func invalidate():
        self._entries = null
        return self

    func add(rule):
        rule.parent = null
        append(self.rules, rule)
        self._entries = null
        return rule

    func extend(rules):
        for r in rules:
            self.add(r)
        return self

    # Nouvelle règle de style (ajoutée et renvoyée).
    func rule(selector, declarations=null):
        return self.add(_rule.StyleRule(selector, declarations))

    func media(query, rules=null):
        return self.add(_at.media(query, rules))

    func supports(condition, rules=null):
        return self.add(_at.supports(condition, rules))

    func container(condition, rules=null, name=null):
        return self.add(_at.container(condition, rules, name))

    func layer(name, rules=null):
        return self.add(_at.layer(name, rules))

    func keyframes(name, frames=null):
        return self.add(_kf.Keyframes(name, frames))

    func remove(rule):
        kept := []
        for r in self.rules:
            if r != rule:
                append(kept, r)
        self.rules = kept
        self._entries = null
        return self

    func insert(index, rule):
        i := index if index <= len(self.rules) else len(self.rules)
        self.rules = self.rules[0:i] + [rule] + self.rules[i:len(self.rules)]
        self._entries = null
        return rule

    func __len__():
        return len(self.rules)

    # Règles de style de premier niveau dont le sélecteur est exactement celui donné (espaces normalisés).
    func find(selector):
        want := _rule._compact_selector(selector)
        out := []
        for r in self.rules:
            if r.kind == "style" and _rule._compact_selector(r.selector) == want:
                append(out, r)
        return out

    func find_keyframes(name):
        found := null
        for r in self._walk_all():
            if r.kind == "keyframes" and r.name == name:
                found = r
        return found

    func keyframes_names():
        out := []
        for r in self._walk_all():
            if r.kind == "keyframes" and not (r.name in out):
                append(out, r.name)
        return out

    # Toutes les règles (at-rules parcourues), imbrication résolue.
    func _walk_all():
        out := []
        for r in self.rules:
            _walk_flat(r, out)
        return out

    func style_rules():
        out := []
        for r in self._walk_all():
            if r.kind == "style":
                append(out, r)
        return out

    # Variables déclarées sur :root / html (valeurs brutes).
    func root_variables():
        out := {}
        for r in self.style_rules():
            s := _s.trim(r.selector)
            if s == ":root" or s == "html":
                for d in r.declarations:
                    if d.is_custom():
                        out[d.property] = d.value
        return out

    func imports():
        out := []
        for r in self.rules:
            if r.kind == "at" and r.name == "import":
                append(out, r.prelude)
        return out

    func entries():
        if self._entries == null:
            self._entries = _build_entries(self)
        return self._entries

    func compute(element, env=null, parent_style=null, inline=null, containers=null):
        return compute(element, [self], env, parent_style, inline, containers)

    func matching_rules(element, env=null, containers=null):
        return matching_rules(element, [self], env, containers)

    func copy():
        s := Stylesheet(null, self.origin, self.href, self.media_text, self.title)
        for r in self.rules:
            s.add(r.copy())
        return s

    func to_css(fmt=null):
        f := fmt if fmt != null else _rule.Format()
        parts := []
        for r in self.rules:
            append(parts, r.to_css(f, 0))
        if f.compact:
            return _s.join("", parts)
        return _s.join("\n\n" if f.pretty else "\n", parts)

    func __str__():
        return self.to_css()

func _walk_flat(r, out):
    if r.kind == "style":
        for x in r.flatten():
            if x.kind == "style":
                append(out, x)
            else:
                _walk_flat(x, out)
    elif r.kind == "at":
        for c in r.rules:
            _walk_flat(c, out)
    else:
        append(out, r)

# ---------------------------------------------------------------- entrées de cascade

# Une règle de style applicable sous conditions : sélecteurs analysés, déclarations développées.
class Entry:
    func init(rule, selectors, declarations, layer_rank, order, conditions):
        self.rule = rule
        self.selectors = selectors          # SelectorList
        self.declarations = declarations
        self.layer_rank = layer_rank
        self.order = order
        self.conditions = conditions        # liste de ("media", MediaQueryList) / ("supports", c) / ...

class _Builder:
    func init(sheet):
        self.sheet = sheet
        self.entries = []
        self.layers = []
        self.anon = 0
        self.order = 0

    func layer_rank(name):
        if name == null:
            return _UNLAYERED
        i := 0
        while i < len(self.layers):
            if self.layers[i] == name:
                return i
            i += 1
        append(self.layers, name)
        return len(self.layers) - 1

    func visit(r, layer, conds):
        if r.kind == "style":
            for x in r.flatten():
                if x.kind == "style":
                    self.style(x, layer, conds)
                else:
                    self.visit(x, layer, conds)
            return
        if r.kind != "at":
            return
        n := r.name
        if n == "layer":
            if r.body == "statement":
                for nm in _s.split(r.prelude, ","):
                    self.layer_rank(_join_layer(layer, _s.trim(nm)))
                return
            name := r.prelude
            if name == "":
                self.anon += 1
                name = "#anonyme-" + str(self.anon)
            full := _join_layer(layer, name)
            self.layer_rank(full)
            for c in r.rules:
                self.visit(c, full, conds)
            return
        cond := null
        if n == "media":
            cond = ("media", _mq.parse_lenient(r.prelude))
        elif n == "supports":
            cond = ("supports", r.prelude)
        elif n == "container":
            cond = ("container", r.prelude)
        elif n == "scope":
            cond = ("scope", _scope_bounds(r.prelude))
        elif n == "starting-style" or n == "document" or n == "-moz-document":
            return
        if cond == null and r.body != "rules":
            return
        c2 := conds if cond == null else conds + [cond]
        for c in r.rules:
            self.visit(c, layer, c2)

    func style(rule, layer, conds):
        lst := null
        try:
            lst = _sp.parse(rule.selector)
        catch e:
            return
        decls := []
        for d in rule.declarations:
            for x in d.expand():
                append(decls, x)
        self.order += 1
        append(self.entries, Entry(rule, lst, decls, self.layer_rank(layer), self.order, conds))

func _join_layer(parent, name):
    if parent == null:
        return name
    return parent + "." + name

# « (début) to (fin) » -> (début, fin ou null).
func _scope_bounds(prelude):
    p := _s.trim(prelude)
    if p == "":
        return (null, null)
    start := null
    end := null
    i := _s.find(p, ") to (")
    if i >= 0:
        start = _s.trim(p[1:i])
        end = _s.trim(p[i + 6:len(p) - 1])
    else:
        start = _s.trim(p[1:len(p) - 1]) if _s.starts_with(p, "(") else p
    return (start, end)

func _build_entries(sheet):
    b := _Builder(sheet)
    for r in sheet.rules:
        b.visit(r, null, [])
    return b

# ---------------------------------------------------------------- correspondance

class _Ctx:
    func init(env, containers):
        self.env = env if env != null else _mq.Environment()
        self.containers = containers

# Racine de portée pour l'élément, ou false si la règle ne s'applique pas.
func _conditions_ok(entry, el, adapter, ctx):
    scope := null
    for c in entry.conditions:
        k := c[0]
        if k == "media":
            if not c[1].matches(ctx.env):
                return false
        elif k == "supports":
            if not _sq.supports(c[1]):
                return false
        elif k == "container":
            if ctx.containers == null:
                return false
            if not _cq.evaluate(ctx.containers(el), c[1]):
                return false
        elif k == "scope":
            root := _scope_root(el, c[1], adapter)
            if root == false:
                return false
            scope = root
    return scope if scope != null else true

func _scope_root(el, bounds, adapter):
    start := bounds[0]
    end := bounds[1]
    if start == null:
        p := adapter.parent(el)
        return p if p != null else el
    root := null
    try:
        root = _sel.closest(el, start, adapter)
    catch e:
        return false
    if root == null:
        return false
    if end != null:
        e := el
        while e != null and e != root:
            ok := false
            try:
                ok = _sel.matches(e, end, adapter)
            catch err:
                ok = false
            if ok:
                return false
            e = adapter.parent(e)
    return root

# Spécificité de la plus forte des alternatives qui correspondent, ou null.
func _match_spec(entry, el, adapter, scope):
    best := null
    for c in entry.selectors.items:
        one := _sp.SelectorList([c], "")
        if _sel.matches(el, one, adapter, scope):
            s := _sp.specificity(c)
            if best == null or _sp.compare_specificity(s, best) > 0:
                best = s
    return best

func _sheets(sheets):
    if isinstance(sheets, Stylesheet):
        return [sheets]
    return sheets

class Match:
    func init(rule, specificity, origin, layer_rank, order, sheet_index, declarations):
        self.rule = rule
        self.specificity = specificity
        self.origin = origin
        self.layer_rank = layer_rank
        self.order = order
        self.sheet_index = sheet_index
        self.declarations = declarations

func _less(a, b):
    i := 0
    while i < len(a):
        if a[i] < b[i]:
            return true
        if a[i] > b[i]:
            return false
        i += 1
    return false

func _sort_by_key(items, keyf):
    # tri par insertion stable (listes courtes)
    out := []
    ks := []
    for it in items:
        k := keyf(it)
        j := len(out)
        append(out, it)
        append(ks, k)
        while j > 0 and _less(k, ks[j - 1]):
            out[j] = out[j - 1]
            ks[j] = ks[j - 1]
            j -= 1
        out[j] = it
        ks[j] = k
    return out

func _all_matches(element, sheets, ctx):
    adapter := _sel.adapter_for(element)
    out := []
    si := 0
    for sh in _sheets(sheets):
        si += 1
        if sh.disabled:
            continue
        if sh.media_text != null and not _mq.matches(sh.media_text, ctx.env):
            continue
        b := sh.entries()
        for e in b.entries:
            sc := _conditions_ok(e, element, adapter, ctx)
            if sc == false:
                continue
            spec := _match_spec(e, element, adapter, sc if sc != true else null)
            if spec == null:
                continue
            append(out, Match(e.rule, spec, ORIGINS[sh.origin], e.layer_rank, e.order, si, e.declarations))
    return out

# Règles appliquées à l'élément, de la plus faible à la plus forte (déclarations normales).
func matching_rules(element, sheets, env=null, containers=null):
    ms := _all_matches(element, sheets, _Ctx(env, containers))
    return _sort_by_key(ms, (m) => [m.origin, m.layer_rank, m.specificity[0], m.specificity[1], m.specificity[2], m.sheet_index, m.order])

# ---------------------------------------------------------------- style calculé

const _FONT_KEYWORDS := {"xx-small": 9.0, "x-small": 10.0, "small": 13.0, "medium": 16.0, "large": 18.0, "x-large": 24.0, "xx-large": 32.0, "xxx-large": 48.0}

class ComputedStyle:
    func init(values, custom, parent=null, font_size_px=16.0, root_font_size_px=16.0):
        self.values = values              # propriété -> valeur (var() résolues)
        self.custom = custom              # --variable -> valeur
        self.parent = parent
        self.font_size_px = font_size_px
        self.root_font_size_px = root_font_size_px
        self.sources = {}                 # propriété -> Match (ou "inline", "inherited")

    # Valeur calculée ; une propriété non définie prend sa valeur initiale (ou null si inconnue).
    func get(name, default=null):
        n := _prop.canonical(name)
        if _prop.is_custom(n):
            if n in self.custom:
                return self.custom[n]
            return default
        if n in self.values:
            return self.values[n]
        if _prop.is_shorthand(n):
            parts := []
            for x in _prop.expand(n, "initial"):
                if x[0] != n:
                    append(parts, self.get(x[0]))
            if len(parts) > 0:
                same := true
                for x in parts:
                    if x != parts[0]:
                        same = false
                if same:
                    return parts[0]
                if n in ["margin", "padding", "inset", "border-color", "border-style", "border-width", "border-radius", "scroll-margin", "scroll-padding"]:
                    return _s.join(" ", parts)
        if default != null:
            return default
        return _prop.initial_value(n)

    func __getitem__(name):
        return self.get(name)

    func has(name):
        n := _prop.canonical(name)
        return n in self.values or n in self.custom

    func is_explicit(name):
        n := _prop.canonical(name)
        return n in self.sources and self.sources[n] != "inherited"

    func variable(name):
        return self.get(name if _s.starts_with(name, "--") else "--" + name)

    func to_dict():
        out := {}
        for k in keys(self.values):
            out[k] = self.values[k]
        for k in keys(self.custom):
            out[k] = self.custom[k]
        return out

    func properties():
        return keys(self.values)

    # Valeur numérique en px (longueurs, calc(), em relatif à la police de l'élément) ; null si non numérique.
    func px(name, env=null):
        v := self.get(name)
        if v == null:
            return null
        e := env if env != null else _mq.Environment()
        ctx := _units.Context(self.font_size_px, self.root_font_size_px, e.width(), e.height())
        try:
            return _fn.evaluate(v, ctx)
        catch err:
            return null

    func is_displayed():
        return self.get("display") != "none"

    func is_visible():
        return self.is_displayed() and self.get("visibility") != "hidden" and self.get("visibility") != "collapse"

func _parse_inline(inline):
    if inline == null:
        return []
    if type(inline) == "dict":
        return _decl.from_dict(inline)
    if type(inline) == "str":
        return _decl.parse_block(inline)
    return inline

func _inline_of(element, adapter):
    try:
        t := adapter.attr(element, "style")
        if t != null:
            return _decl.parse_block(t)
    catch e:
        return []
    return []

# Cascade : valeur gagnante par propriété ; renvoie (gagnants dict propriété -> (valeur, source)).
func _winners(matches, inline_decls):
    cand := []
    for m in matches:
        for d in m.declarations:
            if d.important:
                append(cand, ([5 - m.origin, 1, 0, -m.layer_rank, m.specificity[0], m.specificity[1], m.specificity[2], m.sheet_index, m.order], d, m))
            else:
                append(cand, ([m.origin, 0, 0, m.layer_rank, m.specificity[0], m.specificity[1], m.specificity[2], m.sheet_index, m.order], d, m))
    k := 0
    for d in inline_decls:
        for x in d.expand():
            k += 1
            if x.important:
                append(cand, ([5 - 2, 1, 1, 0, 0, 0, 0, 0, k], x, "inline"))
            else:
                append(cand, ([2, 0, 1, _UNLAYERED, 0, 0, 0, 0, k], x, "inline"))
    ordered := _sort_by_key(cand, (c) => c[0])
    out := {}
    for c in ordered:
        out[c[1].property] = (c[1].value, c[2], c[0][0])
    return (out, ordered)

func _font_px(value, parent_px, root_px, env):
    v := _s.lower(_s.trim(value))
    if v in _FONT_KEYWORDS:
        return _FONT_KEYWORDS[v] * root_px / 16.0
    if v == "smaller":
        return parent_px / 1.2
    if v == "larger":
        return parent_px * 1.2
    ctx := _units.Context(parent_px, root_px, env.width(), env.height(), parent_px)
    try:
        return _fn.evaluate(v, ctx)
    catch e:
        return parent_px

# Style calculé d'un élément. sheets : Stylesheet ou liste ; parent_style : style du parent (calculé
# récursivement s'il est absent) ; inline : style en ligne (texte, dict, liste ; par défaut l'attribut style) ;
# containers : fonction élément -> liste de container_query.Container (du plus proche au plus lointain).
func compute(element, sheets, env=null, parent_style=null, inline=null, containers=null):
    ctx := _Ctx(env, containers)
    adapter := _sel.adapter_for(element)
    ps := parent_style
    if ps == null:
        p := adapter.parent(element)
        if p != null:
            ps = compute(p, sheets, ctx.env, null, null, containers)
    return _compute_one(element, sheets, ctx, ps, inline, adapter)

func _compute_one(element, sheets, ctx, ps, inline, adapter):
    matches := _all_matches(element, sheets, ctx)
    inline_decls := _parse_inline(inline) if inline != null else _inline_of(element, adapter)
    w := _winners(matches, inline_decls)
    winners := w[0]
    # propriétés personnalisées : héritées, puis déclarées
    custom := {}
    if ps != null:
        for k in keys(ps.custom):
            custom[k] = ps.custom[k]
    declared := {}
    for name in keys(winners):
        if _prop.is_custom(name):
            v := winners[name][0]
            lv := _s.lower(_s.trim(v))
            if lv == "initial":
                declared[name] = null
            elif lv == "inherit" or lv == "unset":
                declared[name] = ps.custom[name] if ps != null and name in ps.custom else null
            else:
                declared[name] = v
    scope := _vars.Scope(custom)
    for name in keys(declared):
        if declared[name] == null:
            if name in scope.values:
                scope.values[name] = ""
        else:
            scope.values[name] = declared[name]
    resolved_custom := {}
    for name in keys(scope.values):
        if scope.values[name] == "" and name in declared and declared[name] == null:
            continue
        rv := null
        try:
            rv = scope.value(name)
        catch e:
            rv = null
        if rv != null:
            resolved_custom[name] = rv
    var_scope := _vars.Scope(resolved_custom)
    root_px := ps.root_font_size_px if ps != null else ctx.env.font_size
    parent_px := ps.font_size_px if ps != null else ctx.env.font_size
    values := {}
    sources := {}
    for name in keys(winners):
        if _prop.is_custom(name):
            continue
        raw := winners[name][0]
        v := raw
        if _vars.uses_variables(v):
            v = var_scope.resolve(v)
            if _s.trim(v) == "":
                v = "unset"
        lv := _s.lower(_s.trim(v))
        if lv == "inherit" or ((lv == "unset" or lv == "revert" or lv == "revert-layer") and _prop.is_inherited(name)):
            if ps != null:
                pv := ps.get(name)
                if pv != null:
                    values[name] = pv
                    sources[name] = "inherited"
            continue
        if lv == "initial" or lv == "unset" or lv == "revert" or lv == "revert-layer":
            iv := _prop.initial_value(name)
            if iv != null:
                values[name] = iv
            sources[name] = "initial"
            continue
        values[name] = v
        sources[name] = winners[name][1]
    if ps != null:
        for name in keys(ps.values):
            if not (name in values) and _prop.is_inherited(name):
                values[name] = ps.values[name]
                sources[name] = "inherited"
    fs := parent_px
    if "font-size" in values and sources["font-size"] != "inherited":
        fs = _font_px(values["font-size"], parent_px, root_px, ctx.env)
    is_root := adapter.parent(element) == null
    if is_root:
        root_px = fs
    st := ComputedStyle(values, resolved_custom, ps, fs, root_px)
    if is_root and "font-size" in values:
        st.root_font_size_px = fs
    st.sources = sources
    return st

# Styles calculés de tout un arbre (parents d'abord) : liste de (élément, ComputedStyle) en ordre de document.
func compute_all(root, sheets, env=null, containers=null):
    ctx := _Ctx(env, containers)
    adapter := _sel.adapter_for(root)
    out := []
    start := []
    if adapter.is_element(root):
        start = [root]
    else:
        start = adapter.children(root)
    for el in start:
        _compute_tree(el, sheets, ctx, null, adapter, out)
    return out

func _compute_tree(el, sheets, ctx, ps, adapter, out):
    st := _compute_one(el, sheets, ctx, ps, null, adapter)
    append(out, (el, st))
    for c in adapter.children(el):
        _compute_tree(c, sheets, ctx, st, adapter, out)

# ---------------------------------------------------------------- feuille de l'agent utilisateur

const _BLOCKS := "html, body, address, blockquote, center, dialog, div, figure, figcaption, footer, form, header, hr, legend, listing, main, p, plaintext, pre, search, xmp, article, aside, h1, h2, h3, h4, h5, h6, hgroup, nav, section, dir, dd, dl, dt, menu, ol, ul, fieldset, details, summary"

# Feuille par défaut simplifiée (affichage, marges, titres, emphase) d'un navigateur.
func default_stylesheet():
    sh := Stylesheet(null, "user-agent")
    sh.rule("head, script, style, template, title, meta, link, base, noscript, [hidden], area, datalist, param, source, track", {"display": "none"})
    sh.rule(_BLOCKS, {"display": "block"})
    sh.rule("li", {"display": "list-item"})
    sh.rule("summary", {"display": "list-item"})
    sh.rule("table", {"display": "table", "border-collapse": "separate", "border-spacing": "2px"})
    sh.rule("thead", {"display": "table-header-group"})
    sh.rule("tbody", {"display": "table-row-group"})
    sh.rule("tfoot", {"display": "table-footer-group"})
    sh.rule("tr", {"display": "table-row"})
    sh.rule("td, th", {"display": "table-cell", "padding": "1px"})
    sh.rule("th", {"font-weight": "bold", "text-align": "center"})
    sh.rule("caption", {"display": "table-caption", "text-align": "center"})
    sh.rule("img, video, canvas, input, button, select, textarea, iframe, svg", {"display": "inline-block"})
    sh.rule("body", {"margin": "8px"})
    sh.rule("p, blockquote, figure, dl, ol, ul, pre, menu, fieldset", {"margin-top": "1em", "margin-bottom": "1em"})
    sh.rule("blockquote, figure", {"margin-left": "40px", "margin-right": "40px"})
    sh.rule("ol, ul, menu", {"padding-left": "40px"})
    sh.rule("ol", {"list-style-type": "decimal"})
    sh.rule("ul, menu", {"list-style-type": "disc"})
    sh.rule("h1", {"font-size": "2em", "margin-top": "0.67em", "margin-bottom": "0.67em", "font-weight": "bold"})
    sh.rule("h2", {"font-size": "1.5em", "margin-top": "0.83em", "margin-bottom": "0.83em", "font-weight": "bold"})
    sh.rule("h3", {"font-size": "1.17em", "margin-top": "1em", "margin-bottom": "1em", "font-weight": "bold"})
    sh.rule("h4", {"font-size": "1em", "margin-top": "1.33em", "margin-bottom": "1.33em", "font-weight": "bold"})
    sh.rule("h5", {"font-size": "0.83em", "margin-top": "1.67em", "margin-bottom": "1.67em", "font-weight": "bold"})
    sh.rule("h6", {"font-size": "0.67em", "margin-top": "2.33em", "margin-bottom": "2.33em", "font-weight": "bold"})
    sh.rule("b, strong", {"font-weight": "bold"})
    sh.rule("i, em, cite, var, dfn, address", {"font-style": "italic"})
    sh.rule("pre, code, kbd, samp, tt", {"font-family": "monospace"})
    sh.rule("pre", {"white-space": "pre"})
    sh.rule("small", {"font-size": "smaller"})
    sh.rule("big", {"font-size": "larger"})
    sh.rule("sub", {"vertical-align": "sub", "font-size": "smaller"})
    sh.rule("sup", {"vertical-align": "super", "font-size": "smaller"})
    sh.rule("u, ins", {"text-decoration": "underline"})
    sh.rule("s, strike, del", {"text-decoration": "line-through"})
    sh.rule("a:any-link", {"color": "linktext", "text-decoration": "underline", "cursor": "pointer"})
    sh.rule("mark", {"background-color": "mark", "color": "marktext"})
    sh.rule("hr", {"border-style": "inset", "border-width": "1px", "margin-top": "0.5em", "margin-bottom": "0.5em"})
    sh.rule("center", {"text-align": "center"})
    sh.rule("dialog:not([open])", {"display": "none"})
    return sh
