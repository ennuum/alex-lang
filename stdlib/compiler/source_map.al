# ALEX STANDARD LIBRARY — compiler.source_map
#
# Positions dans les sources et correspondances source ↔ code généré.
#   SourceFile(nom, texte)   décalage <-> (ligne, colonne), texte d'une ligne, extrait avec contexte
#   SourceMap()              correspondances (ligne_gen, col_gen) -> (fichier, ligne, colonne, nom) ;
#                            lookup trouve la correspondance la plus proche qui précède ; export au format
#                            Source Map v3 (VLQ base 64, comme JavaScript) et relecture
#
#   use compiler.source_map as sm
#   f := sm.SourceFile("main.al", texte)
#   print(f.position(42))               # [3, 7] (ligne, colonne ; base 1)
#   print(f.offset(3, 7), f.line_text(3))
#   m := sm.SourceMap("main.out")
#   m.add(1, 1, "main.al", 3, 5, "total")
#   print(m.lookup(1, 9))               # {"file": "main.al", "line": 3, "column": 5, "name": "total"}
#   json_v3 := m.to_v3()                # {"version": 3, "sources": [...], "mappings": "AAEA..."}
#   m2 := sm.from_v3(json_v3)
#
# Lignes et colonnes en base 1 (comme les diagnostics) ; le format v3 est en base 0 en interne.
# Erreurs : IndexError (position hors du fichier), ValueError (VLQ invalide).

from core use len, type
from collections use append
use string as _s

class SourceFile:
    func init(name, text):
        self.name = name
        self.text = text
        self.starts = [0]
        i := 0
        n := len(text)
        while i < n:
            if text[i] == '\n':
                append(self.starts, i + 1)
            i += 1

    func line_count():
        return len(self.starts)

    # (ligne, colonne) d'un décalage (base 0) dans le texte.
    func position(offset):
        if offset < 0 or offset > len(self.text):
            raise("IndexError", "SourceFile.position : décalage " + str(offset) + " hors du fichier")
        lo := 0
        hi := len(self.starts) - 1
        while lo < hi:
            mid := (lo + hi + 1) // 2
            if self.starts[mid] <= offset:
                lo = mid
            else:
                hi = mid - 1
        return [lo + 1, offset - self.starts[lo] + 1]

    func offset(line, column):
        if line < 1 or line > len(self.starts):
            raise("IndexError", "SourceFile.offset : ligne " + str(line) + " hors du fichier")
        return self.starts[line - 1] + column - 1

    func line_text(line):
        if line < 1 or line > len(self.starts):
            raise("IndexError", "SourceFile.line_text : ligne " + str(line) + " hors du fichier")
        a := self.starts[line - 1]
        b := len(self.text)
        if line < len(self.starts):
            b = self.starts[line] - 1
        return _s.substring(self.text, a, b)

    # Lignes [line - before, line + after] numérotées, la ligne visée marquée par « > ».
    func excerpt(line, before=2, after=2):
        out := []
        a := line - before
        if a < 1:
            a = 1
        b := line + after
        if b > len(self.starts):
            b = len(self.starts)
        k := a
        while k <= b:
            mark := "  "
            if k == line:
                mark = "> "
            append(out, mark + _pad_left(str(k), len(str(b))) + " | " + self.line_text(k))
            k += 1
        return _s.join("\n", out)

func _pad_left(s, n):
    out := s
    while len(out) < n:
        out = " " + out
    return out

# ---- VLQ base 64 (Source Map v3) ----
const B64 := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

func encode_vlq(value):
    v := value * 2
    if value < 0:
        v = (-value) * 2 + 1
    out := ""
    while true:
        digit := v % 32
        v = v // 32
        if v > 0:
            digit += 32
        out += str(B64[digit])
        if v == 0:
            break
    return out

