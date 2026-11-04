# Système de fichiers FAT16 sur le périphérique de bloc (ATA ou virtio, bloc.al) : répertoires (chemins
# « a/b/c », « . » et « .. »), noms longs VFAT (UTF-16, comme Windows et Linux), lire, écrire, supprimer,
# créer et supprimer des répertoires. Compatible avec mkfs.fat, mtools et fsck.fat (deux copies de la FAT).
#
# Un répertoire est désigné par sa première grappe (0 : répertoire racine, zone fixe en FAT16) ; ses entrées
# de 32 octets sont numérotées (« positions ») dans l'ordre du disque. Un nom long occupe des entrées LFN
# (attribut 0x0F, 13 caractères UTF-16 chacune, dernier morceau en premier) juste avant l'entrée courte 8.3,
# liées par une somme de contrôle du nom court. À l'écriture, comme Linux : nom court seul si le nom est déjà
# un 8.3 en majuscules, sinon nom long plus un nom court (le nom en majuscules s'il tient en 8.3 et est libre,
# sinon BASE~N.EXT). Recherche insensible à la casse (ASCII).
use hw
use bloc
from collections use append
from core use len
from string use upper, lower, split, chr, ord, join, substring

const ATTR_VOLUME := 8
const ATTR_DIR := 16
const ATTR_ARCHIVE := 32
const ATTR_LFN := 15
const DELETED := 229    # 0xE5 : entrée libre
const EOC := 65528      # 0xFFF8 et plus : fin de chaîne
const MAX_NAME := 255

class Entry:
    name: str := ""     # nom affiché : nom long, sinon nom court (casse d'après les drapeaux NT)
    short: str := ""    # nom court brut (11 octets « NOM     EXT »)
    size: int := 0
    cluster: int := 0
    is_dir: bool := false
    dir: int := 0       # première grappe du répertoire qui contient l'entrée (0 : racine)
    slot: int := 0      # position de l'entrée courte dans ce répertoire (-1 : la racine elle-même)
    first: int := 0     # position de sa première entrée (entrées du nom long comprises)

    func init(name: str, short: str, size: int, cluster: int, is_dir: bool, dir: int, slot: int, first: int):
        self.name = name
        self.short = short
        self.size = size
        self.cluster = cluster
        self.is_dir = is_dir
        self.dir = dir
        self.slot = slot
        self.first = first

bps := 512
spc := 1
fat_start := 0
fat_size := 0
nfats := 2
root_start := 0
root_entries := 0
data_start := 0
clusters := 0
buf := 0       # tampon d'un secteur (données)
dbuf := 0      # tampon d'un secteur de répertoire
fatbuf := 0    # secteur de FAT en cache
fat_sector := -1

func _check_mounted():
    if buf == 0:
        raise("FatError", "volume non monté")

func mount():
    if buf == 0:
        buf = hw.alloc_pages(1)
        dbuf = hw.alloc_pages(1)
        fatbuf = hw.alloc_pages(1)
    bloc.read(0, buf)
    if hw.peek16(buf + 510) != 43605: # signature 0xAA55
        raise("FatError", "pas de système de fichiers FAT (signature du secteur 0)")
    bps = hw.peek16(buf + 11)
    spc = hw.peek8(buf + 13)
    reserved := hw.peek16(buf + 14)
    nfats = hw.peek8(buf + 16)
    root_entries = hw.peek16(buf + 17)
    total := hw.peek16(buf + 19)
    if total == 0:
        total = hw.peek32(buf + 32)
    fat_size = hw.peek16(buf + 22)
    if bps != 512 or fat_size == 0 or root_entries == 0:
        raise("FatError", "seul FAT16 en secteurs de 512 octets est pris en charge")
    fat_start = reserved
    root_start = fat_start + nfats * fat_size
    data_start = root_start + (root_entries * 32 + 511) // 512
    clusters = (total - data_start) // spc
    fat_sector = -1

