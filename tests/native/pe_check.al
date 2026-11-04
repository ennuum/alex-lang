# Contrat binaire d'un exécutable PE32+ produit par le backend natif (Windows x64 / ARM64, UEFI), vérifié sans
# l'exécuter — ce que contrôlait au chargement le lanceur de test C++ retiré (winrun / efirun) :
#   - en-têtes DOS / PE / optionnel PE32+ cohérents, machine et sous-système attendus ;
#   - DYNAMIC_BASE posé (sauf UEFI) et relocations de base bien formées : blocs alignés, entrées DIR64 ou
#     ABSOLUTE seulement, chaque cible à l'intérieur d'une section de l'image ;
#   - table d'importation bien formée : chaque DLL et chaque fonction importée par son nom (pas d'ordinal) ;
#   - sections alignées, aucune section à la fois inscriptible et exécutable, point d'entrée dans une section
#     exécutable.
#
#   alex run tests/native/pe_check.al fichier.exe x64|arm64|uefi|uefi-arm64 [console|gui]
# Affiche « ok » (code 0) ou la première violation (code 1).
use io
use os
use string as s
from core use len

argv := os.args()
if len(argv) < 2:
    print("usage : pe_check fichier x64|arm64|uefi|uefi-arm64 [console|gui]")
    os.exit(2)
b := s.byte_unpack(io.read_file(argv[0]))
kind := argv[1]
want_gui := len(argv) > 2 and argv[2] == "gui"

func fail(msg):
    print("PE invalide (" + argv[0] + ") : " + msg)
    os.exit(1)

func u16(i):
    if i + 2 > len(b):
        fail("lecture hors du fichier à " + str(i))
    return b[i] | (b[i + 1] << 8)

func u32(i):
    if i + 4 > len(b):
        fail("lecture hors du fichier à " + str(i))
    return b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24)

func u64(i):
    return u32(i) | (u32(i + 4) << 32)

if len(b) < 64 or b[0] != 77 or b[1] != 90:
    fail("signature MZ absente")
pe := u32(60)
if u32(pe) != 17744:
    fail("signature PE absente")
machine := u16(pe + 4)
nsec := u16(pe + 6)
optsz := u16(pe + 20)
chars := u16(pe + 22)
opt := pe + 24
if u16(opt) != 523:
    fail("en-tête optionnel PE32+ attendu")
arm := kind == "arm64" or kind == "uefi-arm64"
if arm and machine != 43620:
    fail("machine ARM64 (0xAA64) attendue")
if not arm and machine != 34404:
    fail("machine x86-64 (0x8664) attendue")
if (chars & 2) == 0:
    fail("IMAGE_FILE_EXECUTABLE_IMAGE absent")
entry := u32(opt + 16)
image_base := u64(opt + 24)
sec_align := u32(opt + 32)
file_align := u32(opt + 36)
size_image := u32(opt + 56)
size_headers := u32(opt + 60)
subsystem := u16(opt + 68)
dllchars := u16(opt + 70)
ndirs := u32(opt + 108)
uefi := kind == "uefi" or kind == "uefi-arm64"
if uefi:
    if subsystem != 10:
        fail("sous-système EFI application (10) attendu, obtenu " + str(subsystem))
else:
    want := 2 if want_gui else 3
    if subsystem != want:
        fail("sous-système " + str(want) + " attendu, obtenu " + str(subsystem))
    if (dllchars & 64) == 0:
        fail("DYNAMIC_BASE absent (image non relogeable)")
    if (dllchars & 256) == 0:
        fail("NX_COMPAT absent")
if sec_align == 0 or file_align == 0 or (sec_align & (sec_align - 1)) != 0 or (file_align & (file_align - 1)) != 0:
    fail("alignements invalides")
if image_base % 65536 != 0:
    fail("base de l'image non alignée sur 64 Kio")

