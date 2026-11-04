# ALEX STANDARD LIBRARY — audio.audio_buffer
#
# Tampons audio de travail (échantillons flottants entrelacés) pour le traitement en flux :
#   RingBuffer     tampon CIRCULAIRE de capacité fixe (en trames) entre un producteur (capture, décodeur) et un
#                  consommateur (lecture, analyse) : écriture / lecture par trames, politique de débordement
#                  (« drop_oldest », « drop_new », « error »), compteurs de débordements et de sous-alimentations,
#                  latence en secondes
#   Reblocker      reçoit des morceaux de taille quelconque, rend des BLOCS de taille fixe (FFT, effets, envoi
#                  réseau), avec reste et vidage final complété de silence
#   ChannelSplitter / interleave / deinterleave : passage entrelacé <-> un tableau par canal
#
#   use audio.audio_buffer as ab
#   r := ab.RingBuffer(4096, 2, 48000)            # 4096 trames stéréo
#   r.write(echantillons)
#   bloc := r.read(512)                            # 512 trames (moins si le tampon en contient moins)
#   print(r.available(), r.latency(), r.overruns, r.underruns)
#   rb := ab.Reblocker(1024, 1)
#   for b in rb.push(morceau):                     # blocs complets de 1024 trames
#       traiter(b)
#   dernier := rb.flush()
#
# Erreurs : AudioBufferError (débordement avec la politique « error », trames incomplètes), ArgumentError.

from core use len, type
from collections use append

class RingBuffer:
    func init(capacity_frames, channels=1, rate=44100, policy="drop_oldest"):
        if capacity_frames < 1 or channels < 1:
            raise("ArgumentError", "RingBuffer : capacité et canaux >= 1 attendus")
        if not (policy in ["drop_oldest", "drop_new", "error"]):
            raise("ArgumentError", "RingBuffer : politique drop_oldest, drop_new ou error")
        self.channels = channels
        self.rate = rate
        self.capacity = capacity_frames
        self.policy = policy
        self.data = [0.0 for i in 0..capacity_frames * channels]
        self.start = 0          # trame la plus ancienne
        self.count = 0          # trames présentes
        self.overruns = 0
        self.underruns = 0
        self.written = 0
        self.read_total = 0

    func available():
        return self.count

    func free():
        return self.capacity - self.count

    func latency():
        return self.count / self.rate

    func is_empty():
        return self.count == 0

    func is_full():
        return self.count == self.capacity

    # Écrit des trames (échantillons entrelacés) ; nombre de trames réellement écrites.
    func write(samples):
        c := self.channels
        if len(samples) % c != 0:
            raise("AudioBufferError", "RingBuffer.write : trames incomplètes (" + str(len(samples)) + " échantillons, " + str(c) + " canaux)")
        frames := len(samples) // c
        f := 0
        written := 0
        while f < frames:
            if self.count == self.capacity:
                self.overruns += 1
                if self.policy == "error":
                    raise("AudioBufferError", "RingBuffer : tampon plein (" + str(self.capacity) + " trames)")
                if self.policy == "drop_new":
                    break
                self.start = (self.start + 1) % self.capacity
                self.count -= 1
            pos := (self.start + self.count) % self.capacity
            k := 0
            while k < c:
                self.data[pos * c + k] = samples[f * c + k]
                k += 1
            self.count += 1
            written += 1
            f += 1
        self.written += written
        return written

    # Lit au plus frames trames ; avec pad, complète de silence (et compte une sous-alimentation).
    func read(frames, pad=false):
        c := self.channels
        n := frames
        if n > self.count:
            n = self.count
            if frames > 0:
                self.underruns += 1
        out := []
        f := 0
        while f < n:
            pos := (self.start + f) % self.capacity
            k := 0
            while k < c:
                append(out, self.data[pos * c + k])
                k += 1
            f += 1
        self.start = (self.start + n) % self.capacity
        self.count -= n
        self.read_total += n
        if pad:
            while len(out) < frames * c:
                append(out, 0.0)
        return out

    func peek(frames):
        c := self.channels
        n := frames
        if n > self.count:
            n = self.count
        out := []
        f := 0
        while f < n:
            pos := (self.start + f) % self.capacity
            k := 0
            while k < c:
                append(out, self.data[pos * c + k])
                k += 1
            f += 1
        return out

    func clear():
        self.start = 0
        self.count = 0

    func stats():
        return {"capacity": self.capacity, "available": self.count, "overruns": self.overruns,
                "underruns": self.underruns, "written": self.written, "read": self.read_total, "latency": self.latency()}

class Reblocker:
    func init(block_frames, channels=1):
        if block_frames < 1:
            raise("ArgumentError", "Reblocker : taille de bloc >= 1")
        self.block = block_frames
        self.channels = channels
        self.pending = []
        self.blocks = 0

    func push(samples):
        for x in samples:
            append(self.pending, x)
        out := []
        size := self.block * self.channels
        while len(self.pending) >= size:
            append(out, self.pending[:size])
            self.pending = self.pending[size:]
            self.blocks += 1
        return out

    func pending_frames():
        return len(self.pending) // self.channels

    # Dernier bloc partiel complété de silence (null s'il ne reste rien).
    func flush():
        if len(self.pending) == 0:
            return null
        b := self.pending[:]
        while len(b) < self.block * self.channels:
            append(b, 0.0)
        self.pending = []
        self.blocks += 1
        return b

func deinterleave(samples, channels):
    if len(samples) % channels != 0:
        raise("AudioBufferError", "deinterleave : trames incomplètes")
    out := [[] for c in 0..channels]
    i := 0
    while i < len(samples):
        append(out[i % channels], samples[i])
        i += 1
    return out

func interleave(planes):
    if len(planes) == 0:
        return []
    n := len(planes[0])
    for p in planes:
        if len(p) != n:
            raise("AudioBufferError", "interleave : canaux de longueurs différentes")
    out := []
    i := 0
    while i < n:
        for p in planes:
            append(out, p[i])
        i += 1
    return out

class ChannelSplitter:
    func init(channels):
        self.channels = channels

    func split(samples):
        return deinterleave(samples, self.channels)

    func merge(planes):
        return interleave(planes)

    func channel(samples, index):
        if index < 0 or index >= self.channels:
            raise("ArgumentError", "canal " + str(index) + " hors de 0.." + str(self.channels - 1))
        return [samples[i] for i in 0..len(samples) if i % self.channels == index]
