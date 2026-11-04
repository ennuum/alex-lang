# ALEX STANDARD LIBRARY — office.utils
# Boîte à outils commune à toute la bibliothèque bureautique : octets, texte et encodages, nombres, tri, références
# de cellules, unités de longueur, couleurs, dates (sérials Excel, W3CDTF), détection d'images.
#
#   use office.utils as u
#   u.column_letter(28)                 # "AB"
#   u.parse_cell("$C$7")                # {"row": 7, "col": 3, "abs_row": true, "abs_col": true}
#   u.length("2.5cm")                   # 900000 (EMU)
#   u.color_hex("rouge")                # "FF0000"   (noms français ou anglais, #RGB, #RRGGBB, [r, g, b])
#   u.date_to_serial(2024, 3, 15)       # 45366
#   u.image_info(octets)                # {"format": "png", "width": 640, "height": 480, ...}
#   u.sort(l, (x) => x["nom"])          # tri stable (fusion), O(n log n)
#
# OCTETS (listes d'int 0..255, convention de la stdlib)
#   bytes_of(data)  str -> UTF-8 ; liste/tuple -> liste       slice(data, a, b)   concat(parts)   zeros(n, v=0)
#   find_bytes(data, motif, start=0)   rfind_bytes(data, motif, start=-1)   (motif : str ASCII ou octets)
#   u16le u32le u64le i16le i32le u16be u32be i32be (data, pos)       pack_u16le pack_u32le pack_u64le pack_u16be pack_u32be
#   hex(data, upper=false)  unhex(text)   base64_encode(data)  base64_decode(text)   read_bytes(path)  write_bytes(path, d)
# TEXTE
#   utf8_encode(s)  utf8_decode(data, strict=false)  decode_text(data) (BOM UTF-8/UTF-16 détecté, sinon UTF-8 puis
#   Windows-1252)  utf16_decode(data, big_endian=false)  utf16_encode(s, big_endian=false, bom=false)
#   latin1_encode(s)  latin1_decode(data)  cp1252_decode(data)  cp1252_encode(s)
#   str_find(s, sub, start=0)  str_slice(s, a, b)  xml_escape(s, attr=false)  lines(text)  is_blank(s)
#   pad_left(s, n, ch=" ")  pad_right(s, n, ch=" ")  to_text(v)  chars(s)
# NOMBRES  format_number(x) (écriture la plus courte exacte, « 1.5E+20 » hors [1e-5, 1e15))  parse_number(s) (int,
#   float ou null)  is_number(v)  round_to(x, n)  clamp(x, a, b)
# TRI  sort(l, key=null, reverse=false) -> nouvelle liste (stable)   unique(l)
# CELLULES  column_letter(col)  column_index("AB")  cell_ref(row, col, abs_row=false, abs_col=false)
#   parse_cell(ref)  parse_range("A1:C3") -> {"r1","c1","r2","c2","sheet"}  range_ref(r1, c1, r2, c2)
#   split_sheet_ref("'Feuille 1'!A1") -> [feuille ou null, "A1"]   quote_sheet(name)
# UNITÉS  EMU_PER_INCH EMU_PER_CM EMU_PER_MM EMU_PER_PT EMU_PER_PX  ·  length(v, default_unit="emu") -> EMU
#   (v : nombre ou "12pt" "2.5cm" "30mm" "1in" "96px" "1440tw")   to_unit(emu, unit) -> float
#   pt_to_emu(x)  emu_to_pt(x)  twips(x_pt)  half_points(x_pt)
# COULEURS  color_hex(c) -> "RRGGBB"   color_rgb(c) -> [r, g, b]   color_floats(c) -> [r, g, b] dans 0..1
# DATES  date_to_serial(y, m, d, h=0, mi=0, s=0)  serial_to_date(x) -> dict   now_iso()  iso_datetime(dict)
#   date_parts(v) (dict, str ISO ou sérial -> dict)   is_date_dict(v)
# IMAGES  image_info(data) -> {"format", "width", "height", "mime", "ext", "dpi_x", "dpi_y"} ou null (PNG, JPEG, GIF,
#   BMP, TIFF, WebP, SVG)   mime_for_extension(ext)   extension_for_mime(mime)
# DIVERS  get(d, k, défaut)  merge(a, b)  deep_copy(v)  repeat(x, n) (liste)

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use string
use io
use time

# =================================================================================================== octets

func bytes_of(data):
    t := type(data)
    if t == "str":
        return _n.utf8_encode(data)
    if t == "list":
        return data
    if t == "tuple":
        out := []
        for b in data:
            append(out, b)
        return out
    raise("TypeError", "office.utils : str ou liste d'octets attendue (obtenu '" + t + "')")

func slice(data, start, stop=null):
    return _n.bytes_slice(data, start, stop)

func concat(parts):
    return _n.bytes_concat(parts)

