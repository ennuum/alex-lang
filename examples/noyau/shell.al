# Alex OS : petit interpréteur de commandes sans système d'exploitation. Clavier PS/2 et minuterie par
# interruptions, tâches préemptées par la minuterie, bus PCI, écran VGA, disque ATA ou virtio (bloc.al).
#
#   alexc build --native --freestanding examples/noyau/shell.al -o shell.bin
#   qemu-system-x86_64 -kernel shell.bin -serial stdio -device isa-debug-exit,iobase=0xf4,iosize=0x04
use hw
use tasks
use ecran
use clavier
use bus_pci as pci
use bloc
use fat
use processus
from collections use append
from core use len
from string use split, trim

screen := ecran.Screen()
ticks := 0

# Minuterie (100 Hz) : horloge et préemption des tâches.
func timer(code: int):
    ticks += 1
    hw.eoi(0)
    tasks.yield_now()

func read_line() -> str:
    cs: list[char] := []
    while true:
        c := clavier.read_char()
        if c == '\n':
            screen.put('\n')
            break
        if c == clavier.BACKSPACE:
            if len(cs) > 0:
                cs = [cs[i] for i in 0..len(cs) - 1]
                screen.back()
            continue
        append(cs, c)
        screen.put(c)
    s := ""
    for c in cs:
        s += str(c)
    return s

results: list[int] := [0, 0, 0]
finished := 0

func worker(k: int):
    s := 0
    for i in 0..300000: # aucun yield : seule la minuterie partage le processeur
        s += i * (k + 1)
    results[k] = s
    hw.disable()
    finished += 1
    hw.enable()

func help():
    screen.line("commandes : aide, pci, mem, taches, temps, ls, cd, pwd, mkdir, rmdir, taille, cat, ecrire, rm,")
    screen.line("            lancer, quitter (chemins relatifs au répertoire courant ; \"...\" pour les espaces)")

cwd := "" # répertoire courant (chemin normalisé, "" : la racine)

# Chemin du disque désigné par p depuis le répertoire courant.
func here(p: str) -> str:
    return processus.normalize(cwd, p)

# Mots de la ligne ; « "deux mots" » en forme un seul.
func parse(line: str) -> list[str]:
    out: list[str] := []
    cur := ""
    quoted := false
    started := false
    for c in line:
        if c == '"':
            quoted = not quoted
            started = true
        elif c == ' ' and not quoted:
            if started:
                append(out, cur)
            cur = ""
            started = false
        else:
            cur += str(c)
            started = true
    if started:
        append(out, cur)
    return out

# Sortie d'un programme utilisateur : écran et port série.
func user_out(s: str):
    screen.write(s)
    hw.console_write(s)

func arg(words: list[str], i: int) -> str:
    if i < len(words):
        return words[i]
    return ""

func rest(words: list[str], start: int) -> str:
    s := ""
    i := start
    while i < len(words):
        if i > start:
            s += " "
        s += words[i]
        i += 1
    return s

has_disk := false

hw.pic_init()
hw.on_interrupt(32, timer)
hw.timer_start(100)
hw.irq_enable(0)
clavier.init()
hw.enable()

screen.clear()
screen.line("Alex OS - interpréteur de commandes")
if bloc.init() > 0: # disque virtio s'il y en a un, sinon ATA
    try:
        fat.mount()
        has_disk = true
        via := ""
        if bloc.name() != "ATA":
            via = " (" + bloc.name() + ")"
        screen.line(f"disque FAT16 : {bloc.sectors() // 2048} Mio{via}")
    catch e:
        screen.line(f"disque illisible : {e.message}")
help()
running := true
while running:
    screen.write("/" + cwd + "> ")
    line := trim(read_line())
    print("> " + line)
    if line == "":
        continue
    words := parse(line)
    if len(words) == 0:
        continue
    match words[0]:
        "aide":
            help()
        "pci":
            for d in pci.scan():
                screen.line(f"  {d.bus}:{d.slot}.{d.fn}  {pci.hex4(d.vendor)}:{pci.hex4(d.device)}  {d.kind()}")
        "mem":
            screen.line(f"mémoire physique : {hw.memory_end() // 1048576} Mio")
        "taches":
            finished = 0
            for k in 0..3:
                tasks.spawn(() => worker(k))
            while finished < 3:
                hw.wait()
            screen.line(f"3 tâches préemptées terminées : {results}")
        "temps":
            screen.line(f"{ticks // 100} s depuis le démarrage")
        "ls":
            if has_disk:
                try:
                    for e in fat.list(here(arg(words, 1))):
                        if e.is_dir:
                            screen.line(f"  {e.name}/")
                        else:
                            screen.line(f"  {e.name}")
                catch e:
                    screen.line(f"{e.type} : {e.message}")
            else:
                screen.line("pas de disque")
        "pwd":
            screen.line("/" + cwd)
        "cd":
            target := here(arg(words, 1))
            if fat.is_dir(target):
                cwd = target
            else:
                screen.line("répertoire introuvable : " + arg(words, 1))
        "mkdir":
            try:
                fat.mkdir(here(arg(words, 1)))
                screen.line("créé")
            catch e:
                screen.line(f"{e.type} : {e.message}")
        "rmdir":
            try:
                fat.rmdir(here(arg(words, 1)))
                screen.line("supprimé")
            catch e:
                screen.line(f"{e.type} : {e.message}")
        "taille":
            try:
                e := fat.find(here(words[1]))
                if e == null:
                    screen.line("fichier introuvable : " + words[1])
                else:
                    screen.line(f"{e.name} : {e.size} octets")
            catch e:
                screen.line(f"{e.type} : {e.message}")
        "cat":
            try:
                screen.write(fat.read(here(words[1])))
                print(fat.read(here(words[1])))
            catch e:
                screen.line(f"{e.type} : {e.message}")
        "ecrire":
            try:
                fat.write(here(words[1]), rest(words, 2) + "\n")
                screen.line("écrit")
            catch e:
                screen.line(f"{e.type} : {e.message}")
        "rm":
            try:
                fat.remove(here(words[1]))
                screen.line("supprimé")
            catch e:
                screen.line(f"{e.type} : {e.message}")
        "lancer":
            try:
                args: list[str] := [words[i] for i in 2..len(words)]
                code := processus.run(here(words[1]), args, user_out, read_line, cwd)
                screen.line(f"[{words[1]} terminé, code {code}]")
            catch e:
                screen.line(f"{e.type} : {e.message}")
        "quitter":
            running = false
        _:
            screen.line("commande inconnue : " + words[0])
screen.line("au revoir")
hw.exit(0)
