# alex-media convert : convertit un fichier audio (WAV, FLAC, Ogg... ou tout format lisible par ffmpeg) vers WAV
# (intégré) ou un format ffmpeg ; ou une image (PNG, BMP, PNM) vers une autre, avec redimensionnement.
#   alex run tools/alex-media/alex-media.al -- convert entree sortie [--rate N] [--channels N] [--format s16le]
#                                                                  [--size LxH]
from core use len, to_int
use string as _s
use audio.audio_format as af
use multimedia.recording.export as ex
use multimedia.container.probe as probe
use multimedia.image.decode as dec
use multimedia.image.encode as enc
use multimedia.image.resize as rs

func _opt(args, name, default):
    for i in 0..len(args) - 1:
        if args[i] == name:
            return args[i + 1]
    return default

func main(args):
    pos := []
    i := 0
    while i < len(args):
        if _s.starts_with(args[i], "--"):
            i += 2
            continue
        pos = pos + [args[i]]
        i += 1
    if len(pos) != 2:
        print("usage : alex-media convert entree sortie [--rate N] [--channels N] [--format s16le|s24le|f32le] [--size LxH]")
        return 2
    src := pos[0]
    dst := pos[1]
    info := probe.probe(src)
    if info.has("image") and not info.has("audio"):
        img := dec.load(src)
        size := _opt(args, "--size", null)
        if size != null:
            wh := _s.split(size, "x")
            img = rs.resize(img, to_int(wh[0]), to_int(wh[1]))
        n := enc.save(img, dst)
        print(dst + " : " + img.describe() + ", " + str(n) + " octets")
        return 0
    a := info.first("audio")
    rate := to_int(_opt(args, "--rate", str(a.format.rate)))
    ch := to_int(_opt(args, "--channels", str(a.format.channels)))
    sf := _opt(args, "--format", "s16le")
    last := [-1]
    func show(p):
        pc := to_int(p * 100)
        if pc // 10 != last[0]:
            last[0] = pc // 10
            print("  " + str(pc) + " %")
    r := ex.transcode(src, dst, af.AudioFormat(rate, ch, sf), show)
    print(dst + " : " + str(r["frames_in"]) + " trames lues, " + af.AudioFormat(rate, ch, sf).describe())
    return 0
