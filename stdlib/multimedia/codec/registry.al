# ALEX STANDARD LIBRARY — multimedia.codec.registry
#
# Registre des codecs : chaque codec DÉCLARE ce qu'il sait faire (décoder, encoder), son genre et son origine :
#   « intégré »   écrit en ALEX dans cette bibliothèque (PCM, FLAC, PNG, BMP, PNM, sous-titres texte) ;
#   « système »   fourni par un outil ou une bibliothèque de la machine, branché à l'exécution ;
#   « optionnel » dorsal ajouté par l'application (register).
# Les codecs courants non disponibles (MP3, AAC, Opus, H.264, AV1, JPEG...) sont CONNUS du registre : les
# demander lève UnsupportedError avec une explication, au lieu de simuler une compatibilité.
#
#   use multimedia.codec.registry as reg
#   dec := reg.decoder("pcm_s16le")           # fonction (octets, format) -> échantillons
#   x := dec(octets, fmt)
#   img := reg.decoder("png")(octets)          # Image
#   reg.register("opus", "audio", mon_decodeur, null, "optionnel")
#   print(reg.find("h264"))                    # {"name": "h264", "decode": false, ... "note": "..."}
#
# Erreurs : UnsupportedError (codec connu non disponible, ou inconnu), FormatError (déclaration invalide).

from core use len, type
from collections use append, keys
use audio.audio_format as _af
use multimedia.core.errors as merr
use multimedia.image.decode as _idec
use multimedia.image.encode as _ienc
use multimedia.metadata.subtitles as _subs
use multimedia.codec.audio.flac as _flac
use multimedia.codec.audio.flac_encoder as _flace

const ORIGINS := ["intégré", "système", "optionnel"]

_codecs := {}

func _entry(name, kind, decoder, encoder, origin, note=null, licence=null):
    if not (origin in ORIGINS):
        merr.fail(merr.FORMAT, "origine de codec inconnue : " + str(origin))
    if not (kind in ["audio", "video", "image", "subtitle"]):
        merr.fail(merr.FORMAT, "genre de codec inconnu : " + str(kind))
    return {"name": name, "kind": kind, "decoder": decoder, "encoder": encoder, "origin": origin,
            "decode": decoder != null, "encode": encoder != null, "note": note, "licence": licence}

func register(name, kind, decoder=null, encoder=null, origin="optionnel", note=null, licence=null):
    if type(name) != "str" or len(name) == 0:
        merr.fail(merr.FORMAT, "nom de codec invalide")
    _codecs[name] = _entry(name, kind, decoder, encoder, origin, note, licence)
    return _codecs[name]

# Retire un codec (un codec intégré retiré n'est plus proposé jusqu'au redémarrage du programme).
func unregister(name):
    if name in _codecs:
        _codecs[name] = null

func _pcm(sf):
    return [(data, fmt) => _af.decode(data, _af.AudioFormat(fmt.rate, fmt.channels, sf)),
            (samples, fmt) => _af.encode(samples, _af.AudioFormat(fmt.rate, fmt.channels, sf))]

func _builtins():
    for sf in _af.FORMATS:
        p := _pcm(sf)
        register("pcm_" + sf, "audio", p[0], p[1], "intégré", "PCM non compressé")
    register("flac", "audio", (b) => _flac.decode(b), (samples, fmt) => _flace.encode(_flace.from_float(samples, fmt.channels, _flace.bits_of(fmt)), fmt.rate, _flace.bits_of(fmt)),
             "intégré", "sans perte en ALEX (RFC 9639) : décodage, encodage (prédicteurs fixes, comme flac -1)")
    register("png", "image", (b) => _idec.decode_png(b), (img) => _ienc.encode_png(img), "intégré")
    register("bmp", "image", (b) => _idec.decode_bmp(b), (img) => _ienc.encode_bmp(img), "intégré")
    register("pnm", "image", (b) => _idec.decode_pnm(b), (img) => _ienc.encode_pnm(img), "intégré")
    register("subrip", "subtitle", (t) => _subs.parse_srt(t), (tr) => _subs.format_srt(tr), "intégré")
    register("webvtt", "subtitle", (t) => _subs.parse_vtt(t), (tr) => _subs.format_vtt(tr), "intégré")
    # connus, non fournis : la note dit pourquoi et comment les brancher
    for c in [["mp3", "audio"], ["aac", "audio"], ["opus", "audio"], ["vorbis", "audio"],
              ["alac", "audio"], ["pcm_alaw", "audio"], ["pcm_mulaw", "audio"], ["adpcm_ima", "audio"],
              ["h264", "video"], ["hevc", "video"], ["vp8", "video"], ["vp9", "video"], ["av1", "video"],
              ["mpeg2video", "video"], ["mjpeg", "video"], ["jpeg", "image"], ["gif", "image"], ["webp", "image"],
              ["tiff", "image"], ["avif", "image"]]:
        if not (c[0] in _codecs):
            lic := null
            if c[0] == "h264" or c[0] == "hevc" or c[0] == "aac":
                lic = "brevets possibles selon le pays et l'usage : vérifier avant distribution commerciale"
            register(c[0], c[1], null, null, "optionnel", "aucune implémentation intégrée ; brancher un dorsal avec register()", lic)

_builtins()

func names(kind=null):
    out := []
    for k in keys(_codecs):
        c := _codecs[k]
        if c != null and (kind == null or c["kind"] == kind):
            append(out, k)
    return out

func find(name):
    if name in _codecs and _codecs[name] != null:
        c := _codecs[name]
        return {"name": c["name"], "kind": c["kind"], "decode": c["decode"], "encode": c["encode"],
                "origin": c["origin"], "note": c["note"], "licence": c["licence"]}
    return null

func _need(name, what):
    c := null
    if name in _codecs:
        c = _codecs[name]
    if c == null:
        merr.unsupported("codec « " + str(name) + " »", "inconnu du registre")
    fn := c[what]
    if fn == null:
        verb := "décodage" if what == "decoder" else "encodage"
        merr.unsupported(verb + " " + name, c["note"] if c["note"] != null else "non disponible")
    return fn

func decoder(name):
    return _need(name, "decoder")

func encoder(name):
    return _need(name, "encoder")

func can_decode(name):
    return name in _codecs and _codecs[name] != null and _codecs[name]["decode"]

func can_encode(name):
    return name in _codecs and _codecs[name] != null and _codecs[name]["encode"]
