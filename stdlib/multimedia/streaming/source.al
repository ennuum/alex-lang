# ALEX STANDARD LIBRARY — multimedia.streaming.source
#
# Réception d'un flux audio AMS1 : paquets -> tampon de gigue -> échantillons dans l'ordre, pertes comblées.
#   UdpAudioSource   écoute un port UDP ; démarre au premier paquet de configuration reçu ;
#   TcpAudioSource   accepte une connexion (serveur) ou lit une connexion donnée ;
#   PacketSource     à partir de datagrammes déjà reçus (tests, simulation de réseau).
# read(trames) -> flottants entrelacés ([] à la fin du flux ou après `idle_timeout` sans données) : même interface
# qu'une entrée audio, donc utilisable par Recorder, les pipelines ou le lecteur.
#
#   use multimedia.streaming.source as src
#   r := src.UdpAudioSource(5004, 3)             # port, délai du tampon (paquets)
#   x := r.read(480)
#   print(r.format.describe(), r.buffer.stats())

from core use len
from collections use append
use audio.audio_format as _af
use network.udp as _udp
use network.tcp as _tcp
use multimedia.core.errors as merr
use multimedia.streaming.network_stream as ns
use multimedia.streaming.buffering as jb

class _Depacketizer:
    func init(delay, capacity):
        self.format = null
        self.frames = 0
        self.buffer = jb.JitterBuffer(delay, capacity, "silence")
        self.pending = []
        self.ended = false
        self.invalid = 0
        self.eos_seq = null

    func feed(b):
        p := null
        try:
            p = ns.decode(b)
        catch e:
            self.invalid += 1
            return
        if (p.flags & ns.CONFIG) != 0:
            if self.format == null:
                c := ns.parse_config(p)
                self.format = c["format"]
                self.frames = c["frames"]
                self.buffer.silence = _af.encode([0.0 for i in 0..self.frames * self.format.channels], self.format)
            return
        if (p.flags & ns.EOS) != 0:
            self.eos_seq = p.seq
            return
        if self.format == null:
            return
        self.buffer.push(p)

    func _take():
        while true:
            p := self.buffer.pop()
            if p == null:
                return false
            for x in _af.decode(p.payload if p.payload != null else [], self.format):
                append(self.pending, x)
            return true

    func finish():
        for p in self.buffer.drain():
            for x in _af.decode(p.payload if p.payload != null else [], self.format):
                append(self.pending, x)
        self.ended = true

class PacketSource:
    func init(datagrams, delay=3, capacity=64):
        self.d = _Depacketizer(delay, capacity)
        for b in datagrams:
            self.d.feed(b)
        self.format = self.d.format
        self.buffer = self.d.buffer
        if self.format == null:
            merr.corrupt("AMS", "aucun paquet de configuration reçu")
        self.d.finish()

    func read(frames):
        n := frames * self.format.channels
        k := n if n < len(self.d.pending) else len(self.d.pending)
        out := [self.d.pending[i] for i in 0..k]
        self.d.pending = [self.d.pending[i] for i in k..len(self.d.pending)]
        return out

    func close():
        return null

class UdpAudioSource:
    func init(port, delay=3, capacity=64, host="127.0.0.1", idle_timeout=2.0, start_timeout=5.0):
        self.endpoint = _udp.bind(host, port)
        # tampon de réception agrandi (rafales ; 8 Kio par défaut sous Windows)
        try:
            self.endpoint.socket.set_option("receive_buffer", 1048576)
        catch e:
            pass
        self.port = self.endpoint.port()
        self.d = _Depacketizer(delay, capacity)
        self.buffer = self.d.buffer
        self.idle_timeout = idle_timeout
        self.start_timeout = start_timeout
        self.format = null
        self.closed = false

    func _receive(timeout):
        try:
            dg := self.endpoint.receive(timeout)
            self.d.feed(dg.bytes())
            return true
        catch e:
            if e.type == "TimeoutError":
                return false
            raise(e.type, e.message)

    # Attend le paquet de configuration (format du flux).
    func wait_config():
        while self.d.format == null:
            if not self._receive(self.start_timeout):
                merr.fail(merr.DEVICE, "aucun flux reçu sur le port " + str(self.port))
        self.format = self.d.format
        return self.format

    func read(frames):
        if self.format == null:
            self.wait_config()
        n := frames * self.format.channels
        while len(self.d.pending) < n and not self.d.ended:
            if self.d.eos_seq != null and self.buffer.size() == 0:
                self.d.ended = true
                break
            if self.d._take():
                continue
            if self.d.eos_seq != null:
                self.d.finish()
                break
            if not self._receive(self.idle_timeout):
                self.d.finish()
                break
        k := n if n < len(self.d.pending) else len(self.d.pending)
        out := [self.d.pending[i] for i in 0..k]
        self.d.pending = [self.d.pending[i] for i in k..len(self.d.pending)]
        return out

    func close():
        if not self.closed:
            self.endpoint.close()
            self.closed = true

class TcpAudioSource:
    func init(conn, idle_timeout=5.0):
        self.conn = conn
        self.buf = []
        self.d = _Depacketizer(0, 1024)
        self.buffer = self.d.buffer
        self.idle_timeout = idle_timeout
        self.format = null
        self.closed = false

    func _pull():
        chunk := null
        try:
            chunk = self.conn.read_bytes(65536, self.idle_timeout)
        catch e:
            return false
        if chunk == null or len(chunk) == 0:
            return false
        self.buf = self.buf + chunk
        r := ns.split_stream(self.buf)
        self.buf = r[1]
        for p in r[0]:
            self.d.feed(ns.encode(p))
        return true

    func read(frames):
        while self.d.format == null:
            if not self._pull():
                merr.fail(merr.DEVICE, "flux TCP terminé avant la configuration")
        self.format = self.d.format
        n := frames * self.format.channels
        while len(self.d.pending) < n and not self.d.ended:
            if self.d._take():
                continue
            if self.d.eos_seq != null or not self._pull():
                self.d.finish()
                break
        k := n if n < len(self.d.pending) else len(self.d.pending)
        out := [self.d.pending[i] for i in 0..k]
        self.d.pending = [self.d.pending[i] for i in k..len(self.d.pending)]
        return out

    func close():
        if not self.closed:
            self.conn.close()
            self.closed = true

# Serveur : attend une connexion sur `port` et la lit comme une source.
func accept_tcp(listener, timeout=10.0):
    return TcpAudioSource(listener.accept(timeout))