# Décode une suite de VLQ : liste d'entiers.
func decode_vlq(text):
    out := []
    shift := 1
    acc := 0
    for c in text:
        d := _s.find(B64, str(c))
        if d < 0:
            raise("ValueError", "decode_vlq : caractère invalide '" + str(c) + "'")
        cont := d >= 32
        acc += (d % 32) * shift
        if cont:
            shift *= 32
        else:
            if acc % 2 == 1:
                append(out, -(acc // 2))
            else:
                append(out, acc // 2)
            acc = 0
            shift = 1
    if shift != 1:
        raise("ValueError", "decode_vlq : VLQ tronqué")
    return out

class Mapping:
    func init(gen_line, gen_column, file, line, column, name=null):
        self.gen_line = gen_line
        self.gen_column = gen_column
        self.file = file
        self.line = line
        self.column = column
        self.name = name

    func to_dict():
        return {"file": self.file, "line": self.line, "column": self.column, "name": self.name}

class SourceMap:
    func init(generated_file="<généré>"):
        self.file = generated_file
        self.mappings = []

    func add(gen_line, gen_column, file, line, column, name=null):
        m := Mapping(gen_line, gen_column, file, line, column, name)
        # insertion triée (ligne, colonne générées)
        i := len(self.mappings)
        append(self.mappings, m)
        while i > 0 and _before(m, self.mappings[i - 1]):
            self.mappings[i] = self.mappings[i - 1]
            i -= 1
        self.mappings[i] = m
        return self

    func size():
        return len(self.mappings)

    # Correspondance de la position générée (la plus proche qui précède, sur la même ligne ou avant).
    func lookup(gen_line, gen_column=1):
        best := null
        for m in self.mappings:
            if m.gen_line < gen_line or (m.gen_line == gen_line and m.gen_column <= gen_column):
                best = m
            else:
                break
        if best == null:
            return null
        return best.to_dict()

    # Positions générées qui proviennent d'une ligne de source.
    func generated_for(file, line):
        return [[m.gen_line, m.gen_column] for m in self.mappings if m.file == file and m.line == line]

    func sources():
        out := []
        for m in self.mappings:
            if not (m.file in out):
                append(out, m.file)
        return out

    func to_v3():
        srcs := self.sources()
        names := []
        for m in self.mappings:
            if m.name != null and not (m.name in names):
                append(names, m.name)
        lines := []
        prev_src := 0
        prev_line := 0
        prev_col := 0
        prev_name := 0
        cur := 1
        segs := []
        maxl := 0
        for m in self.mappings:
            if m.gen_line > maxl:
                maxl = m.gen_line
        k := 0
        while cur <= maxl:
            segs = []
            prev_gcol := 0
            while k < len(self.mappings) and self.mappings[k].gen_line == cur:
                m := self.mappings[k]
                si := _index(srcs, m.file)
                seg := encode_vlq(m.gen_column - 1 - prev_gcol) + encode_vlq(si - prev_src) + encode_vlq(m.line - 1 - prev_line) + encode_vlq(m.column - 1 - prev_col)
                prev_gcol = m.gen_column - 1
                prev_src = si
                prev_line = m.line - 1
                prev_col = m.column - 1
                if m.name != null:
                    ni := _index(names, m.name)
                    seg += encode_vlq(ni - prev_name)
                    prev_name = ni
                append(segs, seg)
                k += 1
            append(lines, _s.join(",", segs))
            cur += 1
        return {"version": 3, "file": self.file, "sources": srcs, "names": names, "mappings": _s.join(";", lines)}

func _index(xs, v):
    i := 0
    while i < len(xs):
        if xs[i] == v:
            return i
        i += 1
    return -1

func _before(a, b):
    if a.gen_line != b.gen_line:
        return a.gen_line < b.gen_line
    return a.gen_column < b.gen_column

# Relit une carte v3 (dict).
func from_v3(d):
    m := SourceMap(d["file"])
    srcs := d["sources"]
    names := []
    if "names" in d:
        names = d["names"]
    src := 0
    line := 0
    col := 0
    name := 0
    gl := 1
    for group in _s.split(d["mappings"], ";"):
        gcol := 0
        if group != "":
            for seg in _s.split(group, ","):
                v := decode_vlq(seg)
                gcol += v[0]
                if len(v) >= 4:
                    src += v[1]
                    line += v[2]
                    col += v[3]
                    nm := null
                    if len(v) >= 5:
                        name += v[4]
                        nm = names[name]
                    m.add(gl, gcol + 1, srcs[src], line + 1, col + 1, nm)
        gl += 1
    return m
