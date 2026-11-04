# ALEX STANDARD LIBRARY — web.js.js_generator
#
# Génération de code JavaScript : CodeWriter (écriture indentée qui suit la ligne et la colonne courantes et
# enregistre des associations pour une carte de sources), génération d'un AST (web.js.js_statement /
# js_expression / js_function) avec un style, et concaténation de fichiers avec carte de sources ligne à ligne.
#
#   use web.js.js_generator as jg
#   w := jg.CodeWriter()
#   w.line("function f() {", ("src.al", 0, 0))      # association vers src.al ligne 0 colonne 0
#   w.indent()
#   w.line("return 1;", ("src.al", 1, 4))
#   w.dedent()
#   w.line("}")
#   w.text()                       # function f() {\n  return 1;\n}\n
#   w.source_map("out.js").to_json()
#   jg.generate([js.const_decl("x", 1), je.log([je.ident("x")])])       # const x = 1;\nconsole.log(x);\n
#   r := jg.concat([("a.js", "let a = 1;\n"), ("b.js", "let b = 2;\n")], "bundle.js")
#   r.code, r.map.to_json()        # code concaténé et sa carte
#
# Erreurs : JsError (dédentation sous zéro).

from core use len, type
from collections use append
use string as _s
use web.js.js_errors as _err
use web.js.js_expression as _e
use web.js.js_statement as _st
use web.js.js_source_map as _sm

class CodeWriter:
    func init(indent_text="  "):
        self.indent_text = indent_text
        self.level = 0
        self.parts = []
        self.gen_line = 0
        self.gen_col = 0
        self.mappings = []        # (ligne, colonne, source, ligne_src, colonne_src, nom)
        self.at_line_start = true

    func indent():
        self.level += 1
        return self

    func dedent():
        if self.level == 0:
            _err.js_error("CodeWriter.dedent", "indentation déjà à zéro")
        self.level -= 1
        return self

    func _advance(text):
        for c in text:
            if c == '\n':
                self.gen_line += 1
                self.gen_col = 0
            else:
                self.gen_col += 1

    # Écrit du texte ; origin : (source, ligne, colonne[, nom]) associée au début du texte.
    func write(text, origin=null):
        t := str(text)
        if t == "":
            return self
        if self.at_line_start and self.level > 0 and t != "\n":
            pad := _s.repeat(self.indent_text, self.level)
            append(self.parts, pad)
            self._advance(pad)
        if origin != null:
            append(self.mappings, (self.gen_line, self.gen_col, origin[0], origin[1], origin[2], origin[3] if len(origin) > 3 else null))
        append(self.parts, t)
        self._advance(t)
        self.at_line_start = _s.ends_with(t, "\n")
        return self

    func line(text="", origin=null):
        if text != "":
            self.write(text, origin)
        append(self.parts, "\n")
        self._advance("\n")
        self.at_line_start = true
        return self

    func blank():
        return self.line()

    # Bloc « tête { … } » : fn reçoit le writer pour écrire le contenu.
    func block(head, fn, origin=null):
        self.line(head + " {", origin)
        self.indent()
        fn(self)
        self.dedent()
        self.line("}")
        return self

    func position():
        return (self.gen_line, self.gen_col)

    func text():
        return _s.join("", self.parts)

    func __str__():
        return self.text()

    func source_map(file=null, contents=null):
        m := _sm.SourceMap(file)
        for mp in self.mappings:
            src := mp[2]
            content := contents[src] if contents != null and src in contents else null
            si := m.add_source(src, content)
            m.add(mp[0], mp[1], si, mp[3], mp[4], mp[5])
        return m

# Code d'un nœud ou d'une liste d'instructions (style : web.js.js_expression.Style, texte d'indentation ou null).
func generate(node, style=null):
    s := _e.style_of(style)
    if type(node) == "list":
        return _st.Program(node).emit(s, 0)
    if isinstance(node, _e.Expr) or isinstance(node, _st.Stmt) or _st._is_declaration(node):
        return node.emit(s, 0)
    return _e.expr(node).emit(s, 0)

func generate_compact(node):
    return generate(node, _e.compact_style())

class Concatenated:
    func init(code, source_map):
        self.code = code
        self.map = source_map

# Concatène des fichiers (liste de (chemin, code)) avec une carte associant chaque ligne à son origine ;
# separator : texte inséré entre les fichiers ; embed : contenu d'origine embarqué dans la carte.
func concat(files, out_file=null, separator="\n", embed=true):
    w := CodeWriter("")
    m := _sm.SourceMap(out_file)
    for f in files:
        path := f[0]
        code := f[1]
        si := m.add_source(path, code if embed else null)
        lines := _s.split(code, "\n")
        i := 0
        while i < len(lines):
            ln := lines[i]
            last := i == len(lines) - 1
            if last and ln == "":
                break
            if ln != "":
                m.add(w.gen_line, 0, si, i, 0)
            w.write(ln)
            if not last:
                w.line()
            i += 1
        if not _s.ends_with(code, "\n") and code != "":
            w.line()
        if separator != "\n" and separator != "":
            w.write(separator)
    return Concatenated(w.text(), m)

# Commentaire d'en-tête « /*! … */ » conservé par les minifieurs.
func banner(text):
    return "/*! " + _s.replace(str(text), "*/", "* /") + " */\n"