func zeros(n, value=0):
    return _n.bytes_fill(n, value)

func _needle(m):
    if type(m) == "str":
        return _n.utf8_encode(m)
    return m

func find_bytes(data, motif, start=0):
    return _n.bytes_find(data, _needle(motif), start)

func rfind_bytes(data, motif, start=-1):
    return _n.bytes_rfind(data, _needle(motif), start)

func u16le(b, p):
    return b[p] | (b[p + 1] << 8)

func u32le(b, p):
    return b[p] | (b[p + 1] << 8) | (b[p + 2] << 16) | (b[p + 3] << 24)

func u64le(b, p):
    return u32le(b, p) | (u32le(b, p + 4) << 32)

func i16le(b, p):
    v := u16le(b, p)
    if v >= 32768:
        return v - 65536
    return v

func i32le(b, p):
    v := u32le(b, p)
    if v >= 2147483648:
        return v - 4294967296
    return v

func u16be(b, p):
    return (b[p] << 8) | b[p + 1]

func u32be(b, p):
    return (b[p] << 24) | (b[p + 1] << 16) | (b[p + 2] << 8) | b[p + 3]

func i32be(b, p):
    v := u32be(b, p)
    if v >= 2147483648:
        return v - 4294967296
    return v

func pack_u16le(v):
    return [v & 255, (v >> 8) & 255]

func pack_u32le(v):
    return [v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255]

func pack_u64le(v):
    return _n.bytes_concat([pack_u32le(v & 4294967295), pack_u32le((v >> 32) & 4294967295)])

func pack_u16be(v):
    return [(v >> 8) & 255, v & 255]

