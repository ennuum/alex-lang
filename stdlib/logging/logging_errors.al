# ALEX STANDARD LIBRARY — logging.logging_errors
#
# Erreurs de la journalisation :
#   LoggingError   configuration invalide (gestionnaire qui n'en est pas un, format inconnu, rotation impossible)
#   ValueError     niveau inconnu
#   TypeError      argument du mauvais type
# Une erreur levée PENDANT l'émission d'un message (disque plein...) n'interrompt pas le programme : elle est
# comptée par le gestionnaire (handler.errors) et écrite sur la sortie d'erreur une seule fois.
#
#   use logging.logging_errors as le

const LOGGING := "LoggingError"

func logging_error(fn, message):
    raise(LOGGING, fn + " : " + message)

func unknown_level(level):
    raise("ValueError", "logging : niveau inconnu '" + str(level) + "'")
