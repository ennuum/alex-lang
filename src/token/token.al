# ALEX — token
#
# Jetons produits par le lexer (src/lexer) : classe Token (type, lexème, valeur, ligne, colonne) et table des
# mots-clés (texte -> nom de TokenType : « KW_IF », « KW_FUNC »...).
#
#   use token as tk
#   t := tk.Token("IDENTIFIER", "x", null, 1, 1)
#   print(t.describe(), tk.KEYWORDS["if"])          # IDENTIFIER `x` 1:1 KW_IF

const KEYWORDS := {"and": "KW_AND", "as": "KW_AS", "async": "KW_ASYNC", "await": "KW_AWAIT", "break": "KW_BREAK",
    "finally": "KW_FINALLY", "catch": "KW_CATCH", "class": "KW_CLASS", "const": "KW_CONST",
    "continue": "KW_CONTINUE", "else": "KW_ELSE", "elif": "KW_ELIF", "enum": "KW_ENUM", "extends": "KW_EXTENDS",
    "false": "KW_FALSE", "for": "KW_FOR", "from": "KW_FROM", "func": "KW_FUNC", "if": "KW_IF",
    "import": "KW_IMPORT", "in": "KW_IN", "interface": "KW_INTERFACE", "let": "KW_LET", "match": "KW_MATCH",
    "not": "KW_NOT", "null": "KW_NULL", "or": "KW_OR", "return": "KW_RETURN", "self": "KW_SELF",
    "struct": "KW_STRUCT", "super": "KW_SUPER", "true": "KW_TRUE", "try": "KW_TRY", "use": "KW_USE",
    "while": "KW_WHILE", "yield": "KW_YIELD"}

class Token:
    func init(type, lexeme, value, line, column):
        self.type = type
        self.lexeme = lexeme
        self.value = value
        self.line = line
        self.column = column

    func describe():
        return self.type + " `" + self.lexeme + "` " + str(self.line) + ":" + str(self.column)
