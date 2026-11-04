# ALEX STANDARD LIBRARY — multimedia.core.errors
#
# Types d'erreurs communs à toute la bibliothèque multimédia. Chaque erreur est levée avec raise(TYPE, message) :
# on la reconnaît par `e.type` dans un bloc catch.
#
#   MediaError          erreur générale
#   FormatError         paramètres de format invalides (fréquence, canaux, dimensions, format de points)
#   UnsupportedError    format, codec ou fonction reconnus mais non pris en charge (jamais simulés)
#   CorruptDataError    fichier tronqué, en-tête incohérent, données hors des bornes déclarées
#   LimitError          limite de sécurité dépassée (taille, durée, dimensions, nombre de pistes...)
#   DeviceError         périphérique absent, occupé ou refusé
#   PipelineError       graphe de traitement invalide (cycle, nœud non relié, état incorrect)
#   StateError          opération impossible dans l'état courant (lecture d'un lecteur fermé...)
#   CancelledError      opération annulée (même type que async.cancellation)
#
#   use multimedia.core.errors as merr
#   try:
#       merr.unsupported("codec h264", "aucun décodeur vidéo intégré")
#   catch e:
#       print(e.type, merr.is_media_error(e.type))      # UnsupportedError true

from core use len

const MEDIA := "MediaError"
const FORMAT := "FormatError"
const UNSUPPORTED := "UnsupportedError"
const CORRUPT := "CorruptDataError"
const LIMIT := "LimitError"
const DEVICE := "DeviceError"
const PIPELINE := "PipelineError"
const STATE := "StateError"
const CANCELLED := "CancelledError"

const ALL := [MEDIA, FORMAT, UNSUPPORTED, CORRUPT, LIMIT, DEVICE, PIPELINE, STATE, CANCELLED]

func fail(kind, message):
    raise(kind, "multimédia : " + message)

func unsupported(feature, reason=null):
    m := feature + " non pris en charge"
    if reason != null:
        m = m + " (" + reason + ")"
    fail(UNSUPPORTED, m)

func corrupt(what, detail):
    fail(CORRUPT, what + " : " + detail)

func limit(what, value, maximum):
    fail(LIMIT, what + " = " + str(value) + " dépasse la limite " + str(maximum))

func state(message):
    fail(STATE, message)

func is_media_error(t):
    return t in ALL

# Les erreurs des paquets audio / camera / hardware existants, ramenées à une catégorie multimédia.
func category(t):
    if t in ALL:
        return t
    if t == "AudioFormatError" or t == "ArgumentError":
        return FORMAT
    if t == "AudioDeviceError" or t == "HardwareError" or t == "CameraError":
        return DEVICE
    if t == "CompressionError":
        return CORRUPT
    return MEDIA
