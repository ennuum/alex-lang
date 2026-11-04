# ALEX STANDARD LIBRARY — multimedia.streaming.buffering
#
# Tampon de gigue (jitter buffer) pour les flux en direct : les paquets arrivent en désordre, en double ou
# jamais ; le tampon les remet dans l'ordre des numéros de séquence, attend `delay` paquets avant de
# commencer (absorbe la gigue), jette les doublons et les retardataires, et comble les pertes (silence ou
# répétition du dernier paquet). Numéros de séquence sur 32 bits avec bouclage.
#
#   use multimedia.streaming.buffering as jb
#   b := jb.JitterBuffer(4, 64, "silence")
#   b.push(paquet)                     # paquet : seq, payload (et ce qu'on veut)
#   p := b.pop()                       # paquet suivant dans l'ordre, un paquet de remplacement (p.concealed), ou null
#   print(b.stats())                   # reçus, perdus, en retard, doublons, réordonnés, remplacés
#
# Erreurs : FormatError (paramètres).

from core use len
from collections use append, keys
use multimedia.core.errors as merr

const WRAP := 4294967296

func seq_diff(a, b):
    d := (a - b) % WRAP
    if d >= WRAP // 2:
        d = d - WRAP
    return d

class StreamPacket:
    func init(seq, payload, timestamp=0, flags=0):
        self.seq = seq
        self.payload = payload
        self.timestamp = timestamp
        self.flags = flags
        self.concealed = false

class JitterBuffer:
    func init(delay=4, capacity=64, conceal="silence", silence=null):
        if delay < 0 or capacity <= delay:
            merr.fail(merr.FORMAT, "tampon de gigue : 0 <= délai < capacité")
        if conceal != "silence" and conceal != "repeat" and conceal != "skip":
            merr.fail(merr.FORMAT, "remplacement inconnu : " + str(conceal) + " (silence, repeat, skip)")
        self.delay = delay
        self.capacity = capacity
        self.conceal = conceal
        self.silence = silence
        self.slots = {}
        self.next_seq = null
        self.started = false
        self.last = null
        self.received = 0
        self.lost = 0
        self.late = 0
        self.duplicates = 0
        self.reordered = 0
        self.concealed = 0
        self.overflow = 0
        self.highest = null

    func size():
        return len(keys(self.slots))

    func push(p):
        self.received += 1
        if self.next_seq == null:
            self.next_seq = p.seq
            self.highest = p.seq
        d := seq_diff(p.seq, self.next_seq)
        if d < 0:
            self.late += 1
            return false
        if p.seq in self.slots:
            self.duplicates += 1
            return false
        if seq_diff(p.seq, self.highest) < 0:
            self.reordered += 1
        else:
            self.highest = p.seq
        if d >= self.capacity:
            # trop en avance : on saute la trou (perte massive, reconnexion)
            self.overflow += 1
            self.lost += d
            self.slots = {}
            self.next_seq = p.seq
            d = 0
        self.slots[p.seq] = p
        return true

    func ready():
        if not self.started:
            return self.size() > self.delay
        return self.size() > 0

    # Paquet suivant ; null s'il faut attendre (début du flux ou tampon vide).
    func pop():
        if not self.ready():
            return null
        self.started = true
        s := self.next_seq
        if s in self.slots:
            p := self.slots[s]
            rest := {}
            for k in keys(self.slots):
                if k != s:
                    rest[k] = self.slots[k]
            self.slots = rest
            self.next_seq = (s + 1) % WRAP
            self.last = p
            return p
        # perte : le suivant attendu est absent mais des paquets plus récents sont là
        self.lost += 1
        self.next_seq = (s + 1) % WRAP
        if self.conceal == "skip":
            return self.pop()
        self.concealed += 1
        payload := self.silence
        if self.conceal == "repeat" and self.last != null:
            payload = self.last.payload
        q := StreamPacket(s, payload, 0, 0)
        q.concealed = true
        return q

    # Vide tout ce qui reste (fin du flux), pertes comprises.
    func drain():
        out := []
        while self.size() > 0:
            self.started = true
            p := self.pop()
            if p == null:
                break
            append(out, p)
        return out

    func stats():
        return {"received": self.received, "lost": self.lost, "late": self.late, "duplicates": self.duplicates,
                "reordered": self.reordered, "concealed": self.concealed, "overflow": self.overflow, "buffered": self.size()}
