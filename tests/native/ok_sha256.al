# SHA-256, HMAC-SHA256 et PBKDF2-HMAC-SHA256 : mêmes empreintes en VM (OpenSSL) et en natif (runtime sans OpenSSL).
use network.security as sec
use network.encoding as enc
print(enc.hex_encode(sec.digest("abc")))
print(enc.hex_encode(sec.digest("")))
print(enc.hex_encode(sec.digest("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")))
print(enc.hex_encode(sec.digest("été, 55 octets ou plus pour tester le second bloc final....")))
print(enc.hex_encode(sec.hmac("key", "The quick brown fox jumps over the lazy dog")))
print(enc.hex_encode(sec.hmac("une clé de plus de soixante-quatre octets, hachée d'abord par SHA-256 comme le veut HMAC", "données")))
print(enc.hex_encode(sec.pbkdf2("password", "salt", 1, 32)))
print(enc.hex_encode(sec.pbkdf2("password", "salt", 4096, 40)))
e := sec.hash_password("secret", 1000, "sel-fixe")
print(e)
print(sec.verify_password("secret", e))
print(sec.verify_password("autre", e))
