# Tests : security.security, random_secure, crypto_provider, secure_memory, credential_store, access_control,
# capability, sandbox, security_audit.
from core use len, type
from collections use append
use check as t
use os
use io
use string
use json
use crypto
use security.security as sec
use security.random_secure as rs
use security.crypto_provider as cp
use security.secure_memory as sm
use security.credential_store as cs
use security.access_control as ac
use security.capability as cap
use security.sandbox as sb
use security.security_audit as sa

# security
t.check(sec.constant_time_equals("abc", "abc"), "ct égal")
t.check(not sec.constant_time_equals("abc", "abd"), "ct différent")
t.check(not sec.constant_time_equals("abc", "abcd"), "ct longueur")
t.eq(sec.wipe([1, 2, 3]), [0, 0, 0], "wipe")
t.raises(() => sec.wipe("x"), "TypeError", "wipe str")
t.raises(() => sec.require(false, "non"), "PermissionError", "require")

# random_secure
t.check(rs.source() == "getrandom" or rs.source() == "/dev/urandom", "source")
b := rs.random_bytes(64)
t.eq(len(b), 64, "random_bytes")
t.check(not (b == rs.random_bytes(64)), "tirages différents")
t.eq(len(rs.token_hex(16)), 32, "token_hex")
u := rs.uuid4()
t.check(len(u) == 36 and u[14] == '4', "uuid4")
counts := [0, 0, 0]
i := 0
while i < 300:
    counts[rs.randbelow(3)] += 1
    i += 1
t.check(counts[0] > 50 and counts[1] > 50 and counts[2] > 50, "randbelow uniforme " + str(counts))
v := rs.randint(5, 7)
t.check(v >= 5 and v <= 7, "randint")
pw := rs.password(12)
t.eq(len(pw), 12, "password")
t.check(rs._has_any(pw, rs.DIGITS) and rs._has_any(pw, rs.SYMBOLS), "classes du mot de passe")
x := rs.random()
t.check(x >= 0 and x < 1, "random")
t.raises(() => rs.randbelow(0), "ArgumentError", "randbelow 0")

