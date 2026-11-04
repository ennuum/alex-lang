# hardware.hardware_info, memory_map, permissions, hardware (façade) : analyses de textes /proc, carte mémoire
# (ajout, réserve, allocation, fusion), projections du processus, droits sur des fichiers, règle udev.
from core use len
use os
use hardware
use hardware.hardware_info as hi
use hardware.memory_map as mm
use hardware.permissions as perm
use io

ok := [0]
ko := [0]
func check(cond, label):
    if cond:
        ok[0] += 1
    else:
        ko[0] += 1
        print("ÉCHEC " + label)

cpuinfo := "processor\t: 0\nvendor_id\t: GenuineIntel\nmodel name\t: Test CPU @ 3.00GHz\ncpu MHz\t\t: 3000.000\nphysical id\t: 0\ncore id\t\t: 0\nflags\t\t: fpu lm cx16 lahf_lm popcnt sse4_1 sse4_2 ssse3 avx avx2 bmi1 bmi2 f16c fma movbe xsave vmx\naddress sizes\t: 39 bits physical, 48 bits virtual\n\nprocessor\t: 1\nvendor_id\t: GenuineIntel\nmodel name\t: Test CPU @ 3.00GHz\ncpu MHz\t\t: 1000.000\nphysical id\t: 0\ncore id\t\t: 1\n\nprocessor\t: 2\nphysical id\t: 0\ncore id\t\t: 0\n\nprocessor\t: 3\nphysical id\t: 0\ncore id\t\t: 1\n"
c := hi.parse_cpuinfo(cpuinfo)
check(c.threads == 4 and c.cores == 2 and c.sockets == 1, "cœurs et fils")
check(c.model == "Test CPU @ 3.00GHz" and c.mhz == 2000.0, "modèle, fréquence moyenne")
check(c.has("AVX2") and not c.has("avx512f") and c.x86_level() == 3 and c.virtualization() == "VT-x", "jeux d'instructions")
check(c.address_bits == [39, 48], "tailles d'adresse")
m := hi.parse_meminfo("MemTotal:       16384000 kB\nMemFree:         1000000 kB\nMemAvailable:    8192000 kB\nSwapTotal:       2048000 kB\nSwapFree:        2048000 kB\nHugePages_Total:       0\n")
check(m.total == 16384000 * 1024 and m.available_mib() == 8000 and m.swap_used() == 0, "mémoire")
check(m.used_percent() == 50.0 and m.values["HugePages_Total"] == 0, "pourcentage, compteurs")
check(len(hi.summary()) > 0 and hi.cpu().threads >= 1 and hi.memory().total > 0, "machine réelle")

carte := mm.MemoryMap()
carte.add(0, 0x9FC00, "ram")
carte.add(0x100000, 0x3F00000, "ram")
carte.add(0xFEC00000, 0x1000, "mmio", "IOAPIC")
check(carte.total("ram") == 0x9FC00 + 0x3F00000 and carte.kind_at(0xFEC00010) == "mmio", "carte")
carte.reserve(0x100000, 0x200000, "noyau")
check(carte.find(0x150000).name == "noyau" and carte.total("ram") == 0x9FC00 + 0x3D00000, "réserve")
a := carte.allocate(0x8000, 0x10000)
check(a == 0x10000 and carte.find(a).kind == "allocated", "allocation alignée (page 0 évitée)")
b := carte.allocate(0x100000, 4096, "tampon", 0x1000000)
check(b == 0x1000000, "allocation au-dessus d'un minimum")
carte.release(a)
check(carte.find(a).kind == "ram" and carte.find(0x5000).end == 0x9FC00, "libération et fusion")
check(len(carte.holes(0x100000000)) >= 2 and carte.ram_end() == 0x4000000, "trous, fin de la RAM")
erreur := ""
try:
    carte.allocate(0x80000000)
catch e:
    erreur = e.type
check(erreur == "MemoryError", "plus de place")
racines := mm.parse_iomem("00000000-00000fff : Reserved\n00001000-0009fbff : System RAM\n00100000-bfffffff : System RAM\n  01000000-01ffffff : Kernel code\nfec00000-fec003ff : IOAPIC 0\n")
check(len(racines) == 4 and racines[2].children[0].kind == "kernel" and racines[3].kind == "mmio", "analyse de /proc/iomem")
maps := mm.parse_maps("55d0-55e0 r-xp 00000000 fe:00 123 /usr/bin/alex\n7ff0-8000 rw-p 00000000 00:00 0 [stack]\n9000-a000 rw-p 00000000 00:00 0\n")
check(len(maps) == 3 and maps[0].kind() == "code" and maps[1].kind() == "stack" and maps[2].kind() == "anonymous", "projections")
check(maps[0].executable() and not maps[0].writable() and maps[0].size() == 0x10, "droits des projections")
check(mm.process_usage()["code"] > 0, "projections du processus courant")

moi := perm.current()
check(moi.uid >= 0 and len(moi.group_names()) >= 1 and len(moi.describe()) > 0, "identité")
f := os.tmp_dir() + "/alex_perm_" + str(os.pid())
os.mkdir(f)
fichier := f + "/noeud"

io.write_file(fichier, "x")
os.chmod(fichier, 416)          # 0o640
acc := perm.check(fichier)
check(acc.exists and acc.mode == 416 and acc.kind == "file" and acc.allowed("r"), "accès à un fichier")
check(perm.check(f + "/absent").explain() == f + "/absent n'existe pas (périphérique absent, pilote non chargé, ou machine virtuelle sans ce matériel).", "nœud absent")
check(perm._want_bits("rw") == 6 and perm._mode_text(416) == "rw-r-----", "bits")
check(perm.udev_rule(0x2341, 0x43) == "SUBSYSTEM==\"usb\", ATTRS{idVendor}==\"2341\", ATTRS{idProduct}==\"0043\", MODE=\"0660\", GROUP=\"plugdev\", TAG+=\"uaccess\"", "règle udev")
erreur = ""
try:
    perm.nodes("inconnue")
catch e2:
    erreur = e2.type
check(erreur == "ArgumentError", "catégorie inconnue")
os.rmdir(f, true)
check(len(hardware.summary()) > 0 and hardware.census() != null, "façade hardware")
print("hardware (suite) : " + str(ok[0]) + " OK, " + str(ko[0]) + " échecs")
