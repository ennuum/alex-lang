# ALEX — ast
#
# Arbre syntaxique de la chaîne de compilation vers bytecode : même forme que l'AST du compilateur de
# référence (include/alex/ast/Ast.hpp), APRÈS ses désucrages (décorateurs, with, assert, del, pass,
# déstructuration, tranches, ensembles, extend...). Un nœud est un Node : genre (kind, nom de NodeKind :
# « BinaryExpr », « ForStmt »...), position (line, column) et champs nommés comme en C++ (en snake_case).
#
#   Expressions : Literal(literal_kind, value), Identifier(name), ListLiteral(elements), TupleLiteral(elements),
#     DictLiteral(entries : KeyValue(key, value)), FStringLiteral(parts : FStringPart(is_expr, text, expr)),
#     BinaryExpr(op, left, right), UnaryExpr(op, operand), ConditionalExpr(condition, then_expr, else_expr),
#     RangeExpr(start, end), CallExpr(callee, arguments : Argument(name, value)), IndexExpr(object, index),
#     MemberExpr(object, member), ErrorPropagationExpr(operand), LambdaExpr(function),
#     ComprehensionExpr(comp_kind, element, key, value, clauses : CompClause(kind, variable, expr)).
#   Instructions : Block(statements), VariableDecl(name, type, value, declared_only), ConstDecl(name, type, value),
#     Assignment(target, value), CompoundAssignment(op, target, value), ExpressionStmt(expr),
#     IfStmt(condition, then_block, elif_clauses : ElifClause(condition, body), else_block),
#     WhileStmt(condition, body, else_body), ForStmt(variable, iterable, body, else_body), BreakStmt, ContinueStmt,
#     ReturnStmt(value), TryStmt(try_block, catch_clauses : CatchClause(name, types, body), finally_block),
#     MatchStmt(subject, cases : MatchCase(pattern, guard, body)), FunctionDecl(name, is_async, params, return_type,
#     body, extends_type), StructDecl(name, body), ClassDecl(name, base_class, interfaces, body),
#     InterfaceDecl(name, body), EnumDecl(name, members : EnumMember(name, fields)),
#     ImportStmt(is_from, module_path, names, alias), Program(top_level, uses_set_literal).
#   Auxiliaires : Param(name, type, default_value, is_rest), TypeRef(name, args, nullable),
#     Pattern(pk, literal_kind, literal_value, name, range_low, range_high, enum_type_name, variant_name, subpatterns).
#
#   use ast as ba
#   n := ba.node("Identifier", 3, 5)
#   n.name = "x"
#   print(ba.dump(n))              # (Identifier x)
#
# Opérateurs : BinaryOp (« Add », « Sub », ..., « In », « NotIn »), UnaryOp (« Plus », « Minus », « Not »,
# « BitNot », « Await », « Spread », « DictSpread »).

from core use len, type
from collections use append
use string as _s

const LAMBDA_NAME := "<lambda>"

_uid := [0]

# uid : identifiant unique du nœud (clé des tables d'analyse, ex. résultats d'entiers dimensionnés).
class Node:
    func init(kind, line=0, column=0):
        self.kind = kind
        self.line = line
        self.column = column
        _uid[0] += 1
        self.uid = _uid[0]

func node(kind, line=0, column=0):
    return Node(kind, line, column)

func ident(name, line, column):
    n := Node("Identifier", line, column)
    n.name = name
    return n

func literal(kind, value, line, column):
    n := Node("Literal", line, column)
    n.literal_kind = kind
    n.value = value
    return n

func int_lit(v, line, column):
    return literal("Integer", v, line, column)

func null_lit(line, column):
    return literal("Null", null, line, column)

func str_lit(v, line, column):
    return literal("String", v, line, column)

func argument(name, value):
    a := Node("Argument", 0, 0)
    a.name = name
    a.value = value
    return a

func call(fn, args, line, column):
    c := Node("CallExpr", line, column)
    c.callee = ident(fn, line, column)
    c.arguments = [argument(null, a) for a in args]
    return c

func binary(op, l, r, line, column):
    e := Node("BinaryExpr", line, column)
    e.op = op
    e.left = l
    e.right = r
    return e

func index(obj, i, line, column):
    e := Node("IndexExpr", line, column)
    e.object = ident(obj, line, column)
    e.index = int_lit(i, line, column)
    return e

func block(statements, line, column):
    b := Node("Block", line, column)
    b.statements = statements
    return b

const BINARY_TEXT := {"Add": "+", "Sub": "-", "Mul": "*", "Div": "/", "FloorDiv": "//", "Mod": "%", "Pow": "**",
    "Eq": "==", "Ne": "!=", "Lt": "<", "Le": "<=", "Gt": ">", "Ge": ">=", "And": "and", "Or": "or", "BitAnd": "&",
    "BitOr": "|", "BitXor": "^", "Shl": "<<", "Shr": ">>", "In": "in", "NotIn": "not in"}

func type_ref_text(t):
    if t == null:
        return "any"
    s := t.name
    if len(t.args) > 0:
        s += "[" + _s.join(", ", [type_ref_text(a) for a in t.args]) + "]"
    if t.nullable:
        s += "?"
    return s

# Forme lisible (S-expression), pour le diagnostic.
func dump(n, depth=0):
    pad := _s.repeat("  ", depth)
    if n == null:
        return pad + "null"
    if type(n) == "list":
        return _s.join("\n", [dump(x, depth) for x in n])
    k := n.kind
    head := k
    if k == "Identifier":
        head += " " + n.name
    elif k == "Literal":
        head += " " + str(n.value)
    elif k == "BinaryExpr" or k == "UnaryExpr" or k == "CompoundAssignment":
        head += " " + n.op
    elif k == "MemberExpr":
        head += " ." + n.member
    elif k == "FunctionDecl" or k == "StructDecl" or k == "ClassDecl" or k == "VariableDecl" or k == "ConstDecl" or k == "EnumDecl" or k == "InterfaceDecl":
        head += " " + n.name
    elif k == "ForStmt":
        head += " " + n.variable
    elif k == "ImportStmt":
        head += " " + _s.join(".", n.module_path)
    out := [pad + "(" + head + " @" + str(n.line) + ":" + str(n.column)]
    for f in _children(n):
        if f != null:
            append(out, dump(f, depth + 1))
    return _s.join("\n", out) + ")"

func _children(n):
    k := n.kind
    if k == "BinaryExpr":
        return [n.left, n.right]
    if k == "UnaryExpr" or k == "ErrorPropagationExpr":
        return [n.operand]
    if k == "CallExpr":
        return [n.callee] + [a.value for a in n.arguments]
    if k == "MemberExpr":
        return [n.object]
    if k == "IndexExpr":
        return [n.object, n.index]
    if k == "ListLiteral" or k == "TupleLiteral":
        return n.elements
    if k == "Block":
        return n.statements
    if k == "Program":
        return n.top_level
    if k == "ExpressionStmt":
        return [n.expr]
    if k == "ReturnStmt":
        return [n.value]
    if k == "VariableDecl" or k == "ConstDecl":
        return [n.value]
    if k == "Assignment" or k == "CompoundAssignment":
        return [n.target, n.value]
    if k == "FunctionDecl":
        return [n.body]
    if k == "IfStmt":
        return [n.condition, n.then_block, n.else_block]
    if k == "WhileStmt":
        return [n.condition, n.body]
    if k == "ForStmt":
        return [n.iterable, n.body]
    if k == "LambdaExpr":
        return [n.function]
    return []
