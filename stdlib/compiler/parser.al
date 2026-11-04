# ALEX STANDARD LIBRARY — compiler.parser
#
# Analyseur syntaxique d'ALEX écrit en ALEX (descente récursive) : jetons de compiler.lexer -> arbre de
# compiler.ast. Même grammaire et mêmes priorités que le compilateur natif (src/Parser.cpp) : déclarations
# (func / async func / décorateurs / fonctions fléchées, class / struct / interface / enum, const), imports
# (use, from ... use), if / elif / else, while / for (+ else), try / catch / finally, match (motifs littéraux,
# intervalles, listes, tuples, variantes d'enum, gardes), with, assert, del, pass, extend, déstructuration,
# affectations composées ; expressions : lambdas (x => e, (a, b) => e, func(a) => e), conditionnelle x if c
# else y, intervalles a..b, or / and / not, comparaisons chaînées, in / not in, opérateurs binaires et unaires,
# await, appels (arguments nommés, *étalement), membres, index, tranches a[i:j:k], propagation « ? »,
# littéraux de liste / tuple / dict / ensemble, compréhensions, f-strings.
#
#   use compiler.parser as ps
#   use compiler.ast as ast
#   prog := ps.parse("func carre(x) => x * x\nprint(carre(4))\n", "demo.al")
#   print(ast.dump(prog))
#   e := ps.parse_expression("a + b * 2")         # (Binary + (Name a) (Binary * (Name b) (Literal 2)))
#   r := ps.try_parse(source, "f.al")             # [programme ou null, liste de diagnostics]
#
# L'arbre n'est pas désucré : voir compiler.ast pour les genres de nœuds.
# Erreurs : ParseError (« fichier:ligne:col: message »), LexError (venue du lexer).

from core use len, type
from collections use append
use string as _s
use compiler.lexer as _lx
use compiler.ast as _ast
use compiler.diagnostics as _dg

const COMPOUND := {"PLUS_EQ": "+", "MINUS_EQ": "-", "STAR_EQ": "*", "SLASH_EQ": "/", "SLASH_SLASH_EQ": "//",
    "PERCENT_EQ": "%", "STAR_STAR_EQ": "**", "AMP_EQ": "&", "PIPE_EQ": "|", "CARET_EQ": "^", "LT_LT_EQ": "<<",
    "GT_GT_EQ": ">>"}
const COMPARE := {"EQ_EQ": "==", "BANG_EQ": "!=", "LT": "<", "LT_EQ": "<=", "GT": ">", "GT_EQ": ">="}
const LITERALS := ["INTEGER", "FLOAT", "STRING", "CHAR", "KW_TRUE", "KW_FALSE", "KW_NULL"]

func N(kind, tok, fields):
    return _ast.Node(kind, tok.line, tok.column, fields)

