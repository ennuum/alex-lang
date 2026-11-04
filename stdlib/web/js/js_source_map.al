# ALEX STANDARD LIBRARY — web.js.js_source_map
#
# Cartes de sources (Source Map v3) : encodage / décodage VLQ base64, construction d'une carte (associations
# position générée -> position d'origine, noms), sérialisation JSON, lecture, recherche de la position
# d'origine, commentaire sourceMappingURL (fichier ou carte en ligne data:), composition de deux cartes.
# Lignes et colonnes comptées à partir de 0, comme dans la spécification.
#
#   use web.js.js_source_map as sm
#   m := sm.SourceMap("app.min.js")
#   src := m.add_source("app.js", "let x = 1;")
#   m.add(0, 0, src, 0, 0)
#   m.add(0, 4, src, 0, 4, "x")
#   m.to_json()                    # {"version":3,"file":"app.min.js","sources":["app.js"],"names":["x"],"mappings":"AAAA,IAAIA",...}
#   sm.encode_vlq([0, 0, 0, 0])    # AAAA
#   sm.decode_vlq("IAAIA")         # [4, 0, 0, 4, 0]
#   m2 := sm.parse(json_texte)
#   m2.original_position(0, 5)     # {"source": "app.js", "line": 0, "column": 4, "name": "x"}
#   sm.comment("app.min.js.map")   # //# sourceMappingURL=app.min.js.map
#   sm.inline_comment(m)           # //# sourceMappingURL=data:application/json;charset=utf-8;base64,…
#
# Erreurs : JsValueError (VLQ invalide, carte mal formée, version non prise en charge).

from core use len, type, to_int
from collections use append, keys
use string as _s
use json as _json
use network.encoding as _enc
use web.js.js_errors as _err

const _B64 := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

func _b64_index(c):
    o := _s.ord(c)
    if o >= 65 and o <= 90:
        return o - 65
    if o >= 97 and o <= 122:
        return o - 71
    if o >= 48 and o <= 57:
        return o + 4
    if c == '+':
        return 62
    if c == '/':
        return 63
    return -1

func _encode_one(v):
    x := (-v * 2 + 1) if v < 0 else v * 2
    out := []
    while true:
        digit := x % 32
        x = to_int(x / 32)
        if x > 0:
            digit = digit + 32
        append(out, str(_B64[digit]))
        if x == 0:
            break
    return _s.join("", out)

# Segment VLQ base64 d'une liste d'entiers.
func encode_vlq(values):
    parts := []
    for v in values:
        append(parts, _encode_one(to_int(v)))
    return _s.join("", parts)

# Entiers d'un segment VLQ base64.
func decode_vlq(text):
    out := []
    value := 0
    shift := 0
    for c in text:
        d := _b64_index(c)
        if d < 0:
            _err.value_error("js_source_map.decode_vlq", "caractère VLQ invalide « " + str(c) + " »")
        cont := d >= 32
        d = d % 32
        value = value + d * _pow2(shift)
        shift += 5
        if not cont:
            neg := value % 2 == 1
            v := to_int(value / 2)
            append(out, -v if neg else v)
            value = 0
            shift = 0
    if shift != 0:
        _err.value_error("js_source_map.decode_vlq", "segment VLQ incomplet")
    return out

func _pow2(k):
    r := 1
    i := 0
    while i < k:
        r = r * 2
        i += 1
    return r

# Association : position générée (ligne, colonne) -> source (indice), ligne, colonne, nom (indice) facultatifs.
class Mapping:
    func init(gen_line, gen_column, source=null, line=null, column=null, name=null):
        self.gen_line = gen_line
        self.gen_column = gen_column
        self.source = source
        self.line = line
        self.column = column
        self.name = name

