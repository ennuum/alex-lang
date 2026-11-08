# Tests : client ACME (network.acme) et ce qu'il demande à crypto.x509 — clés P-256 (PKCS#8), CSR PKCS#10,
# empreinte JWK (RFC 7638), corps JWS ES256, jetons, décision de renouvellement, dates UTC ; rotation d'un
# certificat sur le disque (network.tls13.context et network.tls : l'ancien contexte sert tant que clé et
# certificat ne vont pas ensemble). Délivrance de bout en bout si un banc Pebble tourne :
#   ALEX_TEST_ACME=https://localhost:14000/dir ALEX_TEST_ACME_CA=…/pebble.minica.pem  (défis : ALEX_TEST_ACME_PORT, 5002)
#   alexc run tests/stdlib2/test_acme.al
from core use len, to_int
use check as t
use io
use os
use json
use time
use string as s
use crypto
use crypto.der as der
use crypto.ec as ec
use crypto.bigint as bn
use crypto.x509 as x509
use network.acme as acme
use network.tls as tls
use network.tls13 as tls13
use web.server as server
use web.http.response as response
use thread.offload as offload
use asyncio as aio

const B := "build/test_acme/"

func hx(v):
    return crypto.hex_decode(v)

func b64u_dec(v):
    p := v
    while len(p) % 4 != 0:
        p = p + "="
    return crypto.base64_decode(s.replace(s.replace(p, "-", "+"), "_", "/"))

os.mkdir_all(B)
defis := B + "defis"

# Port des défis http-01 (banc Pebble) : jeton servi depuis le dossier defis.
func defi(r):
    tok := s.slice(r.path(), len(acme.CHALLENGE_PATH), len(r.path()))
    f := os.join(defis, tok)
    if acme.valid_token(tok) and os.exists(f):
        return response.text(io.read_raw(f))
    return response.not_found()

# ---------------------------------------------------------------- dates
for v in [0, 951782400, 1709210096, 4102444799]:
    t.eq(x509.utc_seconds(x509.utc_text(v)), v, "utc_seconds(utc_text(" + str(v) + "))")
t.eq(x509.utc_seconds("2026-11-08T12:00:00Z"), 1794139200, "utc_seconds : date connue")

# ---------------------------------------------------------------- clés, CSR
k := x509.new_ec_key()
k2 := x509.load_private_key(x509.private_key_pem(k))
t.eq(k2.kind + "/" + k2.curve, "ec/P-256", "clé neuve relue (PKCS#8)")
t.eq(k2.key.public_bytes(), k.key.public_bytes(), "clé relue : même clé publique")
req := x509.csr(k, ["exemple.test", "www.exemple.test", "192.0.2.7"])
top := der.children(req, der.read(req, 0))
info := req[der.read(req, 0)[1]:top[0][2]]
pub := ec.public_key(ec.curve("P-256"), k.key.public_bytes())
t.check(ec.verify_der(pub, info, der.content(req, top[2])[1:], "sha256"), "CSR : signature ECDSA-SHA256 valide")
t.check(s.contains(s.byte_pack(req), "www.exemple.test"), "CSR : noms dans subjectAltName")
t.check(s.contains(s.byte_pack(req), s.byte_pack([135, 4, 192, 0, 2, 7])), "CSR : adresse IP en iPAddress")
long := x509.csr(k, [s.repeat("a", 60) + ".exemple.test"])
t.check(s.contains(s.byte_pack(long), s.repeat("a", 60)), "CSR : nom de plus de 64 caractères (CN vide, SAN seul)")
t.raises(() => x509.csr(k, []), "ValueError", "CSR sans nom refusé")

# ---------------------------------------------------------------- empreinte, JWS
# clé de la RFC 6979 (A.2.5) : empreinte calculée à part (RFC 7638, membres crv/kty/x/y triés)
kf := x509.PrivateKey("ec", ec.private_key(ec.curve("P-256"), hx("c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721")), "P-256")
c := acme.Client("https://acme.invalid/dir", kf)
t.eq(c.jwk(), {"crv": "P-256", "kty": "EC", "x": "YP7UuiVanTHJYet0xjVtaMBJuJI7Yfps5mliLmDyn7Y", "y": "eQP-EAi4vJmkGunpVii8ZPLxsgwtfp9Rd6PClNRGIpk"}, "JWK de la clé de compte")
t.eq(c.thumbprint(), "DOvxvJiAdIqVWIkFt5hDtCunXLF0BV4-JGv4f-ALSm0", "empreinte JWK (RFC 7638)")
t.eq(c.key_authorization("jeton_1"), "jeton_1.DOvxvJiAdIqVWIkFt5hDtCunXLF0BV4-JGv4f-ALSm0", "autorisation de clé http-01")
c.nonce = "n0nce"
body := json.parse(c._jws("https://acme.invalid/new-acct", {"termsOfServiceAgreed": true}, true))
prot := json.parse(crypto.utf8_decode(b64u_dec(body["protected"])))
t.eq([prot["alg"], prot["nonce"], prot["url"], prot["jwk"]["x"]], ["ES256", "n0nce", "https://acme.invalid/new-acct", c.x], "JWS : en-tête protégé (jwk)")
sig := b64u_dec(body["signature"])
t.eq(len(sig), 64, "JWS : signature r || s sur 64 octets")
t.check(ec.verify(ec.public_key(ec.curve("P-256"), kf.key.public_bytes()), crypto.utf8_encode(body["protected"] + "." + body["payload"]), [bn.from_bytes(sig[0:32]), bn.from_bytes(sig[32:64])], "sha256"), "JWS : signature ES256 valide")
c.kid = "https://acme.invalid/acct/1"
prot = json.parse(crypto.utf8_decode(b64u_dec(json.parse(c._jws("https://acme.invalid/x", null, false))["protected"])))
t.check(prot["kid"] == c.kid and not ("jwk" in prot), "JWS : kid une fois le compte connu")
t.eq(json.parse(c._jws("https://acme.invalid/x", null, false))["payload"], "", "JWS : POST-as-GET (charge vide)")

