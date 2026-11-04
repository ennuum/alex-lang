use commandes
use testing
use io
use os

func test_statistiques():
    testing.assert_eq(commandes.statistiques("un deux\ntrois\n"), [2, 3, 14])

func test_vide():
    testing.assert_eq(commandes.statistiques(""), [0, 0, 0])

func test_compter_fichier():
    f := os.join(os.tmp_dir(), "{{nom}}_test_" + str(os.pid()) + ".txt")
    io.write_file(f, "un deux\r\ntrois\r\n") # fins de ligne Windows
    try:
        testing.assert_eq(commandes.compter(f), [2, 3, 14])
    finally:
        os.remove(f)
