# ALEX STANDARD LIBRARY — security.security_audit
#
# Audit de sécurité :
#   AuditLog : journal d'événements de sécurité INFALSIFIABLE — chaque entrée contient l'empreinte (SHA-256, ou
#              HMAC avec une clé) de la précédente ; modifier, supprimer ou réordonner une entrée casse la
#              chaîne, et verify() le détecte. Fichier au format JSON Lines (une entrée par ligne), ajout seul.
#   Vérifications du système : droits des fichiers sensibles (écriture pour tous, setuid, propriétaire),
#              secrets exposés dans l'environnement, masque de création (umask).
#
#   use security.security_audit as sa
#   log := sa.AuditLog("/var/log/app/audit.jsonl", cle_hmac)       # cle facultative (sinon SHA-256)
#   log.record("ana", "login", "app", "succès", {"ip": "10.0.0.4"})
#   log.record("bob", "delete", "docs/42", "refus")
#   print(log.verify())                       # {"ok": true, "entries": 2} ; sinon "broken_at": n
#   print(log.query({"actor": "bob"}))        # entrées filtrées
#   rapport := sa.check_files(["/etc/app/config.json", "/home/ana/.ssh/id_ed25519"])
#   print(sa.format_findings(rapport + sa.check_environment()))
#
# Erreurs : SignatureError (chaîne rompue avec strict), IoError.

from core use len, type, to_int
from collections use append
use string as _s
use os as _os
use io as _io
use json as _json
use time as _time
use crypto as _c
use _native_fd as _f
use security.security as _sec
use security.crypto_provider as _cp

const GENESIS := "0000000000000000000000000000000000000000000000000000000000000000"

class AuditLog:
    func init(path=null, key=null):
        self.path = path
        self.key = key
        self.entries = []
        self.last_hash = GENESIS
        if path != null and _os.exists(path):
            for line in _s.split(_io.read_file(path), "\n"):
                if _s.trim(line) != "":
                    append(self.entries, _json.parse(line))
            if len(self.entries) > 0:
                self.last_hash = self.entries[len(self.entries) - 1]["hash"]

    func _digest(entry):
        d := {}
        for k in entry:
            if k != "hash":
                d[k] = entry[k]
        text := _json.stringify(d)
        if self.key != null:
            return _cp.hmac_hex("sha256", self.key, text)
        return _cp.hash_hex("sha256", text)

    func record(actor, action, resource=null, outcome="succès", details=null):
        e := {"seq": len(self.entries) + 1, "time": _time.time(), "actor": actor, "action": action,
              "resource": resource, "outcome": outcome, "details": details, "prev": self.last_hash}
        e["hash"] = self._digest(e)
        append(self.entries, e)
        self.last_hash = e["hash"]
        if self.path != null:
            _io.append_file(self.path, _json.stringify(e) + "\n")
        return e

    # {"ok", "entries", "broken_at" (numéro de séquence), "reason"}
    func verify(strict=false):
        prev := GENESIS
        i := 0
        while i < len(self.entries):
            e := self.entries[i]
            reason := null
            if e["seq"] != i + 1:
                reason = "numéro de séquence " + str(e["seq"]) + " à la position " + str(i + 1)
            elif e["prev"] != prev:
                reason = "lien vers l'entrée précédente rompu"
            elif not _sec.constant_time_equals(self._digest(e), e["hash"]):
                reason = "contenu modifié"
            if reason != null:
                if strict:
                    raise("SignatureError", "journal d'audit : chaîne rompue à l'entrée " + str(i + 1) + " (" + reason + ")")
                return {"ok": false, "entries": len(self.entries), "broken_at": i + 1, "reason": reason}
            prev = e["hash"]
            i += 1
        return {"ok": true, "entries": len(self.entries), "broken_at": null, "reason": null}

    func query(filters=null, since=null, until=null):
        out := []
        for e in self.entries:
            ok := true
            if filters != null:
                for k in filters:
                    if not (k in e) or not (e[k] == filters[k]):
                        ok = false
            if since != null and e["time"] < since:
                ok = false
            if until != null and e["time"] > until:
                ok = false
            if ok:
                append(out, e)
        return out

    func failures():
        return [e for e in self.entries if e["outcome"] != "succès" and e["outcome"] != "success" and e["outcome"] != "ok"]

    func size():
        return len(self.entries)

    # Nombre d'échecs par acteur (repérer la force brute).
    func failures_by_actor():
        out := {}
        for e in self.failures():
            a := e["actor"]
            if a in out:
                out[a] += 1
            else:
                out[a] = 1
        return out

# ---------------------------------------------------------------------------------------------------------
# Vérifications
# ---------------------------------------------------------------------------------------------------------

