# alexc — chaîne d'outils ALEX écrite en ALEX : compilateur vers bytecode, compilateur natif et outils du langage.
#
# Aucune ligne de C++ : compilateur (src/, compilé en natif par lui-même) et machine virtuelle écrite en
# ALEX (runtime/vm/vm.al, exécutable alexvm à côté d'alexc). Mêmes commandes et mêmes sorties que l'exécutable alex
# de référence (C++, gardé comme oracle de test), le nom de l'outil mis à part.
#
#   alexc run [--profile[=rapport.json]] prog.al|prog.albc [--] [arguments...]    compile puis exécute sur alexvm
#   alexc run [-- arguments...]                        dans un projet alex.toml : son point d'entrée
#   alexc build prog.al [-o prog.albc] [--stdlib DOSSIER] [--no-typecheck]   bytecode .albc (programme complet)
#   alexc build prog.al --native [--static | --dynamic] [--windows [--gui] | --uefi] [-o exécutable] [--emit-ir F]
#   alexc build prog.al --standalone [-o exécutable]     exécutable autonome (compilateur natif, mode dynamique)
#   alexc native prog.al [-o exécutable] [options de --native]                  (synonyme de build --native)
#   alexc compile prog.al -o prog.albc [--qualifier Q] [--source CHEMIN]        un seul fichier, sans graphe ni prélude
#   alexc check prog.al                                vérifie (analyse, types) sans exécuter
#   alexc test [chemins...] [--filter texte] [--json] [--list] [-j N]
#   alexc fmt [--check] [fichiers|dossiers...]
#   alexc doc <module|fichier.al>... | --json <module> | --html <dossier> [modules] | --list
#   alexc new [modèle] <nom> [--dir dossier] [--ci github|gitlab|aucune] | --list [--json]
#   alexc pkg init|add|remove|install|update|list|publish|verify ...
#   alexc repl                                         boucle interactive (sur alexvm)
#   alexc debug [--protocol 2 [--break-on-exception]] prog.al|prog.albc [arguments...]
#   alexc lsp [--jsonl] [dossier]                     serveur de langage (LSP, ou JSON Lines pour ALEX Studio)
#   alexc vm [-o alexvm] [--windows] [--emit-map]       (re)construit la machine virtuelle
#   alexc dump prog.albc                               désassemblage
#   alexc bundle [-o sortie] [--vm alexvm] [--exe alexc]   alexc portable : SDK (stdlib, runtime, templates, VM)
#                                                      embarqué, utilisable seul (commands.bundle)
#   alexc version [--short | --json] | --version
#
# Machine virtuelle : $ALEX_VM, sinon alexvm dans le dossier d'alexc.
use io
use os
use string as _s
from collections use append
use commands.common as cc
use parser as bp
use bytecode.compiler as bc
use bytecode.format as bf
use resolver as bm
use native.build as nn
use native.ir as nir
use commands.fmt as cmd_fmt
use commands.new as cmd_new
use commands.test as cmd_test
use commands.doc as cmd_doc
use commands.pkg as cmd_pkg
use commands.repl as cmd_repl
use commands.debug as cmd_debug
use commands.lsp as cmd_lsp
use commands.bundle as sdk

const USAGE := "usage: alex <commande> [arguments]\n  build     compile (.albc, --standalone, --native)      run      compile et exécute\n  check     vérifie sans exécuter                          debug    débogueur\n  test      lance les tests                                fmt      formate le code\n  doc       documentation                                  new      nouveau projet\n  pkg       gestionnaire de paquets                        repl     boucle interactive\n  lsp       serveur de langage                             edit     éditeur en terminal\n  version   version du compilateur\n  (outils de la chaîne : native, compile, vm, dump, bundle — voir docs/SELFHOST.md)\n"

func semver():
    return os.alex_build()["version"]

func beta_suffix():
    return " (bêta)" if os.alex_build()["channel"] == "beta" else ""

func ends_al(p):
    return cc.ends_with(p, ".al") and len(p) > 3

func _bi(b, k):
    return b[k] if k in b else ""

