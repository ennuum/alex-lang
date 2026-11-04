# Démonstration (et test, QEMU -smp 4) : plusieurs processus isolés en même temps, répartis sur les cœurs.
# - six exemplaires de CALCUL.ELF tournent ensemble : mêmes adresses virtuelles, espaces d'adressage séparés,
#   chacun trouve son propre résultat ; préemption par la minuterie APIC de chaque cœur ;
# - des exécutables construits ici même tentent des accès interdits : seul le fautif s'arrête.
use hw
use tasks
use disque
use fat
use smp
use processus
from processus use Process
from collections use append
from core use len
from string use strip

print("disque :", disque.init() > 0)
fat.mount()
print("cœurs :", smp.start(100)) # minuterie APIC (préemption) sur chaque cœur

outputs: dict[int, str] := {}
func collector(k: int) -> func(str):
    func add(s: str):
        outputs[k] = outputs[k] + s
    return add

func no_input() -> str:
    return ""

ps: list[Process] := []
k := 0
for g in [11, 22, 33, 44, 55, 66]:
    outputs[k] = ""
    append(ps, processus.spawn("CALCUL.ELF", ["1500000", str(g)], collector(k), no_input))
    k += 1
print("processus lancés ensemble :", len(processus.running()))
cpus: dict[int, bool] := {}
spaces: dict[int, bool] := {}
for i in 0..len(ps):
    code := processus.wait(ps[i])
    print(f"[{ps[i].pid}] code {code}, {strip(outputs[i])}")
    for c in ps[i].cpus:
        cpus[c] = true
print("exécutés sur plusieurs cœurs :", len(cpus) > 1)
print("processus restants :", len(processus.running()))

# ---- Exécutables minimaux (ELF64, un segment chargé en 0x40000000, code à l'octet 120) ----
func image(code: list[int]) -> str:
    total := 120 + len(code)
    buf := hw.alloc_pages(1)
    hw.poke32(buf, 1179403647)        # \x7fELF
    hw.poke8(buf + 4, 2)              # 64 bits
    hw.poke8(buf + 5, 1)              # petit-boutiste
    hw.poke8(buf + 6, 1)
    hw.poke16(buf + 16, 2)            # exécutable
    hw.poke16(buf + 18, 62)           # x86-64
    hw.poke32(buf + 20, 1)
    hw.poke64(buf + 24, 1073741824 + 120) # point d'entrée
    hw.poke64(buf + 32, 64)           # en-têtes de programme
    hw.poke16(buf + 52, 64)
    hw.poke16(buf + 54, 56)
    hw.poke16(buf + 56, 1)
    hw.poke32(buf + 64, 1)            # PT_LOAD
    hw.poke32(buf + 68, 7)
    hw.poke64(buf + 80, 1073741824)
    hw.poke64(buf + 88, 1073741824)
    hw.poke64(buf + 96, total)
    hw.poke64(buf + 104, total)
    hw.poke64(buf + 112, 4096)
    i := 0
    for b in code:
        hw.poke8(buf + 120 + i, b)
        i += 1
    s := hw.string_at(buf, total)
    hw.free_pages(buf, 1)
    return s

exit0: list[int] := [184, 60, 0, 0, 0, 49, 255, 15, 5] # mov eax, 60 ; xor edi, edi ; syscall
tests: list[tuple[str, list[int]]] := []
append(tests, ("LIT_NOYAU", [72, 139, 4, 37, 0, 0, 16, 0]))  # mov rax, [0x100000] : mémoire du noyau
append(tests, ("CLI", [250]))                                 # cli : instruction privilégiée
append(tests, ("UD2", [15, 11]))                              # instruction invalide
append(tests, ("DIV0", [49, 192, 49, 201, 72, 247, 241]))     # xor eax, eax ; xor ecx, ecx ; div rcx
# mov qword [0x40000800], 42 ; mov rdi, [0x40000800] ; mov eax, 60 ; syscall : sa propre page, code 42
append(tests, ("SA_PAGE", [72, 199, 4, 37, 0, 8, 0, 64, 42, 0, 0, 0, 72, 139, 60, 37, 0, 8, 0, 64, 184, 60, 0, 0, 0, 15, 5]))
for t in tests:
    code: list[int] := []
    for b in t[1]:
        append(code, b)
    for b in exit0:
        append(code, b)
    outputs[k] = ""
    p := processus.spawn_image(t[0], image(code), [], collector(k), no_input)
    rc := processus.wait(p)
    print(f"{t[0]} : code {rc} {strip(outputs[k])}")
    k += 1
print("le noyau continue :", hw.cpus() > 0)
hw.exit(0)