func finding(severity, subject, message, advice=null):
    return {"severity": severity, "subject": subject, "message": message, "advice": advice}

func _is_private_key(path):
    n := _s.lower(path)
    return _s.contains(n, "id_rsa") or _s.contains(n, "id_ed25519") or _s.contains(n, "id_ecdsa") or _s.ends_with(n, ".pem") or _s.ends_with(n, ".key") or _s.contains(n, "vault")

func check_files(paths):
    out := []
    for p in paths:
        if not _os.exists(p):
            append(out, finding(_sec.LOW, p, "fichier absent"))
            continue
        st := _f.stat(p, true)
        if type(st) != "list":
            append(out, finding(_sec.LOW, p, "état du fichier illisible"))
            continue
        mode := st[0]
        perm := mode & 4095
        if perm & 2 != 0:
            sev := _sec.HIGH
            if _os.isdir(p) and perm & 512 != 0:
                sev = _sec.LOW
            append(out, finding(sev, p, "modifiable par tous (mode " + _oct(perm) + ")", "chmod o-w " + p))
        if perm & 2048 != 0 and not _os.isdir(p):
            append(out, finding(_sec.HIGH, p, "bit setuid positionné", "vérifier la nécessité ; chmod u-s"))
        if perm & 1024 != 0 and not _os.isdir(p):
            append(out, finding(_sec.MEDIUM, p, "bit setgid positionné"))
        if _is_private_key(p) and perm & 63 != 0:
            append(out, finding(_sec.CRITICAL, p, "clé ou secret lisible par d'autres utilisateurs (mode " + _oct(perm) + ")", "chmod 600 " + p))
        uid := st[1]
        me := _uid()
        if me != null and uid != me and uid != 0 and _is_private_key(p):
            append(out, finding(_sec.MEDIUM, p, "secret appartenant à un autre utilisateur (uid " + str(uid) + ")"))
    return out

func _uid():
    try:
        txt := _io.read_file("/proc/self/status")
        for line in _s.split(txt, "\n"):
            if _s.starts_with(line, "Uid:"):
                parts := [x for x in _s.split(_s.trim(_s.substring(line, 4, len(line))), "\t") if x != ""]
                return to_int(_s.trim(parts[0]))
    catch e:
        return null
    return null

func _oct(n):
    out := ""
    v := n
    while v > 0:
        out = str(v % 8) + out
        v = v // 8
    while len(out) < 3:
        out = "0" + out
    return out

const SECRET_HINTS := ["PASSWORD", "PASSWD", "SECRET", "TOKEN", "API_KEY", "APIKEY", "PRIVATE_KEY", "CREDENTIAL", "AWS_SECRET"]

func check_environment(env=null):
    out := []
    e := env
    if e == null:
        e = _os.env()
    for k in e:
        up := _s.upper(k)
        for h in SECRET_HINTS:
            if _s.contains(up, h) and e[k] != "":
                append(out, finding(_sec.MEDIUM, k, "secret probable dans l'environnement (hérité par tous les processus fils)", "préférer un coffre (security.credential_store)"))
                break
    pth := ""
    if "PATH" in e:
        pth = e["PATH"]
    for part in _s.split(pth, ":"):
        if part == "" or part == ".":
            append(out, finding(_sec.HIGH, "PATH", "le dossier courant fait partie de PATH", "retirer « . » et les entrées vides de PATH"))
            break
    return out

func check_umask():
    txt := null
    try:
        txt = _io.read_file("/proc/self/status")
    catch e:
        return []
    for line in _s.split(txt, "\n"):
        if _s.starts_with(line, "Umask:"):
            v := _s.trim(_s.substring(line, 6, len(line)))
            n := 0
            for c in v:
                n = n * 8 + (_s.ord(c) - 48)
            if n & 2 == 0:
                return [finding(_sec.MEDIUM, "umask", "umask " + v + " : nouveaux fichiers modifiables par tous", "umask 022 (ou 077)")]
            return []
    return []

func run_all(paths=null):
    out := check_environment() + check_umask()
    if paths != null:
        out = out + check_files(paths)
    return out

func format_findings(findings):
    if len(findings) == 0:
        return "Aucun problème détecté."
    ordered := findings[:]
    i := 1
    while i < len(ordered):
        v := ordered[i]
        j := i - 1
        while j >= 0 and _sec.severity_rank(ordered[j]["severity"]) < _sec.severity_rank(v["severity"]):
            ordered[j + 1] = ordered[j]
            j -= 1
        ordered[j + 1] = v
        i += 1
    lines := []
    for f in ordered:
        l := "[" + f["severity"] + "] " + f["subject"] + " : " + f["message"]
        if f["advice"] != null:
            l += " → " + f["advice"]
        append(lines, l)
    return _s.join("\n", lines)