# alex version [--short | --full | --json | --channel | --check CONTRAINTE | fichier.albc]
func cmd_version(args):
    b := os.alex_build()
    if len(args) == 0:
        stable := b["channel"] == "stable"
        print("alex " + b["version"] + (" (stable)" if stable else " (bêta)"))
        print("  canal       " + b["channel"] + ("" if stable else " — version de test, ne pas utiliser en production"))
        print("  build       " + str(b["build"]) + ("" if b["date"] == "" else ", " + b["date"]))
        print("  empreinte   " + b["source_id"] + ("" if b["commit"] == "" else " (commit " + b["commit"] + ")"))
        if _bi(b, "compiler") != "":
            print("  compilé par " + b["compiler"])
        # plateforme d'exécution ; « host » est celle où alexc a été construit (alexc Windows construit sous WSL)
        print("  plateforme  " + os.platform() + "-" + os.arch())
        if _bi(b, "host") != "" and b["host"] != os.platform() + "-" + os.arch():
            print("  construit   sur " + b["host"])
        print("  bytecode    ALBC " + str(bf.SUPPORTED_VERSION_MAJOR) + "." + str(bf.CURRENT_VERSION_MINOR) + " (lit 0.1 à 0." + str(bf.CURRENT_VERSION_MINOR) + ")")
        print("  vm          " + cc.vm_path())
        return 0
    a := args[0]
    if a == "--short":
        print(b["version"])
        return 0
    if a == "--full":
        print(b["full"])
        return 0
    if a == "--channel":
        print(b["channel"])
        return 0
    if a == "--json":
        print("{\"version\": " + cc.json_string(b["version"]) + ", \"full\": " + cc.json_string(b["full"]) +
              ", \"base\": " + cc.json_string(b["base"]) + ", \"major\": " + str(b["major"]) + ", \"minor\": " + str(b["minor"]) +
              ", \"patch\": " + str(b["patch"]) + ", \"channel\": " + cc.json_string(b["channel"]) + ", \"build\": " + str(b["build"]) +
              ", \"date\": " + cc.json_string(b["date"]) + ", \"source_id\": " + cc.json_string(b["source_id"]) +
              ", \"commit\": " + cc.json_string(b["commit"]) + ", \"compiler\": " + cc.json_string(_bi(b, "compiler")) +
              ", \"host\": " + cc.json_string(_bi(b, "host")) + ", \"bytecode\": \"" + str(bf.SUPPORTED_VERSION_MAJOR) + "." + str(bf.CURRENT_VERSION_MINOR) + "\"}")
        return 0
    if a == "--check":
        if len(args) < 2:
            cc.err("usage: alex version --check \">=1.2.0\"\n")
            return 2
        ok := false
        try:
            ok = os.alex_satisfies(args[1])
        catch e:
            cc.err("erreur: contrainte de version invalide : « " + args[1] + " »\n")
            return 2
        if not ok:
            cc.err("alex " + b["version"] + " ne satisfait pas " + args[1] + "\n")
        return 0 if ok else 1
    if len(a) > 0 and a[0] == '-':
        cc.err("option inconnue : " + a + "\nusage: alex version [--short|--full|--json|--channel|--check C|fichier.albc]\n")
        return 2
    bytes := io.read_bytes(a)
    if len(bytes) >= 8 and bytes[0] == 65 and bytes[1] == 76 and bytes[2] == 66 and bytes[3] == 67:
        major := bytes[4] | (bytes[5] << 8)
        minor := bytes[6] | (bytes[7] << 8)
        print(a)
        print("  format      ALBC " + str(major) + "." + str(minor))
        if major != bf.SUPPORTED_VERSION_MAJOR or minor > bf.CURRENT_VERSION_MINOR:
            print("  compatible  non (ce runtime lit le format " + str(bf.SUPPORTED_VERSION_MAJOR) + ".1 à " + str(bf.SUPPORTED_VERSION_MAJOR) + "." + str(bf.CURRENT_VERSION_MINOR) + ")")
            return 1
        m := bf.read_module(bytes)
        print("  compilé par " + ("(inconnu : format antérieur à 0.4)" if m.producer == "" else m.producer))
        if minor >= 4:
            print("  canal       " + ("beta" if (m.flags & bf.FLAG_BETA) != 0 else "stable"))
        print("  compatible  oui (runtime alex " + b["version"] + ")")
        return 0
    cc.err("erreur: '" + a + "' n'est ni un fichier .albc ni un exécutable ALEX autonome\n")
    return 1

