# ALEX STANDARD LIBRARY — hardware.microphone
#
# Microphones et entrées audio (Linux : ALSA, /proc/asound ; Windows : DirectShow par ffmpeg) et enregistrement dans un fichier WAV par
# l'outil du système (arecord, pw-record, parecord, ffmpeg, ou sox « rec »). Le WAV obtenu se lit avec
# hardware.audio.read_wav ; level() en donne le niveau.
#
# Exemple
#   use hardware.microphone as mic
#   if mic.available():
#       mic.record("voix.wav", 3)              # 3 secondes, 16 kHz mono
#       print(mic.level("voix.wav"))           # niveau efficace 0..1
#
# Erreurs : HardwareError (aucun outil d'enregistrement, échec), ArgumentError (paramètres).

from core use len, type, to_int
from collections use append
use string as _s
use os as _os
use process as _proc
use hardware._sys as _sys
use hardware._windows as _win
use hardware.audio as _audio

# Entrées audio (list de hardware.audio.AudioDevice avec capture).
func microphones():
    return _audio.inputs()

func available():
    return len(microphones()) > 0 and recorder() != null

_RECORDERS := ["arecord", "pw-record", "parecord", "ffmpeg", "rec"]

# Outil d'enregistrement disponible, ou null.
func recorder():
    return _sys.find_tool(_RECORDERS)

func _args(tool, path, seconds, rate, channels, device):
    a := []
    if tool == "arecord":
        append(a, "-q")
        if device != null:
            append(a, "-D")
            append(a, device)
        for x in ["-f", "S16_LE", "-r", str(rate), "-c", str(channels), "-d", str(to_int(seconds + 0.999)), path]:
            append(a, x)
    elif tool == "ffmpeg":
        inp := null
        if _win.is_windows():
            # DirectShow : device = AudioDevice.alsa_name(), « audio=... » ou nom affiché ; null : première entrée
            inp = _win.input_args(device, "audio")
            if inp == null:
                _sys.fail("microphone.record", "aucune entrée audio DirectShow")
            # -t coupe selon les instants de DirectShow, qui démarrent en retard à la première ouverture (jusqu'à
            # 200 ms perdus) : on compte plutôt les échantillons (instants renumérotés, puis coupe exacte).
            n := to_int(seconds * rate)
            return ["-loglevel", "error", "-y"] + inp + ["-af", "aresample=" + str(rate) + ",asetpts=N/SR/TB,atrim=end_sample=" + str(n),
                    "-ac", str(channels), path]
        inp = ["-f", "alsa", "-i", device if device != null else "default"]
        a = ["-loglevel", "error", "-y"] + inp + ["-t", str(seconds), "-ar", str(rate), "-ac", str(channels), path]
    elif tool == "rec":
        a = ["-q", "-r", str(rate), "-c", str(channels), "-b", "16", path, "trim", "0", str(seconds)]
    elif tool == "parecord":
        a = ["--file-format=wav", "--rate=" + str(rate), "--channels=" + str(channels), "--format=s16le"]
        if device != null:
            append(a, "--device=" + device)
        append(a, path)
    else:
        a = ["--rate=" + str(rate), "--channels=" + str(channels), "--format=s16"]
        if device != null:
            append(a, "--target=" + device)
        append(a, path)
    return a

# Enregistre seconds secondes dans path (WAV 16 bits). device : nom ALSA (« hw:1,0 ») ou du serveur de son.
# Renvoie path.
func record(path, seconds, rate=16000, channels=1, device=null):
    if type(seconds) != "int" and type(seconds) != "float" or seconds <= 0:
        raise("ArgumentError", "microphone.record : durée > 0 attendue")
    tool := recorder()
    if tool == null:
        _sys.fail("microphone.record", "aucun outil d'enregistrement (arecord, pw-record, parecord, ffmpeg ou rec)")
    args := _args(tool, path, seconds, rate, channels, device)
    if tool == "pw-record" or tool == "parecord":
        # Ces outils enregistrent jusqu'à leur arrêt : SIGINT au bout de la durée (le WAV est alors finalisé).
        p := _proc.spawn(tool, args)
        _os.sleep(seconds)
        p.kill("INT")
        p.wait()
        p.close()
    else:
        r := _proc.run(tool, args, null, seconds + 15)
        if r.code != 0:
            _sys.fail("microphone.record", tool + " a échoué (code " + str(r.code) + ") : " + _s.trim(r.stderr))
    if not _os.exists(path):
        _sys.fail("microphone.record", "aucun fichier produit")
    return path

# Niveau efficace (0..1) d'un enregistrement WAV.
func level(path):
    return _audio.rms(_audio.read_wav(path).samples)
