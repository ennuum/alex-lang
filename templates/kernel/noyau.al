# {{nom}} — noyau démarrable sans système d'exploitation.
#   alexc build --native --freestanding noyau.al -o {{nom}}.bin
#   qemu-system-x86_64 -kernel {{nom}}.bin -serial stdio -device isa-debug-exit,iobase=0xf4,iosize=0x04
# La logique pure (texte.al) se teste dans la VM : alexc test
use hw
use texte

const VGA := 753664 # 0xB8000 : écran texte 80 x 25

func ecran(ligne: int, s: str, attr: int):
    i := 0
    for c in s:
        hw.poke16(VGA + 2 * (ligne * 80 + i), texte.code(c) + (attr << 8))
        i += 1

func main():
    i := 0
    while i < 80 * 25:
        hw.poke16(VGA + 2 * i, 32 + (15 << 8))
        i += 1
    ecran(0, texte.titre("{{Nom}}"), 31)
    ecran(2, "Noyau ALEX demarre.", 10)
    print("{{Nom}} : noyau démarré") # print écrit sur le port série dans un noyau
    print(texte.titre("{{Nom}}"))
    hw.exit(0) # isa-debug-exit : arrête QEMU

main()