const BUILD_USAGE := "usage: alexc build fichier.al [-o sortie.albc]\n       alexc build fichier.al --standalone [-o exécutable] [--runtime binaire-alexvm]\n       alexc build fichier.al --native [-o exécutable] [--emit-ir]\n       alexc build noyau.al --native --freestanding [-o noyau.bin]   (image multiboot, sans OS)\n       alexc build app.al --native --uefi [-o app.efi]               (application UEFI, PE32+)\n       alexc build app.al --native --alexos [-o app.aex]             (exécutable AEX d'Alex OS ; alexc vm --alexos : sa VM)\n       alexc build app.al --native --windows [-o app.exe]            (exécutable Windows x64, PE32+)\n       alexc build app.al --native --windows --gui [-o app.exe]      (application graphique Windows, sans console)\n       alexc build app.al --native --arm64 [--windows [--gui]]   (Linux ou Windows ARM64)\n       (cible de --native par défaut : le système hôte — sous Windows, un exécutable Windows ; --linux : Linux)\n       (--target SYSTÈME-ARCH : cible de --native ; SYSTÈME : linux, windows, uefi, none (sans OS) ;\n        ARCH : x86_64, aarch64 (ou arm64 ; uefi et none : x86_64 seulement). --arm64 choisit aarch64\n        et se combine avec --windows et --gui : --windows --arm64 = --target windows-aarch64)\n       (--native : --emit-map écrit aussi SORTIE.map, adresses et noms des fonctions)\n       (--windows : --icon FICHIER.ico donne une icône à l'exécutable)\n       (--native compile tout programme : sous-ensemble statique typé si possible, sinon mode dynamique\n        — le bytecode de la VM traduit en code machine ; --dynamic l'impose, --static l'interdit)\n"

# Options communes de build / native / compile / vm.
class Opts:
    func init():
        self.src = ""
        self.out = ""
        self.stdlib = null
        self.qualifier = ""
        self.source = ""
        self.typecheck = true
        self.emit_ir = false      # --emit-ir : forme courte de l'IR sur la sortie standard
        self.emit_ir_file = ""    # --emit-ir FICHIER : IR complet dans un fichier (outil de mise au point)
        self.native = false
        self.mode = "auto"
        self.windows = false
        self.gui = false
        self.uefi = false
        self.freestanding = false
        self.a64 = false
        self.standalone = false
        self.runtime = ""
        self.emit_map = false
        self.image_base = 0       # --image-base ADRESSE : ELF statique x86-64 chargé ailleurs qu'à 1 Gio (émulateurs de test)
        self.alexos = false       # --alexos : exécutable AEX d'Alex OS
        self.icon = ""            # --icon FICHIER.ico : icône de l'exécutable Windows (alex vm --windows : logo d'ALEX)
        self.cible = false        # cible choisie explicitement (--target, --linux) : pas de cible par défaut de l'hôte

func _is_arch(t):
    return t in ["x86_64", "x64", "amd64", "aarch64", "arm64"]

