# ALEX STANDARD LIBRARY — microphone.microphone_info
#
# Les microphones de la machine (Linux : entrées ALSA de /proc/asound) : nom, carte, périphérique, nom ALSA,
# pilote de la carte, branchement USB, et le micro par défaut du système (serveur de son).
#
#   use microphone.microphone_info as mi
#   for m in mi.microphones():
#       print(m.describe())                 # « plughw:1,0 USB Audio (carte 1, snd-usb-audio, USB) »
#   m := mi.default()

from core use len
from collections use append
use string as _s
use hardware._sys as _sys
use hardware.audio as _ha

class MicrophoneInfo:
    # card / device : numéros ALSA (null : micro par défaut du système).
    func init(card, device, name):
        self.card = card
        self.device = device
        self.name = name
        self.driver = null
        self.card_name = null
        self.usb = false
        if card != null:
            for c in _ha.cards():
                if c["index"] == card:
                    self.driver = c["driver"]
                    self.card_name = c["name"]
            self.usb = self.driver != null and _s.contains(_s.lower(self.driver), "usb")

    func is_default():
        return self.card == null

    func alsa_name(plug=true):
        if self.card == null:
            return null
        prefix := "plughw:" if plug else "hw:"
        return prefix + str(self.card) + "," + str(self.device)

    func describe():
        if self.card == null:
            return "micro par défaut du système"
        t := self.alsa_name() + " " + self.name + " (carte " + str(self.card)
        if self.driver != null:
            t = t + ", " + self.driver
        if self.usb:
            t = t + ", USB"
        return t + ")"

func microphones():
    return [MicrophoneInfo(d.card, d.device, d.name) for d in _ha.inputs()]

func default():
    return MicrophoneInfo(null, null, "défaut")

func available():
    return len(microphones()) > 0

# Micro dont le nom contient text (sans tenir compte de la casse), ou null.
func find(text):
    t := _s.lower(text)
    for m in microphones():
        if _s.contains(_s.lower(m.name), t):
            return m
        if m.card_name != null and _s.contains(_s.lower(m.card_name), t):
            return m
    return null
