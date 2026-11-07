# ALEX - io.read_raw : octets d'un fichier rendus dans une str (sans liste d'entiers), comme read_bytes.
# Lancer depuis la racine : ./alex run tests/io/test_io_read_raw.al
use io
use string as s
from core use len

chemin := "/tmp/alex-test-read-raw.bin"
octets := [0, 1, 127, 128, 200, 255, 10, 13, 65, 195, 169]
io.write_bytes(chemin, octets)
tout := io.read_raw(chemin)
assert s.byte_len(tout) == len(octets)
assert s.byte_unpack(tout) == octets
assert s.byte_unpack(io.read_raw(chemin, 3, 4)) == [128, 200, 255, 10]
assert io.read_raw(chemin, 9, 100) == s.byte_pack([195, 169])
assert io.read_raw(chemin, 11, 5) == ""
erreur := null
try:
    io.read_raw("/tmp/alex-fichier-absent-xyz", 0, 4)
catch e:
    erreur = e.type
assert erreur != null
io.delete_file(chemin)
print("io.read_raw : OK")
