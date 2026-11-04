# ALEX STANDARD LIBRARY — multimedia.core.buffer
#
# Unités de données qui circulent dans les pipelines :
#   - Packet : données ENCODÉES d'une piste (octets), pts, durée, image clé, fin de flux ;
#   - Frame  : données DÉCODÉES (échantillons audio flottants entrelacés, image, texte de sous-titre), avec leur
#              format, pts et durée ;
#   - RingBuffer : file circulaire bornée d'échantillons (audio temps réel) : écriture, lecture, politique de
#              débordement (« error », « drop_oldest », « drop_newest »), compteurs de pertes et de sous-alimentation.
#
#   use multimedia.core.buffer as mb
#   use multimedia.core.timestamp as ts
#   f := mb.audio_frame([0.0, 0.5], af.VOICE, ts.ZERO)
#   r := mb.RingBuffer(4096, "drop_oldest")
#   r.write(echantillons)
#   bloc := r.read(512)                 # au plus 512 échantillons ; r.underruns compte les lectures incomplètes
#   fin := mb.end_of_stream(0)          # Packet de fin de flux de la piste 0
#
# Erreurs : FormatError (capacité ou politique invalide), LimitError (débordement en politique « error »).

from core use len, type
from collections use append
use multimedia.core.errors as merr
use multimedia.core.timestamp as ts

class Packet:
    func init(stream_index, data, pts=null, duration=0, keyframe=true, eos=false):
        self.stream_index = stream_index
        self.data = data
        self.pts = pts if pts != null else ts.ZERO
        self.duration = duration
        self.keyframe = keyframe
        self.eos = eos

    func size():
        if self.data == null:
            return 0
        return len(self.data)

    func describe():
        if self.eos:
            return "paquet fin de flux (piste " + str(self.stream_index) + ")"
        return "paquet piste " + str(self.stream_index) + " " + str(self.size()) + " octets à " + ts.format_clock(self.pts.seconds())

func end_of_stream(stream_index=0):
    return Packet(stream_index, null, null, 0, false, true)

class Frame:
    func init(kind, data, fmt=null, pts=null, duration=0.0, eos=false):
        self.kind = kind
        self.data = data
        self.format = fmt
        self.pts = pts if pts != null else ts.ZERO
        self.duration = duration
        self.eos = eos
        self.meta = {}

    func seconds():
        return self.pts.seconds()

    func end_seconds():
        return self.pts.seconds() + self.duration

    # Nombre de trames audio (échantillons / canaux) ; 0 pour les autres genres.
    func frames():
        if self.kind != "audio" or self.data == null:
            return 0
        return len(self.data) // self.format.channels

    func describe():
        if self.eos:
            return "fin de flux " + self.kind
        return self.kind + " à " + ts.format_clock(self.seconds()) + " (" + str(self.duration) + " s)"

func audio_frame(samples, fmt, pts=null):
    if len(samples) % fmt.channels != 0:
        merr.fail(merr.FORMAT, str(len(samples)) + " échantillons : pas un nombre entier de trames de " + str(fmt.channels) + " canaux")
    return Frame("audio", samples, fmt, pts, 1.0 * (len(samples) // fmt.channels) / fmt.rate)

func end_frame(kind="audio"):
    return Frame(kind, null, null, null, 0.0, true)

const POLICIES := ["error", "drop_oldest", "drop_newest"]

class RingBuffer:
    func init(capacity, policy="error"):
        if type(capacity) != "int" or capacity <= 0:
            merr.fail(merr.FORMAT, "capacité de tampon invalide : " + str(capacity))
        if not (policy in POLICIES):
            merr.fail(merr.FORMAT, "politique de débordement inconnue : " + str(policy))
        self.capacity = capacity
        self.policy = policy
        self._data = [0.0 for i in 0..capacity]
        self._head = 0
        self._count = 0
        self.dropped = 0
        self.underruns = 0
        self.written = 0
        self.read_total = 0

    func available():
        return self._count

    func free():
        return self.capacity - self._count

    func is_empty():
        return self._count == 0

    func is_full():
        return self._count == self.capacity

    # Écrit des échantillons ; renvoie le nombre réellement conservé.
    func write(samples):
        n := len(samples)
        if n > self.free():
            if self.policy == "error":
                merr.fail(merr.LIMIT, "tampon circulaire plein : " + str(n) + " échantillons pour " + str(self.free()) + " places")
            if self.policy == "drop_newest":
                keep := self.free()
                self.dropped += n - keep
                self._push(samples, 0, keep)
                return keep
            excess := n - self.free()
            if excess >= self._count:
                self.dropped += self._count
                self._head = 0
                self._count = 0
                start := 0
                if n > self.capacity:
                    start = n - self.capacity
                    self.dropped += start
                self._push(samples, start, n)
                return n - start
            self._head = (self._head + excess) % self.capacity
            self._count -= excess
            self.dropped += excess
        self._push(samples, 0, n)
        return n

    func _push(samples, a, b):
        for k in a..b:
            self._data[(self._head + self._count) % self.capacity] = samples[k]
            self._count += 1
        self.written += b - a

    # Lit au plus n échantillons (moins si le tampon en contient moins : sous-alimentation comptée).
    func read(n):
        m := n
        if m > self._count:
            m = self._count
            self.underruns += 1
        out := []
        for k in 0..m:
            append(out, self._data[(self._head + k) % self.capacity])
        self._head = (self._head + m) % self.capacity
        self._count -= m
        self.read_total += m
        return out

    # Lit exactement n échantillons, complétés par du silence en cas de manque.
    func read_padded(n):
        out := self.read(n)
        while len(out) < n:
            append(out, 0.0)
        return out

    func clear():
        self._head = 0
        self._count = 0

    func stats():
        return {"capacity": self.capacity, "available": self._count, "dropped": self.dropped,
                "underruns": self.underruns, "written": self.written, "read": self.read_total}
