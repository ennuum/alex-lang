# ALEX STANDARD LIBRARY — web.css.css_parser
#
# Analyse d'une feuille de style complète (CSS Syntax 3) vers un web.css.stylesheet.Stylesheet : règles,
# at-rules (blocs de règles, blocs de déclarations, instructions), @keyframes, imbrication CSS (règles et
# @media dans une règle), avec RÉCUPÉRATION D'ERREURS comme un navigateur : une déclaration invalide est
# ignorée, une règle mal formée est sautée, un bloc non fermé est clos en fin de texte. Les problèmes sont
# rapportés dans une liste d'Issue (web.css.css_errors) avec leur ligne ; strict=true lève à la première erreur.
#
#   use web.css.css_parser as cp
#   sheet := cp.parse("a { color: red; &:hover { color: blue } } @media print { nav { display: none } }")
#   len(sheet.rules)                         # 2
#   issues := []
#   cp.parse("p { color: ; margin: 0 } }", issues)
#   issues[0].message                        # déclaration invalide « color: »
#   cp.parse_rule("h1, h2 { font-weight: 600 }").selector     # h1, h2
#   cp.parse_declarations("color: red; margin: 0")             # liste de Declaration
#   cp.parse("@import url(a.css) screen; @layer base;").imports()
#
# Erreurs : CssParseError (strict=true uniquement).

from core use len, type
from collections use append
use string as _s
use web.css.css_errors as _err
use web.css.value as _value
use web.css.declaration as _decl
use web.css.css_rule as _rule
use web.css.at_rule as _at
use web.css.keyframes as _kf
use web.css.stylesheet as _sheet
use web.css.selector_parser as _sp

const _KNOWN_AT := ["media", "supports", "container", "layer", "scope", "starting-style", "document", "-moz-document", "font-face", "page", "property", "counter-style", "font-palette-values", "viewport", "font-feature-values", "view-transition", "position-try", "import", "charset", "namespace", "keyframes", "-webkit-keyframes", "-moz-keyframes", "-o-keyframes", "top-left-corner", "top-left", "top-center", "top-right", "top-right-corner", "bottom-left-corner", "bottom-left", "bottom-center", "bottom-right", "bottom-right-corner", "left-top", "left-middle", "left-bottom", "right-top", "right-middle", "right-bottom"]