# SYSTÈME-ARCH, ARCH-SYSTÈME, SYSTÈME seul (x86_64) ou ARCH seule (Linux).
func _target(o, t):
    sys := ""
    arch := ""
    dash := _s.find(t, "-")
    if dash < 0:
        if _is_arch(t):
            arch = t
        else:
            sys = t
    elif _is_arch(t[0:dash]):
        arch = t[0:dash]
        sys = t[dash + 1:len(t)]
    else:
        sys = t[0:dash]
        arch = t[dash + 1:len(t)]
    if sys == "":
        sys = "linux"
    if arch == "":
        arch = "x86_64"
    if not (sys in ["linux", "windows", "uefi", "none", "freestanding"]) or not _is_arch(arch):
        cc.err("cible inconnue : " + t + " (linux, windows, uefi, none ; x86_64, aarch64 : linux-aarch64, windows-arm64, uefi-aarch64...)\n" + BUILD_USAGE)
        return false
    o.native = true
    o.cible = true
    o.a64 = arch == "aarch64" or arch == "arm64"
    o.windows = sys == "windows"
    o.uefi = sys == "uefi"
    o.freestanding = sys == "none" or sys == "freestanding"
    return true

func _parse_int(t):
    v := 0
    if _s.starts_with(t, "0x") or _s.starts_with(t, "0X"):
        for b in _s.byte_unpack(_s.lower(t[2:len(t)])):
            v = v * 16 + (b - 48 if b < 58 else b - 87)
        return v
    return int(t)

func parse_opts(args, o):
    i := 0
    while i < len(args):
        a := args[i]
        if a == "-o" and i + 1 < len(args):
            i += 1
            o.out = args[i]
        elif a == "--stdlib" and i + 1 < len(args):
            i += 1
            o.stdlib = args[i]
        elif a == "--qualifier" and i + 1 < len(args):
            i += 1
            o.qualifier = args[i]
        elif a == "--source" and i + 1 < len(args):
            i += 1
            o.source = args[i]
        elif a == "--emit-ir":
            nx := args[i + 1] if i + 1 < len(args) else ""
            if nx != "" and nx[0] != '-' and not ends_al(nx) and not cc.ends_with(nx, ".albc"):
                i += 1
                o.emit_ir_file = nx
            else:
                o.emit_ir = true
        elif a == "--native":
            o.native = true
        elif a == "--standalone":
            o.standalone = true
        elif a == "--runtime" and i + 1 < len(args):
            i += 1
            o.runtime = args[i]
        elif a == "--static" or a == "--dynamic":
            o.native = true
            o.mode = "static" if a == "--static" else "dynamic"
        elif a == "--windows":
            o.windows = true
            o.native = true
        elif a == "--linux":
            o.native = true
            o.cible = true
        elif a == "--gui":
            o.windows = true
            o.gui = true
            o.native = true
        elif a == "--uefi":
            o.native = true
            o.uefi = true
        elif a == "--freestanding":
            o.freestanding = true
        elif a == "--alexos" or a == "--aex":
            o.alexos = true
            o.native = true
        elif a == "--arm64" or a == "--aarch64":
            o.a64 = true
            o.native = true
        elif a == "--target" and i + 1 < len(args):
            i += 1
            if not _target(o, args[i]):
                return false
        elif a == "--emit-map":
            o.emit_map = true
        elif a == "--image-base" and i + 1 < len(args):
            i += 1
            o.image_base = _parse_int(args[i])
        elif a == "--icon" and i + 1 < len(args):
            i += 1
            o.icon = args[i]
        elif a == "--no-typecheck":
            o.typecheck = false
        elif len(a) > 0 and a[0] == '-':
            cc.err("option inconnue : " + a + "\n" + BUILD_USAGE)
            return false
        elif o.src == "":
            o.src = a
        else:
            cc.err("argument en trop : " + a + "\n" + BUILD_USAGE)
            return false
        i += 1
    return true

# Icône des prochains exécutables Windows (fichier .ico) ; faux, message affiché, si elle est illisible.
func load_icon(path):
    try:
        nn.set_windows_icon(io.read_bytes(path))
        return true
    catch e:
        cc.err("erreur: icône illisible : " + path + "\n")
        return false

