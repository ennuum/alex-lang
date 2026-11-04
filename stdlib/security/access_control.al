# ALEX STANDARD LIBRARY — security.access_control
#
# Contrôle d'accès : rôles (RBAC) avec héritage, permissions hiérarchiques à jokers (« docs.* », « * »), et
# listes de contrôle d'accès (ACL) par ressource avec règles allow / deny — un refus explicite l'emporte
# toujours. explain() dit POURQUOI une décision a été prise.
#
#   use security.access_control as ac
#   pol := ac.AccessControl()
#   pol.add_role("lecteur", ["docs.read"])
#   pol.add_role("auteur", ["docs.write", "docs.comment"], ["lecteur"])       # hérite de lecteur
#   pol.add_role("admin", ["*"])
#   pol.assign("ana", "auteur")
#   print(pol.check("ana", "docs.read"))          # true (hérité)
#   pol.require("ana", "users.delete")            # PermissionError
#   pol.deny("ana", "docs.write", "docs/secret")  # ACL : refus sur une ressource précise
#   print(pol.check("ana", "docs.write", "docs/secret"), pol.check("ana", "docs.write", "docs/public"))   # false true
#   print(pol.explain("ana", "docs.write", "docs/secret"))
#   sauvegarde := pol.to_dict() ; pol2 := ac.from_dict(sauvegarde)
#
# Ressources : chemins « a/b/c » ; une règle sur « docs/* » couvre « docs/x » et « docs/x/y ».
# Erreurs : PermissionError (require), ArgumentError (rôle inconnu, cycle d'héritage).

from core use len, type
from collections use append
use string as _s

# Une permission accordée p couvre-t-elle la permission demandée q ? (« a.* » couvre « a.b » et « a.b.c »)
func permission_matches(granted, wanted):
    if granted == "*" or granted == wanted:
        return true
    if _s.ends_with(granted, ".*"):
        base := _s.substring(granted, 0, len(granted) - 2)
        return wanted == base or _s.starts_with(wanted, base + ".")
    return false

func resource_matches(pattern, resource):
    if pattern == "*" or pattern == resource:
        return true
    if _s.ends_with(pattern, "/*"):
        base := _s.substring(pattern, 0, len(pattern) - 2)
        return resource == base or _s.starts_with(resource, base + "/")
    return false

class Role:
    func init(name, permissions=null, inherits=null):
        self.name = name
        self.permissions = permissions
        if self.permissions == null:
            self.permissions = []
        self.inherits = inherits
        if self.inherits == null:
            self.inherits = []

