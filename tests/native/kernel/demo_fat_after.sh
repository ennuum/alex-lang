#!/bin/sh
# Après demo_fat : le disque modifié par le noyau Alex, vu par l'hôte (mtools, fsck.fat).
# usage : demo_fat_after.sh image
img=$1
export LC_ALL=C.UTF-8
echo "--- hôte : fsck.fat"
fsck.fat -n "$img" > /dev/null 2>&1 && echo "volume sain" || fsck.fat -n "$img"
echo "--- hôte : arborescence de Projets"
mdir -i "$img" -/ -b "::/Projets" | sed 's|^::/||'
echo "--- hôte : contenu lu par mtype"
mtype -i "$img" "::/Projets/Alex OS/Journal de bord.txt"
mtype -i "$img" "::/Mes documents/Liste de courses.txt"
echo "--- hôte : noms courts"
mdir -i "$img" "::/Projets" | grep -E '~|README' | awk '{print $1, $2}'
echo "--- hôte : noms longs relus en Python (UTF-16 avec paires, sommes de contrôle, ordre des morceaux)"
python3 - "$img" <<'PY'
import struct, sys
d = open(sys.argv[1], 'rb').read()
bps, spc, res, nf, rootn = struct.unpack_from('<HBHBH', d, 11)
fsz = struct.unpack_from('<H', d, 22)[0]
root = (res + nf * fsz) * bps
data = root + rootn * 32
fat = res * bps
def chain(c):
    while 2 <= c < 0xFFF8:
        yield c
        c = struct.unpack_from('<H', d, fat + 2 * c)[0]
def entries(c):
    if c == 0:
        yield from (d[root + 32 * i: root + 32 * i + 32] for i in range(rootn))
        return
    for cl in chain(c):
        base = data + (cl - 2) * spc * bps
        yield from (d[base + 32 * i: base + 32 * i + 32] for i in range(spc * bps // 32))
def csum(short):
    s = 0
    for b in short:
        s = (((s & 1) << 7) + (s >> 1) + b) & 255
    return s
def names(c):
    out, parts, want, sm = [], {}, 0, None
    for e in entries(c):
        if e[0] == 0:
            break
        if e[0] == 0xE5:
            parts, want = {}, 0
            continue
        if e[11] == 0x0F:
            seq = e[0] & 31
            if e[0] & 0x40:
                parts, want, sm = {}, seq, e[13]
            assert e[13] == sm and seq == want, 'ordre ou somme LFN incohérents'
            u = e[1:11] + e[14:26] + e[28:32]
            parts[seq] = u
            want -= 1
            continue
        if parts:
            assert want == 0 and csum(e[:11]) == sm, 'somme de contrôle LFN fausse'
            raw = b''.join(parts[k] for k in sorted(parts))
            n = raw.decode('utf-16-le', 'surrogatepass').split('\x00')[0].replace('\uffff', '')
            n = n.encode('utf-16', 'surrogatepass').decode('utf-16')
        else:
            n = e[:8].decode('latin-1').rstrip() + ('.' + e[8:11].decode('latin-1').rstrip() if e[8:11].strip() else '')
        out.append((n, struct.unpack_from('<H', e, 26)[0], e[11]))
        parts = {}
    return out
proj = [c for n, c, a in names(0) if n == 'Projets'][0]
for n, c, a in names(proj):
    if n not in ('.', '..'):
        print('Projets/' + n + ('/' if a & 16 else ''))
PY