func build_native(o):
    src := o.src
    stem := src[0:len(src) - 3] if ends_al(src) else src
    if o.standalone:
        cc.err("--native et --standalone sont exclusifs\n")
        return 1
    # Cible par défaut : le système hôte. Sous Windows, sans cible explicite, un exécutable Windows (PE32+) ;
    # --linux ou --target linux-... produisent un exécutable Linux depuis Windows.
    if os.platform() == "windows" and not (o.cible or o.windows or o.uefi or o.freestanding or o.alexos):
        o.windows = true
    if o.uefi and o.freestanding:
        cc.err("--uefi et --freestanding sont exclusifs (une application UEFI n'est pas une image multiboot)\n")
        return 1
    if o.windows and (o.uefi or o.freestanding):
        cc.err("--windows est exclusif de --uefi et --freestanding\n")
        return 1
    if o.alexos and (o.windows or o.uefi or o.freestanding or o.a64):
        cc.err("--alexos est exclusif de --windows, --uefi, --freestanding et --arm64\n")
        return 1
    if o.alexos:
        nn.set_alexos(true)
    if o.out == "":
        o.out = stem + ".aex" if o.alexos else stem + ".efi" if o.uefi else stem + ".bin" if o.freestanding else stem + ".exe" if o.windows else stem
    if o.out == src:
        cc.err("erreur: la sortie écraserait le fichier source ; précisez -o\n")
        return 1
    if o.icon != "":
        if not o.windows:
            cc.err("erreur: --icon est réservé aux exécutables Windows (--windows)\n")
            return 1
        if not load_icon(o.icon):
            return 1
    m := o.mode
    p := null
    try:
        if m == "static" or o.uefi or o.freestanding:
            p = nn.build(src, o.out, o.stdlib, o.emit_map, o.windows, o.gui, o.uefi, o.freestanding, o.a64, o.image_base)
            m = "static"
        elif m == "dynamic":
            p = nn.build_dynamic(src, o.out, o.stdlib, o.emit_map, o.windows, o.gui, o.a64)
        else:
            if o.emit_ir or o.emit_ir_file != "":
                try:
                    p = nn.build(src, o.out, o.stdlib, o.emit_map, o.windows, o.gui, false, false, o.a64)
                    m = "static"
                catch e:
                    p = nn.build_dynamic(src, o.out, o.stdlib, o.emit_map, o.windows, o.gui, o.a64)
                    m = "dynamic"
            else:
                m = nn.build_auto(src, o.out, o.stdlib, o.windows, o.gui, false, false, o.a64, o.emit_map)
    catch RuntimeError as e:
        # limites du générateur natif (std::runtime_error du compilateur de référence) : « erreur: »
        cc.flush()
        cc.err("erreur: " + e.message + "\n")
        return 1
    if o.emit_ir_file != "" and p != null:
        io.write_file(o.emit_ir_file, nir.dump_full(p))
    if o.emit_ir and p != null:
        cc.out(nir.dump_ir(p))
    what := ""
    if o.a64:
        what = "Application UEFI ARM64 écrite : " if o.uefi else "Image ARM64 sans OS écrite : " if o.freestanding else "Exécutable Windows ARM64 écrit : " if o.windows else "Exécutable ARM64 (Linux) écrit : "
    else:
        what = "Application UEFI écrite : " if o.uefi else "Image multiboot écrite : " if o.freestanding else "Exécutable Windows écrit : " if o.windows else "Exécutable natif écrit : "
    cc.flush()
    cc.err(what + o.out + (" (mode dynamique)" if m == "dynamique" or m == "dynamic" else "") + "\n")
    return 0

# Taille du runtime d'un exécutable : sans le bytecode embarqué s'il y en a un (remorque ALEXAPP1).
func _runtime_bytes(path):
    b := io.read_bytes(path)
    n := len(b)
    if n >= 16 and _s.byte_pack(b[n - 8:n]) == "ALEXAPP1":
        size := 0
        i := 7
        while i >= 0:
            size = (size << 8) | b[n - 16 + i]
            i -= 1
        if size == 0 or size > n - 16:
            raise("RuntimeError", "exécutable autonome corrompu : taille de bytecode embarqué invalide")
        return b[0:n - 16 - size]
    return b

