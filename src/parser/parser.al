# ALEX — parser
#
# Analyseur syntaxique de la chaîne de compilation vers bytecode : portage fidèle de src/Parser.cpp. Il produit
# l'arbre de ast avec exactement les mêmes nœuds, positions et désucrages que le parser de
# référence : décorateurs (f = déco(f) après la définition), fonctions fléchées et lambdas ({ return expr }),
# tranches (__slice), ensembles (__make_set), déstructuration (__dN, __len, raise ValueError), for a, b in
# (__forN), with (__withN + try/finally), assert, del (__del_item), pass, extend, comparaisons chaînées.
# Les compteurs __forN / __dN / __withN sont globaux au processus, comme les « static int » du C++.
#
#   use parser as bp
#   prog := bp.parse_file("prog.al")               # Node « Program »
#   prog2 := bp.parse_text("x := 1\nprint(x)\n", "essai.al")
#
# Erreurs : SyntaxError (« fichier:ligne:colonne: message »), et celles du lexer (lexer).

from core use len, type
from collections use append
use string as _s
use io as _io
use lexer as _lx
use ast as _a
from ast use Node

_counters := {"for": 0, "d": 0, "with": 0}

func _next(name):
    _counters[name] = _counters[name] + 1
    return _counters[name]

# Remet à zéro les compteurs de désucrage (__forN, __dN, __withN) : à appeler entre deux compilations
# indépendantes pour reproduire un processus de compilation neuf.
func reset_counters():
    _counters["for"] = 0
    _counters["d"] = 0
    _counters["with"] = 0

const COMPOUND := {"PLUS_EQ": "Add", "MINUS_EQ": "Sub", "STAR_EQ": "Mul", "SLASH_EQ": "Div",
    "SLASH_SLASH_EQ": "FloorDiv", "PERCENT_EQ": "Mod", "STAR_STAR_EQ": "Pow", "AMP_EQ": "BitAnd",
    "PIPE_EQ": "BitOr", "CARET_EQ": "BitXor", "LT_LT_EQ": "Shl", "GT_GT_EQ": "Shr"}

const COMPARISON := {"EQ_EQ": "Eq", "BANG_EQ": "Ne", "LT": "Lt", "LT_EQ": "Le", "GT": "Gt", "GT_EQ": "Ge"}

func _is_word(t):
    lx := t.lexeme
    if len(lx) == 0:
        return false
    c0 := lx[0]
    if not ((c0 >= 'a' and c0 <= 'z') or (c0 >= 'A' and c0 <= 'Z') or c0 == '_'):
        return false
    for c in lx:
        if not ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_'):
            return false
    return true

func _valid_lvalue(e):
    return e.kind == "Identifier" or e.kind == "MemberExpr" or e.kind == "IndexExpr"

func _is_spread(e):
    return e.kind == "UnaryExpr" and e.op == "Spread"

