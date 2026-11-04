# {{nom}} — point d'entrée.
#   alexc run            (ou : alexc run main.al)
#   alexc test           tests unitaires (dossier tests/)
use salutations

func main():
    print(salutations.bonjour("monde"))
    print(salutations.resume([3, 1, 4, 1, 5]))

main()