# ---- table d'allocation ----
func _fat_get(c: int) -> int:
    sector := fat_start + (2 * c) // 512
    if sector != fat_sector:
        bloc.read(sector, fatbuf)
        fat_sector = sector
    return hw.peek16(fatbuf + (2 * c) % 512)

func _fat_set(c: int, v: int):
    _fat_get(c)
    hw.poke16(fatbuf + (2 * c) % 512, v)
    k := 0
    while k < nfats:
        bloc.write(fat_sector + k * fat_size, fatbuf)
        k += 1

func _lba(cluster: int) -> int:
    return data_start + (cluster - 2) * spc

func _free_chain(c: int):
    while c >= 2 and c < EOC:
        next := _fat_get(c)
        _fat_set(c, 0)
        c = next

func _alloc_cluster() -> int:
    c := 2
    while c < clusters + 2:
        if _fat_get(c) == 0:
            _fat_set(c, 65535)
            return c
        c += 1
    raise("FatError", "disque plein")
    return 0

func _zero_cluster(c: int):
    hw.zero(buf, 512)
    k := 0
    while k < spc:
        bloc.write(_lba(c) + k, buf)
        k += 1

# ---- horodatage ----
func _cmos(reg: int) -> int:
    hw.outb(112, reg)
    v := hw.inb(113)
    return (v >> 4) * 10 + (v & 15) # BCD

