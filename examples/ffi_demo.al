# Démo du module ffi : appeler la libc et la libm.
use ffi

libm := ffi.Library("m")
cos := libm.function("cos", ["f64"], "f64")
print("cos(0) =", cos.call([0.0]))

libc := ffi.Library(null)             # symboles déjà présents dans ALEX
strlen := libc.function("strlen", ["cstr"], "size_t")
print("strlen('héllo') =", strlen.call(["héllo"]))   # 6 : octets UTF-8

# Paramètre de sortie : strtol écrit dans `fin` l'adresse du premier
# caractère non converti.
texte := ffi.cstring("1234xyz")
fin := ffi.Buffer(8)
strtol := libc.function("strtol", ["ptr", "ptr", "i32"], "i64")
n := strtol.call([texte.address(), fin.address(), 10])
print("valeur =", n, " octets consommés =", fin.read("ptr") - texte.address())

texte.free()
fin.free()
libm.close()
