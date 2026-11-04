# ALEX — semantic.analyzer
#
# Analyse sémantique de la chaîne de compilation écrite en ALEX : portage fidèle de src/Analyzer.cpp.
# Résolution lexicale des noms (hissage des fonctions / struct / class / enum, corps de fonctions analysés
# après les instructions de la liste), doublons dans un même scope, réaffectation de constante, arité des
# appels de fonctions et constructeurs connus statiquement, isinstance, super, héritage et interfaces
# (conformité des méthodes), await hors async, extend réservé aux types natifs au niveau supérieur.
# S'arrête à la PREMIÈRE erreur, comme le compilateur de référence.
#
#   use semantic.analyzer as ba
#   ba.analyze(program, "prog.al")        # lève l'erreur sémantique, ou ne fait rien
#
# Erreurs : NameError, DuplicateBindingError, ConstAssignmentError, ArgumentError, InheritanceError,
#           InterfaceError, AsyncError, FeatureNotImplementedError — message « fichier:ligne:colonne: texte ».

from core use len, type
from collections use append
use bytecode.compiler as _bc

const NATIVE_EXTENDABLE := {"list": true, "str": true, "dict": true, "tuple": true, "int": true, "float": true,
    "bool": true, "char": true, "byte": true, "func": true, "null": true}

const PRELINKED := ["print", "input", "str", "__list_append", "__len", "__del_item", "__slice", "__list_insert",
    "__list_remove_at", "__list_clear", "raise", "__dict_remove_key", "isinstance"]

class Binding:
    func init(name, is_const, line, column, function_decl=null):
        self.name = name
        self.is_const = is_const
        self.line = line
        self.column = column
        self.function_decl = function_decl
        self.type_decl = null

class Scope:
    func init(kind, parent):
        self.kind = kind
        self.parent = parent
        self.bindings = {}

# [obligatoires, total] (total 0x7fff avec paramètre variadique)
func _arity_range(fn):
    req := 0
    for p in fn.params:
        if p.default_value == null and not p.is_rest:
            req += 1
    n := len(fn.params)
    return [req, n if n == 0 or not fn.params[n - 1].is_rest else 0x7fff]

