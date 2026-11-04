# ALEX STANDARD LIBRARY — multimedia.video.video_format
#
# Formats vidéo : VideoFormat (dimensions, format de points, cadence rationnelle) et tailles d'images, définis dans
# multimedia.core.format ; ce module les regroupe avec les cadences nommées pour l'espace « video ».
#
#   use multimedia.video.video_format as vfmt
#   f := vfmt.VideoFormat(1920, 1080, "yuv420p", 30000, 1001)
#   print(vfmt.named("29.97"), vfmt.PIXEL_FORMATS)

use multimedia.core.format as _mf
use multimedia.video.frame_rate as _fr

PIXEL_FORMATS := _mf.PIXEL_FORMATS

func VideoFormat(width, height, pixel_format="rgb24", rate_num=25, rate_den=1):
    return _mf.VideoFormat(width, height, pixel_format, rate_num, rate_den)

func image_bytes(width, height, pixel_format):
    return _mf.image_bytes(width, height, pixel_format)

func named(name):
    return _fr.named(name)

# Format vidéo d'une cadence nommée (« 25 », « 29.97 »...).
func with_rate(width, height, name, pixel_format="yuv420p"):
    r := _fr.named(name)
    return _mf.VideoFormat(width, height, pixel_format, r[0], r[1])
