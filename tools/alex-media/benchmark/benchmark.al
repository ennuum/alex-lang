# alex-media benchmark : bancs de performance reproductibles (machine virtuelle ou exécutable natif) :
# décodage FLAC, PNG, WAV, rééchantillonnage, sonie EBU R128, pipeline. Résultat : facteur « temps réel »
# (durée du média / durée de traitement) ou débit, en texte ou TSV (--tsv).
#   alex run tools/alex-media/alex-media.al -- benchmark [--tsv] [--quick]
from core use len
use io
use time
use audio.audio_effects as afx
use multimedia.codec.audio.flac as flac
use multimedia.container.demux as dmx
use multimedia.image.decode as idec
use multimedia.image.encode as ienc
use multimedia.image.image as mi
use multimedia.audio.resampler as rsm
use multimedia.audio.meter as mt
use multimedia.pipeline.node as nd
use multimedia.pipeline.scheduler as ps

func _t(fn):
    t0 := time.monotonic()
    fn()
    return time.monotonic() - t0

func main(args):
    tsv := "--tsv" in args
    quick := "--quick" in args
    rows := []
    F := "tests/multimedia/fixtures/"
    data := io.read_bytes(F + "flac/st16_l5.flac")
    d := _t(() => flac.decode(data, null, false))
    rows = rows + [["flac 44,1 kHz stéréo", 0.3 / d, "x temps réel"]]
    w := _t(() => dmx.open(F + "media/st_s16le.wav").read_all())
    rows = rows + [["wav 11 kHz stéréo", 0.2 / w, "x temps réel"]]
    png := ienc.encode_png(mi.gradient(128, 128, "rgba"))
    p := _t(() => idec.decode(png))
    rows = rows + [["png 128x128 rgba", 128 * 128 / p / 1e6, "Mpoints/s"]]
    sig := afx.sine(440, 0.25 if quick else 1.0, 44100)
    secs := 0.25 if quick else 1.0
    r := _t(() => rsm.resample(sig, 44100, 48000, 1))
    rows = rows + [["rééchantillonnage sinc 44,1 -> 48 kHz", secs / r, "x temps réel"]]
    l := _t(() => mt.loudness(sig, 44100, 1))
    rows = rows + [["sonie EBU R128 mono", secs / l, "x temps réel"]]
    items := [i for i in 0..2000 if true]
    q := _t(() => ps.run_chain([nd.from_list("s", items), nd.map("m", (x) => x + 1), nd.collect("c")]))
    rows = rows + [["pipeline 3 nœuds", 2000 / q, "éléments/s"]]
    for row in rows:
        v := str(row[1])
        if tsv:
            print(row[0] + "\t" + v + "\t" + row[2])
        else:
            print(row[0] + " : " + v + " " + row[2])
    return 0