# alexc build --standalone : la machine virtuelle (alexvm, ou --runtime : un autre alexvm, par exemple alexvm.exe
# pour Windows, ou un exécutable autonome dont le bytecode est remplacé) suivie du bytecode du programme.
func build_standalone(o):
    src := o.src
    stem := src[0:len(src) - 3] if ends_al(src) else src
    rt := o.runtime if o.runtime != "" else cc.vm_path()
    if not os.isfile(rt):
        cc.err("erreur: machine virtuelle introuvable : " + rt + " ; précisez --runtime <chemin>\n")
        return 1
    if o.out == "":
        o.out = stem + (".exe" if cc.ends_with(rt, ".exe") else "")
    if o.out == src:
        cc.err("erreur: la sortie écraserait le fichier source ; précisez -o\n")
        return 1
    cmd_pkg.check_project_requirement()
    bc_bytes := bf.write_module(bm.build_program(src, o.stdlib, o.typecheck))
    base := _runtime_bytes(rt)
    out := [b for b in base]
    for b in bc_bytes:
        append(out, b)
    n := len(bc_bytes)
    i := 0
    while i < 8:
        append(out, (n >> (8 * i)) & 0xFF)
        i += 1
    for c in _s.byte_unpack("ALEXAPP1"):
        append(out, c)
    io.write_bytes(o.out, out)
    try:
        os.chmod(o.out, 0o755)
    catch e:
        pass_ := 0
    cc.err("Exécutable autonome écrit : " + o.out + " (runtime " + str(len(base)) + " octets + bytecode " + str(n) + " octets)\n")
    return 0

func cmd_build(args, force_native):
    o := Opts()
    if not parse_opts(args, o):
        return 1
    if o.src == "":
        cc.err(BUILD_USAGE)
        return 1
    if o.runtime != "" and not o.standalone:
        cc.err("--runtime n'a de sens qu'avec --standalone\n")
        return 1
    if o.freestanding and not o.native and not force_native:
        cc.err("--freestanding s'utilise avec --native\n")
        return 1
    if force_native or o.native:
        return build_native(o)
    if o.standalone:
        return build_standalone(o)
    cmd_pkg.check_project_requirement()
    if o.out == "":
        o.out = o.src[0:len(o.src) - 3] + ".albc" if ends_al(o.src) else o.src + ".albc"
    bytes := bf.write_module(bm.build_program(o.src, o.stdlib, o.typecheck))
    io.write_bytes(o.out, bytes)
    cc.err("Écrit " + str(len(bytes)) + " octets dans " + o.out + "\n")
    return 0

func cmd_compile(args):
    o := Opts()
    if not parse_opts(args, o) or o.src == "":
        cc.err("usage: alex compile fichier.al -o sortie.albc [--qualifier Q] [--source CHEMIN]\n")
        return 1
    if o.out == "":
        o.out = o.src + "bc" if ends_al(o.src) else o.src + ".albc"
    opts := bc.CompileOptions()
    opts.self_qualifier = o.qualifier
    opts.source_path = o.source
    io.write_bytes(o.out, bf.write_module(bc.compile(bp.parse_file(o.src), opts)))
    return 0

func cmd_check(args):
    if len(args) < 1:
        cc.err("usage: alexc check fichier.al\n")
        return 1
    cmd_pkg.check_project_requirement()
    bm.build_program(args[0])
    cc.err("OK : " + args[0] + "\n")
    return 0

func cmd_vm(args):
    o := Opts()
    if not parse_opts(args, o):
        return 1
    if o.alexos:
        nn.set_alexos(true)
    if o.out == "":
        o.out = "alexvm.exe" if o.windows else "alexvm.aex" if o.alexos else "alexvm"
    if o.windows:
        # la VM porte le logo d'ALEX (runtime/alex/windows/alex.ico), sauf --icon
        if o.icon != "":
            if not load_icon(o.icon):
                return 1
        else:
            nn.set_windows_icon(nn.alex_icon(o.stdlib))
    nn.build_vm(o.out, o.stdlib, o.windows, o.emit_map)
    print("Machine virtuelle écrite : " + o.out)
    return 0

