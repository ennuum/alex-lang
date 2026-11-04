use geo.forme as forme
use json

func surface_totale(cercles):
    total := 0.0
    for c in cercles:
        total = total + c.aire()
    return total

func main():
    p := forme.point(3, 4)
    print(p.norme())
    c := forme.Cercle(0, 0, 2)
    print(c.aire())
    print(surface_totale([c]))

main()
