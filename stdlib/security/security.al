# ALEX STANDARD LIBRARY — security.security
#
# Socle du paquet security : types d'erreur, comparaison en temps constant, effacement des listes d'octets,
# conversions octets <-> texte, et classement des niveaux de gravité. Les autres modules du paquet :
#   random_secure (entropie du système), crypto_provider (hachage, HMAC, HKDF, chiffrement authentifié, mots de
#   passe), secure_memory (secrets en pages verrouillées et protégées), credential_store (coffre chiffré),
#   access_control (rôles et listes d'accès), capability (jetons de capacité signés, facettes d'objets),
#   sandbox (exécution confinée), security_audit (journal infalsifiable, vérifications du système).
#
#   use security.security as sec
#   print(sec.constant_time_equals("abc", "abd"))     # false (durée indépendante de la position de l'écart)
#   k := [1, 2, 3]
#   sec.wipe(k)                                       # [0, 0, 0]
#   sec.require(utilisateur_admin, "réservé aux administrateurs")   # PermissionError si faux
#
# Erreurs : SecurityError (générale), PermissionError (accès refusé), AuthenticationError (mot de passe, clé),
# SignatureError (signature / MAC / chaîne d'audit invalide), SandboxError, CredentialError.

from core use len, type
use string as _s
use crypto as _c

const SECURITY := "SecurityError"
const PERMISSION := "PermissionError"
const AUTHENTICATION := "AuthenticationError"
const SIGNATURE := "SignatureError"
const SANDBOX := "SandboxError"
const CREDENTIAL := "CredentialError"

const LOW := "faible"
const MEDIUM := "moyenne"
const HIGH := "élevée"
const CRITICAL := "critique"
const SEVERITIES := ["faible", "moyenne", "élevée", "critique"]

func severity_rank(s):
    i := 0
    while i < len(SEVERITIES):
        if SEVERITIES[i] == s:
            return i
        i += 1
    return -1

func fail(message):
    raise(SECURITY, message)

func deny(message):
    raise(PERMISSION, message)

func require(condition, message="accès refusé"):
    if not condition:
        raise(PERMISSION, message)

# Octets (liste d'int) d'une str (UTF-8) ou d'une liste.
func to_bytes(data):
    if type(data) == "str":
        return _c.utf8_encode(data)
    if type(data) == "list" or type(data) == "tuple":
        return [b for b in data]
    raise("TypeError", "security : str ou liste d'octets attendue (obtenu '" + type(data) + "')")

# Comparaison sans court-circuit (str ou listes d'octets) : la durée ne dépend que des longueurs.
func constant_time_equals(a, b):
    x := to_bytes(a)
    y := to_bytes(b)
    diff := 0
    if len(x) != len(y):
        diff = 1
    n := len(x)
    if len(y) > n:
        n = len(y)
    i := 0
    while i < n:
        u := 0
        v := 0
        if i < len(x):
            u = x[i]
        if i < len(y):
            v = y[i]
        diff = diff | (u ^ v)
        i += 1
    return diff == 0

# Écrase une liste (d'octets) par des zéros. Les str d'ALEX sont immuables : elles ne peuvent pas être
# effacées — garder les secrets en listes d'octets ou dans security.secure_memory.
func wipe(buf):
    if type(buf) != "list":
        raise("TypeError", "wipe : liste attendue (une str ne peut pas être effacée)")
    i := 0
    while i < len(buf):
        buf[i] = 0
        i += 1
    return buf

func is_security_error(t):
    return t == SECURITY or t == PERMISSION or t == AUTHENTICATION or t == SIGNATURE or t == SANDBOX or t == CREDENTIAL
