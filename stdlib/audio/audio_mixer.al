# ALEX STANDARD LIBRARY — audio.audio_mixer
#
# Table de mixage : des pistes (tampons ou sources) avec volume, panoramique, sourdine, solo, départ décalé
# et boucle ; le mixeur produit le mélange stéréo (ou mono) bloc par bloc, avec un volume général, un limiteur
# pour éviter l'écrêtage et des vumètres (crête, efficace) par piste et au total.
#
#   use audio.audio_mixer as am
#   m := am.Mixer(af.CD)
#   batterie := m.add("batterie", tampon_batterie)
#   voix := m.add("voix", tampon_voix, 0.8, -0.3)   # volume 0.8, un peu à gauche
#   voix.start = 2.0                                # entre à 2 s
#   m.master = 0.9
#   sortie := m.render()                            # AudioBuffer complet
#   flux := m.render_block(1024)                    # ou bloc par bloc (lecture en continu)

from core use len, to_int, type
from collections use append
use math
use audio.audio_format as af
use audio.audio_stream as ast
use audio.audio_effects as fx

class Track:
    func init(name, buffer, volume=1.0, pan=0.0):
        self.name = name
        self.buffer = buffer             # audio_stream.AudioBuffer (converti au format du mixeur)
        self.volume = volume
        self.pan = pan                   # -1 gauche .. 1 droite
        self.muted = false
        self.solo = false
        self.start = 0.0                 # secondes
        self.loop = false
        self.peak = 0.0
        self.rms = 0.0

    func gains():
        angle := (self.pan + 1.0) * math.PI / 4.0
        return [self.volume * math.cos(angle) * math.sqrt(2.0), self.volume * math.sin(angle) * math.sqrt(2.0)]

class Mixer:
    func init(fmt=null):
        self.format = af.named(fmt if fmt != null else af.CD)
        self.tracks = []
        self.master = 1.0
        self.limit = true
        self.position = 0                # trame courante (render_block)
        self.peak = 0.0
        self.rms = 0.0

    # Ajoute une piste (AudioBuffer ou list d'échantillons mono au format du mixeur).
    func add(name, source, volume=1.0, pan=0.0):
        buf := source
        if type_of_list(source):
            buf = ast.AudioBuffer(source, af.AudioFormat(self.format.rate, 1, "s16le"))
        mono := buf.convert(af.AudioFormat(self.format.rate, 1, buf.format.sample_format))
        t := Track(name, mono, volume, pan)
        append(self.tracks, t)
        return t

    func track(name):
        for t in self.tracks:
            if t.name == name:
                return t
        return null

    func remove(name):
        self.tracks = [t for t in self.tracks if t.name != name]

    func _audible(t):
        any_solo := false
        for x in self.tracks:
            if x.solo:
                any_solo = true
        if t.muted:
            return false
        return t.solo or not any_solo

    # Durée totale (secondes) : fin de la dernière piste non bouclée.
    func duration():
        d := 0.0
        for t in self.tracks:
            e := t.start + t.buffer.duration()
            if e > d:
                d = e
        return d

    # Mélange des trames [first, first + count) : échantillons entrelacés au format du mixeur.
    func _mix(first, count):
        ch := self.format.channels
        out := [0.0 for i in 0..count * ch]
        for t in self.tracks:
            if not self._audible(t):
                continue
            g := t.gains()
            src := t.buffer.samples
            n := len(src)
            if n == 0:
                continue
            offset := to_int(t.start * self.format.rate)
            p := 0.0
            s2 := 0.0
            heard := 0
            f := 0
            while f < count:
                k := first + f - offset
                if k >= 0 and (k < n or t.loop):
                    v := src[k % n]
                    if ch == 1:
                        out[f] = out[f] + v * t.volume
                    else:
                        out[f * ch] = out[f * ch] + v * g[0]
                        out[f * ch + 1] = out[f * ch + 1] + v * g[1]
                    a := v * t.volume
                    if a < 0:
                        a = -a
                    if a > p:
                        p = a
                    s2 += v * v * t.volume * t.volume
                    heard += 1
                f += 1
            t.peak = p
            t.rms = math.sqrt(s2 / heard) if heard > 0 else 0.0
        out = [x * self.master for x in out]
        if self.limit:
            out = fx.limiter(out, 0.95)
        self.peak = fx.peak(out)
        self.rms = fx.rms(out)
        return out

    # Tout le morceau (AudioBuffer).
    func render():
        frames := to_int(self.duration() * self.format.rate)
        return ast.AudioBuffer(self._mix(0, frames), self.format)

    # Bloc suivant de frames trames (lecture en continu) ; [] après la fin (sauf pistes en boucle).
    func render_block(frames):
        total := to_int(self.duration() * self.format.rate)
        looping := false
        for t in self.tracks:
            if t.loop:
                looping = true
        if self.position >= total and not looping:
            return []
        out := self._mix(self.position, frames)
        self.position += frames
        return out

    func rewind():
        self.position = 0

    # Joue le mélange sur la sortie (flux) par blocs.
    func play_to(stream, block=4096):
        self.rewind()
        while true:
            b := self.render_block(block)
            if len(b) == 0:
                break
            stream.write(b)
        stream.drain()

    func describe():
        lines := ["mixeur " + self.format.describe() + ", " + str(len(self.tracks)) + " pistes, volume " + str(self.master)]
        for t in self.tracks:
            etat := ""
            if t.muted:
                etat = " (muette)"
            if t.solo:
                etat = etat + " (solo)"
            append(lines, "  " + t.name + " : volume " + str(t.volume) + ", pan " + str(t.pan) + ", début " + str(t.start) + " s" + etat)
        out := lines[0]
        k := 1
        while k < len(lines):
            out = out + "\n" + lines[k]
            k += 1
        return out

func type_of_list(x):
    return type(x) == "list"