class AccessControl:
    func init():
        self.roles = {}
        self.assignments = {}     # sujet -> [rôles]
        self.direct = {}          # sujet -> [permissions]
        self.rules = []           # [effet, sujet, permission, ressource]

    func add_role(name, permissions=null, inherits=null):
        if inherits != null:
            for p in inherits:
                if not (p in self.roles):
                    raise("ArgumentError", "rôle parent inconnu : " + p)
        self.roles[name] = Role(name, permissions, inherits)
        self._check_cycles(name, [])
        return self.roles[name]

    func _check_cycles(name, path):
        if name in path:
            raise("ArgumentError", "cycle d'héritage de rôles : " + _s.join(" -> ", path + [name]))
        for p in self.roles[name].inherits:
            self._check_cycles(p, path + [name])

    func grant(role, permission):
        self._role(role)
        if not (permission in self.roles[role].permissions):
            append(self.roles[role].permissions, permission)
        return self

    func revoke(role, permission):
        r := self._role(role)
        r.permissions = [p for p in r.permissions if p != permission]
        return self

    func _role(name):
        if not (name in self.roles):
            raise("ArgumentError", "rôle inconnu : " + name)
        return self.roles[name]

    func assign(subject, role):
        self._role(role)
        if not (subject in self.assignments):
            self.assignments[subject] = []
        if not (role in self.assignments[subject]):
            append(self.assignments[subject], role)
        return self

    func unassign(subject, role):
        if subject in self.assignments:
            self.assignments[subject] = [r for r in self.assignments[subject] if r != role]
        return self

    func grant_subject(subject, permission):
        if not (subject in self.direct):
            self.direct[subject] = []
        append(self.direct[subject], permission)
        return self

    func roles_of(subject, effective=true):
        base := []
        if subject in self.assignments:
            base = self.assignments[subject]
        if not effective:
            return base[:]
        out := []
        for r in base:
            self._collect(r, out)
        return out

    func _collect(role, out):
        if role in out:
            return
        append(out, role)
        for p in self.roles[role].inherits:
            self._collect(p, out)

    # [permission, origine] accordées (directes puis rôles effectifs).
    func permissions_of(subject):
        out := []
        if subject in self.direct:
            for p in self.direct[subject]:
                append(out, [p, "directe"])
        for r in self.roles_of(subject):
            for p in self.roles[r].permissions:
                append(out, [p, "rôle " + r])
        return out

    func allow(subject, permission, resource):
        append(self.rules, ["allow", subject, permission, resource])
        return self

    func deny(subject, permission, resource="*"):
        append(self.rules, ["deny", subject, permission, resource])
        return self

    func _subject_matches(rule_subject, subject):
        if rule_subject == "*" or rule_subject == subject:
            return true
        if _s.starts_with(rule_subject, "@"):
            return _s.substring(rule_subject, 1, len(rule_subject)) in self.roles_of(subject)
        return false

    # [autorisé, raison]
    func decide(subject, permission, resource=null):
        for r in self.rules:
            if r[0] == "deny" and self._subject_matches(r[1], subject) and permission_matches(r[2], permission):
                if (resource == null and r[3] == "*") or (resource != null and resource_matches(r[3], resource)):
                    return [false, "refus explicite (" + r[1] + ", " + r[2] + ", " + r[3] + ")"]
        if resource != null:
            for r in self.rules:
                if r[0] == "allow" and self._subject_matches(r[1], subject) and permission_matches(r[2], permission) and resource_matches(r[3], resource):
                    return [true, "autorisation sur la ressource (" + r[1] + ", " + r[2] + ", " + r[3] + ")"]
        for pg in self.permissions_of(subject):
            if permission_matches(pg[0], permission):
                return [true, "permission « " + pg[0] + " » (" + pg[1] + ")"]
        return [false, "aucune permission ne couvre « " + permission + " »"]

    func check(subject, permission, resource=null):
        return self.decide(subject, permission, resource)[0]

    func require(subject, permission, resource=null):
        d := self.decide(subject, permission, resource)
        if not d[0]:
            where := ""
            if resource != null:
                where = " sur " + resource
            raise("PermissionError", subject + " : « " + permission + " »" + where + " refusé — " + d[1])
        return true

    func explain(subject, permission, resource=null):
        d := self.decide(subject, permission, resource)
        verdict := "REFUSÉ"
        if d[0]:
            verdict = "AUTORISÉ"
        return verdict + " : " + d[1]

    # Fonction protégée : fn n'est appelée que si subject_fn() a la permission.
    func guard(permission, subject_fn, fn):
        return (*args) => _guarded(self, permission, subject_fn, fn, args)

    func to_dict():
        return {"roles": [{"name": r.name, "permissions": r.permissions, "inherits": r.inherits} for r in [self.roles[k] for k in self.roles]],
                "assignments": self.assignments, "direct": self.direct, "rules": self.rules}

func _guarded(pol, permission, subject_fn, fn, args):
    pol.require(subject_fn(), permission)
    return fn(*args)

func from_dict(d):
    pol := AccessControl()
    pending := d["roles"][:]
    guard := 0
    while len(pending) > 0 and guard < 1000:
        rest := []
        for r in pending:
            ok := true
            for p in r["inherits"]:
                if not (p in pol.roles):
                    ok = false
            if ok:
                pol.add_role(r["name"], r["permissions"], r["inherits"])
            else:
                append(rest, r)
        pending = rest
        guard += 1
    for s in d["assignments"]:
        for r in d["assignments"][s]:
            pol.assign(s, r)
    for s in d["direct"]:
        for p in d["direct"][s]:
            pol.grant_subject(s, p)
    pol.rules = d["rules"]
    return pol
