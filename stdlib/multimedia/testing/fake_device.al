# ALEX STANDARD LIBRARY — multimedia.testing.fake_device
#
# Faux périphériques pour tester sans matériel, de façon reproductible :
#   FakeAudioOutput   même interface qu'une sortie audio (write, drain, close) : garde les échantillons, compte
#                     les écritures, simule une panne après N écritures, une latence (horloge manuelle) ;
#   FakeAudioInput    entrée qui fournit un signal généré (sinus, silence, bruit) par read(trames) ;
#   FakeCamera        images de test (mire, dégradé animé) avec horodatage, read() -> multimedia.image.Image.
#
#   use multimedia.testing.fake_device as fake
#   sortie := fake.FakeAudioOutput(fmt)
#   lecteur := mp.Player(sortie)
#   ...
#   print(sortie.frames(), sortie.writes, sortie.closed)
#   panne := fake.FakeAudioOutput(fmt, 3)      # DeviceError à la 4e écriture

from core use len, to_int
from collections use append
use audio.audio_effects as _fx
use multimedia.core.errors as merr
use multimedia.image.image as mi

class FakeAudioOutput:
    func init(fmt, fail_after=null, clock=null, latency=0.0):
        self.format = fmt
        self.samples = []
        self.writes = 0
        self.drains = 0
        self.closed = false
        self.fail_after = fail_after
        self.clock = clock
        self.latency = latency

    func write(samples):
        if self.closed:
            merr.state("sortie factice fermée")
        if self.fail_after != null and self.writes >= self.fail_after:
            merr.fail(merr.DEVICE, "sortie factice : panne simulée après " + str(self.fail_after) + " écritures")
        if len(samples) % self.format.channels != 0:
            merr.fail(merr.FORMAT, "écriture de trames incomplètes")
        for x in samples:
            append(self.samples, x)
        self.writes += 1
        if self.clock != null:
            self.clock.advance(1.0 * (len(samples) // self.format.channels) / self.format.rate)
        return len(samples)

    func drain():
        self.drains += 1
        if self.clock != null and self.latency > 0:
            self.clock.advance(self.latency)

    func close():
        self.closed = true

    func frames():
        return len(self.samples) // self.format.channels

    func duration():
        return 1.0 * self.frames() / self.format.rate

class FakeAudioInput:
    func init(fmt, signal="sine", frequency=440.0, seconds=1.0, volume=0.5):
        self.format = fmt
        n := to_int(seconds * fmt.rate)
        mono := []
        if signal == "sine":
            mono = _fx.sine(frequency, seconds, fmt.rate, volume)
        elif signal == "noise":
            mono = _fx.noise(seconds, fmt.rate, volume)
        else:
            mono = [0.0 for i in 0..n]
        data := []
        for x in mono:
            for c in 0..fmt.channels:
                append(data, x)
        self.data = data
        self.pos = 0
        self.closed = false

    func read(frames):
        if self.closed:
            merr.state("entrée factice fermée")
        n := frames * self.format.channels
        end := self.pos + n
        if end > len(self.data):
            end = len(self.data)
        out := [self.data[k] for k in self.pos..end]
        self.pos = end
        return out

    func close():
        self.closed = true

class FakeCamera:
    func init(width=64, height=48, fps=25, pattern="gradient", frames=null):
        self.width = width
        self.height = height
        self.fps = fps
        self.pattern = pattern
        self.limit = frames
        self.index = 0
        self.closed = false

    # Image suivante (mode rgb), ou null après `frames` images. L'image n bouge d'un point par image.
    func read():
        if self.closed:
            merr.state("caméra factice fermée")
        if self.limit != null and self.index >= self.limit:
            return null
        img := mi.Image(self.width, self.height, "rgb")
        shift := self.index
        for y in 0..self.height:
            for x in 0..self.width:
                if self.pattern == "checker":
                    v := 255 if (((x + shift) // 8) + (y // 8)) % 2 == 0 else 0
                    img.set(x, y, [v, v, v])
                else:
                    img.set(x, y, [((x + shift) * 255) // self.width % 256, (y * 255) // self.height, (self.index * 16) % 256])
        img.meta = {"index": self.index, "timestamp": 1.0 * self.index / self.fps}
        self.index += 1
        return img

    func close():
        self.closed = true
