# ALEX STANDARD LIBRARY — audio.audio_device
#
# Périphériques audio du système (Linux : ALSA /proc/asound, via hardware.audio) avec ouverture de flux :
# sorties (haut-parleurs, casques, HDMI) et entrées (micros), périphérique par défaut, formats proposés,
# outil de lecture / capture disponible.
#
#   use audio.audio_device as ad
#   for d in ad.outputs():
#       print(d.describe())                      # « hw:0,0 HDA Intel PCH : ALC257 Analog (sortie) »
#   out := ad.default_output().open(af.CD)       # audio_stream.PlayerStream
#   out.write(echantillons)
#   out.close()

from core use len
from collections use append
use hardware.audio as _ha
use hardware._sys as _sys
use audio.audio_format as af
use audio.audio_stream as ast

class AudioDevice:
    # info : hardware.audio.AudioDevice (null : périphérique par défaut du système).
    func init(info):
        self.info = info
        self.name = "défaut"
        self.card = null
        self.device = null
        self.playback = true
        self.capture = true
        if info != null:
            self.name = info.name
            self.card = info.card
            self.device = info.device
            self.playback = info.playback
            self.capture = info.capture

    func is_default():
        return self.info == null

    # Nom pour les outils (« hw:0,0 » / « plughw:0,0 » pour ALSA), ou null pour le défaut.
    func alsa_name(plug=true):
        if self.info == null:
            return null
        prefix := "plughw:" if plug else "hw:"
        return prefix + str(self.card) + "," + str(self.device)

    func open(fmt=null):
        if not self.playback:
            raise("HardwareError", "audio : " + self.name + " n'est pas une sortie")
        return ast.PlayerStream(fmt if fmt != null else af.CD, self.alsa_name())

    func open_input(fmt=null):
        if not self.capture:
            raise("HardwareError", "audio : " + self.name + " n'est pas une entrée")
        return ast.CaptureStream(fmt if fmt != null else af.VOICE, self.alsa_name())

    func describe():
        sens := []
        if self.playback:
            append(sens, "sortie")
        if self.capture:
            append(sens, "entrée")
        t := self.name
        if self.info != null:
            t = "hw:" + str(self.card) + "," + str(self.device) + " " + t
        out := t + " ("
        k := 0
        while k < len(sens):
            if k > 0:
                out = out + ", "
            out = out + sens[k]
            k += 1
        return out + ")"

func devices():
    return [AudioDevice(d) for d in _ha.devices()]

func outputs():
    return [d for d in devices() if d.playback]

func inputs():
    return [d for d in devices() if d.capture]

# Périphérique par défaut du système (son serveur : PipeWire / PulseAudio / ALSA « default »).
func default_output():
    return AudioDevice(null)

func default_input():
    return AudioDevice(null)

func player_available():
    return ast.player_command(af.CD) != null

func recorder_available():
    return ast.capture_command(af.VOICE) != null

# Cartes son (list de dict index, id, driver, name).
func cards():
    return _ha.cards()