class _Parser:
    func init(text, issues, strict):
        self.tokens = []
        for t in _value.tokenize(str(text)):
            if t.kind != _value.COMMENT:
                append(self.tokens, t)
        self.n = len(self.tokens)
        self.i = 0
        self.issues = issues
        self.strict = strict
        self.seen_rule = false

    func issue(code, message, line, level="error"):
        if self.strict and level == "error":
            _err.parse_error("css_parser", "ligne " + str(line) + " : " + message)
        if self.issues != null:
            append(self.issues, _err.Issue(level, code, message, null, line))

    func peek():
        if self.i < self.n:
            return self.tokens[self.i]
        return null

    func line():
        t := self.peek()
        if t != null:
            return t.line
        if self.n > 0:
            return self.tokens[self.n - 1].line
        return 1

    func skip_ws():
        while self.i < self.n and self.tokens[self.i].kind == _value.WHITESPACE:
            self.i += 1

    # Jetons jusqu'à un arrêt de profondeur 0 (« ; », « { », « } » selon stops), parenthèses équilibrées.
    func collect(stop_semicolon, stop_open, stop_close):
        out := []
        depth := 0
        while self.i < self.n:
            t := self.tokens[self.i]
            k := t.kind
            if depth == 0:
                if stop_semicolon and k == _value.SEMICOLON:
                    return out
                if stop_open and k == _value.OPEN and t.value == "{":
                    return out
                if stop_close and k == _value.CLOSE and t.value == "}":
                    return out
            if k == _value.FUNCTION or k == _value.OPEN:
                depth += 1
            elif k == _value.CLOSE:
                if depth > 0:
                    depth -= 1
            append(out, t)
            self.i += 1
        return out

    # Saute un bloc « { … } » (le « { » courant compris).
    func skip_block():
        depth := 0
        while self.i < self.n:
            t := self.tokens[self.i]
            self.i += 1
            if t.kind == _value.OPEN and t.value == "{":
                depth += 1
            elif t.kind == _value.CLOSE and t.value == "}":
                depth -= 1
                if depth <= 0:
                    return

    func expect_open():
        t := self.peek()
        if t != null and t.kind == _value.OPEN and t.value == "{":
            self.i += 1
            return true
        return false

    # Consomme le « } » fermant (ou signale un bloc non fermé).
    func close_block(start_line, what):
        t := self.peek()
        if t != null and t.kind == _value.CLOSE and t.value == "}":
            self.i += 1
            return
        self.issue("unclosed-block", "bloc « " + what + " » non fermé (ouvert ligne " + str(start_line) + ")", start_line)

    # ------------------------------------------------------------ niveau supérieur

    func stylesheet():
        rules := []
        while true:
            self.skip_ws()
            t := self.peek()
            if t == null:
                break
            if t.kind == _value.CDO or t.kind == _value.CDC or t.kind == _value.SEMICOLON:
                self.i += 1
                continue
            if t.kind == _value.CLOSE:
                self.issue("unexpected-token", "« " + t.value + " » inattendu", t.line)
                self.i += 1
                continue
            r := null
            if t.kind == _value.AT:
                r = self.at_rule(true, false)
            else:
                r = self.qualified(false)
            if r != null:
                append(rules, r)
        return rules

    # ------------------------------------------------------------ règles

    func qualified(nested):
        line := self.line()
        prelude := self.collect(true, true, nested)
        t := self.peek()
        text := _s.trim(_value.serialize(prelude))
        if t == null:
            if text != "":
                self.issue("unexpected-eof", "règle « " + text + " » sans bloc", line)
            return null
        if t.kind == _value.SEMICOLON or (t.kind == _value.CLOSE and t.value == "}"):
            if t.kind == _value.SEMICOLON:
                self.i += 1
            self.issue("missing-block", "« { » attendu après « " + text + " »", line)
            return null
        self.i += 1
        self.seen_rule = true
        r := _rule.StyleRule(text, [], line)
        bad_selector := false
        if text == "":
            self.issue("invalid-selector", "sélecteur vide", line)
            bad_selector = true
        else:
            try:
                _sp.parse(text, nested)
            catch e:
                self.issue("invalid-selector", "sélecteur invalide « " + text + " »", line)
                bad_selector = true
        self.block_contents(r, line, text)
        if bad_selector:
            return null
        return r

    # Contenu d'un bloc de règle : déclarations et règles imbriquées.
    func block_contents(owner, start_line, what):
        while true:
            self.skip_ws()
            t := self.peek()
            if t == null:
                self.issue("unclosed-block", "bloc « " + what + " » non fermé (ouvert ligne " + str(start_line) + ")", start_line)
                return
            if t.kind == _value.CLOSE and t.value == "}":
                self.i += 1
                return
            if t.kind == _value.SEMICOLON:
                self.i += 1
                continue
            if t.kind == _value.AT:
                r := self.at_rule(false, true)
                if r != null:
                    if owner.kind == "style":
                        owner.add_child(r)
                    else:
                        owner.add(r)
                continue
            if self.looks_like_rule():
                r := self.qualified(true)
                if r != null:
                    if owner.kind == "style":
                        owner.add_child(r)
                    else:
                        owner.add(r)
                continue
            self.declaration_into(owner.declarations)

    # Une règle imbriquée commence ici si un « { » de profondeur 0 précède le prochain « ; » / « } ».
    func looks_like_rule():
        t := self.peek()
        # « nom: … » sans « { » avant « ; » est une déclaration ; « a:hover { » est une règle.
        if t.kind == _value.IDENT and _s.starts_with(t.value, "--"):
            return false
        j := self.i
        depth := 0
        while j < self.n:
            x := self.tokens[j]
            k := x.kind
            if depth == 0:
                if k == _value.SEMICOLON or (k == _value.CLOSE and x.value == "}"):
                    return false
                if k == _value.OPEN and x.value == "{":
                    return true
            if k == _value.FUNCTION or (k == _value.OPEN and x.value != "{"):
                depth += 1
            elif k == _value.CLOSE and x.value != "}":
                if depth > 0:
                    depth -= 1
            j += 1
        return false

    func declaration_into(target):
        line := self.line()
        toks := self.collect(true, false, true)
        t := self.peek()
        if t != null and t.kind == _value.SEMICOLON:
            self.i += 1
        text := _s.trim(_value.serialize(toks))
        if text == "":
            return
        d := _decl.parse(text, false)
        if d == null:
            self.issue("invalid-declaration", "déclaration invalide « " + text + " »", line)
            return
        d.line = line
        append(target, d)

    # Liste de déclarations seule (corps de @font-face, @page...) ; les at-rules de marge (@top-left) sont gardées.
    func declaration_block(owner, start_line):
        while true:
            self.skip_ws()
            t := self.peek()
            if t == null:
                self.issue("unclosed-block", "bloc « @" + owner.name + " » non fermé (ouvert ligne " + str(start_line) + ")", start_line)
                return
            if t.kind == _value.CLOSE and t.value == "}":
                self.i += 1
                return
            if t.kind == _value.SEMICOLON:
                self.i += 1
                continue
            if t.kind == _value.AT:
                r := self.at_rule(false, false)
                if r != null:
                    owner.add(r)
                continue
            self.declaration_into(owner.declarations)

    # ------------------------------------------------------------ at-rules

    func at_rule(top, in_style):
        at := self.peek()
        self.i += 1
        line := at.line
        name := _s.lower(at.value)
        prelude_toks := self.collect(true, true, not top)
        prelude := _s.trim(_value.serialize(prelude_toks))
        t := self.peek()
        has_block := t != null and t.kind == _value.OPEN and t.value == "{"
        if not has_block and t != null and t.kind == _value.SEMICOLON:
            self.i += 1
        if not (name in _KNOWN_AT):
            self.issue("unknown-at-rule", "at-rule inconnue « @" + name + " »", line, "warning")
        if name == "charset" or name == "import" or name == "namespace":
            if has_block:
                self.issue("unexpected-block", "« @" + name + " » n'accepte pas de bloc", line)
                self.skip_block()
                return null
            if not top:
                self.issue("misplaced-at-rule", "« @" + name + " » doit être au niveau supérieur", line)
                return null
            if name != "charset" and self.seen_rule:
                self.issue("misplaced-at-rule", "« @" + name + " » après des règles est ignorée", line)
                return null
            if prelude == "":
                self.issue("invalid-at-rule", "« @" + name + " » sans paramètre", line)
                return null
            return _at.AtRule(name, prelude, "statement", line)
        if name == "layer" and not has_block:
            if prelude == "":
                self.issue("invalid-at-rule", "« @layer; » sans nom", line)
                return null
            return _at.AtRule("layer", prelude, "statement", line)
        if not has_block:
            if t == null:
                self.issue("unexpected-eof", "« @" + name + " » inachevée", line)
            elif t.kind == _value.CLOSE:
                self.issue("missing-block", "bloc attendu après « @" + name + " »", line)
            else:
                self.issue("missing-block", "bloc attendu après « @" + name + " »", line)
            return null
        self.i += 1
        self.seen_rule = true
        if _s.ends_with(name, "keyframes"):
            return self.keyframes(name, prelude, line)
        kind := _at.body_kind(name)
        r := _at.AtRule(name, prelude, kind, line)
        if kind == "declarations":
            self.declaration_block(r, line)
        elif in_style:
            self.block_contents(r, line, "@" + name)
        else:
            self.rule_list(r, line)
        return r

    # Bloc de règles (corps de @media, @supports, @layer...) hors d'une règle de style.
    func rule_list(owner, start_line):
        while true:
            self.skip_ws()
            t := self.peek()
            if t == null:
                self.issue("unclosed-block", "bloc « @" + owner.name + " » non fermé (ouvert ligne " + str(start_line) + ")", start_line)
                return
            if t.kind == _value.CLOSE and t.value == "}":
                self.i += 1
                return
            if t.kind == _value.SEMICOLON or t.kind == _value.CDO or t.kind == _value.CDC:
                self.i += 1
                continue
            r := null
            if t.kind == _value.AT:
                r = self.at_rule(false, false)
            else:
                r = self.qualified(false)
            if r != null:
                owner.add(r)

    func keyframes(name, prelude, line):
        prefix := ""
        if _s.starts_with(name, "-"):
            prefix = name[0:len(name) - 9]
        nm := prelude
        if _s.starts_with(nm, "\"") and _s.ends_with(nm, "\"") and len(nm) >= 2:
            nm = nm[1:len(nm) - 1]
        k := _kf.Keyframes(nm, null, prefix)
        k.line = line
        if nm == "":
            self.issue("invalid-at-rule", "@keyframes sans nom", line)
        while true:
            self.skip_ws()
            t := self.peek()
            if t == null:
                self.issue("unclosed-block", "bloc « @keyframes » non fermé (ouvert ligne " + str(line) + ")", line)
                return k
            if t.kind == _value.CLOSE and t.value == "}":
                self.i += 1
                return k
            if t.kind == _value.SEMICOLON:
                self.i += 1
                continue
            fline := self.line()
            sel := _s.trim(_value.serialize(self.collect(true, true, true)))
            if not self.expect_open():
                self.issue("missing-block", "bloc attendu après l'image clé « " + sel + " »", fline)
                t2 := self.peek()
                if t2 != null and t2.kind == _value.SEMICOLON:
                    self.i += 1
                continue
            holder := _rule.StyleRule("x", [])
            self.block_contents(holder, fline, sel)
            ok := true
            try:
                k.frame(sel, holder.declarations)
            catch e:
                ok = false
            if not ok:
                self.issue("invalid-keyframe", "sélecteur d'image clé invalide « " + sel + " »", fline)

