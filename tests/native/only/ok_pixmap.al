# Module pixmap (dessin 2D logiciel) : propriétés vérifiables sans fichier de police ni écran.
use pixmap

p := pixmap.create(64, 48)
pixmap.clear(p, 0xFF102030)
print(str(pixmap.width(p)) + "x" + str(pixmap.height(p)) + " " + str(pixmap.get(p, 3, 3) == 0xFF102030))
pixmap.fill(p, 10, 10, 20, 10, 0xFF8366FF)
print(str(pixmap.get(p, 10, 10) == 0xFF8366FF) + " " + str(pixmap.get(p, 29, 19) == 0xFF8366FF) + " " + str(pixmap.get(p, 30, 19) == 0xFF102030))
# découpe : rien ne sort du rectangle
pixmap.set_clip(p, 0, 0, 8, 8)
pixmap.fill(p, 0, 0, 64, 48, 0xFFFF0000)
pixmap.reset_clip(p)
print(str(pixmap.get(p, 7, 7) == 0xFFFF0000) + " " + str(pixmap.get(p, 8, 8) == 0xFF102030))
# mélange alpha à moitié : milieu entre deux couleurs
q := pixmap.create(4, 4)
pixmap.clear(q, 0xFF000000)
pixmap.blend(q, 0, 0, 4, 4, 0x80FFFFFF)
g := pixmap.get(q, 1, 1) & 255
print(str(g >= 126 and g <= 130))
# rectangle arrondi : le coin est transparent à l'intérieur de l'arrondi, le centre plein
r := pixmap.create(40, 40)
pixmap.clear(r, 0xFF000000)
pixmap.fill_round(r, 0, 0, 40, 40, 12, 0xFFFFFFFF)
print(str(pixmap.get(r, 0, 0) & 255) + " " + str(pixmap.get(r, 20, 20) & 255))
# deux surfaces identiques ont la même somme de contrôle, une différente non
a := pixmap.create(16, 16)
b := pixmap.create(16, 16)
pixmap.clear(a, 0xFF336699)
pixmap.clear(b, 0xFF336699)
print(str(pixmap.checksum(a) == pixmap.checksum(b)))
pixmap.put(b, 5, 5, 0xFFFFFFFF)
print(str(pixmap.checksum(a) != pixmap.checksum(b)))
# copie
pixmap.blit(a, 0, 0, p, 10, 10, 8, 8)
print(str(pixmap.get(a, 0, 0) == 0xFF8366FF))
# PNG écrit puis supprimé
print(str(pixmap.save_png(p, "/tmp/alex_pixmap_test.png")))
pixmap.destroy(p)