class SourceMap:
    func init(file=null, source_root=null):
        self.file = file
        self.source_root = source_root
        self.sources = []
        self.sources_content = []
        self.names = []
        self.mappings = []
        self.ignore_list = []

    # Indice d'une source (ajoutée si besoin) ; content : texte d'origine embarqué (sourcesContent).
    func add_source(path, content=null):
        i := 0
        while i < len(self.sources):
            if self.sources[i] == path:
                if content != null:
                    self.sources_content[i] = content
                return i
            i += 1
        append(self.sources, path)
        append(self.sources_content, content)
        return len(self.sources) - 1

    func name_index(name):
        i := 0
        while i < len(self.names):
            if self.names[i] == name:
                return i
            i += 1
        append(self.names, name)
        return len(self.names) - 1

    # source : indice ou chemin ; name : texte ou null.
    func add(gen_line, gen_column, source=null, line=null, column=null, name=null):
        si := source
        if type(source) == "str":
            si = self.add_source(source)
        ni := null
        if name != null:
            ni = self.name_index(name)
        append(self.mappings, Mapping(gen_line, gen_column, si, line, column, ni))
        return self

    func sorted_mappings():
        out := []
        for m in self.mappings:
            append(out, m)
        i := 1
        while i < len(out):
            cur := out[i]
            j := i - 1
            while j >= 0 and (out[j].gen_line > cur.gen_line or (out[j].gen_line == cur.gen_line and out[j].gen_column > cur.gen_column)):
                out[j + 1] = out[j]
                j -= 1
            out[j + 1] = cur
            i += 1
        return out

    # Champ « mappings » encodé.
    func encode_mappings():
        ms := self.sorted_mappings()
        lines := []
        cur_line := 0
        segs := []
        prev_col := 0
        prev_src := 0
        prev_line := 0
        prev_col_src := 0
        prev_name := 0
        for m in ms:
            while cur_line < m.gen_line:
                append(lines, _s.join(",", segs))
                segs = []
                cur_line += 1
                prev_col = 0
            vals := [m.gen_column - prev_col]
            prev_col = m.gen_column
            if m.source != null:
                append(vals, m.source - prev_src)
                append(vals, m.line - prev_line)
                append(vals, m.column - prev_col_src)
                prev_src = m.source
                prev_line = m.line
                prev_col_src = m.column
                if m.name != null:
                    append(vals, m.name - prev_name)
                    prev_name = m.name
            append(segs, encode_vlq(vals))
        append(lines, _s.join(",", segs))
        return _s.join(";", lines)

    func to_dict():
        d := {"version": 3}
        if self.file != null:
            d["file"] = self.file
        if self.source_root != null:
            d["sourceRoot"] = self.source_root
        d["sources"] = self.sources
        has_content := false
        for c in self.sources_content:
            if c != null:
                has_content = true
        if has_content:
            d["sourcesContent"] = self.sources_content
        d["names"] = self.names
        d["mappings"] = self.encode_mappings()
        if len(self.ignore_list) > 0:
            d["ignoreList"] = self.ignore_list
        return d

    func to_json(indent=null):
        return _json.stringify(self.to_dict(), indent, false)

    # Position d'origine de la position générée (dernière association de la ligne à gauche de la colonne).
    func original_position(gen_line, gen_column):
        best := null
        for m in self.mappings:
            if m.gen_line == gen_line and m.gen_column <= gen_column and m.source != null:
                if best == null or m.gen_column >= best.gen_column:
                    best = m
        if best == null:
            return null
        return {"source": self.sources[best.source], "line": best.line, "column": best.column, "name": self.names[best.name] if best.name != null else null}

    # Positions générées correspondant à une position d'origine.
    func generated_positions(source, line, column=null):
        si := -1
        i := 0
        while i < len(self.sources):
            if self.sources[i] == source:
                si = i
            i += 1
        out := []
        for m in self.mappings:
            if m.source == si and m.line == line and (column == null or m.column == column):
                append(out, (m.gen_line, m.gen_column))
        return out

# Lit une carte (texte JSON ou dict).
func parse(data):
    d := _json.parse(data) if type(data) == "str" else data
    if not ("version" in d) or d["version"] != 3:
        _err.value_error("js_source_map.parse", "version de carte non prise en charge")
    if "sections" in d:
        _err.value_error("js_source_map.parse", "cartes indexées (sections) non prises en charge")
    m := SourceMap(d["file"] if "file" in d else null, d["sourceRoot"] if "sourceRoot" in d else null)
    contents := d["sourcesContent"] if "sourcesContent" in d else []
    i := 0
    for s in d["sources"]:
        append(m.sources, s)
        append(m.sources_content, contents[i] if i < len(contents) else null)
        i += 1
    for nm in (d["names"] if "names" in d else []):
        append(m.names, nm)
    line := 0
    src := 0
    oline := 0
    ocol := 0
    name := 0
    for group in _s.split(d["mappings"], ";"):
        col := 0
        if group != "":
            for seg in _s.split(group, ","):
                if seg == "":
                    continue
                v := decode_vlq(seg)
                col += v[0]
                if len(v) >= 4:
                    src += v[1]
                    oline += v[2]
                    ocol += v[3]
                    nm := null
                    if len(v) >= 5:
                        name += v[4]
                        nm = name
                    append(m.mappings, Mapping(line, col, src, oline, ocol, nm))
                elif len(v) == 1:
                    append(m.mappings, Mapping(line, col))
                else:
                    _err.value_error("js_source_map.parse", "segment de longueur " + str(len(v)) + " invalide")
        line += 1
    return m

func comment(url, css=false):
    if css:
        return "/*# sourceMappingURL=" + url + " */"
    return "//# sourceMappingURL=" + url

func inline_comment(m, css=false):
    data := "data:application/json;charset=utf-8;base64," + _enc.base64_encode(m.to_json())
    return comment(data, css)

# URL de carte citée dans un source (commentaire final), ou null.
func find_url(source):
    i := -1
    k := 0
    while true:
        j := _s.find(source[k:len(source)], "sourceMappingURL=")
        if j < 0:
            break
        i = k + j
        k = i + 1
    if i < 0:
        return null
    rest := source[i + 17:len(source)]
    j := 0
    while j < len(rest) and rest[j] != ' ' and rest[j] != '\n' and rest[j] != '\r' and rest[j] != '*':
        j += 1
    return rest[0:j]

# Carte de c ∘ b : b associe le code intermédiaire aux sources, outer associe le code final à l'intermédiaire.
func compose(outer, inner):
    out := SourceMap(outer.file)
    for m in outer.mappings:
        if m.source == null:
            continue
        p := inner.original_position(m.line, m.column)
        if p == null:
            continue
        out.add(m.gen_line, m.gen_column, p["source"], p["line"], p["column"], p["name"])
    return out