# sections : [rva, taille virtuelle, pointeur fichier, taille fichier, caractéristiques, nom]
secs := []
st := opt + optsz
for k in 0..nsec:
    o := st + 40 * k
    name := s.byte_pack([c for c in b[o:o + 8] if c != 0])
    rva := u32(o + 12)
    vs := u32(o + 8)
    raw := u32(o + 20)
    rs := u32(o + 16)
    ch := u32(o + 36)
    if rva % sec_align != 0:
        fail("section " + name + " non alignée")
    if rs > 0 and (raw % file_align != 0 or raw + rs > len(b)):
        fail("données de la section " + name + " hors du fichier")
    if (ch & 2147483648) != 0 and (ch & 536870912) != 0:
        fail("section " + name + " à la fois inscriptible et exécutable")
    if rva + vs > size_image:
        fail("section " + name + " au-delà de SizeOfImage")
    secs = secs + [[rva, vs, raw, rs, ch, name]]

func sec_of(rva):
    for x in secs:
        if rva >= x[0] and rva < x[0] + (x[1] if x[1] > x[3] else x[3]):
            return x
    return null

func off(rva):
    x := sec_of(rva)
    if x == null:
        if rva < size_headers:
            return rva
        fail("RVA " + str(rva) + " hors des sections")
    if rva - x[0] >= x[3]:
        fail("RVA " + str(rva) + " dans la partie non initialisée de " + x[5])
    return x[2] + rva - x[0]

es := sec_of(entry)
if es == null or (es[4] & 536870912) == 0:
    fail("point d'entrée hors d'une section exécutable")

# relocations de base (répertoire 5)
nrel := 0
if ndirs > 5 and u32(opt + 112 + 8 * 5 + 4) > 0:
    rva := u32(opt + 112 + 40)
    size := u32(opt + 112 + 44)
    o := off(rva)
    end := o + size
    while o < end:
        page := u32(o)
        bs := u32(o + 4)
        if bs < 8 or bs % 4 != 0 or o + bs > end:
            fail("bloc de relocations mal formé")
        i := 8
        while i < bs:
            e := u16(o + i)
            t := e >> 12
            if t == 10:
                tgt := page + (e & 4095)
                x := sec_of(tgt)
                if x == null or tgt + 8 > x[0] + (x[1] if x[1] > x[3] else x[3]):
                    fail("relocation hors de l'image : RVA " + str(tgt))
                nrel += 1
            elif t != 0:
                fail("type de relocation " + str(t) + " (seuls DIR64 et ABSOLUTE sont attendus)")
            i += 2
        o += bs
elif not uefi:
    fail("relocations de base absentes alors que DYNAMIC_BASE est posé")

func cstr(o):
    out := []
    while b[o] != 0:
        out = out + [b[o]]
        o += 1
    return s.byte_pack(out)

# imports (répertoire 1)
nimp := 0
dlls := []
fns := []
if ndirs > 1 and u32(opt + 112 + 12) > 0:
    o := off(u32(opt + 112 + 8))
    while true:
        ilt := u32(o)
        name_rva := u32(o + 12)
        iat := u32(o + 16)
        if ilt == 0 and name_rva == 0 and iat == 0:
            break
        dll := cstr(off(name_rva))
        if dll == "":
            fail("nom de DLL vide")
        dlls = dlls + [s.lower(dll)]
        t := off(ilt if ilt != 0 else iat)
        while true:
            v := u64(t)
            if v == 0:
                break
            if (v >> 63) != 0:
                fail("import par ordinal depuis " + dll)
            fn := cstr(off((v & 2147483647) + 2))
            if fn == "":
                fail("import sans nom depuis " + dll)
            fns = fns + [fn]
            nimp += 1
            t += 8
        o += 20
elif not uefi:
    fail("aucun import (kernel32 attendu)")
if uefi and nimp != 0:
    fail("une application UEFI n'importe rien")
res := ndirs > 2 and u32(opt + 112 + 20) > 0
# ligne de détail : DLL importées, fonctions, présence de ressources (manifeste des applications graphiques)
detail := "dll=" + s.join(",", dlls) + " fonctions=" + s.join(",", fns) + " ressources=" + ("oui" if res else "non")
print("ok    PE " + kind + " : " + str(nsec) + " sections, " + str(nrel) + " relocations, " + str(nimp) + " imports")
print(detail)