class Parser:
    func init(tokens, file="<source>"):
        self.toks = [t for t in tokens if t.type != "COMMENT"]
        self.file = file
        self.pos = 0

    # ---- primitives ----
    func peek(k=0):
        i := self.pos + k
        if i >= len(self.toks):
            return self.toks[len(self.toks) - 1]
        return self.toks[i]

    func check(t):
        return self.peek().type == t

    func advance():
        t := self.toks[self.pos]
        if self.pos < len(self.toks) - 1:
            self.pos += 1
        return t

    func accept(t):
        if self.check(t):
            self.advance()
            return true
        return false

    func expect(t, msg):
        if not self.check(t):
            self.error(self.peek(), msg)
        return self.advance()

    func error(tok, msg):
        found := tok.type
        if tok.lexeme != "":
            found = "'" + tok.lexeme + "'"
        raise("ParseError", self.file + ":" + str(tok.line) + ":" + str(tok.column) + ": " + msg + " (trouvé " + found + ")")

    func at_end():
        return self.check("END_OF_FILE")

    # ---- programme / blocs ----
    func parse_program():
        body := []
        while not self.at_end():
            append(body, self.statement())
        return _ast.Node("Program", 1, 1, {"body": body})

    func block_body():
        self.expect("NEWLINE", "attendu un retour à la ligne avant un bloc indenté")
        self.expect("INDENT", "attendu une indentation pour ouvrir le bloc")
        out := []
        while not self.check("DEDENT") and not self.at_end():
            append(out, self.statement())
        self.expect("DEDENT", "attendu une dés-indentation pour fermer le bloc")
        return out

    func colon_block():
        self.expect("COLON", "attendu ':' avant le bloc")
        return self.block_body()

    # ---- instructions ----
    func statement():
        t := self.peek()
        k := t.type
        if k == "AT":
            decorators := []
            while self.accept("AT"):
                append(decorators, self.expression())
                self.expect("NEWLINE", "attendu une fin de ligne après un décorateur")
            if not self.check("KW_FUNC") and not self.check("KW_ASYNC"):
                self.error(self.peek(), "un décorateur doit être suivi d'une déclaration 'func'")
            fn := self.statement()
            if fn.kind != "Func":
                self.error(t, "un décorateur ne s'applique qu'à une fonction")
            fn.decorators = decorators
            return fn
        if k == "KW_USE" or k == "KW_FROM":
            return self.import_stmt()
        if k == "KW_ASYNC":
            if self.peek(1).type != "KW_FUNC":
                self.error(t, "'async' doit être immédiatement suivi de 'func'")
            self.advance()
            return self.func_decl(true)
        if k == "KW_FUNC":
            if self.peek(1).type == "LPAREN":
                return self.simple_statement()
            return self.func_decl(false)
        if k == "KW_STRUCT":
            self.advance()
            nm := self.expect("IDENTIFIER", "attendu un nom de struct").lexeme
            return N("Struct", t, {"name": nm, "body": self.colon_block()})
        if k == "KW_CLASS":
            return self.class_decl()
        if k == "KW_INTERFACE":
            self.advance()
            nm := self.expect("IDENTIFIER", "attendu un nom d'interface").lexeme
            return N("Interface", t, {"name": nm, "body": self.colon_block()})
        if k == "KW_ENUM":
            return self.enum_decl()
        if k == "KW_CONST":
            self.advance()
            nm := self.expect("IDENTIFIER", "attendu un nom de constante après 'const'").lexeme
            ty := null
            if self.accept("COLON"):
                ty = self.type_ref()
            self.expect("COLON_EQ", "attendu ':=' après le nom de la constante")
            v := self.expression()
            self.expect("NEWLINE", "attendu une fin de ligne après la déclaration de constante")
            return N("Const", t, {"name": nm, "type": ty, "value": v})
        if k == "KW_IF":
            return self.if_stmt()
        if k == "KW_WHILE":
            self.advance()
            c := self.expression()
            body := self.colon_block()
            eb := null
            if self.accept("KW_ELSE"):
                eb = self.colon_block()
            return N("While", t, {"cond": c, "body": body, "else_body": eb})
        if k == "KW_FOR":
            return self.for_stmt()
        if k == "KW_TRY":
            return self.try_stmt()
        if k == "KW_MATCH":
            return self.match_stmt()
        if k == "KW_BREAK":
            self.advance()
            self.expect("NEWLINE", "attendu une fin de ligne après 'break'")
            return N("Break", t, {})
        if k == "KW_CONTINUE":
            self.advance()
            self.expect("NEWLINE", "attendu une fin de ligne après 'continue'")
            return N("Continue", t, {})
        if k == "KW_RETURN":
            self.advance()
            v := null
            if not self.check("NEWLINE"):
                v = self.expr_or_tuple()
            self.expect("NEWLINE", "attendu une fin de ligne après 'return'")
            return N("Return", t, {"value": v})
        return self.simple_statement()

    func word_token(t):
        lx := t.lexeme
        if lx == "" or not (_lx._is_alpha(lx[0])):
            return false
        for c in lx:
            if not _lx._is_alnum(c):
                return false
        return true

    func module_path():
        parts := []
        kw_last := false
        if not self.check("IDENTIFIER") and self.word_token(self.peek()) and not self.check("NEWLINE"):
            append(parts, self.advance().lexeme)
            kw_last = true
        else:
            append(parts, self.expect("IDENTIFIER", "attendu un nom de module").lexeme)
        while self.accept("DOT"):
            if not self.check("IDENTIFIER") and self.word_token(self.peek()):
                append(parts, self.advance().lexeme)
                kw_last = true
                continue
            append(parts, self.expect("IDENTIFIER", "attendu un segment de chemin de module après '.'").lexeme)
            kw_last = false
        return [parts, kw_last]

    func import_stmt():
        t := self.peek()
        if self.accept("KW_USE"):
            mp := self.module_path()
            alias := null
            if self.accept("KW_AS"):
                alias = self.expect("IDENTIFIER", "attendu un identifiant après 'as'").lexeme
            elif mp[1]:
                self.error(self.peek(), "module '" + mp[0][len(mp[0]) - 1] + "' : mot-clé du langage, un alias est requis (use ... as nom)")
            self.expect("NEWLINE", "attendu une fin de ligne après l'instruction 'use'")
            return N("Use", t, {"path": mp[0], "alias": alias})
        self.expect("KW_FROM", "attendu 'use' ou 'from'")
        mp := self.module_path()
        self.expect("KW_USE", "attendu 'use' après le chemin de module dans une instruction 'from'")
        names := [self.expect("IDENTIFIER", "attendu au moins un identifiant importé").lexeme]
        while self.accept("COMMA"):
            append(names, self.expect("IDENTIFIER", "attendu un identifiant après ','").lexeme)
        self.expect("NEWLINE", "attendu une fin de ligne après l'instruction 'from ... use'")
        return N("FromUse", t, {"path": mp[0], "names": names})

    func type_ref():
        t := self.peek()
        nm := null
        args := []
        if self.accept("KW_NULL"):
            nm = "null"
        elif self.accept("KW_FUNC"):
            nm = "func"
            self.expect("LPAREN", "attendu '(' après 'func' dans un type")
            if not self.check("RPAREN"):
                append(args, self.type_ref())
                while self.accept("COMMA"):
                    append(args, self.type_ref())
            self.expect("RPAREN", "attendu ')' dans un type de fonction")
            if self.accept("THIN_ARROW"):
                append(args, self.type_ref())
            else:
                append(args, N("TypeRef", t, {"name": "any", "args": [], "nullable": false}))
        else:
            nm = self.expect("IDENTIFIER", "attendu un type").lexeme
            if self.accept("LBRACKET"):
                append(args, self.type_ref())
                while self.accept("COMMA"):
                    append(args, self.type_ref())
                self.expect("RBRACKET", "attendu ']' après les paramètres du type")
        nullable := self.accept("QUESTION")
        return N("TypeRef", t, {"name": nm, "args": args, "nullable": nullable})

    func params():
        out := []
        if self.check("RPAREN"):
            return out
        while true:
            rest := self.accept("STAR")
            nt := self.expect("IDENTIFIER", "attendu un nom de paramètre")
            ty := null
            dv := null
            if self.accept("COLON"):
                ty = self.type_ref()
            if self.accept("EQ"):
                if rest:
                    self.error(nt, "un paramètre variadique '*" + nt.lexeme + "' ne peut pas avoir de valeur par défaut")
                dv = self.expression()
            append(out, N("Param", nt, {"name": nt.lexeme, "type": ty, "default": dv, "rest": rest}))
            if not self.accept("COMMA"):
                break
            if rest and not self.check("RPAREN"):
                self.error(self.peek(), "le paramètre variadique doit être le dernier")
            if self.check("RPAREN"):
                break
        return out

    func arguments():
        out := []
        if self.check("RPAREN"):
            return out
        while true:
            t := self.peek()
            if self.check("STAR"):
                self.advance()
                append(out, N("Arg", t, {"name": null, "value": N("Spread", t, {"value": self.expression()})}))
            elif self.check("IDENTIFIER") and self.peek(1).type == "EQ":
                nm := self.advance().lexeme
                self.advance()
                append(out, N("Arg", t, {"name": nm, "value": self.expression()}))
            else:
                append(out, N("Arg", t, {"name": null, "value": self.expression()}))
            if not self.accept("COMMA"):
                break
            if self.check("RPAREN"):
                break
        return out

    func func_decl(is_async):
        ft := self.expect("KW_FUNC", "attendu 'func'")
        nm := self.expect("IDENTIFIER", "attendu un nom de fonction après 'func'").lexeme
        self.expect("LPAREN", "attendu '(' après le nom de la fonction")
        ps := self.params()
        self.expect("RPAREN", "attendu ')' après la liste de paramètres")
        rt := null
        if self.accept("THIN_ARROW"):
            rt = self.type_ref()
        short := false
        body := null
        if self.accept("ARROW"):
            et := self.peek()
            v := self.expression()
            self.expect("NEWLINE", "attendu une fin de ligne après le corps d'une fonction fléchée '=>'")
            body = [N("Return", et, {"value": v})]
            short = true
        elif self.check("NEWLINE"):
            self.advance()
            body = []
        else:
            body = self.colon_block()
        return N("Func", ft, {"name": nm, "params": ps, "ret_type": rt, "body": body, "is_async": is_async,
                              "decorators": [], "short": short, "extends_type": null})

    func class_decl():
        t := self.expect("KW_CLASS", "attendu 'class'")
        nm := self.expect("IDENTIFIER", "attendu un nom de classe").lexeme
        base := null
        if self.accept("KW_EXTENDS"):
            base = self.expect("IDENTIFIER", "attendu un nom de classe après 'extends'").lexeme
        ifs := []
        if self.check("IDENTIFIER") and self.peek().lexeme == "implements":
            self.advance()
            append(ifs, self.expect("IDENTIFIER", "attendu un nom d'interface après 'implements'").lexeme)
            while self.accept("COMMA"):
                append(ifs, self.expect("IDENTIFIER", "attendu un nom d'interface après ','").lexeme)
        return N("Class", t, {"name": nm, "base": base, "interfaces": ifs, "body": self.colon_block()})

    func enum_decl():
        t := self.expect("KW_ENUM", "attendu 'enum'")
        nm := self.expect("IDENTIFIER", "attendu un nom d'enum").lexeme
        self.expect("COLON", "attendu ':' après le nom de l'enum")
        self.expect("NEWLINE", "attendu une fin de ligne avant les membres de l'enum")
        self.expect("INDENT", "attendu une indentation pour les membres de l'enum")
        members := []
        while not self.check("DEDENT") and not self.at_end():
            mt := self.expect("IDENTIFIER", "attendu un nom de membre d'enum")
            fields := []
            if self.accept("LPAREN"):
                if not self.check("RPAREN"):
                    while true:
                        fnm := self.expect("IDENTIFIER", "attendu un nom de champ dans la variante d'enum").lexeme
                        ft := null
                        if self.accept("COLON"):
                            ft = self.type_ref()
                        append(fields, N("Param", mt, {"name": fnm, "type": ft, "default": null, "rest": false}))
                        if not self.accept("COMMA"):
                            break
                self.expect("RPAREN", "attendu ')' après les champs de la variante d'enum")
            append(members, N("EnumMember", mt, {"name": mt.lexeme, "fields": fields}))
            self.expect("NEWLINE", "attendu une fin de ligne après un membre d'enum")
        self.expect("DEDENT", "attendu une dés-indentation pour fermer l'enum")
        return N("Enum", t, {"name": nm, "members": members})

    func if_stmt():
        t := self.expect("KW_IF", "attendu 'if'")
        c := self.expression()
        then_body := self.colon_block()
        elifs := []
        while self.check("KW_ELIF"):
            et := self.advance()
            ec := self.expression()
            append(elifs, N("Elif", et, {"cond": ec, "body": self.colon_block()}))
        eb := null
        if self.accept("KW_ELSE"):
            eb = self.colon_block()
        return N("If", t, {"cond": c, "then_body": then_body, "elifs": elifs, "else_body": eb})

    func for_stmt():
        t := self.expect("KW_FOR", "attendu 'for'")
        vars := []
        if self.check("STAR") or self.peek(1).type == "COMMA":
            while true:
                star := self.accept("STAR")
                idt := self.expect("IDENTIFIER", "attendu un identifiant dans la cible du 'for'")
                append(vars, N("Target", idt, {"expr": N("Name", idt, {"name": idt.lexeme}), "star": star}))
                if not self.accept("COMMA"):
                    break
        else:
            idt := self.expect("IDENTIFIER", "attendu un identifiant après 'for'")
            append(vars, N("Target", idt, {"expr": N("Name", idt, {"name": idt.lexeme}), "star": false}))
        self.expect("KW_IN", "attendu 'in' dans une boucle for")
        it := self.expression()
        body := self.colon_block()
        eb := null
        if self.accept("KW_ELSE"):
            eb = self.colon_block()
        return N("For", t, {"vars": vars, "iter": it, "body": body, "else_body": eb})

    func try_stmt():
        t := self.expect("KW_TRY", "attendu 'try'")
        body := self.colon_block()
        catches := []
        generic := false
        while self.check("KW_CATCH"):
            ct := self.advance()
            types := []
            nm := null
            if self.check("LPAREN"):
                self.advance()
                append(types, self.expect("IDENTIFIER", "attendu un type d'exception après '('").lexeme)
                while self.accept("COMMA"):
                    append(types, self.expect("IDENTIFIER", "attendu un type d'exception après ','").lexeme)
                self.expect("RPAREN", "attendu ')' après la liste des types d'exception")
                if self.accept("KW_AS"):
                    nm = self.expect("IDENTIFIER", "attendu un nom après 'as'").lexeme
            elif self.check("IDENTIFIER"):
                first := self.advance().lexeme
                if self.check("KW_AS") or self.check("COMMA"):
                    append(types, first)
                    while self.accept("COMMA"):
                        append(types, self.expect("IDENTIFIER", "attendu un type d'exception après ','").lexeme)
                    self.expect("KW_AS", "attendu 'as nom' après les types d'exception (ou parenthèses : catch (A, B):)")
                    nm = self.expect("IDENTIFIER", "attendu un nom après 'as'").lexeme
                else:
                    nm = first
            if generic:
                self.error(ct, "clause 'catch' inatteignable : elle suit une clause 'catch' générique")
            if len(types) == 0:
                generic = true
            append(catches, N("Catch", ct, {"types": types, "name": nm, "body": self.colon_block()}))
        fb := null
        if self.accept("KW_FINALLY"):
            fb = self.colon_block()
        if len(catches) == 0 and fb == null:
            self.error(t, "'try' doit être suivi d'au moins un 'catch' ou d'un 'finally'")
        return N("Try", t, {"body": body, "catches": catches, "finally_body": fb})

    func pattern():
        t := self.peek()
        k := t.type
        if k in LITERALS:
            low := self.literal()
            if self.accept("DOT_DOT"):
                high := self.literal()
                return N("Pattern", t, {"pk": "range", "low": low.value, "high": high.value})
            return N("Pattern", t, {"pk": "literal", "value": low.value})
        if k == "LBRACKET":
            self.advance()
            items := []
            if not self.check("RBRACKET"):
                append(items, self.pattern())
                while self.accept("COMMA"):
                    append(items, self.pattern())
            self.expect("RBRACKET", "attendu ']' pour fermer le motif de liste")
            return N("Pattern", t, {"pk": "list", "items": items})
        if k == "LPAREN":
            self.advance()
            if self.check("RPAREN"):
                self.error(t, "motif vide entre parenthèses non autorisé (ni groupement ni tuple, §16/§22)")
            first := self.pattern()
            if self.accept("RPAREN"):
                return first
            if self.check("COMMA"):
                items := [first]
                while self.accept("COMMA"):
                    append(items, self.pattern())
                self.expect("RPAREN", "attendu ')' pour fermer le motif de tuple")
                return N("Pattern", t, {"pk": "tuple", "items": items})
            self.error(self.peek(), "attendu ',' (motif de tuple) ou ')' (groupement) après le motif")
        if k == "IDENTIFIER":
            self.advance()
            if t.lexeme == "_":
                return N("Pattern", t, {"pk": "wildcard"})
            if not self.check("DOT"):
                return N("Pattern", t, {"pk": "bind", "name": t.lexeme})
            self.advance()
            vt := self.expect("IDENTIFIER", "attendu un nom de variante après '.' dans un motif")
            items := []
            if self.accept("LPAREN"):
                if not self.check("RPAREN"):
                    append(items, self.pattern())
                    while self.accept("COMMA"):
                        append(items, self.pattern())
                self.expect("RPAREN", "attendu ')' après les sous-motifs de la variante")
            return N("Pattern", t, {"pk": "variant", "enum_name": t.lexeme, "variant": vt.lexeme, "items": items})
        self.error(t, "motif de 'match' invalide : attendu un littéral, '_', un identifiant, 'EnumName.Variant', '[...]' ou '(...)'")

    func match_stmt():
        t := self.expect("KW_MATCH", "attendu 'match'")
        subj := self.expression()
        self.expect("COLON", "attendu ':' après l'expression de 'match'")
        self.expect("NEWLINE", "attendu une fin de ligne avant les cas de 'match'")
        self.expect("INDENT", "attendu une indentation pour les cas de 'match'")
        cases := []
        while not self.check("DEDENT") and not self.at_end():
            pt := self.peek()
            p := self.pattern()
            g := null
            if self.accept("KW_IF"):
                g = self.expression()
            self.expect("COLON", "attendu ':' après le motif de 'match'")
            append(cases, N("Case", pt, {"pattern": p, "guard": g, "body": self.block_body()}))
        self.expect("DEDENT", "attendu une dés-indentation pour fermer 'match'")
        return N("Match", t, {"subject": subj, "cases": cases})

    func is_lvalue(e):
        return e.kind == "Name" or e.kind == "Member" or e.kind == "Index"

    func expr_or_tuple():
        t := self.peek()
        first := self.expression()
        if not self.check("COMMA"):
            return first
        items := [first]
        while self.accept("COMMA"):
            if self.check("NEWLINE"):
                break
            append(items, self.element())
        return N("TupleLit", t, {"elements": items})

    func destructure(first, st):
        targets := []
        if first != null:
            append(targets, N("Target", first, {"expr": first, "star": false}))
        else:
            self.target_into(targets)
        while self.accept("COMMA"):
            if self.check("COLON_EQ") or self.check("EQ"):
                break
            self.target_into(targets)
        declare := false
        if self.accept("COLON_EQ"):
            declare = true
        elif not self.accept("EQ"):
            self.error(self.peek(), "attendu ':=' ou '=' après les cibles de la déstructuration")
        for tg in targets:
            if declare and tg.expr.kind != "Name":
                self.error(st, "les cibles de ':=' doivent être des identifiants simples")
            if not declare and not self.is_lvalue(tg.expr):
                self.error(st, "cible de déstructuration invalide : identifiant, accès membre ('.') ou indexage ('[]')")
        v := self.expr_or_tuple()
        self.expect("NEWLINE", "attendu une fin de ligne après la déstructuration")
        nstar := 0
        for tg in targets:
            if tg.star:
                nstar += 1
        if v.kind == "TupleLit" and nstar == 0 and len(v.elements) != len(targets):
            self.error(st, "déstructuration : " + str(len(targets)) + " cible(s) pour " + str(len(v.elements)) + " valeur(s)")
        return N("Destructure", st, {"targets": targets, "value": v, "declare": declare})

    func target_into(targets):
        t := self.peek()
        if self.accept("STAR"):
            idt := self.expect("IDENTIFIER", "attendu un identifiant après '*'")
            append(targets, N("Target", t, {"expr": N("Name", idt, {"name": idt.lexeme}), "star": true}))
        else:
            e := self.expression()
            append(targets, N("Target", e, {"expr": e, "star": false}))

    func contextual(word):
        st := self.peek()
        if st.type != "IDENTIFIER" or st.lexeme != word:
            return false
        nx := self.peek(1).type
        return nx != "EQ" and nx != "COLON_EQ" and nx != "DOT" and nx != "COLON" and nx != "COMMA" and nx != "NEWLINE" and not (nx in COMPOUND)

    func simple_statement():
        st := self.peek()
        if st.type == "IDENTIFIER" and self.peek(1).type == "COLON":
            nm := self.advance().lexeme
            self.advance()
            ty := self.type_ref()
            if self.check("NEWLINE"):
                self.advance()
                return N("VarDecl", st, {"name": nm, "type": ty, "value": null, "declared_only": true})
            self.expect("COLON_EQ", "attendu ':=' après le type de la variable")
            v := self.expression()
            self.expect("NEWLINE", "attendu une fin de ligne après une déclaration de variable")
            return N("VarDecl", st, {"name": nm, "type": ty, "value": v, "declared_only": false})
        if self.contextual("with"):
            self.advance()
            res := self.expression()
            nm := null
            if self.accept("KW_AS"):
                nm = self.expect("IDENTIFIER", "attendu un nom après 'as'").lexeme
            return N("With", st, {"resource": res, "name": nm, "body": self.colon_block()})
        if st.type == "IDENTIFIER" and st.lexeme == "pass" and self.peek(1).type == "NEWLINE":
            self.advance()
            self.advance()
            return N("Pass", st, {})
        if self.contextual("assert"):
            self.advance()
            c := self.expression()
            m := null
            if self.accept("COMMA"):
                m = self.expression()
            self.expect("NEWLINE", "attendu une fin de ligne après 'assert'")
            return N("Assert", st, {"cond": c, "message": m})
        if self.contextual("del"):
            self.advance()
            targets := []
            while true:
                e := self.expression()
                if e.kind != "Index":
                    self.error(st, "'del' ne supprime qu'un élément indexé : del liste[i] ou del dict[clé]")
                append(targets, e)
                if not self.accept("COMMA"):
                    break
            self.expect("NEWLINE", "attendu une fin de ligne après 'del'")
            return N("Del", st, {"targets": targets})
        if st.type == "IDENTIFIER" and st.lexeme == "extend" and self.peek(1).type == "IDENTIFIER" and self.peek(2).type == "COLON":
            self.advance()
            tt := self.advance()
            body := self.colon_block()
            for f in body:
                if f.kind != "Func":
                    self.error(st, "un bloc 'extend' ne contient que des méthodes (func)")
                f.extends_type = tt.lexeme
            if len(body) == 0:
                self.error(tt, "bloc 'extend' vide")
            return N("Extend", st, {"type_name": tt.lexeme, "methods": body})
        if st.type == "STAR":
            return self.destructure(null, st)
        target := self.expression()
        if self.check("COMMA"):
            return self.destructure(target, st)
        if self.check("COLON_EQ"):
            if target.kind != "Name":
                self.error(st, "la partie gauche de ':=' doit être un identifiant simple (§9)")
            self.advance()
            v := self.expr_or_tuple()
            self.expect("NEWLINE", "attendu une fin de ligne après une déclaration de variable")
            return N("VarDecl", st, {"name": target.name, "type": null, "value": v, "declared_only": false})
        if self.check("EQ"):
            if not self.is_lvalue(target):
                self.error(st, "cible d'affectation invalide : seuls un identifiant, un accès membre ('.') ou un indexage ('[]') sont assignables")
            self.advance()
            v := self.expr_or_tuple()
            self.expect("NEWLINE", "attendu une fin de ligne après une affectation")
            return N("Assign", st, {"target": target, "value": v})
        if self.peek().type in COMPOUND:
            if not self.is_lvalue(target):
                self.error(st, "cible d'affectation composée invalide")
            op := COMPOUND[self.advance().type]
            v := self.expression()
            self.expect("NEWLINE", "attendu une fin de ligne après une affectation composée")
            return N("CompoundAssign", st, {"op": op, "target": target, "value": v})
        self.expect("NEWLINE", "attendu une fin de ligne après une instruction-expression")
        return N("ExprStmt", st, {"expr": target})

    # ---- expressions ----
    func expression():
        return self.conditional()

    func element():
        t := self.peek()
        if self.accept("STAR"):
            return N("Spread", t, {"value": self.expression()})
        return self.expression()

    func conditional():
        t := self.peek()
        left := self.range_operand()
        if self.accept("KW_IF"):
            c := self.expression()
            self.expect("KW_ELSE", "attendu 'else' pour compléter l'expression conditionnelle 'x if c else y'")
            e := self.expression()
            return N("Ternary", t, {"cond": c, "then_expr": left, "else_expr": e})
        return left

    func range_operand():
        t := self.peek()
        left := self.logical_or()
        if self.accept("DOT_DOT"):
            right := self.logical_or()
            return N("Range", t, {"start": left, "end": right})
        return left

    func logical_or():
        left := self.logical_and()
        while self.check("KW_OR"):
            t := self.advance()
            left = N("Binary", t, {"op": "or", "left": left, "right": self.logical_and()})
        return left

    func logical_and():
        left := self.not_expr()
        while self.check("KW_AND"):
            t := self.advance()
            left = N("Binary", t, {"op": "and", "left": left, "right": self.not_expr()})
        return left

    func not_expr():
        if self.check("KW_NOT"):
            t := self.advance()
            return N("Unary", t, {"op": "not", "operand": self.not_expr()})
        return self.comparison()

    func is_cmp():
        k := self.peek().type
        return (k in COMPARE) or k == "KW_IN" or (k == "KW_NOT" and self.peek(1).type == "KW_IN")

    func comparison():
        left := self.bit_or()
        result := null
        while self.is_cmp():
            t := self.advance()
            op := null
            if t.type == "KW_IN":
                op = "in"
            elif t.type == "KW_NOT":
                self.advance()
                op = "not in"
            else:
                op = COMPARE[t.type]
            start := self.pos
            right := self.bit_or()
            stop := self.pos
            more := self.is_cmp()
            if more:
                k := start
                while k < stop:
                    if self.toks[k].type == "LPAREN":
                        self.error(self.toks[k], "comparaison chaînée : l'opérande du milieu ne doit pas contenir d'appel ni de parenthèses (utilisez une variable temporaire)")
                    k += 1
            nd := N("Binary", t, {"op": op, "left": left, "right": right})
            if result == null:
                result = nd
            else:
                result = N("Binary", t, {"op": "and", "left": result, "right": nd})
            if not more:
                break
            left = right.copy()
        if result == null:
            return left
        return result

    func binary_level(ops, next):
        left := next()
        while self.peek().type in ops:
            t := self.advance()
            left = N("Binary", t, {"op": ops[t.type], "left": left, "right": next()})
        return left

    func bit_or():
        return self.binary_level({"PIPE": "|"}, () => self.bit_xor())

    func bit_xor():
        return self.binary_level({"CARET": "^"}, () => self.bit_and())

    func bit_and():
        return self.binary_level({"AMP": "&"}, () => self.shift())

    func shift():
        return self.binary_level({"LT_LT": "<<", "GT_GT": ">>"}, () => self.additive())

    func additive():
        return self.binary_level({"PLUS": "+", "MINUS": "-"}, () => self.multiplicative())

    func multiplicative():
        return self.binary_level({"STAR": "*", "SLASH": "/", "SLASH_SLASH": "//", "PERCENT": "%"}, () => self.power())

    func power():
        t := self.peek()
        left := self.unary()
        if self.accept("STAR_STAR"):
            return N("Binary", t, {"op": "**", "left": left, "right": self.power()})
        return left

    func unary():
        t := self.peek()
        ops := {"PLUS": "+", "MINUS": "-", "KW_NOT": "not", "TILDE": "~", "KW_AWAIT": "await"}
        if t.type in ops:
            self.advance()
            return N("Unary", t, {"op": ops[t.type], "operand": self.unary()})
        return self.postfix()

    func postfix():
        e := self.primary()
        while true:
            t := self.peek()
            if self.accept("DOT"):
                mt := self.expect("IDENTIFIER", "attendu un nom de membre après '.'")
                e = N("Member", t, {"object": e, "member": mt.lexeme})
            elif self.accept("LBRACKET"):
                start := null
                if not self.check("COLON"):
                    start = self.expression()
                if self.accept("COLON"):
                    stop := null
                    step := null
                    if not self.check("COLON") and not self.check("RBRACKET"):
                        stop = self.expression()
                    if self.accept("COLON"):
                        if not self.check("RBRACKET"):
                            step = self.expression()
                    self.expect("RBRACKET", "attendu ']' après la tranche")
                    e = N("Slice", t, {"object": e, "start": start, "stop": stop, "step": step})
                    continue
                if start == null:
                    self.error(self.peek(), "expression attendue")
                self.expect("RBRACKET", "attendu ']' après l'index")
                e = N("Index", t, {"object": e, "index": start})
            elif self.accept("LPAREN"):
                args := self.arguments()
                self.expect("RPAREN", "attendu ')' après la liste d'arguments")
                e = N("Call", t, {"callee": e, "args": args})
            elif self.accept("QUESTION"):
                e = N("Propagate", t, {"operand": e})
            else:
                break
        return e

    func literal():
        t := self.advance()
        k := t.type
        if k == "INTEGER":
            return N("Literal", t, {"value": t.value, "lit": "int"})
        if k == "FLOAT":
            return N("Literal", t, {"value": t.value, "lit": "float", "raw": t.lexeme})
        if k == "STRING":
            return N("Literal", t, {"value": t.value, "lit": "str"})
        if k == "CHAR":
            return N("Literal", t, {"value": t.value, "lit": "char"})
        if k == "KW_TRUE":
            return N("Literal", t, {"value": true, "lit": "bool"})
        if k == "KW_FALSE":
            return N("Literal", t, {"value": false, "lit": "bool"})
        if k == "KW_NULL":
            return N("Literal", t, {"value": null, "lit": "null"})
        self.error(t, "littéral attendu")

    func fstring(t):
        content := t.value
        parts := []
        buf := []
        i := 0
        n := len(content)
        while i < n:
            c := content[i]
            if c == '{':
                if len(buf) > 0:
                    append(parts, _s.join("", buf))
                    buf = []
                j := i + 1
                depth := 1
                while j < n and depth > 0:
                    if content[j] == '{':
                        depth += 1
                    elif content[j] == '}':
                        depth -= 1
                        if depth == 0:
                            break
                    j += 1
                text := _s.substring(content, i + 1, j)
                sub := null
                try:
                    sub = Parser(_lx.tokenize(text, self.file), self.file)
                catch e:
                    self.error(t, "expression interpolée invalide dans une f-string : " + e.message)
                ex := null
                try:
                    ex = sub.expression()
                catch e:
                    self.error(t, "expression interpolée invalide dans une f-string")
                if not sub.check("NEWLINE") and not sub.check("END_OF_FILE"):
                    self.error(t, "jetons résiduels après l'expression interpolée d'une f-string")
                append(parts, ex)
                i = j + 1
            else:
                append(buf, str(c))
                i += 1
        if len(buf) > 0:
            append(parts, _s.join("", buf))
        return N("FString", t, {"parts": parts})

    func arrow_ahead():
        if not self.check("LPAREN"):
            return false
        depth := 0
        i := 0
        while true:
            k := self.peek(i).type
            if k == "LPAREN" or k == "LBRACKET" or k == "LBRACE":
                depth += 1
            elif k == "RPAREN" or k == "RBRACKET" or k == "RBRACE":
                depth -= 1
                if depth == 0:
                    return self.peek(i + 1).type == "ARROW"
            elif k == "END_OF_FILE":
                return false
            i += 1

    func lambda_rest(t, ps):
        self.expect("ARROW", "attendu '=>' dans une lambda")
        return N("Lambda", t, {"params": ps, "body": self.expression()})

    func comp_clauses():
        out := []
        while self.check("KW_FOR") or self.check("KW_IF"):
            kw := self.advance()
            if kw.type == "KW_FOR":
                v := self.expect("IDENTIFIER", "attendu un identifiant après 'for' dans une compréhension").lexeme
                if self.check("COMMA"):
                    self.error(self.peek(), "la déstructuration n'est pas supportée dans un 'for' de compréhension")
                self.expect("KW_IN", "attendu 'in' dans une clause 'for' de compréhension")
                append(out, N("CompFor", kw, {"var": v, "iter": self.range_operand()}))
            else:
                append(out, N("CompIf", kw, {"cond": self.logical_or()}))
        return out

    func primary():
        t := self.peek()
        k := t.type
        if k in LITERALS:
            return self.literal()
        if k == "FSTRING":
            return self.fstring(self.advance())
        if k == "KW_FUNC":
            self.advance()
            if not self.check("LPAREN"):
                self.error(self.peek(), "attendu '(' : une fonction anonyme s'écrit func(paramètres) => expression")
            self.advance()
            ps := self.params()
            self.expect("RPAREN", "attendu ')' après la liste de paramètres")
            return self.lambda_rest(t, ps)
        if k == "IDENTIFIER" or k == "KW_SELF" or k == "KW_SUPER":
            if k == "IDENTIFIER" and self.peek(1).type == "ARROW":
                self.advance()
                return self.lambda_rest(t, [N("Param", t, {"name": t.lexeme, "type": null, "default": null, "rest": false})])
            self.advance()
            return N("Name", t, {"name": t.lexeme})
        if k == "LPAREN":
            if self.arrow_ahead():
                self.advance()
                ps := self.params()
                self.expect("RPAREN", "attendu ')' après la liste de paramètres")
                return self.lambda_rest(t, ps)
            self.advance()
            if self.check("RPAREN"):
                self.error(t, "expression vide entre parenthèses non autorisée (ni groupement ni tuple, §16/§22)")
            first := self.element()
            if self.accept("RPAREN"):
                if first.kind == "Spread":
                    self.error(t, "'*' non autorisé dans un simple groupement")
                return first
            if self.check("COMMA"):
                items := [first]
                while self.accept("COMMA"):
                    if self.check("RPAREN"):
                        break
                    append(items, self.element())
                self.expect("RPAREN", "attendu ')' pour fermer le tuple")
                return N("TupleLit", t, {"elements": items})
            self.error(self.peek(), "attendu ',' (tuple) ou ')' (groupement) après l'expression")
        if k == "LBRACKET":
            self.advance()
            items := []
            if not self.check("RBRACKET"):
                first := self.element()
                if self.check("KW_FOR"):
                    cl := self.comp_clauses()
                    self.expect("RBRACKET", "attendu ']' pour fermer la compréhension de liste")
                    return N("Comprehension", t, {"comp": "list", "element": first, "key": null, "value": null, "clauses": cl})
                append(items, first)
                while self.accept("COMMA"):
                    if self.check("RBRACKET"):
                        break
                    append(items, self.element())
            self.expect("RBRACKET", "attendu ']' pour fermer la liste")
            return N("ListLit", t, {"elements": items})
        if k == "LBRACE":
            self.advance()
            entries := []
            if self.check("RBRACE"):
                self.advance()
                return N("DictLit", t, {"entries": entries})
            if self.check("STAR_STAR"):
                st := self.advance()
                append(entries, N("DictSpread", st, {"value": self.expression()}))
                while self.accept("COMMA"):
                    if self.check("RBRACE"):
                        break
                    append(entries, self.dict_entry())
                self.expect("RBRACE", "attendu '}' pour fermer le dictionnaire")
                return N("DictLit", t, {"entries": entries})
            key := self.expression()
            if self.check("KW_FOR") or self.check("COMMA") or self.check("RBRACE"):
                if self.check("KW_FOR"):
                    cl := self.comp_clauses()
                    self.expect("RBRACE", "attendu '}' pour fermer l'ensemble")
                    return N("Comprehension", t, {"comp": "set", "element": key, "key": null, "value": null, "clauses": cl})
                items := [key]
                while self.accept("COMMA"):
                    if self.check("RBRACE"):
                        break
                    append(items, self.element())
                self.expect("RBRACE", "attendu '}' pour fermer l'ensemble")
                return N("SetLit", t, {"elements": items})
            self.expect("COLON", "attendu ':' entre la clé et la valeur d'un dictionnaire")
            val := self.expression()
            if self.check("KW_FOR"):
                cl := self.comp_clauses()
                self.expect("RBRACE", "attendu '}' pour fermer la compréhension de dictionnaire")
                return N("Comprehension", t, {"comp": "dict", "element": null, "key": key, "value": val, "clauses": cl})
            append(entries, N("DictEntry", key, {"key": key, "value": val}))
            while self.accept("COMMA"):
                if self.check("RBRACE"):
                    break
                append(entries, self.dict_entry())
            self.expect("RBRACE", "attendu '}' pour fermer le dictionnaire")
            return N("DictLit", t, {"entries": entries})
        self.error(t, "expression attendue")

    func dict_entry():
        t := self.peek()
        if self.accept("STAR_STAR"):
            return N("DictSpread", t, {"value": self.expression()})
        key := self.expression()
        self.expect("COLON", "attendu ':' entre la clé et la valeur d'un dictionnaire")
        return N("DictEntry", key, {"key": key, "value": self.expression()})

# Programme (nœud Program) d'un texte source.
func parse(source, file="<source>"):
    return Parser(_lx.tokenize(source, file), file).parse_program()

func parse_tokens(tokens, file="<source>"):
    return Parser(tokens, file).parse_program()

# Une seule expression (le texte entier doit être consommé).
func parse_expression(text, file="<expression>"):
    p := Parser(_lx.tokenize(text, file), file)
    e := p.expression()
    p.accept("NEWLINE")
    if not p.at_end():
        p.error(p.peek(), "jetons résiduels après l'expression")
    return e

# [programme ou null, diagnostics] — ne lève pas.
func try_parse(source, file="<source>"):
    bag := _dg.DiagnosticBag(file, source)
    try:
        return [parse(source, file), bag]
    catch e:
        d := _dg.from_error(e, file)
        d.phase = e.type
        if e.type == "LexError":
            d.code = "E0101"
        else:
            d.code = "E0201"
        bag.add(d)
        return [null, bag]
