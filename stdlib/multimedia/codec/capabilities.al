# ALEX STANDARD LIBRARY — multimedia.codec.capabilities
#
# Tableau des capacités de décodage / encodage déclarées par le registre, par genre, avec l'origine et les notes
# (licence, raison de l'absence). Sert aux messages d'erreur, à la documentation et à `diagnostics`.
#
#   use multimedia.codec.capabilities as caps
#   print(caps.table())                    # [{"name": "png", "kind": "image", "decode": true, ...}, ...]
#   print(caps.decodable("audio"))         # ["pcm_f32le", "pcm_s16le", ...]
#   print(caps.missing("video"))           # ["av1", "h264", ...] : connus, non disponibles
#   print(caps.report())                   # texte lisible

from core use len
from collections use append
use string as _s
use algorithm.sort as _sort
use multimedia.codec.registry as reg

func table(kind=null):
    return [reg.find(n) for n in _sort.sorted(reg.names(kind))]

func decodable(kind=null):
    return [c["name"] for c in table(kind) if c["decode"]]

func encodable(kind=null):
    return [c["name"] for c in table(kind) if c["encode"]]

func missing(kind=null):
    return [c["name"] for c in table(kind) if not c["decode"] and not c["encode"]]

func report():
    out := []
    for kind in ["audio", "video", "image", "subtitle"]:
        out = out + [kind + " — décode : " + _s.join(", ", decodable(kind)) + " ; encode : " + _s.join(", ", encodable(kind)) + " ; non disponibles : " + _s.join(", ", missing(kind))]
    return _s.join("\n", out)
