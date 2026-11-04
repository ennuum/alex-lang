# ALEX STANDARD LIBRARY — multimedia.core.format
#
# Description des formats bruts :
#   - genres de pistes : « audio », « video », « image », « subtitle », « data » ;
#   - audio : AudioFormat du paquet audio (fréquence, canaux, u8 / s16le / s24le / s32le / f32le) ;
#   - vidéo et images : VideoFormat (largeur, hauteur, format de points, cadence rationnelle) ;
#   - formats de points : gray8, rgb24, bgr24, rgba32, bgra32, yuyv422, nv12, yuv420p (taille d'une image).
#
#   use multimedia.core.format as mf
#   v := mf.VideoFormat(1280, 720, "yuv420p", 30000, 1001)
#   print(v.frame_bytes(), v.fps(), v.describe())     # 1382400 29.97... 1280x720 yuv420p 29.97 i/s
#   a := mf.audio(48000, 2, "f32le")                  # audio.audio_format.AudioFormat
#
# Erreurs : FormatError (dimensions, cadence, format de points inconnu).

from core use len, type, to_int, gcd
use audio.audio_format as _af
use multimedia.core.errors as merr

const KINDS := ["audio", "video", "image", "subtitle", "data"]

# Format de points -> [bits par point (moyenne), nombre de plans, a de l'alpha].
const PIXEL_FORMATS := {"gray8": [8, 1, false], "rgb24": [24, 1, false], "bgr24": [24, 1, false],
    "rgba32": [32, 1, true], "bgra32": [32, 1, true], "yuyv422": [16, 1, false], "nv12": [12, 2, false],
    "yuv420p": [12, 3, false]}

func check_kind(kind):
    if not (kind in KINDS):
        merr.fail(merr.FORMAT, "genre de piste inconnu : " + str(kind))
    return kind

func check_pixel_format(pf):
    if not (pf in PIXEL_FORMATS):
        merr.fail(merr.FORMAT, "format de points inconnu : " + str(pf))
    return pf

# Octets d'une image width x height dans ce format (les formats 4:2:0 exigent des dimensions paires).
func image_bytes(width, height, pf):
    check_pixel_format(pf)
    if pf == "yuv420p" or pf == "nv12":
        if width % 2 != 0 or height % 2 != 0:
            merr.fail(merr.FORMAT, pf + " exige des dimensions paires : " + str(width) + "x" + str(height))
        return width * height + 2 * ((width // 2) * (height // 2))
    if pf == "yuyv422" and width % 2 != 0:
        merr.fail(merr.FORMAT, "yuyv422 exige une largeur paire : " + str(width))
    return width * height * PIXEL_FORMATS[pf][0] // 8

func has_alpha(pf):
    return PIXEL_FORMATS[check_pixel_format(pf)][2]

class VideoFormat:
    func init(width, height, pixel_format="rgb24", rate_num=25, rate_den=1):
        if type(width) != "int" or type(height) != "int" or width <= 0 or height <= 0:
            merr.fail(merr.FORMAT, "dimensions invalides : " + str(width) + "x" + str(height))
        if type(rate_num) != "int" or type(rate_den) != "int" or rate_num <= 0 or rate_den <= 0:
            merr.fail(merr.FORMAT, "cadence invalide : " + str(rate_num) + "/" + str(rate_den))
        check_pixel_format(pixel_format)
        g := gcd(rate_num, rate_den)
        self.width = width
        self.height = height
        self.pixel_format = pixel_format
        self.rate_num = rate_num // g
        self.rate_den = rate_den // g

    func fps():
        return 1.0 * self.rate_num / self.rate_den

    func frame_bytes():
        return image_bytes(self.width, self.height, self.pixel_format)

    func pixels():
        return self.width * self.height

    # Durée d'une image, en secondes.
    func frame_duration():
        return 1.0 * self.rate_den / self.rate_num

    func with_size(width, height):
        return VideoFormat(width, height, self.pixel_format, self.rate_num, self.rate_den)

    func equals(o):
        return self.width == o.width and self.height == o.height and self.pixel_format == o.pixel_format and self.rate_num == o.rate_num and self.rate_den == o.rate_den

    func describe():
        f := to_int(self.fps() * 100 + 0.5)
        fs := str(f // 100)
        if f % 100 != 0:
            r := f % 100
            fs = fs + "." + ("0" if r < 10 else "") + str(r)
        return str(self.width) + "x" + str(self.height) + " " + self.pixel_format + " " + fs + " i/s"

func audio(rate=44100, channels=2, sample_format="s16le"):
    try:
        return _af.AudioFormat(rate, channels, sample_format)
    catch e:
        merr.fail(merr.FORMAT, e.message)

func video(width, height, pixel_format="rgb24", rate_num=25, rate_den=1):
    return VideoFormat(width, height, pixel_format, rate_num, rate_den)

# Débit brut d'un format audio (octets/s).
func audio_byte_rate(fmt):
    return fmt.bytes_per_second()

# Débit brut d'un format vidéo non compressé (octets/s).
func video_byte_rate(vf):
    return vf.frame_bytes() * vf.rate_num // vf.rate_den
