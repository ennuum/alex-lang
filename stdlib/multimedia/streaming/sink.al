# ALEX STANDARD LIBRARY — multimedia.streaming.sink
#
# Émission d'un flux audio en direct au format AMS1 (multimedia.streaming.network_stream) :
#   UdpAudioSink  datagrammes vers hôte:port (paquet de configuration répété toutes les `config_every` paquets,
#                 pour qu'un récepteur qui arrive en cours de route puisse démarrer) ;
#   TcpAudioSink  connexion TCP (flux ordonné, configuration une fois) ;
#   MemorySink    paquets gardés en mémoire (tests, simulation de réseau : perte, désordre, doublons).
# write(échantillons) découpe en paquets de `frames` trames (PCM s16le), horodatés en échantillons.
#
#   use multimedia.streaming.sink as snk
#   s := snk.UdpAudioSink("127.0.0.1", 5004, af.AudioFormat(48000, 2, "s16le"), 480)
#   s.write(bloc)
#   s.close()                            # envoie le paquet de fin de flux

from core use len
from collections use append
use audio.audio_format as _af
use network.udp as _udp
use network.tcp as _tcp
use multimedia.core.errors as merr
use multimedia.streaming.network_stream as ns
use multimedia.streaming.buffering as jb

class _Packetizer:
    func init(fmt, frames):
        self.format = _af.AudioFormat(fmt.rate, fmt.channels, "s16le")
        self.frames = frames
        self.pending = []
        self.seq = 1
        self.timestamp = 0
        self.sent = 0

    func packets(samples, final=false):
        out := []
        for x in samples:
            append(self.pending, x)
        n := self.frames * self.format.channels
        while len(self.pending) >= n or (final and len(self.pending) > 0):
            take := n if len(self.pending) >= n else len(self.pending)
            chunk := [self.pending[k] for k in 0..take]
            self.pending = [self.pending[k] for k in take..len(self.pending)]
            append(out, jb.StreamPacket(self.seq, _af.encode(chunk, self.format), self.timestamp, ns.KEY))
            self.seq = (self.seq + 1) % jb.WRAP
            self.timestamp += take // self.format.channels
        return out

class MemorySink:
    func init(fmt, frames=480):
        self.pk = _Packetizer(fmt, frames)
        self.format = self.pk.format
        self.datagrams = [ns.encode(ns.config_packet(self.pk.format, frames))]
        self.closed = false

    func write(samples):
        for p in self.pk.packets(samples):
            append(self.datagrams, ns.encode(p))
        return len(samples)

    func close():
        if not self.closed:
            for p in self.pk.packets([], true):
                append(self.datagrams, ns.encode(p))
            append(self.datagrams, ns.encode(jb.StreamPacket(self.pk.seq, [], self.pk.timestamp, ns.EOS)))
            self.closed = true

class UdpAudioSink:
    func init(host, port, fmt, frames=480, config_every=50):
        self.host = host
        self.port = port
        self.pk = _Packetizer(fmt, frames)
        self.format = self.pk.format
        self.endpoint = _udp.open(4)
        self.config_every = config_every
        self.config = ns.encode(ns.config_packet(self.pk.format, frames))
        self.endpoint.send_to(self.config, host, port)
        self.count = 0
        self.closed = false

    func _send(p):
        self.endpoint.send_to(ns.encode(p), self.host, self.port)
        self.count += 1
        if self.config_every > 0 and self.count % self.config_every == 0:
            self.endpoint.send_to(self.config, self.host, self.port)

    func write(samples):
        if self.closed:
            merr.state("émetteur fermé")
        for p in self.pk.packets(samples):
            self._send(p)
        return len(samples)

    func drain():
        return null

    func close():
        if self.closed:
            return
        for p in self.pk.packets([], true):
            self._send(p)
        self.endpoint.send_to(ns.encode(jb.StreamPacket(self.pk.seq, [], self.pk.timestamp, ns.EOS)), self.host, self.port)
        self.endpoint.close()
        self.closed = true

class TcpAudioSink:
    func init(host, port, fmt, frames=480, timeout=5.0):
        self.pk = _Packetizer(fmt, frames)
        self.format = self.pk.format
        self.conn = _tcp.connect(host, port, timeout)
        self.conn.write_bytes(ns.encode(ns.config_packet(self.pk.format, frames)))
        self.closed = false

    func write(samples):
        if self.closed:
            merr.state("émetteur fermé")
        for p in self.pk.packets(samples):
            self.conn.write_bytes(ns.encode(p))
        return len(samples)

    func drain():
        return null

    func close():
        if self.closed:
            return
        for p in self.pk.packets([], true):
            self.conn.write_bytes(ns.encode(p))
        self.conn.write_bytes(ns.encode(jb.StreamPacket(self.pk.seq, [], self.pk.timestamp, ns.EOS)))
        self.conn.close()
        self.closed = true