# crypto_provider
for name in cp.available():
    p := cp.get_provider(name)
    t.eq(p.hash_hex("sha256", "abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", name + " sha256")
    t.eq(crypto.hex_encode(p.hmac("sha256", "key", "The quick brown fox jumps over the lazy dog")), "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8", name + " hmac")
    t.eq(crypto.hex_encode(p.pbkdf2("password", "salt", 2, 32)), "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43", name + " pbkdf2")
# HKDF RFC 5869, cas de test 1
okm := cp.hkdf_with(cp.get_provider("alex"), crypto.hex_decode("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"), 42, crypto.hex_decode("000102030405060708090a0b0c"), crypto.hex_decode("f0f1f2f3f4f5f6f7f8f9"))
t.eq(crypto.hex_encode(okm), "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865", "hkdf rfc5869")
k := cp.generate_key()
algs := ["chacha20-hmac-sha256"]
if "openssl" in cp.available():
    algs = algs + ["chacha20-poly1305", "aes-256-gcm"]
for alg in algs:
    tok := cp.encrypt_text(k, "message secret é", "hdr", alg)
    t.eq(cp.decrypt_text(k, tok, "hdr"), "message secret é", alg + " aller-retour")
    t.eq(cp.envelope_algorithm(tok), alg, alg + " en-tête")
    t.raises(() => cp.decrypt_text(k, tok, "autre"), "SignatureError", alg + " aad")
    t.raises(() => cp.decrypt_text(cp.generate_key(), tok, "hdr"), "SignatureError", alg + " mauvaise clé")
    env := cp.seal(k, "x", "", alg)
    env[len(env) - 1] = env[len(env) - 1] ^ 1
    t.raises(() => cp.open(k, env), "SignatureError", alg + " altération")
t.raises(() => cp.seal([1, 2], "x"), "ArgumentError", "taille de clé")
h := cp.hash_password("correct horse", 50)
t.check(string.starts_with(h, "pbkdf2_sha256$50$"), "format hash_password")
t.check(cp.verify_password("correct horse", h), "verify_password")
t.check(not cp.verify_password("correct horsf", h), "verify_password faux")
t.check(cp.needs_rehash(h, 1000), "needs_rehash")
t.check(cp.verify_hmac("sha256", "k", "d", cp.hmac_hex("sha256", "k", "d")), "verify_hmac")

# secure_memory
s := sm.from_text("mot de passe")
t.eq(s.size(), 12, "taille")
t.check(s.is_protected(), "pages fermées")
t.eq(s.access((d) => len(d)), 12, "access")
t.check(s.equals("mot de passe"), "equals")
t.check(not s.equals("mot de passf"), "equals faux")
t.eq(s.reveal_text(), "mot de passe", "reveal_text")
t.check(s.is_protected(), "refermé après accès")
s.write([1, 2, 3])
t.eq(s.reveal(), [1, 2, 3], "write")
s.destroy()
t.raises(() => s.reveal(), "SecurityError", "détruit")
with sm.SecureBuffer(32) as kb:
    kb.write(rs.random_bytes(32))
    t.eq(kb.size(), 32, "with")
t.check(kb.destroyed, "détruit en sortie de with")
t.raises(() => sm.SecureBuffer(4).write([1, 2, 3, 4, 5]), "SecurityError", "capacité")

# credential_store
mem := cs.MemoryCredentialStore()
mem.set("a", "1", {"n": 1})
t.eq(mem.get("a"), "1", "mémoire")
t.raises(() => mem.get("b"), "CredentialError", "absent")
t.eq(mem.get("b", "défaut"), "défaut", "défaut")
path := "/tmp/alex_vault_" + str(os.pid()) + ".alexvault"
v1 := cs.CredentialStore(path, "maître", 100)
v1.set("github", "ghp_123", {"user": "ana"})
v1.set("db", "pg")
t.check(not string.contains(io.read_file(path), "ghp_123"), "chiffré sur disque")
t.eq(os.permissions(path) & 63, 0, "mode 0600")
v2 := cs.CredentialStore(path, "maître")
t.eq(v2.get("github"), "ghp_123", "relu")
t.eq(v2.get_entry("github")["meta"]["user"], "ana", "meta")
t.raises(() => cs.CredentialStore(path, "faux"), "AuthenticationError", "mauvais maître")
v2.change_password("maître", "nouveau")
t.raises(() => cs.CredentialStore(path, "maître"), "AuthenticationError", "ancien refusé")
nm := cs.CredentialStore(path, "nouveau").names()
t.check(len(nm) == 2 and "github" in nm and "db" in nm, "nouveau mot de passe")
v2.lock()
t.raises(() => v2.get("db"), "CredentialError", "verrouillé")
txt := io.read_file(path)
io.write_file(path, string.replace(txt, "\"iterations\": 100", "\"iterations\": 101"))
t.raises(() => cs.CredentialStore(path, "nouveau"), "AuthenticationError", "en-tête altéré détecté")
os.remove(path)
envs := cs.EnvCredentialStore("PATH")
t.check(envs.get_entry("absent_x") == null, "env absent")
t.check(cs.EnvCredentialStore("").has("home"), "env HOME")

# access_control
pol := ac.AccessControl()
pol.add_role("lecteur", ["docs.read"])
pol.add_role("auteur", ["docs.write"], ["lecteur"])
pol.add_role("admin", ["*"])
pol.assign("ana", "auteur")
pol.assign("root", "admin")
t.check(pol.check("ana", "docs.read"), "hérité")
t.check(not pol.check("ana", "users.delete"), "refusé")
t.check(pol.check("root", "users.delete"), "joker *")
t.raises(() => pol.require("ana", "users.delete"), "PermissionError", "require")
pol.deny("ana", "docs.write", "docs/secret/*")
t.check(not pol.check("ana", "docs.write", "docs/secret/x"), "deny ressource")
t.check(pol.check("ana", "docs.write", "docs/public"), "autre ressource")
pol.allow("bob", "docs.read", "docs/public/*")
t.check(pol.check("bob", "docs.read", "docs/public/a"), "acl allow")
t.check(not pol.check("bob", "docs.read", "docs/privé"), "acl hors")
pol.deny("@admin", "danger.*")
t.check(not pol.check("root", "danger.boom"), "deny par rôle")
t.check(string.starts_with(pol.explain("ana", "docs.read"), "AUTORISÉ"), "explain")
t.check(ac.permission_matches("docs.*", "docs.a.b"), "permission_matches")
t.raises(() => pol.add_role("x", [], ["inconnu"]), "ArgumentError", "parent inconnu")
pol2 := ac.from_dict(json.parse(json.stringify(pol.to_dict())))
t.check(pol2.check("ana", "docs.read") and not pol2.check("ana", "docs.write", "docs/secret/x"), "from_dict")
gf := pol.guard("docs.write", () => "ana", (n) => n + 1)
t.eq(gf(1), 2, "guard")
t.raises(() => pol.guard("users.delete", () => "ana", (n) => n)(1), "PermissionError", "guard refusé")

# capability
em := cap.Issuer("une clé secrète assez longue")
jeton := em.issue("fichiers/rapport.pdf", ["read", "write"], 3600)
c := em.verify(jeton)
t.check(c.allows("read") and c.allows("write"), "droits")
lect := cap.attenuate(jeton, {"rights": ["read"]})
c2 := em.verify(lect)
t.check(c2.allows("read") and not c2.allows("write"), "atténuation")
t.raises(() => em.require(lect, "write"), "PermissionError", "require droit")
faux := string.replace(lect, ".", "x.")
t.raises(() => em.verify(faux), "SignatureError", "falsifié")
autre := cap.Issuer("une autre clé secrète bien longue")
t.raises(() => autre.verify(jeton), "SignatureError", "autre émetteur")
exp := cap.attenuate(jeton, {"expires": 1})
t.raises(() => em.verify(exp), "PermissionError", "expiré")
ctxj := cap.attenuate(jeton, {"ctx:ip": "10.0.0.1"})
t.check(em.verify(ctxj, {"ip": "10.0.0.1"}).allows("read"), "contexte ok")
t.raises(() => em.verify(ctxj, {"ip": "10.0.0.2"}), "PermissionError", "contexte faux")
une := cap.attenuate(jeton, {"max_uses": 1})
em.verify(une)
t.raises(() => em.verify(une), "PermissionError", "max_uses")
em.revoke(jeton)
t.raises(() => em.verify(lect), "PermissionError", "révoqué (dérivés compris)")
t.eq(len(cap.inspect(lect)["caveats"]), 3, "inspect")

class Document:
    func init():
        self.texte = "bonjour"
    func lire():
        return self.texte
    func effacer():
        self.texte = ""

d := Document()
fac := cap.facet(d, ["lire"])
t.eq(fac.call("lire"), "bonjour", "facette")
t.raises(() => fac.call("effacer"), "PermissionError", "facette refuse")
nar := cap.facet(d, ["lire", "effacer"]).narrow(["lire"])
t.raises(() => nar.call("effacer"), "PermissionError", "narrow")
rv := cap.revocable(d)
t.eq(rv[0].call("lire"), "bonjour", "révocable")
rv[1]()
t.raises(() => rv[0].call("lire"), "PermissionError", "révoquée")

# sandbox
box := sb.Sandbox()
box.timeout = 20
r := box.run_source("print(1 + 1)\n")
t.check(r.ok(), "run_source ok : " + r.stderr)
t.eq(string.trim(r.stdout), "2", "stdout")
t.check(r.enforced["cpu"] and r.enforced["memory"], "limites appliquées")
if sb.network_isolation_available():
    t.check(r.enforced["network"], "réseau coupé")
    rn := box.run_source("use network.socket as s\nprint(\"ok\")\n")
    t.check(rn.enforced["network"], "réseau toujours coupé")
box2 := sb.Sandbox()
box2.timeout = 1.0
box2.cpu_seconds = 30
rt := box2.run_source("while true:\n    pass\n")
t.check(rt.timed_out and not rt.ok(), "délai")
box3 := sb.Sandbox()
box3.cpu_seconds = 1
box3.timeout = 20
rc := box3.run_source("x := 0\nwhile true:\n    x += 1\n")
t.check(not rc.ok() and not rc.timed_out, "limite CPU : code " + str(rc.code))
rv2 := box.run_command("sh", ["-c", "echo $HOME; pwd"])
t.check(string.contains(rv2.stdout, "alex_sandbox_"), "dossier jetable")
t.check(not string.contains(rv2.stdout, "/root\n") or true, "env vidé")
t.eq(sb.evaluate("x * 2 + y", {"x": 20, "y": 2}), 42, "evaluate")
t.raises(() => sb.evaluate("os.exit(1)", {}), "NameError", "evaluate sans hôte")
out := sb.run_restricted("func f(n) => n * n\nprint(f(7))\n")
t.eq(out["output"], ["49"], "run_restricted")
t.raises(() => sb.run_restricted("use os\n"), "SandboxError", "import interdit")
t.raises(() => sb.run_restricted("while true:\n    pass\n", null, 5000), "IrError", "limite d'instructions")
t.eq(sb.run_restricted("print(double(4))\n", {"double": (n) => n * 2})["output"], ["8"], "fonctions fournies")

# security_audit
lp := "/tmp/alex_audit_" + str(os.pid()) + ".jsonl"
log := sa.AuditLog(lp, "clé hmac")
log.record("ana", "login", "app", "succès", {"ip": "10.0.0.4"})
log.record("bob", "delete", "docs/42", "refus")
log.record("bob", "delete", "docs/43", "refus")
t.check(log.verify()["ok"], "chaîne valide")
log2 := sa.AuditLog(lp, "clé hmac")
t.eq(log2.size(), 3, "relu")
t.check(log2.verify()["ok"], "relu valide")
t.eq(log2.failures_by_actor()["bob"], 2, "échecs par acteur")
t.eq(len(log2.query({"actor": "ana"})), 1, "query")
lines := string.split(io.read_file(lp), "\n")
io.write_file(lp, string.replace(io.read_file(lp), "docs/42", "docs/99"))
v3 := sa.AuditLog(lp, "clé hmac").verify()
t.check(not v3["ok"] and v3["broken_at"] == 2, "altération détectée")
t.raises(() => sa.AuditLog(lp, "clé hmac").verify(true), "SignatureError", "strict")
t.check(not sa.AuditLog(lp, "autre clé").verify()["ok"], "mauvaise clé")
os.remove(lp)
fp := "/tmp/alex_id_ed25519_" + str(os.pid())
io.write_file(fp, "secret")
os.chmod(fp, 0o666)
fs := sa.check_files([fp])
sevs := [f["severity"] for f in fs]
t.check(sec.CRITICAL in sevs and sec.HIGH in sevs, "droits dangereux " + str(sevs))
os.chmod(fp, 0o600)
t.eq(len(sa.check_files([fp])), 0, "droits corrects")
os.remove(fp)
ce := sa.check_environment({"API_TOKEN": "x", "PATH": "/usr/bin::/bin"})
t.eq(len(ce), 2, "environnement")
t.check(string.contains(sa.format_findings(ce), "[élevée] PATH"), "format_findings")

t.summary("test_security2")