class Analyzer:
    func init(filename):
        self.filename = filename
        self.current = null
        self.types = null
        self.current_class = null
        self.async_stack = []

    func error(code, line, column, message):
        raise(code, self.filename + ":" + str(line) + ":" + str(column) + ": " + message)

    func push_scope(kind):
        self.current = Scope(kind, self.current)

    func pop_scope():
        self.current = self.current.parent

    func lookup(name):
        s := self.current
        while s != null:
            if name in s.bindings:
                return s.bindings[name]
            s = s.parent
        return null

    func declare(name, is_const, line, column, fn=null):
        if name in self.current.bindings:
            self.error("DuplicateBindingError", line, column, "'" + name + "' est déjà déclaré dans ce scope (§5.1)")
        b := Binding(name, is_const, line, column, fn)
        self.current.bindings[name] = b
        return b

    func analyze(program):
        self.push_scope("Global")
        for n in PRELINKED:
            self.declare(n, false, 0, 0)
        self.types = _bc.TypeIndex(program.top_level)
        self.statements(program.top_level, true)
        self.pop_scope()

    # ------------------------------------------------------------------ instructions
    func statements(stmts, is_top=false):
        for s in stmts:
            k := s.kind
            if k == "FunctionDecl":
                if s.extends_type != "":
                    if not is_top:
                        self.error("FeatureNotImplementedError", s.line, s.column, "'extend' n'est permis qu'au niveau supérieur du fichier")
                    if not (s.extends_type in NATIVE_EXTENDABLE):
                        self.error("FeatureNotImplementedError", s.line, s.column, "'extend " + s.extends_type + "' : seuls les types natifs (list, str, dict, tuple, int, float, bool, char, byte, func, null) peuvent être étendus")
                    continue
                self.declare(s.name, false, s.line, s.column, s)
            elif k == "StructDecl":
                b := self.declare(s.name, false, s.line, s.column)
                b.type_decl = self.types.find(s.name) if is_top else null
            elif k == "ClassDecl" or k == "InterfaceDecl":
                if not is_top:
                    self.error("FeatureNotImplementedError", s.line, s.column, ("class" if k == "ClassDecl" else "interface") + " '" + s.name + "' doit être déclarée au niveau supérieur du fichier")
                b := self.declare(s.name, false, s.line, s.column)
                b.type_decl = self.types.find(s.name)
            elif k == "EnumDecl":
                self.declare(s.name, false, s.line, s.column)
        deferred := []
        for s in stmts:
            k := s.kind
            if k == "FunctionDecl" or k == "StructDecl" or k == "ClassDecl" or k == "InterfaceDecl":
                append(deferred, s)
            elif k == "EnumDecl":
                self.enum_decl(s)
            else:
                self.statement(s)
        for d in deferred:
            k := d.kind
            if k == "FunctionDecl":
                self.function_decl(d, d.extends_type != "")
            elif k == "ClassDecl":
                self.class_decl(d)
            elif k == "InterfaceDecl":
                self.interface_decl(d)
            else:
                self.struct_decl(d)

    func block(b):
        self.push_scope("Block")
        self.statements(b.statements)
        self.pop_scope()

    func assign_target(target):
        if target.kind == "Identifier":
            b := self.lookup(target.name)
            if b == null:
                self.error("NameError", target.line, target.column, "réaffectation de '" + target.name + "' : aucun binding accessible (§5.1)")
            if b.is_const:
                self.error("ConstAssignmentError", target.line, target.column, "'" + target.name + "' est une constante (const), réaffectation interdite")
            return
        if target.kind == "MemberExpr" and target.object.kind == "Identifier" and target.object.name == "super":
            self.error("InheritanceError", target.line, target.column, "on ne peut pas affecter via 'super' : les champs appartiennent à l'instance, utiliser 'self." + target.member + "'")
        self.expr(target)

    func function_decl(fn, bind_self):
        for p in fn.params:
            if p.default_value != null:
                self.expr(p.default_value)
        self.push_scope("Function")
        append(self.async_stack, fn.is_async)
        if bind_self:
            self.declare("self", false, fn.line, fn.column)
        for p in fn.params:
            self.declare(p.name, false, p.line, p.column)
        self.statements(fn.body.statements)
        self.async_stack = self.async_stack[0:len(self.async_stack) - 1]
        self.pop_scope()

    func struct_decl(s):
        self.push_scope("Block")
        for st in s.body.statements:
            if st.kind == "FunctionDecl":
                self.declare(st.name, false, st.line, st.column, st)
                self.function_decl(st, true)
            else:
                self.statement(st)
        self.pop_scope()

    func interface_decl(i):
        seen := {}
        for st in i.body.statements:
            if st.kind != "FunctionDecl":
                self.error("InterfaceError", st.line, st.column, "une interface ne peut contenir que des signatures de méthodes ('" + i.name + "')")
            if len(st.body.statements) > 0:
                self.error("InterfaceError", st.line, st.column, "la méthode '" + st.name + "' de l'interface '" + i.name + "' ne peut pas avoir de corps")
            if st.name in seen:
                self.error("DuplicateBindingError", st.line, st.column, "'" + st.name + "' est déjà déclarée dans l'interface '" + i.name + "'")
            seen[st.name] = true

    func check_class_hierarchy(c, td):
        if c.base_class == null:
            return
        base := c.base_class
        if base == c.name:
            self.error("InheritanceError", c.line, c.column, "la classe '" + c.name + "' ne peut pas hériter d'elle-même")
        b := self.lookup(base)
        if b == null:
            self.error("NameError", c.line, c.column, "la classe de base '" + base + "' n'est pas définie (extends, §26)")
        if b.type_decl != null:
            if b.type_decl.kind == "Struct":
                self.error("InheritanceError", c.line, c.column, "'" + base + "' est une struct : seule une classe peut servir de base (struct = sans héritage, §41)")
            if b.type_decl.kind == "Interface":
                self.error("InheritanceError", c.line, c.column, "'" + base + "' est une interface : utiliser 'implements' plutôt que 'extends'")
        elif b.function_decl != null:
            self.error("InheritanceError", c.line, c.column, "'" + base + "' est une fonction, pas une classe")
        if td.kind == "Class" and self.types.chain(td)[1]:
            self.error("InheritanceError", c.line, c.column, "héritage cyclique impliquant la classe '" + c.name + "'")

    func check_interface_conformance(c, td):
        seen := {}
        for iname in c.interfaces:
            if iname in seen:
                self.error("InterfaceError", c.line, c.column, "l'interface '" + iname + "' est listée deux fois dans 'implements' de '" + c.name + "'")
            seen[iname] = true
            b := self.lookup(iname)
            if b == null:
                self.error("NameError", c.line, c.column, "l'interface '" + iname + "' n'est pas définie (implements, §32)")
            if b.type_decl == null:
                continue
            if b.type_decl.kind != "Interface":
                self.error("InterfaceError", c.line, c.column, "'" + iname + "' n'est pas une interface : 'implements' n'accepte que des interfaces")
            for sig in b.type_decl.own_methods():
                fm := self.types.find_method(td, sig.name)
                impl := fm[0]
                if impl == null:
                    if fm[1] != null:
                        continue
                    self.error("InterfaceError", c.line, c.column, "la classe '" + c.name + "' n'implémente pas la méthode '" + sig.name + "' exigée par l'interface '" + iname + "'")
                ri := _arity_range(sig)
                rc := _arity_range(impl)
                if rc[0] > ri[0] or rc[1] < ri[1]:
                    span := str(ri[0]) if ri[0] == ri[1] else str(ri[0]) + " à " + str(ri[1])
                    self.error("InterfaceError", impl.line, impl.column, "la méthode '" + c.name + "." + impl.name + "' n'a pas la signature exigée par '" + iname + "." + sig.name + "' (l'interface appelle avec " + span + " argument(s))")

    func class_decl(c):
        td := self.types.find(c.name)
        if td == null:
            return
        self.check_class_hierarchy(c, td)
        self.check_interface_conformance(c, td)
        members := {}
        saved := self.current_class
        self.current_class = td
        for st in c.body.statements:
            if st.kind == "FunctionDecl":
                self._claim(members, c, st)
                self.function_decl(st, true)
            elif st.kind == "VariableDecl":
                self._claim(members, c, st)
                self.push_scope("Function")
                append(self.async_stack, false)
                self.declare("self", false, st.line, st.column)
                if not st.declared_only:
                    self.expr(st.value)
                self.async_stack = self.async_stack[0:len(self.async_stack) - 1]
                self.pop_scope()
            else:
                self.error("FeatureNotImplementedError", st.line, st.column, "le corps d'une classe ne peut contenir que des méthodes ('func') et des champs ('nom := valeur')")
        self.current_class = saved

    func _claim(members, c, st):
        if st.name in members:
            self.error("DuplicateBindingError", st.line, st.column, "'" + st.name + "' est déjà un membre de la classe '" + c.name + "'")
        members[st.name] = true

    func enum_decl(e):
        seen := {}
        for m in e.members:
            if m.name in seen:
                self.error("DuplicateBindingError", m.line, m.column, "'" + m.name + "' est déjà une variante de l'enum '" + e.name + "'")
            seen[m.name] = true

    func pattern_bindings(p):
        if p.pk == "Bind":
            self.declare(p.name, false, p.line, p.column)
        elif p.pk == "EnumVariant" or p.pk == "List" or p.pk == "Tuple":
            for sub in p.subpatterns:
                self.pattern_bindings(sub)

    func statement(s):
        k := s.kind
        if k == "VariableDecl":
            if s.declared_only:
                self.error("FeatureNotImplementedError", s.line, s.column, "'" + s.name + "' : une déclaration sans valeur (nom: Type) n'est permise que pour un champ de classe ou de struct")
            self.expr(s.value)
            self.declare(s.name, false, s.line, s.column)
        elif k == "ConstDecl":
            self.expr(s.value)
            self.declare(s.name, true, s.line, s.column)
        elif k == "Assignment" or k == "CompoundAssignment":
            self.assign_target(s.target)
            self.expr(s.value)
        elif k == "ExpressionStmt":
            self.expr(s.expr)
        elif k == "IfStmt":
            self.expr(s.condition)
            self.block(s.then_block)
            for e in s.elif_clauses:
                self.expr(e.condition)
                self.block(e.body)
            if s.else_block != null:
                self.block(s.else_block)
        elif k == "WhileStmt":
            self.expr(s.condition)
            self.block(s.body)
            if s.else_body != null:
                self.block(s.else_body)
        elif k == "ForStmt":
            self.expr(s.iterable)
            self.push_scope("Block")
            self.declare(s.variable, false, s.line, s.column)
            self.statements(s.body.statements)
            self.pop_scope()
            if s.else_body != null:
                self.block(s.else_body)
        elif k == "BreakStmt" or k == "ContinueStmt":
            return
        elif k == "ReturnStmt":
            if s.value != null:
                self.expr(s.value)
        elif k == "TryStmt":
            self.block(s.try_block)
            for c in s.catch_clauses:
                self.push_scope("Block")
                if c.name != null:
                    self.declare(c.name, false, s.line, s.column)
                self.statements(c.body.statements)
                self.pop_scope()
            if s.finally_block != null:
                self.block(s.finally_block)
        elif k == "FunctionDecl":
            self.declare(s.name, false, s.line, s.column, s)
            self.function_decl(s, false)
        elif k == "StructDecl":
            self.declare(s.name, false, s.line, s.column)
            self.struct_decl(s)
        elif k == "EnumDecl":
            self.declare(s.name, false, s.line, s.column)
            self.enum_decl(s)
        elif k == "MatchStmt":
            self.expr(s.subject)
            for c in s.cases:
                self.push_scope("Block")
                self.pattern_bindings(c.pattern)
                if c.guard != null:
                    self.expr(c.guard)
                self.statements(c.body.statements)
                self.pop_scope()
        elif k == "ClassDecl" or k == "InterfaceDecl":
            self.error("FeatureNotImplementedError", s.line, s.column, k + " doit être déclarée au niveau supérieur du fichier")
        elif k == "ImportStmt":
            if not s.is_from:
                self.declare(s.alias if s.alias != null else s.module_path[len(s.module_path) - 1], false, s.line, s.column)
            else:
                for n in s.names:
                    self.declare(n, false, s.line, s.column)
        else:
            self.error("NameError", s.line, s.column, "instruction non prise en charge par l'analyseur sémantique P2")

    # ------------------------------------------------------------------ expressions
    func check_call_arity(call, fn, label=""):
        fname := fn.name if label == "" else label
        n := len(fn.params)
        has_rest := n > 0 and fn.params[n - 1].is_rest
        for a in call.arguments:
            if a.name == null and a.value.kind == "UnaryExpr" and a.value.op == "Spread":
                return
            if a.name != null and has_rest:
                self.error("ArgumentError", call.line, call.column, "les arguments nommés ne sont pas supportés pour '" + fname + "' (paramètre variadique '*" + fn.params[n - 1].name + "')")
        if has_rest:
            n -= 1
        filled := [false for i in 0..n]
        positional := 0
        for a in call.arguments:
            if a.name == null:
                if positional >= n and has_rest:
                    continue
                if positional >= n:
                    self.error("ArgumentError", call.line, call.column, "trop d'arguments dans l'appel de '" + fname + "' (attendu au plus " + str(n) + ")")
                filled[positional] = true
                positional += 1
        for a in call.arguments:
            if a.name == null:
                continue
            idx := -1
            i := 0
            while i < len(fn.params):
                if fn.params[i].name == a.name:
                    idx = i
                    break
                i += 1
            if idx < 0:
                self.error("ArgumentError", call.line, call.column, "l'argument nommé '" + a.name + "' ne correspond à aucun paramètre de '" + fname + "'")
            if filled[idx]:
                self.error("ArgumentError", call.line, call.column, "l'argument '" + a.name + "' est fourni à la fois positionnellement et par nom dans l'appel de '" + fname + "'")
            filled[idx] = true
        i := 0
        while i < n:
            if not filled[i] and fn.params[i].default_value == null:
                self.error("ArgumentError", call.line, call.column, "argument manquant pour le paramètre '" + fn.params[i].name + "' de '" + fname + "'")
            i += 1

    func check_construction(call, td):
        if td.kind == "Interface":
            self.error("InterfaceError", call.line, call.column, "l'interface '" + td.name + "' ne peut pas être instanciée : elle ne décrit qu'un contrat")
        if td.kind != "Class":
            return
        fm := self.types.find_method(td, "init")
        if fm[0] != null:
            self.check_call_arity(call, fm[0], td.name)
        elif fm[1] == null and len(call.arguments) > 0:
            self.error("ArgumentError", call.line, call.column, "la classe '" + td.name + "' n'a pas de constructeur 'init' : aucun argument attendu, " + str(len(call.arguments)) + " fourni(s)")

    func check_super_call(call, member):
        base := self.types.find(self.current_class.base)
        if base == null or base.kind != "Class":
            return
        fm := self.types.find_method(base, member.member)
        if fm[0] == null:
            if fm[1] != null:
                return
            self.error("InheritanceError", call.line, call.column, "aucune classe parente de '" + self.current_class.name + "' ne définit la méthode '" + member.member + "'")
        self.check_call_arity(call, fm[0], "super." + member.member)

    func _is_qualified(e):
        return e.kind == "MemberExpr" and e.object.kind == "Identifier"

    func call_expr(call):
        if call.callee.kind == "Identifier":
            name := call.callee.name
            b := self.lookup(name)
            if b == null:
                self.error("NameError", call.callee.line, call.callee.column, "'" + name + "' n'est pas défini (§5.3)")
            if name == "isinstance":
                args := call.arguments
                shape_ok := len(args) == 2 and args[0].name == null and args[1].name == null and (args[1].value.kind == "Identifier" or self._is_qualified(args[1].value))
                if not shape_ok:
                    self.error("ArgumentError", call.line, call.column, "isinstance attend (valeur, NomDeType) : deux arguments positionnels, le second étant un nom de type")
                ta := args[1].value
                if self._is_qualified(ta):
                    alias := ta.object
                    if self.lookup(alias.name) == null:
                        self.error("NameError", alias.line, alias.column, "'" + alias.name + "' n'est pas défini (§5.3)")
                    self.expr(args[0].value)
                    return
                tb := self.lookup(ta.name)
                if tb == null:
                    self.error("NameError", ta.line, ta.column, "'" + ta.name + "' n'est pas défini (§5.3)")
                if tb.function_decl != null:
                    self.error("ArgumentError", ta.line, ta.column, "'" + ta.name + "' est une fonction : isinstance attend un nom de struct, class ou interface")
                self.expr(args[0].value)
                return
            if b.function_decl != null:
                self.check_call_arity(call, b.function_decl)
            elif b.type_decl != null:
                self.check_construction(call, b.type_decl)
        else:
            self.expr(call.callee)
            if call.callee.kind == "MemberExpr":
                m := call.callee
                if m.object.kind == "Identifier" and m.object.name == "super":
                    self.check_super_call(call, m)
        for a in call.arguments:
            self.expr(a.value)

    func expr(e):
        k := e.kind
        if k == "Literal":
            return
        if k == "Identifier":
            if e.name == "super":
                self.error("InheritanceError", e.line, e.column, "'super' ne s'utilise que sous la forme 'super.membre'")
            if self.lookup(e.name) == null:
                self.error("NameError", e.line, e.column, "'" + e.name + "' n'est pas défini (§5.3)")
            return
        if k == "ListLiteral" or k == "TupleLiteral":
            for x in e.elements:
                self.expr(x)
            return
        if k == "DictLiteral":
            for kv in e.entries:
                self.expr(kv.key)
                self.expr(kv.value)
            return
        if k == "FStringLiteral":
            for p in e.parts:
                if p.is_expr:
                    self.expr(p.expr)
            return
        if k == "BinaryExpr":
            self.expr(e.left)
            self.expr(e.right)
            return
        if k == "UnaryExpr":
            if e.op == "Await" and len(self.async_stack) > 0 and not self.async_stack[len(self.async_stack) - 1]:
                self.error("AsyncError", e.line, e.column, "'await' n'est permis que dans une 'async func' ou au niveau supérieur d'un module")
            self.expr(e.operand)
            return
        if k == "ConditionalExpr":
            self.expr(e.condition)
            self.expr(e.then_expr)
            self.expr(e.else_expr)
            return
        if k == "RangeExpr":
            self.expr(e.start)
            self.expr(e.end)
            return
        if k == "CallExpr":
            self.call_expr(e)
            return
        if k == "LambdaExpr":
            self.function_decl(e.function, false)
            return
        if k == "ComprehensionExpr":
            opened := 0
            for c in e.clauses:
                self.expr(c.expr)
                if c.clause_kind == "For":
                    self.push_scope("Block")
                    opened += 1
                    self.declare(c.variable, false, c.line, c.column)
            if e.comp_kind == "Dict":
                self.expr(e.key)
                self.expr(e.value)
            else:
                self.expr(e.element)
            while opened > 0:
                self.pop_scope()
                opened -= 1
            return
        if k == "IndexExpr":
            self.expr(e.object)
            self.expr(e.index)
            return
        if k == "MemberExpr":
            if e.object.kind == "Identifier" and e.object.name == "super":
                if self.current_class == null:
                    self.error("InheritanceError", e.line, e.column, "'super' n'est utilisable que dans une méthode de classe")
                if self.current_class.base == null:
                    self.error("InheritanceError", e.line, e.column, "'super' est inutilisable : la classe '" + self.current_class.name + "' n'a pas de classe de base")
                return
            self.expr(e.object)
            return
        if k == "ErrorPropagationExpr":
            self.expr(e.operand)
            return
        self.error("NameError", e.line, e.column, "expression non prise en charge par l'analyseur sémantique P2")

func analyze(program, filename="<source>"):
    Analyzer(filename).analyze(program)