class Parser:
    func init(tokens, filename):
        self.tokens = tokens
        self.n = len(tokens)
        self.filename = filename
        self.pos = 0
        self.pending = []
        self.uses_set = false
        self.last_segment_keyword = false

    # ------------------------------------------------------------------ flux de jetons
    func peek(k=0):
        i := self.pos + k
        if i >= self.n:
            return self.tokens[self.n - 1]
        return self.tokens[i]

    func previous():
        return self.tokens[self.pos - 1]

    func check(t):
        i := self.pos
        if i >= self.n:
            i = self.n - 1
        return self.tokens[i].type == t

    func advance():
        i := self.pos
        if i >= self.n:
            i = self.n - 1
        if self.tokens[i].type != "EOF":
            self.pos += 1
        return self.tokens[self.pos - 1]

    func accept(t):
        if not self.check(t):
            return false
        self.advance()
        return true

    func expect(t, message):
        if self.check(t):
            return self.advance()
        p := self.peek()
        self.error(p, message + " (obtenu " + p.type + ("" if p.lexeme == "" else " `" + p.lexeme + "`") + ")")

    func error(tok, message):
        raise("SyntaxError", self.filename + ":" + str(tok.line) + ":" + str(tok.column) + ": " + message)

    func error_at(line, column, message):
        raise("SyntaxError", self.filename + ":" + str(line) + ":" + str(column) + ": " + message)

    func drain(into):
        for st in self.pending:
            append(into, st)
        self.pending = []

    # ------------------------------------------------------------------ programme
    func parse_program():
        prog := Node("Program", 1, 1)
        prog.top_level = []
        while not self.check("EOF"):
            append(prog.top_level, self.parse_statement())
            self.drain(prog.top_level)
        prog.uses_set_literal = self.uses_set
        return prog

    func parse_expression():
        return self.parse_conditional()

    func parse_statement():
        t := self.peek().type
        if t == "AT":
            decorators := []
            at_tok := self.peek()
            while self.accept("AT"):
                append(decorators, self.parse_expression())
                self.expect("NEWLINE", "attendu une fin de ligne après un décorateur")
            if not self.check("KW_FUNC") and not self.check("KW_ASYNC"):
                self.error(self.peek(), "un décorateur doit être suivi d'une déclaration 'func'")
            fn := self.parse_statement()
            if fn.kind != "FunctionDecl":
                self.error(at_tok, "un décorateur ne s'applique qu'à une fonction")
            fname := fn.name
            value := _a.ident(fname, at_tok.line, at_tok.column)
            i := len(decorators) - 1
            while i >= 0:
                c := Node("CallExpr", at_tok.line, at_tok.column)
                c.callee = decorators[i]
                c.arguments = [_a.argument(null, value)]
                value = c
                i -= 1
            asg := Node("Assignment", at_tok.line, at_tok.column)
            asg.target = _a.ident(fname, at_tok.line, at_tok.column)
            asg.value = value
            append(self.pending, asg)
            return fn
        if t == "KW_USE" or t == "KW_FROM":
            return self.parse_import()
        if t == "KW_ASYNC":
            if self.peek(1).type != "KW_FUNC":
                self.error(self.peek(), "'async' doit être immédiatement suivi de 'func'")
            self.advance()
            return self.parse_function_decl(true)
        if t == "KW_FUNC":
            if self.peek(1).type == "LPAREN":
                return self.parse_simple_statement()
            return self.parse_function_decl(false)
        if t == "KW_STRUCT":
            return self.parse_struct()
        if t == "KW_CLASS":
            return self.parse_class()
        if t == "KW_INTERFACE":
            return self.parse_interface()
        if t == "KW_ENUM":
            return self.parse_enum()
        if t == "KW_CONST":
            return self.parse_const()
        if t == "KW_IF":
            return self.parse_if()
        if t == "KW_WHILE":
            return self.parse_while()
        if t == "KW_FOR":
            return self.parse_for()
        if t == "KW_TRY":
            return self.parse_try()
        if t == "KW_MATCH":
            return self.parse_match()
        if t == "KW_BREAK":
            tok := self.advance()
            self.expect("NEWLINE", "attendu une fin de ligne après 'break'")
            return Node("BreakStmt", tok.line, tok.column)
        if t == "KW_CONTINUE":
            tok := self.advance()
            self.expect("NEWLINE", "attendu une fin de ligne après 'continue'")
            return Node("ContinueStmt", tok.line, tok.column)
        if t == "KW_RETURN":
            tok := self.advance()
            r := Node("ReturnStmt", tok.line, tok.column)
            r.value = null
            if not self.check("NEWLINE"):
                r.value = self.parse_expr_or_tuple()
            self.expect("NEWLINE", "attendu une fin de ligne après 'return'")
            return r
        return self.parse_simple_statement()

    func parse_block_body():
        p := self.peek()
        b := Node("Block", p.line, p.column)
        b.statements = []
        self.expect("NEWLINE", "attendu un retour à la ligne avant un bloc indenté")
        self.expect("INDENT", "attendu une indentation pour ouvrir le bloc")
        while not self.check("DEDENT") and not self.check("EOF"):
            append(b.statements, self.parse_statement())
            self.drain(b.statements)
        self.expect("DEDENT", "attendu une dés-indentation pour fermer le bloc")
        return b

    func parse_colon_block():
        self.expect("COLON", "attendu ':' avant le bloc")
        return self.parse_block_body()

    # ------------------------------------------------------------------ imports
    func parse_module_path():
        parts := []
        self.last_segment_keyword = false
        if not self.check("IDENTIFIER") and _is_word(self.peek()) and self.peek().type != "NEWLINE":
            append(parts, self.advance().lexeme)
            self.last_segment_keyword = true
        else:
            append(parts, self.expect("IDENTIFIER", "attendu un nom de module").lexeme)
        while self.accept("DOT"):
            if not self.check("IDENTIFIER") and _is_word(self.peek()):
                append(parts, self.advance().lexeme)
                self.last_segment_keyword = true
                continue
            append(parts, self.expect("IDENTIFIER", "attendu un segment de chemin de module après '.'").lexeme)
            self.last_segment_keyword = false
        return parts

    func parse_import():
        p := self.peek()
        n := Node("ImportStmt", p.line, p.column)
        n.names = []
        n.alias = null
        if self.accept("KW_USE"):
            n.is_from = false
            n.module_path = self.parse_module_path()
            kw_last := self.last_segment_keyword
            if self.accept("KW_AS"):
                n.alias = self.expect("IDENTIFIER", "attendu un identifiant après 'as'").lexeme
            elif kw_last:
                self.error(self.peek(), "module '" + n.module_path[len(n.module_path) - 1] + "' : mot-clé du langage, un alias est requis (use ... as nom)")
            self.expect("NEWLINE", "attendu une fin de ligne après l'instruction 'use'")
            return n
        self.expect("KW_FROM", "attendu 'use' ou 'from'")
        n.is_from = true
        n.module_path = self.parse_module_path()
        self.expect("KW_USE", "attendu 'use' après le chemin de module dans une instruction 'from'")
        append(n.names, self.expect("IDENTIFIER", "attendu au moins un identifiant importé").lexeme)
        while self.accept("COMMA"):
            append(n.names, self.expect("IDENTIFIER", "attendu un identifiant après ','").lexeme)
        self.expect("NEWLINE", "attendu une fin de ligne après l'instruction 'from ... use'")
        return n

    # ------------------------------------------------------------------ types, paramètres, arguments
    func parse_type():
        tok := self.peek()
        t := Node("TypeRef", tok.line, tok.column)
        t.args = []
        t.nullable = false
        if self.accept("KW_NULL"):
            t.name = "null"
        elif self.accept("KW_FUNC"):
            t.name = "func"
            self.expect("LPAREN", "attendu '(' après 'func' dans un type")
            if not self.check("RPAREN"):
                append(t.args, self.parse_type())
                while self.accept("COMMA"):
                    append(t.args, self.parse_type())
            self.expect("RPAREN", "attendu ')' dans un type de fonction")
            if self.accept("THIN_ARROW"):
                append(t.args, self.parse_type())
            else:
                any := Node("TypeRef", 0, 0)
                any.name = "any"
                any.args = []
                any.nullable = false
                append(t.args, any)
        else:
            t.name = self.expect("IDENTIFIER", "attendu un type").lexeme
            if self.accept("LBRACKET"):
                append(t.args, self.parse_type())
                while self.accept("COMMA"):
                    append(t.args, self.parse_type())
                self.expect("RBRACKET", "attendu ']' après les paramètres du type")
        if self.accept("QUESTION"):
            t.nullable = true
        return t

    func mk_spread(tok, op, operand):
        u := Node("UnaryExpr", tok.line, tok.column)
        u.op = op
        u.operand = operand
        return u

    func parse_dict_entry(d):
        kv := Node("KeyValue", 0, 0)
        if self.check("STAR_STAR"):
            st := self.advance()
            kv.key = self.mk_spread(st, "DictSpread", self.parse_expression())
            kv.value = _a.null_lit(st.line, st.column)
        else:
            kv.key = self.parse_expression()
            self.expect("COLON", "attendu ':' entre la clé et la valeur d'un dictionnaire")
            kv.value = self.parse_expression()
        append(d.entries, kv)

    func parse_element():
        if self.check("STAR"):
            st := self.advance()
            return self.mk_spread(st, "Spread", self.parse_expression())
        return self.parse_expression()

    func parse_parameter_list():
        params := []
        if self.check("RPAREN"):
            return params
        while true:
            p := Node("Param", 0, 0)
            p.is_rest = self.accept("STAR")
            name_tok := self.expect("IDENTIFIER", "attendu un nom de paramètre")
            p.name = name_tok.lexeme
            p.line = name_tok.line
            p.column = name_tok.column
            p.type = null
            p.default_value = null
            if self.accept("COLON"):
                p.type = self.parse_type()
            if self.accept("EQ"):
                if p.is_rest:
                    self.error(name_tok, "un paramètre variadique '*" + p.name + "' ne peut pas avoir de valeur par défaut")
                p.default_value = self.parse_expression()
            was_rest := p.is_rest
            append(params, p)
            if not self.accept("COMMA"):
                break
            if was_rest and not self.check("RPAREN"):
                self.error(self.peek(), "le paramètre variadique doit être le dernier")
            if self.check("RPAREN"):
                break
        return params

    func parse_argument_list():
        args := []
        if self.check("RPAREN"):
            return args
        while true:
            if self.check("STAR"):
                st := self.advance()
                append(args, _a.argument(null, self.mk_spread(st, "Spread", self.parse_expression())))
            elif self.check("IDENTIFIER") and self.peek(1).type == "EQ":
                name := self.advance().lexeme
                self.advance()
                append(args, _a.argument(name, self.parse_expression()))
            else:
                append(args, _a.argument(null, self.parse_expression()))
            if not self.accept("COMMA"):
                break
            if self.check("RPAREN"):
                break
        return args

    # ------------------------------------------------------------------ déclarations
    func parse_function_decl(is_async):
        func_tok := self.expect("KW_FUNC", "attendu 'func'")
        n := Node("FunctionDecl", func_tok.line, func_tok.column)
        n.is_async = is_async
        n.extends_type = ""
        n.return_type = null
        n.name = self.expect("IDENTIFIER", "attendu un nom de fonction après 'func'").lexeme
        self.expect("LPAREN", "attendu '(' après le nom de la fonction")
        n.params = self.parse_parameter_list()
        self.expect("RPAREN", "attendu ')' après la liste de paramètres")
        if self.accept("THIN_ARROW"):
            n.return_type = self.parse_type()
        if self.accept("ARROW"):
            et := self.peek()
            value := self.parse_expression()
            self.expect("NEWLINE", "attendu une fin de ligne après le corps d'une fonction fléchée '=>'")
            r := Node("ReturnStmt", et.line, et.column)
            r.value = value
            n.body = _a.block([r], et.line, et.column)
        elif self.check("NEWLINE"):
            self.advance()
            n.body = _a.block([], func_tok.line, func_tok.column)
        else:
            n.body = self.parse_colon_block()
        return n

    func parse_struct():
        tok := self.expect("KW_STRUCT", "attendu 'struct'")
        n := Node("StructDecl", tok.line, tok.column)
        n.name = self.expect("IDENTIFIER", "attendu un nom de struct").lexeme
        n.body = self.parse_colon_block()
        return n

    func parse_class():
        tok := self.expect("KW_CLASS", "attendu 'class'")
        n := Node("ClassDecl", tok.line, tok.column)
        n.name = self.expect("IDENTIFIER", "attendu un nom de classe").lexeme
        n.base_class = null
        n.interfaces = []
        if self.accept("KW_EXTENDS"):
            n.base_class = self.expect("IDENTIFIER", "attendu un nom de classe après 'extends'").lexeme
        if self.check("IDENTIFIER") and self.peek().lexeme == "implements":
            self.advance()
            append(n.interfaces, self.expect("IDENTIFIER", "attendu un nom d'interface après 'implements'").lexeme)
            while self.accept("COMMA"):
                append(n.interfaces, self.expect("IDENTIFIER", "attendu un nom d'interface après ','").lexeme)
        n.body = self.parse_colon_block()
        return n

    func parse_interface():
        tok := self.expect("KW_INTERFACE", "attendu 'interface'")
        n := Node("InterfaceDecl", tok.line, tok.column)
        n.name = self.expect("IDENTIFIER", "attendu un nom d'interface").lexeme
        n.body = self.parse_colon_block()
        return n

    func parse_enum():
        tok := self.expect("KW_ENUM", "attendu 'enum'")
        n := Node("EnumDecl", tok.line, tok.column)
        n.name = self.expect("IDENTIFIER", "attendu un nom d'enum").lexeme
        n.members = []
        self.expect("COLON", "attendu ':' après le nom de l'enum")
        self.expect("NEWLINE", "attendu une fin de ligne avant les membres de l'enum")
        self.expect("INDENT", "attendu une indentation pour les membres de l'enum")
        while not self.check("DEDENT") and not self.check("EOF"):
            mt := self.expect("IDENTIFIER", "attendu un nom de membre d'enum")
            m := Node("EnumMember", mt.line, mt.column)
            m.name = mt.lexeme
            m.fields = []
            m.field_types = []
            if self.accept("LPAREN"):
                if not self.check("RPAREN"):
                    self._enum_field(m)
                    while self.accept("COMMA"):
                        self._enum_field(m)
                self.expect("RPAREN", "attendu ')' après les champs de la variante d'enum")
            append(n.members, m)
            self.expect("NEWLINE", "attendu une fin de ligne après un membre d'enum")
        self.expect("DEDENT", "attendu une dés-indentation pour fermer l'enum")
        return n

    func _enum_field(m):
        append(m.fields, self.expect("IDENTIFIER", "attendu un nom de champ dans la variante d'enum").lexeme)
        append(m.field_types, self.parse_type() if self.accept("COLON") else null)

    func parse_const():
        tok := self.expect("KW_CONST", "attendu 'const'")
        n := Node("ConstDecl", tok.line, tok.column)
        n.name = self.expect("IDENTIFIER", "attendu un nom de constante après 'const'").lexeme
        n.type = null
        if self.accept("COLON"):
            n.type = self.parse_type()
        self.expect("COLON_EQ", "attendu ':=' après le nom de la constante")
        n.value = self.parse_expression()
        self.expect("NEWLINE", "attendu une fin de ligne après la déclaration de constante")
        return n

    func parse_if():
        tok := self.expect("KW_IF", "attendu 'if'")
        n := Node("IfStmt", tok.line, tok.column)
        n.condition = self.parse_expression()
        n.then_block = self.parse_colon_block()
        n.elif_clauses = []
        n.else_block = null
        while self.check("KW_ELIF"):
            self.advance()
            c := Node("ElifClause", 0, 0)
            c.condition = self.parse_expression()
            c.body = self.parse_colon_block()
            append(n.elif_clauses, c)
        if self.accept("KW_ELSE"):
            n.else_block = self.parse_colon_block()
        return n

    func parse_while():
        tok := self.expect("KW_WHILE", "attendu 'while'")
        n := Node("WhileStmt", tok.line, tok.column)
        n.condition = self.parse_expression()
        n.body = self.parse_colon_block()
        n.else_body = null
        if self.accept("KW_ELSE"):
            n.else_body = self.parse_colon_block()
        return n

    func parse_for():
        tok := self.expect("KW_FOR", "attendu 'for'")
        n := Node("ForStmt", tok.line, tok.column)
        n.else_body = null
        unpack := []
        if self.check("STAR") or self.peek(1).type == "COMMA":
            while true:
                star := self.accept("STAR")
                idt := self.expect("IDENTIFIER", "attendu un identifiant dans la cible du 'for'")
                append(unpack, [_a.ident(idt.lexeme, idt.line, idt.column), star])
                if not self.accept("COMMA"):
                    break
            n.variable = "__for" + str(_next("for"))
        else:
            n.variable = self.expect("IDENTIFIER", "attendu un identifiant après 'for'").lexeme
        self.expect("KW_IN", "attendu 'in' dans une boucle for")
        n.iterable = self.parse_expression()
        n.body = self.parse_colon_block()
        if self.accept("KW_ELSE"):
            n.else_body = self.parse_colon_block()
        if len(unpack) > 0:
            pre := self.build_unpack(n.variable, unpack, true, tok.line, tok.column, true)
            n.body.statements = pre + n.body.statements
        return n

    func parse_try():
        tok := self.expect("KW_TRY", "attendu 'try'")
        n := Node("TryStmt", tok.line, tok.column)
        n.try_block = self.parse_colon_block()
        n.catch_clauses = []
        n.finally_block = null
        saw_generic := false
        while self.check("KW_CATCH"):
            ct := self.advance()
            c := Node("CatchClause", ct.line, ct.column)
            c.types = []
            c.name = null
            if self.check("LPAREN"):
                self.advance()
                append(c.types, self.expect("IDENTIFIER", "attendu un type d'exception après '('").lexeme)
                while self.check("COMMA"):
                    self.advance()
                    append(c.types, self.expect("IDENTIFIER", "attendu un type d'exception après ','").lexeme)
                self.expect("RPAREN", "attendu ')' après la liste des types d'exception")
                if self.check("KW_AS"):
                    self.advance()
                    c.name = self.expect("IDENTIFIER", "attendu un nom après 'as'").lexeme
            elif self.check("IDENTIFIER"):
                first := self.advance().lexeme
                if self.check("KW_AS") or self.check("COMMA"):
                    append(c.types, first)
                    while self.check("COMMA"):
                        self.advance()
                        append(c.types, self.expect("IDENTIFIER", "attendu un type d'exception après ','").lexeme)
                    self.expect("KW_AS", "attendu 'as nom' après les types d'exception (ou parenthèses : catch (A, B):)")
                    c.name = self.expect("IDENTIFIER", "attendu un nom après 'as'").lexeme
                else:
                    c.name = first
            if saw_generic:
                self.error(ct, "clause 'catch' inatteignable : elle suit une clause 'catch' générique")
            if len(c.types) == 0:
                saw_generic = true
            c.body = self.parse_colon_block()
            append(n.catch_clauses, c)
        if self.check("KW_FINALLY"):
            self.advance()
            n.finally_block = self.parse_colon_block()
        if len(n.catch_clauses) == 0 and n.finally_block == null:
            self.error(tok, "'try' doit être suivi d'au moins un 'catch' ou d'un 'finally'")
        return n

    # ------------------------------------------------------------------ match
    func parse_literal_pattern():
        tok := self.peek()
        pat := _pattern("Literal", tok.line, tok.column)
        lit := self.parse_literal_from_token()
        pat.literal_value = lit.value
        pat.literal_kind = lit.literal_kind
        return pat

    func parse_match_pattern():
        t := self.peek().type
        if t == "INTEGER" or t == "FLOAT" or t == "STRING" or t == "CHAR" or t == "KW_TRUE" or t == "KW_FALSE" or t == "KW_NULL":
            low := self.parse_literal_pattern()
            if self.accept("DOT_DOT"):
                high := self.parse_literal_pattern()
                r := _pattern("Range", low.line, low.column)
                r.range_low = low
                r.range_high = high
                return r
            return low
        if t == "LBRACKET":
            ot := self.advance()
            pat := _pattern("List", ot.line, ot.column)
            if not self.check("RBRACKET"):
                append(pat.subpatterns, self.parse_match_pattern())
                while self.accept("COMMA"):
                    append(pat.subpatterns, self.parse_match_pattern())
            self.expect("RBRACKET", "attendu ']' pour fermer le motif de liste")
            return pat
        if t == "LPAREN":
            ot := self.advance()
            if self.check("RPAREN"):
                self.error(ot, "motif vide entre parenthèses non autorisé (ni groupement ni tuple, §16/§22)")
            first := self.parse_match_pattern()
            if self.accept("RPAREN"):
                return first
            if self.check("COMMA"):
                pat := _pattern("Tuple", ot.line, ot.column)
                append(pat.subpatterns, first)
                while self.accept("COMMA"):
                    append(pat.subpatterns, self.parse_match_pattern())
                self.expect("RPAREN", "attendu ')' pour fermer le motif de tuple")
                return pat
            self.error(self.peek(), "attendu ',' (motif de tuple) ou ')' (groupement) après le motif")
        if t == "IDENTIFIER":
            tok := self.advance()
            if tok.lexeme == "_":
                return _pattern("Wildcard", tok.line, tok.column)
            if not self.check("DOT"):
                pat := _pattern("Bind", tok.line, tok.column)
                pat.name = tok.lexeme
                return pat
            self.advance()
            vt := self.expect("IDENTIFIER", "attendu un nom de variante après '.' dans un motif")
            pat := _pattern("EnumVariant", tok.line, tok.column)
            pat.enum_type_name = tok.lexeme
            pat.variant_name = vt.lexeme
            if self.accept("LPAREN"):
                if not self.check("RPAREN"):
                    append(pat.subpatterns, self.parse_match_pattern())
                    while self.accept("COMMA"):
                        append(pat.subpatterns, self.parse_match_pattern())
                self.expect("RPAREN", "attendu ')' après les sous-motifs de la variante")
            return pat
        self.error(self.peek(), "motif de 'match' invalide : attendu un littéral, '_', un identifiant, 'EnumName.Variant', '[...]' ou '(...)' ")

    func parse_match():
        tok := self.expect("KW_MATCH", "attendu 'match'")
        n := Node("MatchStmt", tok.line, tok.column)
        n.subject = self.parse_expression()
        n.cases = []
        self.expect("COLON", "attendu ':' après l'expression de 'match'")
        self.expect("NEWLINE", "attendu une fin de ligne avant les cas de 'match'")
        self.expect("INDENT", "attendu une indentation pour les cas de 'match'")
        while not self.check("DEDENT") and not self.check("EOF"):
            c := Node("MatchCase", 0, 0)
            c.pattern = self.parse_match_pattern()
            c.guard = null
            if self.accept("KW_IF"):
                c.guard = self.parse_expression()
            self.expect("COLON", "attendu ':' après le motif de 'match'")
            c.body = self.parse_block_body()
            append(n.cases, c)
        self.expect("DEDENT", "attendu une dés-indentation pour fermer 'match'")
        return n

    # ------------------------------------------------------------------ instructions simples
    func parse_expr_or_tuple():
        st := self.peek()
        first := self.parse_expression()
        if not self.check("COMMA"):
            return first
        tup := Node("TupleLiteral", st.line, st.column)
        tup.elements = [first]
        while self.accept("COMMA"):
            if self.check("NEWLINE"):
                break
            append(tup.elements, self.parse_expression())
        return tup

    # targets : [[expr, étoile], ...]
    func build_unpack(tmp, targets, declare, line, col, check_length):
        out := []
        stars := 0
        star_at := 0
        i := 0
        while i < len(targets):
            if targets[i][1]:
                stars += 1
                star_at = i
            i += 1
        if stars > 1:
            self.error_at(line, col, "une seule cible '*reste' est permise dans une déstructuration")
        n := len(targets)
        fixed := n - 1 if stars > 0 else n
        if check_length:
            cond := _a.binary("Lt" if stars > 0 else "Ne", _a.call("__len", [_a.ident(tmp, line, col)], line, col), _a.int_lit(fixed, line, col), line, col)
            msg := _a.binary("Add", _a.str_lit("déstructuration : " + ("au moins " if stars > 0 else "") + str(fixed) + " valeur(s) attendue(s), obtenu ", line, col), _a.call("str", [_a.call("__len", [_a.ident(tmp, line, col)], line, col)], line, col), line, col)
            rs := Node("ExpressionStmt", line, col)
            rs.expr = _a.call("raise", [_a.str_lit("ValueError", line, col), msg], line, col)
            ifs := Node("IfStmt", line, col)
            ifs.condition = cond
            ifs.then_block = _a.block([rs], line, col)
            ifs.elif_clauses = []
            ifs.else_block = null
            append(out, ifs)
        i = 0
        while i < n:
            texpr := targets[i][0]
            tl := texpr.line
            tc := texpr.column
            value := null
            if not targets[i][1]:
                k := i if (stars == 0 or i < star_at) else -(n - i)
                value = _a.index(tmp, k, tl, tc)
            else:
                after := n - 1 - star_at
                value = _a.call("__slice", [_a.ident(tmp, tl, tc), _a.int_lit(star_at, tl, tc), _a.null_lit(tl, tc) if after == 0 else _a.int_lit(-after, tl, tc), _a.null_lit(tl, tc)], tl, tc)
            if declare:
                if texpr.kind != "Identifier":
                    self.error_at(tl, tc, "la cible de ':' doit être un identifiant simple")
                d := Node("VariableDecl", tl, tc)
                d.name = texpr.name
                d.type = null
                d.declared_only = false
                d.value = value
                append(out, d)
            else:
                asg := Node("Assignment", tl, tc)
                asg.target = texpr
                asg.value = value
                append(out, asg)
            i += 1
        return out

    func parse_destructuring(first, start_tok):
        targets := []
        if first != null:
            append(targets, [first, false])
        else:
            self._parse_target(targets)
        while self.accept("COMMA"):
            if self.check("COLON_EQ") or self.check("EQ"):
                break
            self._parse_target(targets)
        declare := false
        if self.accept("COLON_EQ"):
            declare = true
        elif self.accept("EQ"):
            declare = false
        else:
            self.error(self.peek(), "attendu ':=' ou '=' après les cibles de la déstructuration")
        for t in targets:
            if declare and t[0].kind != "Identifier":
                self.error(start_tok, "les cibles de ':=' doivent être des identifiants simples")
            if not declare and not _valid_lvalue(t[0]):
                self.error(start_tok, "cible de déstructuration invalide : identifiant, accès membre ('.') ou indexage ('[]')")
        rhs := self.parse_expr_or_tuple()
        self.expect("NEWLINE", "attendu une fin de ligne après la déstructuration")
        tmp := "__d" + str(_next("d"))
        has_star := false
        for t in targets:
            has_star = has_star or t[1]
        static_len := rhs.kind == "TupleLiteral" and not has_star and len(rhs.elements) == len(targets)
        if rhs.kind == "TupleLiteral" and not has_star and not static_len:
            self.error_at(start_tok.line, start_tok.column, "déstructuration : " + str(len(targets)) + " cible(s) pour " + str(len(rhs.elements)) + " valeur(s)")
        d := Node("VariableDecl", start_tok.line, start_tok.column)
        d.name = tmp
        d.type = null
        d.declared_only = false
        d.value = rhs
        for st in self.build_unpack(tmp, targets, declare, start_tok.line, start_tok.column, not static_len):
            append(self.pending, st)
        return d

    func _parse_target(targets):
        star := self.accept("STAR")
        e := null
        if star:
            idt := self.expect("IDENTIFIER", "attendu un identifiant après '*'")
            e = _a.ident(idt.lexeme, idt.line, idt.column)
        else:
            e = self.parse_expression()
        append(targets, [e, star])

    func parse_simple_statement():
        st := self.peek()
        nx := self.peek(1).type
        if st.type == "IDENTIFIER" and nx == "COLON":
            n := Node("VariableDecl", st.line, st.column)
            n.name = self.advance().lexeme
            self.advance()
            n.type = self.parse_type()
            n.declared_only = false
            if self.check("NEWLINE"):
                self.advance()
                n.declared_only = true
                n.value = _a.null_lit(n.line, n.column)
                return n
            self.expect("COLON_EQ", "attendu ':=' après le type de la variable")
            n.value = self.parse_expression()
            self.expect("NEWLINE", "attendu une fin de ligne après une déclaration de variable")
            return n
        if st.type == "IDENTIFIER" and st.lexeme == "with" and nx != "EQ" and nx != "COLON_EQ" and nx != "DOT" and nx != "COLON" and nx != "COMMA" and nx != "NEWLINE" and not (nx in COMPOUND):
            line := st.line
            col := st.column
            self.advance()
            resource := self.parse_expression()
            bind := ""
            if self.accept("KW_AS"):
                bind = self.expect("IDENTIFIER", "attendu un nom après 'as'").lexeme
            body := self.parse_colon_block()
            tmp := "__with" + str(_next("with"))
            decl := Node("VariableDecl", line, col)
            decl.name = tmp
            decl.type = null
            decl.declared_only = false
            decl.value = resource
            enter := Node("VariableDecl", line, col)
            enter.name = tmp + "e" if bind == "" else bind
            enter.type = null
            enter.declared_only = false
            enter.value = _method_call(tmp, "__enter__", [], line, col)
            append(self.pending, enter)
            tr := Node("TryStmt", line, col)
            tr.try_block = body
            tr.catch_clauses = []
            ex := Node("ExpressionStmt", line, col)
            ex.expr = _method_call(tmp, "__exit__", [_a.null_lit(line, col), _a.null_lit(line, col), _a.null_lit(line, col)], line, col)
            tr.finally_block = _a.block([ex], line, col)
            append(self.pending, tr)
            return decl
        if st.type == "IDENTIFIER" and st.lexeme == "pass" and nx == "NEWLINE":
            self.advance()
            self.advance()
            s := Node("ExpressionStmt", st.line, st.column)
            s.expr = _a.null_lit(st.line, st.column)
            return s
        if st.type == "IDENTIFIER" and (st.lexeme == "assert" or st.lexeme == "del"):
            stmt_form := nx != "EQ" and nx != "COLON_EQ" and nx != "DOT" and nx != "COLON" and nx != "COMMA" and nx != "NEWLINE" and not (nx in COMPOUND)
            if stmt_form:
                line := st.line
                col := st.column
                self.advance()
                if st.lexeme == "assert":
                    cond := self.parse_expression()
                    msg := null
                    if self.accept("COMMA"):
                        msg = self.parse_expression()
                    self.expect("NEWLINE", "attendu une fin de ligne après 'assert'")
                    if msg == null:
                        msg = _a.str_lit("assertion échouée", line, col)
                    else:
                        msg = _a.call("str", [msg], line, col)
                    rs := Node("ExpressionStmt", line, col)
                    rs.expr = _a.call("raise", [_a.str_lit("AssertionError", line, col), msg], line, col)
                    ne := Node("UnaryExpr", line, col)
                    ne.op = "Not"
                    ne.operand = cond
                    ifs := Node("IfStmt", line, col)
                    ifs.condition = ne
                    ifs.then_block = _a.block([rs], line, col)
                    ifs.elif_clauses = []
                    ifs.else_block = null
                    return ifs
                dels := []
                while true:
                    t := self.parse_expression()
                    if t.kind != "IndexExpr":
                        self.error_at(line, col, "'del' ne supprime qu'un élément indexé : del liste[i] ou del dict[clé]")
                    s := Node("ExpressionStmt", line, col)
                    s.expr = _a.call("__del_item", [t.object, t.index], line, col)
                    append(dels, s)
                    if not self.accept("COMMA"):
                        break
                self.expect("NEWLINE", "attendu une fin de ligne après 'del'")
                k := 1
                while k < len(dels):
                    append(self.pending, dels[k])
                    k += 1
                return dels[0]
        if st.type == "IDENTIFIER" and st.lexeme == "extend" and nx == "IDENTIFIER" and self.peek(2).type == "COLON":
            self.advance()
            type_tok := self.advance()
            body := self.parse_colon_block()
            fns := []
            for s in body.statements:
                if s.kind != "FunctionDecl":
                    self.error_at(s.line, s.column, "un bloc 'extend' ne contient que des méthodes (func)")
                s.extends_type = type_tok.lexeme
                append(fns, s)
            if len(fns) == 0:
                self.error_at(type_tok.line, type_tok.column, "bloc 'extend' vide")
            k := 1
            while k < len(fns):
                append(self.pending, fns[k])
                k += 1
            return fns[0]
        if st.type == "STAR":
            return self.parse_destructuring(null, st)
        target := self.parse_expression()
        if self.check("COMMA"):
            return self.parse_destructuring(target, st)
        if self.check("COLON_EQ"):
            if target.kind != "Identifier":
                self.error(st, "la partie gauche de ':=' doit être un identifiant simple (§9)")
            self.advance()
            n := Node("VariableDecl", st.line, st.column)
            n.name = target.name
            n.type = null
            n.declared_only = false
            n.value = self.parse_expr_or_tuple()
            self.expect("NEWLINE", "attendu une fin de ligne après une déclaration de variable")
            return n
        if self.check("EQ"):
            if not _valid_lvalue(target):
                self.error(st, "cible d'affectation invalide : seuls un identifiant, un accès membre ('.') ou un indexage ('[]') sont assignables")
            self.advance()
            n := Node("Assignment", st.line, st.column)
            n.target = target
            n.value = self.parse_expr_or_tuple()
            self.expect("NEWLINE", "attendu une fin de ligne après une affectation")
            return n
        pt := self.peek().type
        if pt in COMPOUND:
            if not _valid_lvalue(target):
                self.error(st, "cible d'affectation composée invalide : seuls un identifiant, un accès membre ('.') ou un indexage ('[]') sont assignables")
            self.advance()
            n := Node("CompoundAssignment", st.line, st.column)
            n.op = COMPOUND[pt]
            n.target = target
            n.value = self.parse_expression()
            self.expect("NEWLINE", "attendu une fin de ligne après une affectation composée")
            return n
        self.expect("NEWLINE", "attendu une fin de ligne après une instruction-expression")
        n := Node("ExpressionStmt", st.line, st.column)
        n.expr = target
        return n

    # ------------------------------------------------------------------ expressions
    func parse_range_operand():
        st := self.peek()
        left := self.parse_logical_or()
        if self.check("DOT_DOT"):
            self.advance()
            right := self.parse_logical_or()
            r := Node("RangeExpr", st.line, st.column)
            r.start = left
            r.end = right
            left = r
        return left

    func parse_conditional():
        st := self.peek()
        left := self.parse_range_operand()
        if self.check("KW_IF"):
            self.advance()
            cond := self.parse_expression()
            self.expect("KW_ELSE", "attendu 'else' pour compléter l'expression conditionnelle 'x if c else y'")
            other := self.parse_expression()
            n := Node("ConditionalExpr", st.line, st.column)
            n.condition = cond
            n.then_expr = left
            n.else_expr = other
            return n
        return left

    func parse_comprehension_clauses():
        clauses := []
        while self.check("KW_FOR") or self.check("KW_IF"):
            kw := self.advance()
            c := Node("CompClause", kw.line, kw.column)
            if kw.type == "KW_FOR":
                c.clause_kind = "For"
                c.variable = self.expect("IDENTIFIER", "attendu un identifiant après 'for' dans une compréhension").lexeme
                if self.check("COMMA"):
                    self.error(self.peek(), "la déstructuration n'est pas supportée dans un 'for' (§18 : un seul identifiant) ; itérez sur les paires avec items(d) et lisez p[0] / p[1]")
                self.expect("KW_IN", "attendu 'in' dans une clause 'for' de compréhension")
                c.expr = self.parse_range_operand()
            else:
                c.clause_kind = "If"
                c.variable = ""
                c.expr = self.parse_logical_or()
            append(clauses, c)
        return clauses

    func _bin(op, tok, l, r):
        n := Node("BinaryExpr", tok.line, tok.column)
        n.op = op
        n.left = l
        n.right = r
        return n

    func parse_logical_or():
        left := self.parse_logical_and()
        while self.check("KW_OR"):
            op := self.advance()
            left = self._bin("Or", op, left, self.parse_logical_and())
        return left

    func parse_not():
        if self.check("KW_NOT"):
            op := self.advance()
            n := Node("UnaryExpr", op.line, op.column)
            n.op = "Not"
            n.operand = self.parse_not()
            return n
        return self.parse_comparison()

    func parse_logical_and():
        left := self.parse_not()
        while self.check("KW_AND"):
            op := self.advance()
            left = self._bin("And", op, left, self.parse_not())
        return left

    func _is_cmp():
        t := self.peek().type
        return (t in COMPARISON) or t == "KW_IN" or (t == "KW_NOT" and self.peek(1).type == "KW_IN")

    func parse_comparison():
        left := self.parse_bitwise_or()
        result := null
        while self._is_cmp():
            op_tok := self.advance()
            op := ""
            if op_tok.type == "KW_IN":
                op = "In"
            elif op_tok.type == "KW_NOT":
                self.advance()
                op = "NotIn"
            else:
                op = COMPARISON[op_tok.type]
            rhs_start := self.pos
            right := self.parse_bitwise_or()
            rhs_end := self.pos
            more := self._is_cmp()
            right_copy := null
            if more:
                k := rhs_start
                while k < rhs_end:
                    if self.tokens[k].type == "LPAREN":
                        self.error(self.tokens[k], "comparaison chaînée : l'opérande du milieu ne doit pas contenir d'appel ni de parenthèses (utilisez une variable temporaire)")
                    k += 1
                save := self.pos
                self.pos = rhs_start
                right_copy = self.parse_bitwise_or()
                self.pos = save
            node := self._bin(op, op_tok, left, right)
            if result == null:
                result = node
            else:
                conj := Node("BinaryExpr", node.line, node.column)
                conj.op = "And"
                conj.left = result
                conj.right = node
                result = conj
            if not more:
                break
            left = right_copy
        return result if result != null else left

    func parse_bitwise_or():
        left := self.parse_bitwise_xor()
        while self.check("PIPE"):
            op := self.advance()
            left = self._bin("BitOr", op, left, self.parse_bitwise_xor())
        return left

    func parse_bitwise_xor():
        left := self.parse_bitwise_and()
        while self.check("CARET"):
            op := self.advance()
            left = self._bin("BitXor", op, left, self.parse_bitwise_and())
        return left

    func parse_bitwise_and():
        left := self.parse_shift()
        while self.check("AMP"):
            op := self.advance()
            left = self._bin("BitAnd", op, left, self.parse_shift())
        return left

    func parse_shift():
        left := self.parse_additive()
        while self.check("LT_LT") or self.check("GT_GT"):
            op := self.advance()
            left = self._bin("Shl" if op.type == "LT_LT" else "Shr", op, left, self.parse_additive())
        return left

    func parse_additive():
        left := self.parse_multiplicative()
        while self.check("PLUS") or self.check("MINUS"):
            op := self.advance()
            left = self._bin("Add" if op.type == "PLUS" else "Sub", op, left, self.parse_multiplicative())
        return left

    func parse_multiplicative():
        left := self.parse_power()
        while self.check("STAR") or self.check("SLASH") or self.check("SLASH_SLASH") or self.check("PERCENT"):
            op := self.advance()
            k := "Mod"
            if op.type == "STAR":
                k = "Mul"
            elif op.type == "SLASH":
                k = "Div"
            elif op.type == "SLASH_SLASH":
                k = "FloorDiv"
            left = self._bin(k, op, left, self.parse_power())
        return left

    func parse_power():
        st := self.peek()
        left := self.parse_unary()
        if self.check("STAR_STAR"):
            self.advance()
            right := self.parse_power()
            return self._bin("Pow", st, left, right)
        return left

    func parse_unary():
        t := self.peek().type
        op := ""
        if t == "PLUS":
            op = "Plus"
        elif t == "MINUS":
            op = "Minus"
        elif t == "KW_NOT":
            op = "Not"
        elif t == "TILDE":
            op = "BitNot"
        elif t == "KW_AWAIT":
            op = "Await"
        else:
            return self.parse_postfix()
        tok := self.advance()
        operand := self.parse_unary()
        n := Node("UnaryExpr", tok.line, tok.column)
        n.op = op
        n.operand = operand
        return n

    func parse_postfix():
        e := self.parse_primary()
        while true:
            if self.check("DOT"):
                dt := self.advance()
                mt := self.expect("IDENTIFIER", "attendu un nom de membre après '.'")
                m := Node("MemberExpr", dt.line, dt.column)
                m.object = e
                m.member = mt.lexeme
                e = m
            elif self.check("LBRACKET"):
                bt := self.advance()
                start := null
                if not self.check("COLON"):
                    start = self.parse_expression()
                if self.check("COLON"):
                    sl := bt.line
                    sc := bt.column
                    self.advance()
                    stop := null
                    step := null
                    if not self.check("COLON") and not self.check("RBRACKET"):
                        stop = self.parse_expression()
                    if self.accept("COLON"):
                        if not self.check("RBRACKET"):
                            step = self.parse_expression()
                    self.expect("RBRACKET", "attendu ']' après la tranche")
                    c := Node("CallExpr", sl, sc)
                    c.callee = _a.ident("__slice", sl, sc)
                    c.arguments = []
                    for part in [e, start, stop, step]:
                        append(c.arguments, _a.argument(null, part if part != null else _a.null_lit(sl, sc)))
                    e = c
                    continue
                if start == null:
                    self.error(self.peek(), "expression attendue")
                self.expect("RBRACKET", "attendu ']' après l'index")
                ix := Node("IndexExpr", bt.line, bt.column)
                ix.object = e
                ix.index = start
                e = ix
            elif self.check("LPAREN"):
                pt := self.advance()
                args := self.parse_argument_list()
                self.expect("RPAREN", "attendu ')' après la liste d'arguments")
                c := Node("CallExpr", pt.line, pt.column)
                c.callee = e
                c.arguments = args
                e = c
            elif self.check("QUESTION"):
                qt := self.advance()
                p := Node("ErrorPropagationExpr", qt.line, qt.column)
                p.operand = e
                e = p
            else:
                break
        return e

    func parse_literal_from_token():
        tok := self.advance()
        t := tok.type
        if t == "INTEGER":
            return _a.literal("Integer", tok.value, tok.line, tok.column)
        if t == "FLOAT":
            return _a.literal("Float", tok.value, tok.line, tok.column)
        if t == "STRING":
            return _a.literal("String", tok.value, tok.line, tok.column)
        if t == "CHAR":
            return _a.literal("Char", tok.value, tok.line, tok.column)
        if t == "KW_TRUE":
            return _a.literal("Boolean", true, tok.line, tok.column)
        if t == "KW_FALSE":
            return _a.literal("Boolean", false, tok.line, tok.column)
        if t == "KW_NULL":
            return _a.literal("Null", null, tok.line, tok.column)
        self.error(tok, "littéral attendu")

    func parse_embedded(text, line, column):
        sub := null
        try:
            sub = _lx.tokenize_text(text, self.filename)
        catch e:
            self.error_at(line, column, "expression interpolée invalide dans une f-string : " + e.message)
        p := Parser(sub, self.filename)
        ex := null
        try:
            ex = p.parse_expression()
        catch e:
            self.error_at(line, column, "expression interpolée invalide dans une f-string")
        if not p.check("NEWLINE") and not p.check("EOF"):
            self.error_at(line, column, "jetons résiduels après l'expression interpolée d'une f-string")
        return ex

    func parse_fstring(tok):
        n := Node("FStringLiteral", tok.line, tok.column)
        n.parts = []
        content := _s.byte_unpack(tok.value)
        buf := []
        i := 0
        m := len(content)
        while i < m:
            c := content[i]
            if c == 123:
                if len(buf) > 0:
                    append(n.parts, _fpart_text(_s.byte_pack(buf)))
                    buf = []
                j := i + 1
                depth := 1
                while j < m and depth > 0:
                    if content[j] == 123:
                        depth += 1
                    elif content[j] == 125:
                        depth -= 1
                        if depth == 0:
                            break
                    j += 1
                expr_text := _s.byte_pack([content[k] for k in i + 1..j])
                fp := Node("FStringPart", 0, 0)
                fp.is_expr = true
                fp.text = ""
                fp.expr = self.parse_embedded(expr_text, tok.line, tok.column)
                append(n.parts, fp)
                i = j + 1
            else:
                append(buf, c)
                i += 1
        if len(buf) > 0:
            append(n.parts, _fpart_text(_s.byte_pack(buf)))
        return n

    func finish_lambda(line, column, params):
        self.expect("ARROW", "attendu '=>' dans une lambda")
        et := self.peek()
        value := self.parse_expression()
        r := Node("ReturnStmt", et.line, et.column)
        r.value = value
        fn := Node("FunctionDecl", line, column)
        fn.name = _a.LAMBDA_NAME
        fn.is_async = false
        fn.params = params
        fn.return_type = null
        fn.extends_type = ""
        fn.body = _a.block([r], et.line, et.column)
        lam := Node("LambdaExpr", line, column)
        lam.function = fn
        return lam

    func parse_func_lambda():
        ft := self.expect("KW_FUNC", "attendu 'func'")
        if not self.check("LPAREN"):
            self.error(self.peek(), "attendu '(' : une fonction anonyme s'écrit func(paramètres) => expression")
        self.advance()
        params := self.parse_parameter_list()
        self.expect("RPAREN", "attendu ')' après la liste de paramètres")
        return self.finish_lambda(ft.line, ft.column, params)

    func paren_arrow_ahead():
        if self.peek().type != "LPAREN":
            return false
        depth := 0
        i := 0
        while true:
            t := self.peek(i).type
            if t == "LPAREN" or t == "LBRACKET" or t == "LBRACE":
                depth += 1
            elif t == "RPAREN" or t == "RBRACKET" or t == "RBRACE":
                depth -= 1
                if depth == 0:
                    return self.peek(i + 1).type == "ARROW"
            elif t == "EOF":
                return false
            i += 1

    func parse_arrow_lambda():
        first := self.peek()
        params := []
        if first.type == "IDENTIFIER":
            p := Node("Param", first.line, first.column)
            p.name = first.lexeme
            p.type = null
            p.default_value = null
            p.is_rest = false
            self.advance()
            append(params, p)
        else:
            self.expect("LPAREN", "attendu '('")
            params = self.parse_parameter_list()
            self.expect("RPAREN", "attendu ')' après la liste de paramètres")
        return self.finish_lambda(first.line, first.column, params)

    func parse_primary():
        t := self.peek().type
        if t == "INTEGER" or t == "FLOAT" or t == "STRING" or t == "CHAR" or t == "KW_TRUE" or t == "KW_FALSE" or t == "KW_NULL":
            return self.parse_literal_from_token()
        if t == "FSTRING":
            return self.parse_fstring(self.advance())
        if t == "KW_FUNC":
            return self.parse_func_lambda()
        if t == "IDENTIFIER" or t == "KW_SELF" or t == "KW_SUPER":
            if t == "IDENTIFIER" and self.peek(1).type == "ARROW":
                return self.parse_arrow_lambda()
            tok := self.advance()
            name := tok.lexeme if tok.lexeme != "" else tok.type
            if tok.type == "KW_SELF":
                name = "self"
            if tok.type == "KW_SUPER":
                name = "super"
            return _a.ident(name, tok.line, tok.column)
        if t == "LPAREN":
            if self.paren_arrow_ahead():
                return self.parse_arrow_lambda()
            ot := self.advance()
            if self.check("RPAREN"):
                self.error(ot, "expression vide entre parenthèses non autorisée (ni groupement ni tuple, §16/§22)")
            first := self.parse_element()
            if self.accept("RPAREN"):
                if _is_spread(first):
                    self.error(ot, "'*' non autorisé dans un simple groupement")
                return first
            if self.check("COMMA"):
                tup := Node("TupleLiteral", ot.line, ot.column)
                tup.elements = [first]
                while self.accept("COMMA"):
                    if self.check("RPAREN"):
                        break
                    append(tup.elements, self.parse_element())
                self.expect("RPAREN", "attendu ')' pour fermer le tuple")
                return tup
            self.error(self.peek(), "attendu ',' (tuple) ou ')' (groupement) après l'expression")
        if t == "LBRACKET":
            ot := self.advance()
            lst := Node("ListLiteral", ot.line, ot.column)
            lst.elements = []
            if not self.check("RBRACKET"):
                first := self.parse_element()
                if self.check("KW_FOR"):
                    comp := Node("ComprehensionExpr", ot.line, ot.column)
                    comp.comp_kind = "List"
                    comp.element = first
                    comp.key = null
                    comp.value = null
                    comp.clauses = self.parse_comprehension_clauses()
                    self.expect("RBRACKET", "attendu ']' pour fermer la compréhension de liste")
                    return comp
                append(lst.elements, first)
                while self.accept("COMMA"):
                    if self.check("RBRACKET"):
                        break
                    append(lst.elements, self.parse_element())
            self.expect("RBRACKET", "attendu ']' pour fermer la liste")
            return lst
        if t == "LBRACE":
            ot := self.advance()
            d := Node("DictLiteral", ot.line, ot.column)
            d.entries = []
            if not self.check("RBRACE"):
                if self.check("STAR_STAR"):
                    st := self.advance()
                    kv := Node("KeyValue", 0, 0)
                    kv.key = self.mk_spread(st, "DictSpread", self.parse_expression())
                    kv.value = _a.null_lit(st.line, st.column)
                    append(d.entries, kv)
                    while self.accept("COMMA"):
                        if self.check("RBRACE"):
                            break
                        self.parse_dict_entry(d)
                    self.expect("RBRACE", "attendu '}' pour fermer le dictionnaire")
                    return d
                key := self.parse_expression()
                if self.check("KW_FOR") or self.check("COMMA") or self.check("RBRACE"):
                    self.uses_set = true
                    list_expr := null
                    if self.check("KW_FOR"):
                        comp := Node("ComprehensionExpr", ot.line, ot.column)
                        comp.comp_kind = "List"
                        comp.element = key
                        comp.key = null
                        comp.value = null
                        comp.clauses = self.parse_comprehension_clauses()
                        list_expr = comp
                    else:
                        lst := Node("ListLiteral", ot.line, ot.column)
                        lst.elements = [key]
                        while self.accept("COMMA"):
                            if self.check("RBRACE"):
                                break
                            append(lst.elements, self.parse_element())
                        list_expr = lst
                    self.expect("RBRACE", "attendu '}' pour fermer l'ensemble")
                    return _a.call("__make_set", [list_expr], ot.line, ot.column)
                self.expect("COLON", "attendu ':' entre la clé et la valeur d'un dictionnaire")
                value := self.parse_expression()
                if self.check("KW_FOR"):
                    comp := Node("ComprehensionExpr", ot.line, ot.column)
                    comp.comp_kind = "Dict"
                    comp.element = null
                    comp.key = key
                    comp.value = value
                    comp.clauses = self.parse_comprehension_clauses()
                    self.expect("RBRACE", "attendu '}' pour fermer la compréhension de dictionnaire")
                    return comp
                kv := Node("KeyValue", 0, 0)
                kv.key = key
                kv.value = value
                append(d.entries, kv)
                while self.accept("COMMA"):
                    if self.check("RBRACE"):
                        break
                    self.parse_dict_entry(d)
            self.expect("RBRACE", "attendu '}' pour fermer le dictionnaire")
            return d
        self.error(self.peek(), "expression attendue")

func _pattern(pk, line, column):
    p := Node("Pattern", line, column)
    p.pk = pk
    p.literal_kind = "Null"
    p.literal_value = null
    p.name = ""
    p.range_low = null
    p.range_high = null
    p.enum_type_name = ""
    p.variant_name = ""
    p.subpatterns = []
    return p

func _fpart_text(text):
    fp := Node("FStringPart", 0, 0)
    fp.is_expr = false
    fp.text = text
    fp.expr = null
    return fp

func _method_call(tmp, member, args, line, col):
    m := Node("MemberExpr", line, col)
    m.object = _a.ident(tmp, line, col)
    m.member = member
    c := Node("CallExpr", line, col)
    c.callee = m
    c.arguments = [_a.argument(null, a) for a in args]
    return c

func parse_tokens(tokens, filename="<source>"):
    return Parser(tokens, filename).parse_program()

func parse_bytes(src_bytes, filename="<source>"):
    return Parser(_lx.tokenize(src_bytes, filename), filename).parse_program()

func parse_text(text, filename="<source>"):
    return Parser(_lx.tokenize_text(text, filename), filename).parse_program()

func parse_file(path):
    return parse_bytes(_io.read_bytes(path), path)
