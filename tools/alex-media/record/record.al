# alex-media record : enregistre le microphone (ou une source de test) dans un fichier.
#   alex run tools/alex-media/alex-media.al -- record sortie.wav [--seconds 5] [--rate 48000] [--channels 1]
#                                                              [--until-silence] [--test-tone]
from core use len, to_int, to_float
use audio.audio_format as af
use multimedia.recording.recorder as rec
use multimedia.recording.microphone as mic
use multimedia.testing.fake_device as fake

func _opt(args, name, default):
    for i in 0..len(args) - 1:
        if args[i] == name:
            return args[i + 1]
    return default

func main(args):
    if len(args) == 0 or args[0] == "--help":
        print("usage : alex-media record sortie [--seconds S] [--rate N] [--channels N] [--until-silence] [--test-tone]")
        return 2
    dst := args[0]
    secs := to_float(_opt(args, "--seconds", "5"))
    fmt := af.AudioFormat(to_int(_opt(args, "--rate", "48000")), to_int(_opt(args, "--channels", "1")), "s16le")
    src := null
    if "--test-tone" in args:
        src = fake.FakeAudioInput(fmt, "sine", 440.0, secs)
    else:
        if not mic.available():
            print("alex-media record : aucun microphone utilisable (" + str(mic.diagnose()["advice"]) + ") ; --test-tone pour essayer sans micro")
            return 1
        src = mic.open(fmt)
    r := rec.Recorder(src, fmt, dst)
    r.on_level = null
    st := null
    if "--until-silence" in args:
        st = r.record_until_silence(secs)
    else:
        st = r.record(secs)
    print(dst + " : " + str(st["duration"]) + " s, crête " + str(st["peak_db"]) + " dBFS, arrêt : " + str(st["stopped_by"]))
    return 0