t.check(acme.valid_token("aZ09_-x") and not acme.valid_token("") and not acme.valid_token("../x") and not acme.valid_token("a.b"), "jetons de défi : alphabet base64url seulement")

# ---------------------------------------------------------------- renouvellement
pair := x509.self_signed("exemple.test", ["exemple.test"], 90)
io.write_file(B + "auto.pem", pair[0])
t.check(acme.needs_renewal(B + "absent.pem", ["exemple.test"]), "renouvellement : certificat absent")
t.check(acme.needs_renewal(B + "auto.pem", ["exemple.test"]), "renouvellement : certificat d'attente auto-signé")
io.write_file(B + "illisible.pem", "pas un certificat")
t.check(acme.needs_renewal(B + "illisible.pem", ["exemple.test"]), "renouvellement : fichier illisible")

# ---------------------------------------------------------------- rotation sur le disque
a := x509.self_signed("localhost", ["localhost"], 30)
b := x509.self_signed("localhost", ["localhost"], 30)
io.write_file(B + "rot.pem", a[0])
io.write_file(B + "rot.key", a[1])
ctx := tls13.context(B + "rot.pem", B + "rot.key")
time.sleep(1.1)                                              # empreinte des fichiers : date de modification
io.write_file(B + "rot.key", b[1])                           # clé remplacée, certificat pas encore
t.check(tls13.context(B + "rot.pem", B + "rot.key") == ctx, "rotation : l'ancien contexte sert pendant le remplacement")
t.check(tls._mismatch(B + "rot.pem", B + "rot.key"), "rotation : couple incohérent détecté (OpenSSL garde l'ancien contexte)")
io.write_file(B + "rot.pem", b[0])
ctx2 := tls13.context(B + "rot.pem", B + "rot.key")
t.check(ctx2 != ctx and not tls._mismatch(B + "rot.pem", B + "rot.key"), "rotation : nouveau contexte une fois le couple cohérent")
t.raises(() => tls13.context(B + "rot.pem", B + "absent.key"), "IoError", "sans ancien contexte, l'erreur remonte")

# ---------------------------------------------------------------- de bout en bout (Pebble)
dir_url := os.getenv("ALEX_TEST_ACME")
if dir_url != null and dir_url != "":
    os.mkdir_all(defis)
    for f in os.list_dir(defis):
        os.remove(os.join(defis, f))
    cfg := server.config("127.0.0.1", to_int(os.getenv("ALEX_TEST_ACME_PORT", "5002")))
    cfg.access_log = false
    srv := server.Server(defi, cfg).start()
    for f in ["pebble.pem", "pebble.key"]:
        if os.exists(B + f):
            os.remove(B + f)
    job := offload.submit(acme.issue, [dir_url, B + "compte.key", B + "pebble.pem", B + "pebble.key", ["exemple.test", "www.exemple.test"], defis, "admin@exemple.test", os.getenv("ALEX_TEST_ACME_CA")])
    t0 := time.monotonic()
    while not aio.done(job) and time.monotonic() - t0 < 60.0:
        offload.poll()
        srv.step(0.01)
    srv.close()
    r := aio.result(job)
    chain := x509.load_certificates(io.read_raw(B + "pebble.pem"))
    t.check(len(chain) >= 2 and x509.matches_host(chain[0], "www.exemple.test"), "Pebble : chaîne délivrée, noms couverts")
    t.check(x509.key_matches(chain[0], x509.load_private_key(io.read_raw(B + "pebble.key"))), "Pebble : clé assortie")
    t.eq(r["not_after"], chain[0].not_after, "Pebble : date de fin rendue")
    t.check(not acme.needs_renewal(B + "pebble.pem", ["exemple.test"]), "Pebble : certificat neuf, pas de renouvellement")
    t.check(acme.needs_renewal(B + "pebble.pem", ["autre.test"]), "Pebble : nom non couvert, renouvellement")
    t.eq(len(os.list_dir(defis)), 0, "Pebble : fichiers de défi retirés")
else:
    print("  (banc Pebble absent : ALEX_TEST_ACME non défini, délivrance non testée)")

t.summary("test_acme")