# Feuille de style depuis du texte ; issues : liste qui reçoit les Issue ; strict : lève à la première erreur.
func parse(text, issues=null, strict=false, origin="author", href=null):
    p := _Parser(text, issues, strict)
    sh := _sheet.Stylesheet(null, origin, href)
    for r in p.stylesheet():
        sh.add(r)
    return sh

# Règles (liste) sans feuille.
func parse_rules(text, issues=null, strict=false):
    return _Parser(text, issues, strict).stylesheet()

# Une seule règle (« sélecteur { … } » ou at-rule) ; CssParseError s'il n'y en a pas exactement une.
func parse_rule(text, issues=null):
    rules := _Parser(text, issues, false).stylesheet()
    if len(rules) != 1:
        _err.parse_error("css_parser.parse_rule", "une règle attendue, " + str(len(rules)) + " trouvée(s)")
    return rules[0]

# Déclarations d'un bloc ou d'un attribut style (sans accolades).
func parse_declarations(text, issues=null, strict=false):
    p := _Parser(text, issues, strict)
    holder := _rule.StyleRule("x", [])
    while true:
        p.skip_ws()
        t := p.peek()
        if t == null:
            break
        if t.kind == _value.SEMICOLON:
            p.i += 1
            continue
        if t.kind == _value.CLOSE and t.value == "}":
            p.issue("unexpected-token", "« } » inattendu", t.line)
            p.i += 1
            continue
        p.declaration_into(holder.declarations)
    return holder.declarations

# Liste de problèmes d'un texte CSS (erreurs de syntaxe uniquement ; voir web.css.css_validate pour le reste).
func check(text):
    issues := []
    parse(text, issues)
    return issues

func is_valid(text):
    for i in check(text):
        if i.is_error():
            return false
    return true
