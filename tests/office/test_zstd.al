# ALEX - décompression Zstandard (office.compression, décodeur natif) comparée à libzstd.
# Fichiers produits par tests/office/data/zstd/mkzstd_ref.py.   ./alex run tests/office/test_zstd.al
use io
use ffi
use testing
from testing use assert_eq, assert_true
use office.compression as z

const DATA := "tests/office/data/zstd/"
# [cas, taille, crc32] : niveaux 1 / 3 / 7 / 19 / 22, somme de contrôle, sans taille annoncée, trame ignorable,
# plusieurs trames, plusieurs blocs, flux vide
const CASES := [["text19", 57798, 3258906502], ["text1", 57798, 3258906502], ["bin3", 30000, 712020666],
                ["bin22", 30000, 712020666], ["rle", 70000, 2714022324], ["multi", 9007, 3748093041],
                ["big", 300000, 2802201714], ["empty", 0, 0]]

func t_cases():
    for c in CASES:
        d := z.zstd_decompress(io.read_bytes(DATA + c[0] + ".zst"))
        assert_eq([c[0], len(d), z.crc32(d)], c)

testing.test("zstd : flux de libzstd (Huffman 1 / 4 flux, FSE, RLE, répétitions)", t_cases)

func t_auto():
    b := io.read_bytes(DATA + "text1.zst")
    assert_eq(z.detect(b), "zstd")
    assert_eq(len(z.decompress(b)), 57798)
    assert_eq(z.zstd_content_size(b), 57798)
    assert_eq(z.zstd_content_size(io.read_bytes(DATA + "rle.zst")), -1)

testing.test("zstd : détection automatique, taille annoncée", t_auto)

func t_buffer():
    b := io.read_bytes(DATA + "big.zst")
    src := ffi.Buffer(len(b))
    src.write_array("u8", b)
    out := z.zstd_decompress_buffer(src, 0, len(b), 300000)
    assert_eq(out.size(), 300000)
    assert_eq(out.read_array("u8", 4, 299996), [(299996 * 299996 >> 5) & 255, (299997 * 299997 >> 5) & 255, (299998 * 299998 >> 5) & 255, (299999 * 299999 >> 5) & 255])
    out.free()
    src.free()

testing.test("zstd : décompression de tampon à tampon", t_buffer)

func t_errors():
    b := io.read_bytes(DATA + "text19.zst")
    bad := [x for x in b]
    bad[len(bad) // 2] = bad[len(bad) // 2] ^ 0x5A
    bad[len(bad) // 2 + 1] = bad[len(bad) // 2 + 1] ^ 0xA5
    failed := false
    try:
        d := z.zstd_decompress(bad)
        failed = len(d) != 57798 or z.crc32(d) != 3258906502
    catch e:
        failed = true
    assert_true(failed)
    failed = false
    try:
        z.zstd_decompress(b[0:len(b) // 3])
    catch e:
        failed = true
    assert_true(failed)
    failed = false
    try:
        z.zstd_decompress(b, 1000)
    catch e:
        failed = true
    assert_true(failed)

testing.test("zstd : flux corrompu ou tronqué, limite de taille", t_errors)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) zstd en échec")
print("ZSTD: OK")
