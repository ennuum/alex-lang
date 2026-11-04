# ALEX STANDARD LIBRARY — process.exit_code
#
# Codes de sortie des processus : conventions (0 succès, 1 échec, 2 mauvais usage, sysexits.h 64..78, 126/127 du
# shell, 128+n « tué par le signal n »), signaux, et une valeur ExitStatus qui sait se décrire.
#
#   use process.exit_code as ec
#   s := ec.ExitStatus(process.run("false").code)
#   print(s.success(), s.describe())        # false  « échec (code 1) »
#   print(ec.describe(-9))                   # « tué par le signal KILL (9) »
#   print(ec.describe(130))                  # « code 130 (convention du shell : signal INT) »
#   os.exit(ec.USAGE)
#
# Dans le module process, un code NÉGATIF signifie « tué par le signal -code ». Un shell, lui, renvoie 128 + n :
# from_shell / to_shell convertissent d'une convention à l'autre.

from core use type
from collections use contains_key
use system.signal as _sig

const SUCCESS := 0
const FAILURE := 1
const MISUSE := 2          # mauvais usage d'une commande intégrée du shell / arguments invalides
# sysexits.h (BSD) : codes conventionnels des outils système
const USAGE := 64          # mauvaise utilisation (arguments)
const DATAERR := 65        # données d'entrée invalides
const NOINPUT := 66        # fichier d'entrée absent ou illisible
const NOUSER := 67         # utilisateur inconnu
const NOHOST := 68         # hôte inconnu
const UNAVAILABLE := 69    # service indisponible
const SOFTWARE := 70       # erreur interne
const OSERR := 71          # erreur du système
const OSFILE := 72         # fichier système absent ou invalide
const CANTCREAT := 73      # création de fichier impossible
const IOERR := 74          # erreur d'entrée-sortie
const TEMPFAIL := 75       # échec temporaire, réessayer
const PROTOCOL := 76       # erreur de protocole distant
const NOPERM := 77         # permission refusée
const CONFIG := 78         # erreur de configuration
# shell
const CANNOT_EXECUTE := 126
const NOT_FOUND := 127
const SIGNAL_BASE := 128

_names := {0: "succès", 1: "échec", 2: "mauvais usage", 64: "mauvaise utilisation (EX_USAGE)",
           65: "données invalides (EX_DATAERR)", 66: "entrée absente (EX_NOINPUT)", 67: "utilisateur inconnu (EX_NOUSER)",
           68: "hôte inconnu (EX_NOHOST)", 69: "service indisponible (EX_UNAVAILABLE)", 70: "erreur interne (EX_SOFTWARE)",
           71: "erreur du système (EX_OSERR)", 72: "fichier système invalide (EX_OSFILE)",
           73: "création impossible (EX_CANTCREAT)", 74: "erreur d'entrée-sortie (EX_IOERR)",
           75: "échec temporaire (EX_TEMPFAIL)", 76: "erreur de protocole (EX_PROTOCOL)", 77: "permission refusée (EX_NOPERM)",
           78: "erreur de configuration (EX_CONFIG)", 126: "programme non exécutable", 127: "commande introuvable"}

func _need_int(fn, code):
    if type(code) != "int":
        raise("TypeError", "exit_code." + fn + " : code entier attendu (obtenu '" + type(code) + "')")

func _signal_name(n):
    try:
        return _sig.name_of(n)
    catch e:
        return null

# Vrai si le code (convention du module process) indique une mort par signal.
func is_signal(code):
    _need_int("is_signal", code)
    return code < 0

# Numéro du signal qui a tué le processus (code négatif), sinon null.
func signal_of(code):
    _need_int("signal_of", code)
    if code < 0:
        return -code
    return null

# Code (convention du module process) d'un processus tué par le signal sig (nom ou numéro).
func from_signal(sig):
    return -_sig.number(sig)

# Convention du shell (128 + n) -> convention du module process (-n). Les autres codes sont inchangés.
func from_shell(code):
    _need_int("from_shell", code)
    if code > SIGNAL_BASE and code < SIGNAL_BASE + 65:
        return SIGNAL_BASE - code
    return code

# Convention du module process -> code renvoyé par un shell (signal n : 128 + n).
func to_shell(code):
    _need_int("to_shell", code)
    if code < 0:
        return SIGNAL_BASE - code
    return code & 255

func success(code):
    return code == 0

# Texte lisible : « succès », « échec (code 1) », « tué par le signal TERM (15) », « commande introuvable (127) ».
func describe(code):
    if code == null:
        return "en cours (pas encore terminé)"
    _need_int("describe", code)
    if code < 0:
        name := _signal_name(-code)
        if name == null:
            return "tué par le signal " + str(-code)
        return "tué par le signal " + name + " (" + str(-code) + ")"
    if code == 0:
        return "succès"
    if code > SIGNAL_BASE and code < SIGNAL_BASE + 65:
        name := _signal_name(code - SIGNAL_BASE)
        if name != null:
            return "code " + str(code) + " (convention du shell : signal " + name + ")"
    if contains_key(_names, code):
        return _names[code] + " (code " + str(code) + ")"
    return "échec (code " + str(code) + ")"

# Code à renvoyer au système pour une exception Alex (type) : correspondance raisonnable avec sysexits.
func for_error(error_type):
    m := {"ArgumentError": USAGE, "ValueError": DATAERR, "TypeError": SOFTWARE, "IoError": IOERR,
          "PermissionError": NOPERM, "TimeoutError": TEMPFAIL, "NetworkError": UNAVAILABLE,
          "ConfigError": CONFIG, "InterruptError": SIGNAL_BASE + 2}
    if contains_key(m, error_type):
        return m[error_type]
    return FAILURE

class ExitStatus:
    func init(code):
        if code != null:
            _need_int("ExitStatus", code)
        self.code = code

    func finished():
        return self.code != null

    func success():
        return self.code == 0

    func signaled():
        return self.code != null and self.code < 0

    func signal():
        if self.signaled():
            return _signal_name(-self.code)
        return null

    func shell_code():
        if self.code == null:
            return null
        return to_shell(self.code)

    func describe():
        return describe(self.code)

    # Lève ProcessError si le processus n'a pas réussi.
    func check(what="processus"):
        if self.code != 0:
            raise("ProcessError", what + " : " + describe(self.code))
        return self