# alexc bundle : copie d'alexc (ou de --exe) suivie du SDK courant (dossier de la stdlib et ses voisins runtime/,
# templates/) et de la VM (--vm, défaut : celle d'alexc ; --vm "" : sans VM).
func cmd_bundle(args, stdlib):
    exe := cc.self_path()
    vm := cc.vm_path()
    out := ""
    i := 0
    while i < len(args):
        a := args[i]
        if (a == "-o" or a == "--vm" or a == "--exe") and i + 1 < len(args):
            if a == "-o":
                out = args[i + 1]
            elif a == "--vm":
                vm = args[i + 1]
            else:
                exe = args[i + 1]
            i += 2
            continue
        cc.err("usage: alexc bundle [-o sortie] [--vm alexvm] [--exe alexc]\n")
        return 1
    if out == "":
        out = "alexc-portable.exe" if os.platform() == "windows" else "alexc-portable"
    if vm != "" and not os.isfile(vm):
        cc.err("machine virtuelle introuvable : " + vm + " (--vm, ou --vm \"\" pour un SDK sans VM)\n")
        return 1
    root := os.dirname(os.absolute(stdlib))
    r := sdk.pack(exe, root, vm, out)
    print("alexc portable écrit : " + out + " (" + str(r[0]) + " fichiers, " + str(r[1] // 1024) + " Kio de SDK)")
    return 0

func cmd_dump(args):
    if len(args) < 1:
        cc.err("usage: alex dump fichier.albc\n")
        return 1
    print(bf.dump(bf.read_module(io.read_bytes(args[0]))))
    return 0

# Point d'entrée déclaré dans alex.toml (`entry`, défaut main.al), "" sans manifeste ou si le fichier manque.
func manifest_entry():
    if not os.isfile("alex.toml"):
        return ""
    entry := "main.al"
    try:
        m := cmd_pkg.parse_manifest(io.read_file("alex.toml"), "alex.toml")
        if m["entry"] != "":
            entry = m["entry"]
    catch e:
        pass
    return entry if os.isfile(entry) else ""

# Compile `path` (sauf .albc) puis l'exécute sur alexvm ; renvoie le code de sortie.
func run_program(path, prog_args, opts, entry_append, quiet):
    albc := path
    tmp := ""
    if not cc.ends_with(path, ".albc"):
        cmd_pkg.check_project_requirement()
        tmp = os.join(os.tmp_dir(), "alexc-run-" + str(os.pid()) + ".albc")
        io.write_bytes(tmp, bf.write_module(bm.build_program(path, null, true, entry_append)))
        albc = tmp
    vm := cc.vm_path()
    if not os.isfile(vm):
        if tmp != "":
            os.remove(tmp)
        cc.err("machine virtuelle introuvable : " + vm + " (ALEX_VM, ou `alex vm -o " + vm + "`)\n")
        return 1
    # la VM meurt avec alexc (arrêt par un IDE, délai dépassé) et efface elle-même le .albc temporaire
    vargs := ["--parent", str(os.pid()), "--script", path]
    if tmp != "":
        append(vargs, "--delete")
    for o in opts:
        append(vargs, o)
    append(vargs, albc)
    for a in prog_args:
        append(vargs, a)
    os.setenv("ALEX_EXE", cc.self_path())
    if quiet:
        os.setenv("ALEX_QUIET_RUN", "1")
    cc.flush()
    code := os.wait(os.spawn(vm, vargs))
    if tmp != "" and os.exists(tmp):
        os.remove(tmp)
    return code

func cmd_run(all_args):
    opts := []
    first := 0
    while first < len(all_args) and _s.starts_with(all_args[first], "--profile"):
        append(opts, all_args[first])
        first += 1
    args := all_args[first:len(all_args)]
    # projet alex.toml : `alexc run` ou `alexc run -- arguments...` lance le point d'entrée
    if len(args) < 1 or args[0] == "--":
        entry := manifest_entry()
        if entry != "":
            args = [entry] + args
    if len(args) < 1 or args[0] == "--":
        cc.err("usage: alexc run fichier.al|fichier.albc [--] [arguments...]  (ou, dans un projet avec alex.toml : alexc run [-- arguments...])\n")
        return 1
    # `alexc run prog.al -- --help` : « -- » sépare les options d'alex de celles du programme, qui ne le reçoit pas
    rest := args[1:len(args)]
    if len(rest) > 0 and rest[0] == "--":
        rest = rest[1:len(rest)]
    return run_program(args[0], rest, opts, "", false)

# Processus fils de `alexc test` : exécute un fichier de test et ses fonctions test_*.
func cmd_test_file(args):
    file := args[0]
    filter := args[1] if len(args) >= 2 else ""
    d := cmd_test.discover(file)
    extra := ""
    if d["has_functions"] and not d["self_running"]:
        extra = cmd_test.epilogue(d["tests"], filter, d["has_async"])
    return run_program(file, [], [], extra, true)

func main():
    stdlib := cc.stdlib_root()
    # Chaîne d'outils des programmes lancés ou compilés par alexc (sous-processus, exécutables natifs) : ALEX_EXE
    # s'il désigne un fichier existant (fixé par l'environnement, ou chemin d'origine embarqué dans alexc), sinon
    # alexc lui-même (installation déplacée ; pas sous une VM).
    me := cc.self_path()
    cur := os.getenv("ALEX_EXE")
    keep := cur != null and cur != "" and os.isfile(cur)
    if not keep and me != "" and os.stem(me) != "alexvm":
        os.setenv("ALEX_EXE", me)
    argv := os.args()
    if len(argv) < 1:
        cc.err(USAGE + "\nalex " + semver() + beta_suffix() + "\n")
        return 1
    cmd := argv[0]
    rest := argv[1:len(argv)]
    if cmd == "--version" or cmd == "-V":
        return cmd_version(rest)
    if cmd == "version":
        return cmd_version(rest)
    if cmd == "help" or cmd == "--help" or cmd == "-h":
        print(USAGE + "\nalex " + semver() + beta_suffix() + " — `alex <commande>` sans argument affiche son usage")
        return 0
    if cmd == "run":
        return cmd_run(rest)
    if cmd == "build":
        return cmd_build(rest, false)
    if cmd == "native":
        return cmd_build(rest, true)
    if cmd == "compile":
        return cmd_compile(rest)
    if cmd == "check":
        return cmd_check(rest)
    if cmd == "vm":
        return cmd_vm(rest)
    if cmd == "dump":
        return cmd_dump(rest)
    if cmd == "bundle":
        return cmd_bundle(rest, stdlib)
    if cmd == "fmt":
        return cmd_fmt.run(rest)
    if cmd == "new":
        return cmd_new.run(rest, os.join(os.dirname(stdlib), "templates") if os.dirname(stdlib) != "." else "templates")
    if cmd == "doc":
        return cmd_doc.run(rest, stdlib)
    if cmd == "test":
        return cmd_test.run(rest, cc.self_path())
    if cmd == "__test-file" and len(rest) >= 1:
        return cmd_test_file(rest)
    if cmd == "pkg":
        return cmd_pkg.run(rest)
    if cmd == "repl":
        return cmd_repl.run()
    if cmd == "edit":
        # éditeur de code (stdlib/outils/editeur.al) : alex edit [--gui] [fichier...]
        return run_program(os.join(stdlib, "outils/editeur.al"), rest, [], "", true)
    if cmd == "debug":
        return cmd_debug.run(rest, stdlib)
    if cmd == "lsp":
        return cmd_lsp.run(rest, stdlib)
    if cmd == "studio":
        cc.err("ALEX Studio est distribué à part : lancez « alex-studio [dossier | fichier.al] »\n")
        return 1
    cc.err("commande inconnue: " + cmd + "\n")
    return 1

code := 0
try:
    code = main()
catch e:
    # même forme que l'alex de référence : « TypeErreur: fichier:ligne:colonne: message »
    cc.flush()
    cc.err(str(e) + "\n")
    code = 1
cc.flush()
if code != 0:
    os.exit(code)