func pack_u32be(v):
    return [(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255]

func hex(data, upper=false):
    return _n.hex_encode(bytes_of(data), upper)

func unhex(text):
    return _n.hex_decode(text)

func base64_encode(data):
    return _n.base64_encode(data)

func base64_decode(text):
    return _n.base64_decode(text)

func read_bytes(path):
    return io.read_bytes(path)

func write_bytes(path, data):
    return io.write_bytes(path, bytes_of(data))

# =================================================================================================== texte

func utf8_encode(s):
    return _n.utf8_encode(s)

func utf8_decode(data, strict=false):
    return _n.utf8_decode(data, strict)

func latin1_encode(s, replacement=null):
    return _n.latin1_encode(s, replacement)

func latin1_decode(data):
    return _n.latin1_decode(data)

# Windows-1252 : 0x80..0x9F (le reste coïncide avec Latin-1). 0 : position non attribuée.
const _CP1252 := [8364, 0, 8218, 402, 8222, 8230, 8224, 8225, 710, 8240, 352, 8249, 338, 0, 381, 0, 0, 8216, 8217, 8220, 8221, 8226, 8211, 8212, 732, 8482, 353, 8250, 339, 0, 382, 376]

func cp1252_decode(data):
    out := []
    for b in data:
        if b >= 128 and b < 160 and _CP1252[b - 128] != 0:
            append(out, str(string.chr(_CP1252[b - 128])))
        else:
            append(out, str(string.chr(b)))
    return string.join("", out)

func cp1252_encode(s, replacement=63):
    out := []
    for c in s:
        o := string.ord(c)
        if o < 128 or (o >= 160 and o < 256):
            append(out, o)
            continue
        k := 0
        found := -1
        while k < 32:
            if _CP1252[k] == o:
                found = k + 128
                break
            k = k + 1
        if found < 0:
            if replacement == null:
                raise("ValueError", "cp1252_encode : caractère non représentable '" + str(c) + "'")
            found = replacement
        append(out, found)
    return out

func utf16_decode(data, big_endian=false):
    out := []
    n := len(data) - (len(data) % 2)
    i := 0
    while i < n:
        u := 0
        if big_endian:
            u = (data[i] << 8) | data[i + 1]
        else:
            u = data[i] | (data[i + 1] << 8)
        i = i + 2
        if u >= 55296 and u <= 56319 and i + 1 < n:
            v := 0
            if big_endian:
                v = (data[i] << 8) | data[i + 1]
            else:
                v = data[i] | (data[i + 1] << 8)
            if v >= 56320 and v <= 57343:
                i = i + 2
                append(out, str(string.chr(65536 + ((u - 55296) << 10) + (v - 56320))))
                continue
            append(out, str(string.chr(65533)))
        elif u >= 55296 and u <= 57343:
            append(out, str(string.chr(65533)))
        else:
            append(out, str(string.chr(u)))
    return string.join("", out)

func utf16_encode(s, big_endian=false, bom=false):
    out := []
    if bom:
        if big_endian:
            out = [254, 255]
        else:
            out = [255, 254]
    for c in s:
        o := string.ord(c)
        units := [o]
        if o >= 65536:
            o = o - 65536
            units = [55296 + (o >> 10), 56320 + (o & 1023)]
        for u in units:
            if big_endian:
                append(out, (u >> 8) & 255)
                append(out, u & 255)
            else:
                append(out, u & 255)
                append(out, (u >> 8) & 255)
    return out

# Décode un fichier texte : BOM UTF-8 / UTF-16 (LE, BE) reconnu et retiré ; sinon UTF-8 strict, et en cas d'échec
# Windows-1252 (fichiers « ANSI » produits par Excel sous Windows).
func decode_text(data):
    n := len(data)
    if n >= 3 and data[0] == 239 and data[1] == 187 and data[2] == 191:
        return _n.utf8_decode(_n.bytes_slice(data, 3, null), false)
    if n >= 2 and data[0] == 255 and data[1] == 254:
        return utf16_decode(_n.bytes_slice(data, 2, null), false)
    if n >= 2 and data[0] == 254 and data[1] == 255:
        return utf16_decode(_n.bytes_slice(data, 2, null), true)
    try:
        return _n.utf8_decode(data, true)
    catch e:
        return cp1252_decode(data)

func str_find(s, sub, start=0):
    return _n.str_find(s, sub, start)

func str_slice(s, start, stop=null):
    return _n.str_slice(s, start, stop)

func xml_escape(s, attr=false):
    return _n.xml_escape(to_text(s), attr)

func chars(s):
    out := []
    for c in s:
        append(out, str(c))
    return out

# Découpe en lignes (\n, \r\n, \r) ; une fin de ligne finale ne crée pas de ligne vide.
func lines(text):
    t := string.replace(string.replace(text, "\r\n", "\n"), "\r", "\n")
    parts := string.split(t, "\n")
    if len(parts) > 0 and parts[len(parts) - 1] == "":
        out := []
        i := 0
        while i < len(parts) - 1:
            append(out, parts[i])
            i = i + 1
        return out
    return parts

func is_blank(s):
    return s == null or string.trim(s) == ""

func pad_left(s, width, ch=" "):
    t := to_text(s)
    while len(t) < width:
        t = ch + t
    return t

func pad_right(s, width, ch=" "):
    t := to_text(s)
    while len(t) < width:
        t = t + ch
    return t

# Texte d'affichage d'une valeur : null -> "", nombres sans « .0 » superflu, bool -> "true"/"false".
func to_text(v):
    t := type(v)
    if t == "str":
        return v
    if v == null:
        return ""
    if t == "int" or t == "float":
        return _n.num_format(v)
    if t == "bool":
        if v:
            return "true"
        return "false"
    return str(v)

# =================================================================================================== nombres

func format_number(x):
    return _n.num_format(x)

func parse_number(s):
    return _n.num_parse(s)

func is_number(v):
    t := type(v)
    return t == "int" or t == "float"

func clamp(x, lo, hi):
    if x < lo:
        return lo
    if x > hi:
        return hi
    return x

# Arrondi « commercial » (demi loin de zéro), comme ROUND d'Excel.
func round_to(x, digits=0):
    f := 1.0
    k := 0
    while k < digits:
        f = f * 10.0
        k = k + 1
    while k > digits:
        f = f / 10.0
        k = k - 1
    v := to_float(x) * f
    r := 0.0
    if v >= 0:
        r = to_float(to_int(v + 0.5 + 0.0000000001))
    else:
        r = -to_float(to_int(-v + 0.5 + 0.0000000001))
    return r / f

# =================================================================================================== tri

func _merge_sort(items, keys_, lo, hi, tmp, reverse):
    if hi - lo < 2:
        return null
    mid := (lo + hi) // 2
    _merge_sort(items, keys_, lo, mid, tmp, reverse)
    _merge_sort(items, keys_, mid, hi, tmp, reverse)
    i := lo
    j := mid
    k := lo
    while i < mid and j < hi:
        take_right := false
        if reverse:
            take_right = keys_[j] > keys_[i]
        else:
            take_right = keys_[j] < keys_[i]
        if take_right:
            tmp[k] = j
            j = j + 1
        else:
            tmp[k] = i
            i = i + 1
        k = k + 1
    while i < mid:
        tmp[k] = i
        i = i + 1
        k = k + 1
    while j < hi:
        tmp[k] = j
        j = j + 1
        k = k + 1
    # réordonne items et keys_ sur [lo, hi)
    vi := []
    vk := []
    m := lo
    while m < hi:
        append(vi, items[tmp[m]])
        append(vk, keys_[tmp[m]])
        m = m + 1
    m = lo
    while m < hi:
        items[m] = vi[m - lo]
        keys_[m] = vk[m - lo]
        m = m + 1

# Tri stable O(n log n) ; renvoie une NOUVELLE liste. key : fonction appliquée une fois par élément.
func sort(l, key=null, reverse=false):
    items := []
    ks := []
    for x in l:
        append(items, x)
        if key == null:
            append(ks, x)
        else:
            append(ks, key(x))
    tmp := _n.bytes_fill(len(items), 0)
    _merge_sort(items, ks, 0, len(items), tmp, reverse)
    return items

# Éléments distincts dans l'ordre de première apparition (valeurs hachables).
func unique(l):
    seen := {}
    out := []
    for x in l:
        if not contains_key(seen, x):
            seen[x] = true
            append(out, x)
    return out

# =================================================================================================== cellules

const _LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

# 1 -> "A", 26 -> "Z", 27 -> "AA" ; colonnes 1..16384 (XFD).
func column_letter(col):
    if type(col) != "int" or col < 1:
        raise("ValueError", "column_letter : numéro de colonne >= 1 attendu (obtenu " + str(col) + ")")
    s := ""
    n := col
    while n > 0:
        r := (n - 1) % 26
        s = str(_LETTERS[r]) + s
        n = (n - 1) // 26
    return s

func column_index(letters):
    if type(letters) != "str" or letters == "":
        raise("ValueError", "column_index : lettres de colonne attendues")
    n := 0
    for c in string.upper(letters):
        o := string.ord(c)
        if o < 65 or o > 90:
            raise("ValueError", "column_index : lettre invalide dans '" + letters + "'")
        n = n * 26 + (o - 64)
    return n

func cell_ref(row, col, abs_row=false, abs_col=false):
    s := ""
    if abs_col:
        s = "$"
    s = s + column_letter(col)
    if abs_row:
        s = s + "$"
    return s + str(row)

# "B3", "$B$3", "b3" -> {"row": 3, "col": 2, "abs_row", "abs_col"} ; ValueError si invalide.
# Une colonne seule ("B") donne row = null ; une ligne seule ("3") donne col = null.
func parse_cell(ref):
    if type(ref) != "str":
        raise("ValueError", "référence de cellule attendue (obtenu '" + type(ref) + "')")
    cs := chars(string.trim(ref))
    i := 0
    n := len(cs)
    abs_col := false
    abs_row := false
    if i < n and cs[i] == "$":
        abs_col = true
        i = i + 1
    letters := ""
    while i < n:
        o := string.ord(cs[i])
        if (o >= 65 and o <= 90) or (o >= 97 and o <= 122):
            letters = letters + cs[i]
            i = i + 1
        else:
            break
    if i < n and cs[i] == "$":
        abs_row = true
        i = i + 1
    digits := ""
    while i < n:
        o := string.ord(cs[i])
        if o >= 48 and o <= 57:
            digits = digits + cs[i]
            i = i + 1
        else:
            break
    if i != n or (letters == "" and digits == ""):
        raise("ValueError", "référence de cellule invalide : '" + ref + "'")
    if letters == "" and abs_col:
        abs_row = true
        abs_col = false
    col := null
    row := null
    if letters != "":
        col = column_index(letters)
    if digits != "":
        row = to_int(digits)
        if row < 1:
            raise("ValueError", "référence de cellule invalide : '" + ref + "'")
    return {"row": row, "col": col, "abs_row": abs_row, "abs_col": abs_col}

# Coupe "Feuille!A1" ou "'Ma feuille'!A1:B2" en [nom ou null, reste].
func split_sheet_ref(ref):
    t := string.trim(ref)
    if string.starts_with(t, "'"):
        cs := chars(t)
        i := 1
        name := ""
        while i < len(cs):
            if cs[i] == "'":
                if i + 1 < len(cs) and cs[i + 1] == "'":
                    name = name + "'"
                    i = i + 2
                    continue
                break
            name = name + cs[i]
            i = i + 1
        if i + 1 < len(cs) and cs[i + 1] == "!":
            return [name, _n.str_slice(t, i + 2, null)]
        raise("ValueError", "référence invalide : " + ref)
    p := string.find(t, "!")
    if p < 0:
        return [null, t]
    return [_n.str_slice(t, 0, p), _n.str_slice(t, p + 1, null)]

# Met un nom de feuille entre apostrophes si nécessaire (espaces, ponctuation, commence par un chiffre).
func quote_sheet(name):
    need := false
    first := true
    for c in name:
        o := string.ord(c)
        ok := (o >= 65 and o <= 90) or (o >= 97 and o <= 122) or o == 95 or o > 127 or (not first and ((o >= 48 and o <= 57) or o == 46))
        if not ok:
            need = true
        first = false
    if not need:
        return name
    return "'" + string.replace(name, "'", "''") + "'"

# "A1:C3" (ou "A1", "A:C", "1:3", "Feuille!A1:B2") -> {"r1","c1","r2","c2","sheet"} normalisé (r1 <= r2, c1 <= c2).
# Colonne entière : r1 = 1, r2 = 1048576 ; ligne entière : c1 = 1, c2 = 16384.
func parse_range(ref):
    sp := split_sheet_ref(ref)
    body := sp[1]
    parts := string.split(body, ":")
    if len(parts) > 2:
        raise("ValueError", "plage invalide : '" + ref + "'")
    a := parse_cell(parts[0])
    b := a
    if len(parts) == 2:
        b = parse_cell(parts[1])
    r1 := a["row"]
    r2 := b["row"]
    c1 := a["col"]
    c2 := b["col"]
    if r1 == null:
        r1 = 1
    if r2 == null:
        r2 = 1048576
    if c1 == null:
        c1 = 1
    if c2 == null:
        c2 = 16384
    if r1 > r2:
        t := r1
        r1 = r2
        r2 = t
    if c1 > c2:
        t := c1
        c1 = c2
        c2 = t
    return {"r1": r1, "c1": c1, "r2": r2, "c2": c2, "sheet": sp[0]}

func range_ref(r1, c1, r2, c2, absolute=false):
    a := cell_ref(r1, c1, absolute, absolute)
    if r1 == r2 and c1 == c2:
        return a
    return a + ":" + cell_ref(r2, c2, absolute, absolute)

# =================================================================================================== unités

const EMU_PER_INCH := 914400
const EMU_PER_CM := 360000
const EMU_PER_MM := 36000
const EMU_PER_PT := 12700
const EMU_PER_PX := 9525
const EMU_PER_TWIP := 635

func _unit_factor(unit):
    u := string.lower(unit)
    if u == "emu" or u == "":
        return 1.0
    if u == "in" or u == "inch" or u == "inches" or u == "\"":
        return 914400.0
    if u == "cm":
        return 360000.0
    if u == "mm":
        return 36000.0
    if u == "pt" or u == "pts" or u == "point" or u == "points":
        return 12700.0
    if u == "px":
        return 9525.0
    if u == "tw" or u == "twip" or u == "twips" or u == "dxa":
        return 635.0
    if u == "pc" or u == "pica":
        return 152400.0
    raise("ValueError", "unité de longueur inconnue : '" + unit + "' (emu, in, cm, mm, pt, px, tw, pc)")

# Longueur -> EMU (int). v : nombre (dans default_unit) ou texte « 12pt », « 2,5 cm », « 1in », « 96px ».
func length(v, default_unit="emu"):
    t := type(v)
    if t == "int" or t == "float":
        return to_int(round_to(to_float(v) * _unit_factor(default_unit), 0))
    if t != "str":
        raise("TypeError", "length : nombre ou texte attendu (obtenu '" + t + "')")
    s := string.replace(string.trim(v), ",", ".")
    cs := chars(s)
    i := 0
    while i < len(cs):
        o := string.ord(cs[i])
        if (o >= 48 and o <= 57) or cs[i] == "." or cs[i] == "-" or cs[i] == "+":
            i = i + 1
        else:
            break
    num := parse_number(_n.str_slice(s, 0, i))
    if num == null:
        raise("ValueError", "longueur invalide : '" + v + "'")
    unit := string.trim(_n.str_slice(s, i, null))
    if unit == "":
        unit = default_unit
    return to_int(round_to(to_float(num) * _unit_factor(unit), 0))

# EMU -> valeur dans `unit` (float).
func to_unit(emu, unit):
    return to_float(emu) / _unit_factor(unit)

func pt_to_emu(x):
    return to_int(round_to(to_float(x) * 12700.0, 0))

func emu_to_pt(x):
    return to_float(x) / 12700.0

# Points -> twips (1/20 pt, unité de Word pour les marges et retraits).
func twips(x_pt):
    return to_int(round_to(to_float(x_pt) * 20.0, 0))

# Points -> demi-points (taille de police dans Word : w:sz).
func half_points(x_pt):
    return to_int(round_to(to_float(x_pt) * 2.0, 0))

# =================================================================================================== couleurs

const _COLOR_NAMES := {"black": "000000", "noir": "000000", "white": "FFFFFF", "blanc": "FFFFFF", "red": "FF0000", "rouge": "FF0000", "green": "008000", "vert": "008000", "lime": "00FF00", "blue": "0000FF", "bleu": "0000FF", "yellow": "FFFF00", "jaune": "FFFF00", "cyan": "00FFFF", "magenta": "FF00FF", "fuchsia": "FF00FF", "gray": "808080", "grey": "808080", "gris": "808080", "silver": "C0C0C0", "argent": "C0C0C0", "lightgray": "D3D3D3", "lightgrey": "D3D3D3", "darkgray": "A9A9A9", "darkgrey": "A9A9A9", "maroon": "800000", "bordeaux": "800000", "olive": "808000", "navy": "000080", "marine": "000080", "purple": "800080", "violet": "800080", "teal": "008080", "orange": "FFA500", "pink": "FFC0CB", "rose": "FFC0CB", "brown": "A52A2A", "marron": "A52A2A", "gold": "FFD700", "or": "FFD700", "indigo": "4B0082", "darkblue": "00008B", "darkred": "8B0000", "darkgreen": "006400", "lightblue": "ADD8E6", "lightgreen": "90EE90", "beige": "F5F5DC", "turquoise": "40E0D0", "coral": "FF7F50", "salmon": "FA8072", "khaki": "F0E68C", "crimson": "DC143C", "steelblue": "4682B4", "slategray": "708090"}

const _HEXDIGITS := "0123456789ABCDEF"

func _hex2(v):
    v = clamp(to_int(v), 0, 255)
    return str(_HEXDIGITS[v >> 4]) + str(_HEXDIGITS[v & 15])

func _is_hex(s):
    for c in string.upper(s):
        if string.find(_HEXDIGITS, str(c)) < 0:
            return false
    return true

# Normalise une couleur en "RRGGBB" majuscules. Accepte "#RGB", "#RRGGBB", "RRGGBB", "#AARRGGBB" (alpha ignoré),
# un nom (français ou anglais), [r, g, b] (0..255) ou [r, g, b] flottants 0..1.
func color_hex(c):
    t := type(c)
    if t == "list" or t == "tuple":
        if len(c) < 3:
            raise("ValueError", "couleur [r, g, b] attendue")
        all_float := type(c[0]) == "float" and type(c[1]) == "float" and type(c[2]) == "float"
        if all_float and c[0] <= 1.0 and c[1] <= 1.0 and c[2] <= 1.0:
            return _hex2(round_to(c[0] * 255.0, 0)) + _hex2(round_to(c[1] * 255.0, 0)) + _hex2(round_to(c[2] * 255.0, 0))
        return _hex2(c[0]) + _hex2(c[1]) + _hex2(c[2])
    if t != "str":
        raise("TypeError", "couleur : texte ou [r, g, b] attendu (obtenu '" + t + "')")
    s := string.trim(c)
    low := string.lower(string.replace(string.replace(s, " ", ""), "-", ""))
    if contains_key(_COLOR_NAMES, low):
        return _COLOR_NAMES[low]
    if string.starts_with(s, "#"):
        s = _n.str_slice(s, 1, null)
    s = string.upper(s)
    if not _is_hex(s):
        raise("ValueError", "couleur invalide : '" + c + "'")
    if len(s) == 3:
        a := str(s[0])
        b := str(s[1])
        d := str(s[2])
        return a + a + b + b + d + d
    if len(s) == 6:
        return s
    if len(s) == 8:
        return _n.str_slice(s, 2, null)
    raise("ValueError", "couleur invalide : '" + c + "'")

func color_rgb(c):
    h := color_hex(c)
    b := _n.hex_decode(h)
    return [b[0], b[1], b[2]]

func color_floats(c):
    rgb := color_rgb(c)
    return [to_float(rgb[0]) / 255.0, to_float(rgb[1]) / 255.0, to_float(rgb[2]) / 255.0]

# =================================================================================================== dates

func _base_days():
    return time.days_from_civil(1899, 12, 31)

# Date (et heure) -> numéro de série Excel (système 1900, avec le faux 29/02/1900 d'Excel). int si l'heure est nulle.
func date_to_serial(year, month, day, hour=0, minute=0, second=0):
    d := time.days_from_civil(year, month, day) - _base_days()
    if d >= 60:
        d = d + 1
    if hour == 0 and minute == 0 and second == 0:
        return d
    return to_float(d) + (to_float(hour) * 3600.0 + to_float(minute) * 60.0 + to_float(second)) / 86400.0

# Numéro de série Excel -> {"year","month","day","hour","minute","second"} (secondes arrondies).
func serial_to_date(x):
    v := to_float(x)
    days := to_int(v)
    if v < 0:
        raise("ValueError", "numéro de série de date négatif : " + str(x))
    secs := to_int(round_to((v - to_float(days)) * 86400.0, 0))
    if secs >= 86400:
        secs = secs - 86400
        days = days + 1
    y := 1900
    m := 1
    d := 0
    if days == 60:
        y = 1900
        m = 2
        d = 29
    else:
        dd := days
        if days > 60:
            dd = days - 1
        if dd == 0:
            return {"year": 1899, "month": 12, "day": 31, "hour": secs // 3600, "minute": (secs // 60) % 60, "second": secs % 60}
        ymd := time.civil_from_days(dd + _base_days())
        y = ymd[0]
        m = ymd[1]
        d = ymd[2]
    return {"year": y, "month": m, "day": d, "hour": secs // 3600, "minute": (secs // 60) % 60, "second": secs % 60}

func is_date_dict(v):
    return type(v) == "dict" and contains_key(v, "year") and contains_key(v, "month") and contains_key(v, "day")

# dict, texte ISO 8601 ou sérial Excel -> dict de champs (hour/minute/second à 0 par défaut).
func date_parts(v):
    t := type(v)
    if t == "dict":
        return {"year": v["year"], "month": v["month"], "day": v["day"], "hour": get(v, "hour", 0), "minute": get(v, "minute", 0), "second": to_int(get(v, "second", 0))}
    if t == "str":
        f := time.parse_iso(string.trim(v))
        return {"year": f["year"], "month": f["month"], "day": f["day"], "hour": f["hour"], "minute": f["minute"], "second": f["second"]}
    if t == "int" or t == "float":
        return serial_to_date(v)
    raise("TypeError", "date attendue (dict, texte ISO ou sérial)")

# dict de champs -> "AAAA-MM-JJTHH:MM:SSZ" (W3CDTF, utilisé par les métadonnées OOXML / ODF).
func iso_datetime(f, z=true):
    s := pad_left(str(f["year"]), 4, "0") + "-" + pad_left(str(f["month"]), 2, "0") + "-" + pad_left(str(f["day"]), 2, "0") + "T" + pad_left(str(get(f, "hour", 0)), 2, "0") + ":" + pad_left(str(get(f, "minute", 0)), 2, "0") + ":" + pad_left(str(to_int(get(f, "second", 0))), 2, "0")
    if z:
        s = s + "Z"
    return s

func iso_date(f):
    return pad_left(str(f["year"]), 4, "0") + "-" + pad_left(str(f["month"]), 2, "0") + "-" + pad_left(str(f["day"]), 2, "0")

# Date et heure UTC courantes au format W3CDTF.
func now_iso():
    g := time.gmtime()
    return iso_datetime(g)

# =================================================================================================== images

const _MIME := {"png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "jpe": "image/jpeg", "gif": "image/gif", "bmp": "image/bmp", "tif": "image/tiff", "tiff": "image/tiff", "webp": "image/webp", "svg": "image/svg+xml", "emf": "image/x-emf", "wmf": "image/x-wmf", "ico": "image/x-icon", "xml": "application/xml", "rels": "application/vnd.openxmlformats-package.relationships+xml", "pdf": "application/pdf", "txt": "text/plain", "csv": "text/csv", "html": "text/html", "htm": "text/html", "json": "application/json", "zip": "application/zip", "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation", "odt": "application/vnd.oasis.opendocument.text", "ods": "application/vnd.oasis.opendocument.spreadsheet", "odp": "application/vnd.oasis.opendocument.presentation", "bin": "application/octet-stream"}

func mime_for_extension(ext):
    e := string.lower(ext)
    if string.starts_with(e, "."):
        e = _n.str_slice(e, 1, null)
    if contains_key(_MIME, e):
        return _MIME[e]
    return "application/octet-stream"

func extension_for_mime(mime):
    m := string.lower(mime)
    if m == "image/jpeg":
        return "jpeg"
    if m == "image/tiff":
        return "tiff"
    for k in keys(_MIME):
        if _MIME[k] == m:
            return k
    return "bin"

func _info(fmt, w, h, dx=96, dy=96):
    return {"format": fmt, "width": w, "height": h, "mime": mime_for_extension(fmt), "ext": fmt, "dpi_x": dx, "dpi_y": dy}

func _png_info(d):
    w := u32be(d, 16)
    h := u32be(d, 20)
    dx := 96
    dy := 96
    # recherche du segment pHYs (résolution) dans les premiers blocs
    p := 8
    n := len(d)
    while p + 12 <= n:
        clen := u32be(d, p)
        ctype := _n.latin1_decode(_n.bytes_slice(d, p + 4, p + 8))
        if ctype == "pHYs" and clen >= 9 and p + 17 <= n:
            ppx := u32be(d, p + 8)
            ppy := u32be(d, p + 12)
            if d[p + 16] == 1 and ppx > 0 and ppy > 0:
                dx = to_int(round_to(to_float(ppx) * 0.0254, 0))
                dy = to_int(round_to(to_float(ppy) * 0.0254, 0))
            break
        if ctype == "IDAT" or ctype == "IEND":
            break
        p = p + 12 + clen
    info := _info("png", w, h, dx, dy)
    info["bit_depth"] = d[24]
    info["color_type"] = d[25]
    info["interlace"] = d[28]
    return info

func _jpeg_info(d):
    n := len(d)
    p := 2
    dx := 96
    dy := 96
    while p + 4 <= n:
        if d[p] != 255:
            p = p + 1
            continue
        marker := d[p + 1]
        if marker == 255:
            p = p + 1
            continue
        if marker == 216 or marker == 1 or (marker >= 208 and marker <= 215):
            p = p + 2
            continue
        seglen := u16be(d, p + 2)
        if marker == 224 and seglen >= 14 and p + 18 <= n:
            # APP0 JFIF : unités, densités
            if d[p + 4] == 74 and d[p + 5] == 70 and d[p + 6] == 73 and d[p + 7] == 70:
                units := d[p + 11]
                xd := u16be(d, p + 12)
                yd := u16be(d, p + 14)
                if units == 1 and xd > 0 and yd > 0:
                    dx = xd
                    dy = yd
                elif units == 2 and xd > 0 and yd > 0:
                    dx = to_int(round_to(to_float(xd) * 2.54, 0))
                    dy = to_int(round_to(to_float(yd) * 2.54, 0))
        if (marker >= 192 and marker <= 207) and marker != 196 and marker != 200 and marker != 204:
            if p + 9 > n:
                return null
            info := _info("jpeg", u16be(d, p + 7), u16be(d, p + 5), dx, dy)
            info["components"] = d[p + 9]
            info["bits"] = d[p + 4]
            info["progressive"] = marker == 194
            return info
        p = p + 2 + seglen
    return null

func _tiff_info(d):
    le := d[0] == 73
    rd16 := (p) => u16le(d, p) if le else u16be(d, p)
    rd32 := (p) => u32le(d, p) if le else u32be(d, p)
    ifd := rd32(4)
    if ifd + 2 > len(d):
        return null
    count := rd16(ifd)
    w := 0
    h := 0
    k := 0
    while k < count:
        e := ifd + 2 + k * 12
        if e + 12 > len(d):
            break
        tag := rd16(e)
        typ := rd16(e + 2)
        val := rd16(e + 8) if typ == 3 else rd32(e + 8)
        if tag == 256:
            w = val
        elif tag == 257:
            h = val
        k = k + 1
    return _info("tiff", w, h)

func _svg_dim(s, name):
    p := string.find(s, name + "=\"")
    if p < 0:
        return 0
    rest := _n.str_slice(s, p + len(name) + 2, null)
    q := string.find(rest, "\"")
    if q < 0:
        return 0
    v := string.trim(_n.str_slice(rest, 0, q))
    try:
        return to_int(round_to(to_float(length(v, "px")) / 9525.0, 0))
    catch e:
        return 0

# Format et dimensions (pixels) d'une image ; null si le format n'est pas reconnu.
func image_info(data):
    d := bytes_of(data)
    n := len(d)
    if n >= 29 and d[0] == 137 and d[1] == 80 and d[2] == 78 and d[3] == 71:
        return _png_info(d)
    if n >= 4 and d[0] == 255 and d[1] == 216:
        return _jpeg_info(d)
    if n >= 10 and d[0] == 71 and d[1] == 73 and d[2] == 70:
        return _info("gif", u16le(d, 6), u16le(d, 8))
    if n >= 26 and d[0] == 66 and d[1] == 77:
        h := i32le(d, 22)
        if h < 0:
            h = -h
        return _info("bmp", i32le(d, 18), h)
    if n >= 8 and ((d[0] == 73 and d[1] == 73 and d[2] == 42) or (d[0] == 77 and d[1] == 77 and d[3] == 42)):
        return _tiff_info(d)
    if n >= 30 and d[0] == 82 and d[1] == 73 and d[2] == 70 and d[3] == 70 and d[8] == 87 and d[9] == 69 and d[10] == 66 and d[11] == 80:
        kind := _n.latin1_decode(_n.bytes_slice(d, 12, 16))
        if kind == "VP8X":
            return _info("webp", 1 + (d[24] | (d[25] << 8) | (d[26] << 16)), 1 + (d[27] | (d[28] << 8) | (d[29] << 16)))
        if kind == "VP8 ":
            return _info("webp", u16le(d, 26) & 16383, u16le(d, 28) & 16383)
        if kind == "VP8L":
            b0 := d[21]
            b1 := d[22]
            b2 := d[23]
            b3 := d[24]
            return _info("webp", 1 + (((b1 & 63) << 8) | b0), 1 + (((b3 & 15) << 10) | (b2 << 2) | ((b1 & 192) >> 6)))
    head := _n.utf8_decode(_n.bytes_slice(d, 0, 2048), false)
    if string.contains(head, "<svg"):
        return _info("svg", _svg_dim(head, "width"), _svg_dim(head, "height"))
    return null

# =================================================================================================== divers

func get(d, k, fallback=null):
    if type(d) == "dict" and contains_key(d, k):
        v := d[k]
        if v == null:
            return fallback
        return v
    return fallback

# Nouveau dict : a complété/écrasé par b.
func merge(a, b):
    out := {}
    if a != null:
        for k in keys(a):
            out[k] = a[k]
    if b != null:
        for k in keys(b):
            out[k] = b[k]
    return out

func deep_copy(v):
    t := type(v)
    if t == "list" or t == "tuple":
        out := []
        for x in v:
            append(out, deep_copy(x))
        return out
    if t == "dict":
        out := {}
        for k in keys(v):
            out[k] = deep_copy(v[k])
        return out
    return v

func repeat(x, n):
    out := []
    k := 0
    while k < n:
        append(out, x)
        k = k + 1
    return out