# Date et heure FAT d'après l'horloge CMOS : (date << 16) | heure.
func _stamp() -> int:
    date := ((_cmos(9) + 20) << 9) | (_cmos(8) << 5) | _cmos(7) # années depuis 1980
    time := (_cmos(4) << 11) | (_cmos(2) << 5) | (_cmos(0) // 2)
    return (date << 16) | time

# ---- positions des entrées d'un répertoire ----
func _slots(dc: int) -> int:
    if dc == 0:
        return root_entries
    n := 0
    c := dc
    while c >= 2 and c < EOC:
        n += 16 * spc
        c = _fat_get(c)
    return n

# Secteur contenant l'entrée en position slot du répertoire dc.
func _slot_lba(dc: int, slot: int) -> int:
    if dc == 0:
        return root_start + slot // 16
    per := 16 * spc
    c := dc
    i := slot // per
    while i > 0:
        c = _fat_get(c)
        i -= 1
    return _lba(c) + (slot % per) // 16

# ---- noms ----
func _is_upper83_char(c: int) -> bool:
    if (c >= 65 and c <= 90) or (c >= 48 and c <= 57):
        return true
    for x in "$%'-_@~`!(){}^#&":
        if ord(x) == c:
            return true
    return false

# Vrai si name est un nom 8.3 valide (caractères permis, en majuscules).
func _valid83(name: str) -> bool:
    parts := split(name, ".")
    if len(parts) > 2 or len(parts[0]) == 0 or len(parts[0]) > 8:
        return false
    if len(parts) == 2 and (len(parts[1]) == 0 or len(parts[1]) > 3):
        return false
    for p in parts:
        for c in p:
            if not _is_upper83_char(ord(c)):
                return false
    return true

func _pad(s: str, n: int) -> str:
    r := s
    while len(r) < n:
        r += " "
    return r

func _pack(base: str, ext: str) -> str:
    return _pad(base, 8) + _pad(ext, 3)

# Nom 8.3 (déjà valide) -> 11 octets.
func _pack83(name: str) -> str:
    parts := split(name, ".")
    if len(parts) == 2:
        return _pack(parts[0], parts[1])
    return _pack(parts[0], "")

func _checksum(raw: int) -> int:
    sum := 0
    i := 0
    while i < 11:
        sum = ((((sum & 1) << 7) + (sum >> 1)) + hw.peek8(raw + i)) & 255
        i += 1
    return sum

func _checksum_str(short: str) -> int:
    return _checksum(hw.byte_addr(short))

# Nom court affiché (« NOM.EXT », minuscules d'après l'octet 12 : bit 3 nom, bit 4 extension).
func _display(e: int) -> str:
    nt := hw.peek8(e + 12)
    base := ""
    ext := ""
    i := 0
    while i < 11:
        b := hw.peek8(e + i)
        if i == 0 and b == 5:
            b = 229
        if b != 32:
            ch := str(chr(b))
            if i < 8:
                if (nt & 8) != 0:
                    ch = lower(ch)
                base += ch
            else:
                if (nt & 16) != 0:
                    ch = lower(ch)
                ext += ch
        i += 1
    if ext == "":
        return base
    return base + "." + ext

# Chaîne -> unités UTF-16 ; unités UTF-16 -> chaîne (paires de substitution comprises).
func _to_utf16(s: str) -> list[int]:
    out: list[int] := []
    for c in s:
        cp := ord(c)
        if cp >= 65536:
            cp -= 65536
            append(out, 55296 + (cp >> 10))
            append(out, 56320 + (cp & 1023))
        else:
            append(out, cp)
    return out

func _from_utf16(units: list[int]) -> str:
    s := ""
    i := 0
    while i < len(units):
        u := units[i]
        if u >= 55296 and u < 56320 and i + 1 < len(units) and units[i + 1] >= 56320 and units[i + 1] < 57344:
            s += str(chr(65536 + ((u - 55296) << 10) + (units[i + 1] - 56320)))
            i += 2
            continue
        s += str(chr(u))
        i += 1
    return s

LFN_OFFSETS: list[int] := [1, 3, 5, 7, 9, 14, 16, 18, 20, 22, 24, 28, 30] # 13 caractères UTF-16 par entrée

# Unités UTF-16 d'une entrée LFN (jusqu'au 0 final, sans le bourrage 0xFFFF).
func _lfn_units(e: int) -> list[int]:
    out: list[int] := []
    for off in LFN_OFFSETS:
        u := hw.peek16(e + off)
        if u == 0:
            return out
        if u != 65535:
            append(out, u)
    return out

func _check_name(name: str):
    if name == "" or name == "." or name == "..":
        raise("FatError", "nom invalide : '" + name + "'")
    if len(_to_utf16(name)) > MAX_NAME:
        raise("FatError", "nom trop long (255 caractères au plus) : " + name)
    for c in name:
        cp := ord(c)
        if cp < 32:
            raise("FatError", "caractère de contrôle interdit dans un nom : " + name)
        for x in "\"*/:<>?\\|":
            if ord(x) == cp:
                raise("FatError", "caractère interdit dans un nom (\"*/:<>?\\|) : " + name)

# ---- lecture d'un répertoire ----
# Entrées du répertoire dc, « . » et « .. » comprises, étiquettes de volume exclues.
func _scan(dc: int) -> list[Entry]:
    out: list[Entry] := []
    total := _slots(dc)
    parts: list[list[int]] := [] # morceaux du nom long en cours, indice = ordre - 1
    expect := 0                   # prochain ordre attendu (0 : pas de nom long en cours)
    sum := 0
    lfn_first := -1
    lba := -1
    slot := 0
    while slot < total:
        l := _slot_lba(dc, slot)
        if l != lba:
            bloc.read(l, dbuf)
            lba = l
        e := dbuf + 32 * (slot % 16)
        first := hw.peek8(e)
        if first == 0:
            return out
        attr := hw.peek8(e + 11)
        if first == DELETED:
            expect = 0
        elif attr == ATTR_LFN:
            seq := first & 31
            if (first & 64) != 0 and seq >= 1:
                empty: list[int] := []
                parts = [empty for j in 0..seq]
                sum = hw.peek8(e + 13)
                lfn_first = slot
                expect = seq
            if expect > 0 and seq == expect and hw.peek8(e + 13) == sum:
                parts[seq - 1] = _lfn_units(e)
                expect -= 1
                if expect == 0:
                    expect = -1 # nom long complet, en attente de son entrée courte
            else:
                expect = 0
        else:
            if (attr & ATTR_VOLUME) == 0:
                name := ""
                start := slot
                if expect == -1 and _checksum(e) == sum:
                    units: list[int] := []
                    for p in parts:
                        for u in p:
                            append(units, u)
                    name = _from_utf16(units)
                    start = lfn_first
                else:
                    name = _display(e)
                append(out, Entry(name, hw.string_at(e, 11), hw.peek32(e + 28), hw.peek16(e + 26),
                                  (attr & ATTR_DIR) != 0, dc, slot, start))
            expect = 0
        slot += 1
    return out

func _same(e: Entry, name: str) -> bool:
    up := upper(name)
    if upper(e.name) == up:
        return true
    return _valid83(up) and e.short == _pack83(up)

func _lookup(dc: int, name: str) -> Entry?:
    for e in _scan(dc):
        if _same(e, name):
            return e
    return null

func _components(path: str) -> list[str]:
    out: list[str] := []
    for p in split(path, "/"):
        if p != "" and p != ".":
            append(out, p)
    return out

func _root() -> Entry:
    return Entry("/", "", 0, 0, true, 0, -1, -1)

# Grappe du répertoire désigné par les composants comps (« .. » compris) ; erreur s'il n'existe pas.
func _dir_of(comps: list[str]) -> int:
    dc := 0
    for c in comps:
        if c == ".." and dc == 0:
            continue
        e := _lookup(dc, c)
        if e == null:
            raise("FatError", "répertoire introuvable : " + c)
        if not e.is_dir:
            raise("FatError", "n'est pas un répertoire : " + c)
        dc = e.cluster
    return dc

func _parent(comps: list[str]) -> list[str]:
    return [comps[i] for i in 0..len(comps) - 1]

# ---- API ----
# Entrée désignée par path (« / » ou « » : la racine), ou null.
func find(path: str) -> Entry?:
    _check_mounted()
    comps := _components(path)
    if len(comps) == 0:
        return _root()
    try:
        dc := _dir_of(_parent(comps))
        last := comps[len(comps) - 1]
        if last == ".." and dc == 0:
            return _root()
        return _lookup(dc, last)
    catch e:
        return null
    return null

func is_dir(path: str) -> bool:
    e := find(path)
    if e == null:
        return false
    return e.is_dir

# Contenu du répertoire path (sans « . » ni « .. »).
func list(path: str = "") -> list[Entry]:
    d := find(path)
    if d == null:
        raise("FatError", "répertoire introuvable : " + path)
    if not d.is_dir:
        raise("FatError", "n'est pas un répertoire : " + path)
    out: list[Entry] := []
    for e in _scan(d.cluster):
        if e.name != "." and e.name != "..":
            append(out, e)
    return out

func read(path: str) -> str:
    e := find(path)
    if e == null:
        raise("FatError", "fichier introuvable : " + path)
    if e.is_dir:
        raise("FatError", "est un répertoire : " + path)
    pages := e.size // 4096 + 1
    data := hw.alloc_pages(pages)
    done := 0
    c := e.cluster
    while done < e.size and c >= 2 and c < EOC:
        k := 0
        while k < spc and done < e.size:
            bloc.read(_lba(c) + k, buf)
            n := e.size - done
            if n > 512:
                n = 512
            hw.copy(data + done, buf, n)
            done += n
            k += 1
        c = _fat_get(c)
    text := hw.string_at(data, e.size)
    hw.free_pages(data, pages)
    return text

# Écrit le texte dans une nouvelle chaîne de grappes ; renvoie la première (0 : texte vide).
func _store(text: str) -> int:
    size := hw.byte_size(text)
    src := hw.byte_addr(text)
    first := 0
    prev := 0
    done := 0
    while done < size:
        c := _alloc_cluster()
        if prev == 0:
            first = c
        else:
            _fat_set(prev, c)
        prev = c
        k := 0
        while k < spc:
            hw.zero(buf, 512)
            n := size - done
            if n > 512:
                n = 512
            if n > 0:
                hw.copy(buf, src + done, n)
                done += n
            bloc.write(_lba(c) + k, buf)
            k += 1
    return first

# Première position d'une suite de count entrées libres du répertoire dc ; un sous-répertoire plein est
# agrandi d'une grappe (mise à zéro) autant que nécessaire.
func _free_run(dc: int, count: int) -> int:
    total := _slots(dc)
    run := 0
    start := -1
    lba := -1
    slot := 0
    while slot < total:
        l := _slot_lba(dc, slot)
        if l != lba:
            bloc.read(l, dbuf)
            lba = l
        b := hw.peek8(dbuf + 32 * (slot % 16))
        if b == 0 or b == DELETED:
            if run == 0:
                start = slot
            run += 1
            if run == count:
                return start
        else:
            run = 0
        slot += 1
    if dc == 0:
        raise("FatError", "répertoire racine plein")
    last := dc
    while _fat_get(last) < EOC:
        last = _fat_get(last)
    while run < count:
        c := _alloc_cluster()
        _zero_cluster(c)
        _fat_set(last, c)
        last = c
        if run == 0:
            start = total
        run += 16 * spc
        total += 16 * spc
    return start

func _write_lfn(dc: int, slot: int, seq: int, sum: int, units: list[int], part: int):
    l := _slot_lba(dc, slot)
    bloc.read(l, dbuf)
    e := dbuf + 32 * (slot % 16)
    hw.zero(e, 32)
    hw.poke8(e, seq)
    hw.poke8(e + 11, ATTR_LFN)
    hw.poke8(e + 13, sum)
    j := 0
    for off in LFN_OFFSETS:
        idx := 13 * part + j
        v := 65535
        if idx < len(units):
            v = units[idx]
        elif idx == len(units):
            v = 0
        hw.poke16(e + off, v)
        j += 1
    bloc.write(l, dbuf)

func _write_short(dc: int, slot: int, short: str, attr: int, cluster: int, size: int):
    l := _slot_lba(dc, slot)
    bloc.read(l, dbuf)
    e := dbuf + 32 * (slot % 16)
    hw.zero(e, 32)
    hw.store_string(short, e)
    hw.poke8(e + 11, attr)
    st := _stamp()
    hw.poke16(e + 14, st & 65535)
    hw.poke16(e + 16, st >> 16)
    hw.poke16(e + 18, st >> 16)
    hw.poke16(e + 22, st & 65535)
    hw.poke16(e + 24, st >> 16)
    hw.poke16(e + 26, cluster)
    hw.poke32(e + 28, size)
    bloc.write(l, dbuf)

func _update(e: Entry, cluster: int, size: int):
    l := _slot_lba(e.dir, e.slot)
    bloc.read(l, dbuf)
    p := dbuf + 32 * (e.slot % 16)
    st := _stamp()
    hw.poke16(p + 18, st >> 16)
    hw.poke16(p + 22, st & 65535)
    hw.poke16(p + 24, st >> 16)
    hw.poke16(p + 26, cluster)
    hw.poke32(p + 28, size)
    bloc.write(l, dbuf)

func _short_taken(dc: int, short: str) -> bool:
    for e in _scan(dc):
        if e.short == short:
            return true
    return false

# Nom de base et extension du nom court d'un nom long (majuscules, caractères non permis -> « _ »).
func _basis(name: str) -> list[str]:
    up := upper(name)
    dot := -1
    i := 0
    for c in up:
        if c == '.':
            dot = i
        i += 1
    base := ""
    ext := ""
    i = 0
    for c in up:
        cp := ord(c)
        if c == ' ' or (c == '.' and i != dot):
            i += 1
            continue
        if i == dot:
            i += 1
            continue
        ch := "_"
        if _is_upper83_char(cp):
            ch = str(c)
        if dot >= 0 and i > dot:
            if len(ext) < 3:
                ext += ch
        else:
            base += ch
        i += 1
    if base == "":
        base = "_"
    return [base, ext]

# Nom court (11 octets) et besoin d'un nom long pour name dans le répertoire dc.
func _short_for(dc: int, name: str) -> tuple[str, bool]:
    up := upper(name)
    if _valid83(name):
        return (_pack83(name), false)
    if _valid83(up) and not _short_taken(dc, _pack83(up)):
        return (_pack83(up), true)
    be := _basis(name)
    n := 1
    while n < 1000000:
        tail := "~" + str(n)
        base := be[0]
        if len(base) > 8 - len(tail):
            base = substring(base, 0, 8 - len(tail))
        cand := _pack(base + tail, be[1])
        if not _short_taken(dc, cand):
            return (cand, true)
        n += 1
    raise("FatError", "plus de nom court disponible pour " + name)
    return ("", true)

# Crée l'entrée name (nom long si nécessaire) dans le répertoire dc.
func _create(dc: int, name: str, attr: int, cluster: int, size: int):
    sn := _short_for(dc, name)
    short := sn[0]
    units := _to_utf16(name)
    n := 0
    if sn[1]:
        n = (len(units) + 12) // 13
    start := _free_run(dc, n + 1)
    sum := _checksum_str(short)
    j := 0
    while j < n:
        order := n - j
        seq := order
        if j == 0:
            seq = seq | 64
        _write_lfn(dc, start + j, seq, sum, units, order - 1)
        j += 1
    _write_short(dc, start + n, short, attr, cluster, size)

# Crée ou remplace le fichier path avec le texte text (répertoires parents existants).
func write(path: str, text: str):
    _check_mounted()
    comps := _components(path)
    if len(comps) == 0:
        raise("FatError", "chemin de fichier vide")
    dc := _dir_of(_parent(comps))
    name := comps[len(comps) - 1]
    _check_name(name)
    old := _lookup(dc, name)
    if old != null:
        if old.is_dir:
            raise("FatError", "est un répertoire : " + path)
        _free_chain(old.cluster)
        _update(old, _store(text), hw.byte_size(text))
        return
    _create(dc, name, ATTR_ARCHIVE, _store(text), hw.byte_size(text))

# Marque libres les entrées de e (nom long compris).
func _erase(e: Entry):
    s := e.first
    while s <= e.slot:
        l := _slot_lba(e.dir, s)
        bloc.read(l, dbuf)
        hw.poke8(dbuf + 32 * (s % 16), DELETED)
        bloc.write(l, dbuf)
        s += 1

func remove(path: str):
    e := find(path)
    if e == null:
        raise("FatError", "fichier introuvable : " + path)
    if e.is_dir:
        raise("FatError", "est un répertoire (rmdir) : " + path)
    _free_chain(e.cluster)
    _erase(e)

# Crée le répertoire path (son parent doit exister).
func mkdir(path: str):
    _check_mounted()
    comps := _components(path)
    if len(comps) == 0:
        raise("FatError", "la racine existe déjà")
    dc := _dir_of(_parent(comps))
    name := comps[len(comps) - 1]
    _check_name(name)
    if _lookup(dc, name) != null:
        raise("FatError", "existe déjà : " + path)
    c := _alloc_cluster()
    _zero_cluster(c)
    _write_short(c, 0, _pack(".", ""), ATTR_DIR, c, 0)
    _write_short(c, 1, _pack("..", ""), ATTR_DIR, dc, 0)
    _create(dc, name, ATTR_DIR, c, 0)

# Supprime le répertoire vide path.
func rmdir(path: str):
    e := find(path)
    if e == null:
        raise("FatError", "répertoire introuvable : " + path)
    if not e.is_dir:
        raise("FatError", "n'est pas un répertoire : " + path)
    if e.slot < 0 or e.name == "..":
        raise("FatError", "impossible de supprimer ce répertoire : " + path)
    if len(list(path)) > 0:
        raise("FatError", "répertoire non vide : " + path)
    _free_chain(e.cluster)
    _erase(e)
