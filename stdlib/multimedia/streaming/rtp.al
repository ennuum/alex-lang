# ALEX STANDARD LIBRARY — multimedia.streaming.rtp
#
# Flux audio RTP standard (RFC 3550), en ALEX pur, interopérable avec ffmpeg, VLC, GStreamer et la téléphonie :
#   - paquets RTP : en-tête complet (version 2, bourrage, extension, CSRC, marqueur, type de charge utile, numéro
#     de séquence 16 bits, horodatage 32 bits, SSRC), décodage strict de données NON FIABLES ;
#   - charges utiles (RFC 3551 / RFC 3190) : L16 et L24 (PCM grand-boutiste), PCMU (G.711 loi µ) et PCMA (G.711
#     loi A) ; types statiques 0 (PCMU/8000), 8 (PCMA/8000), 10 (L16/44100/2), 11 (L16/44100/1), dynamiques sinon ;
#   - SDP (RFC 4566) : description à donner au récepteur (ffmpeg -i flux.sdp, VLC), et lecture d'une description ;
#   - RtpAudioSink : émission par UDP, paquets d'au plus `max_payload` octets (1200 : sous la MTU d'Internet) ;
#   - RtpAudioSource : réception, verrouillage sur la première source (SSRC), numéros de séquence étendus à 32 bits
#     (bouclage), tampon de gigue (désordre, doublons, pertes comblées), même interface qu'une entrée audio ;
#   - RtpPacketSource : à partir de datagrammes déjà reçus (tests, simulation de réseau).
# Pas de RTCP (rapports de réception) : les lecteurs courants n'en ont pas besoin pour un flux en direct.
#
#   use multimedia.streaming.rtp as rtp
#   tx := rtp.RtpAudioSink("192.168.1.20", 5004, af.AudioFormat(48000, 2, "s16le"))     # L16, type dynamique 96
#   io.write_file("flux.sdp", tx.sdp())          # puis : ffplay -protocol_whitelist file,udp,rtp flux.sdp
#   tx.write(bloc)
#   rx := rtp.RtpAudioSource(5004, null, "PCMU")  # p. ex. ffmpeg ... -acodec pcm_mulaw -f rtp rtp://hôte:5004
#   x := rx.read(160)
#
# Erreurs : CorruptDataError (paquet invalide), FormatError (codec, format), DeviceError (aucun flux reçu).

from core use len, type, to_int
from collections use append, keys
use string as _s
use os as _os
use audio.audio_format as _af
use network.udp as _udp
use multimedia.core.errors as merr
use multimedia.streaming.buffering as jb

const VERSION := 2
const CODECS := ["L16", "L24", "PCMU", "PCMA"]
# Types statiques de la RFC 3551 : [codec, fréquence, canaux].
const STATIC := {0: ["PCMU", 8000, 1], 8: ["PCMA", 8000, 1], 10: ["L16", 44100, 2], 11: ["L16", 44100, 1]}
const DYNAMIC := 96
const MAX_PAYLOAD := 1200
const RECEIVE_BUFFER := 1048576

# ------------------------------------------------------------------------------------------- paquets
class RtpPacket:
    func init(pt, seq, timestamp, ssrc, payload, marker=false, csrc=null, extension=null):
        self.pt = pt
        self.seq = seq
        self.timestamp = timestamp
        self.ssrc = ssrc
        self.payload = payload
        self.marker = marker
        self.csrc = csrc if csrc != null else []
        self.extension = extension          # null ou [profil (16 bits), octets (multiple de 4)]

func _be(v, n):
    return [(v >> (8 * (n - 1 - i))) & 255 for i in 0..n]

func _rbe(b, at, n):
    v := 0
    for k in 0..n:
        v = (v << 8) | b[at + k]
    return v

func encode(p):
    cc := len(p.csrc)
    if cc > 15:
        merr.fail(merr.FORMAT, "RTP : " + str(cc) + " CSRC (15 au plus)")
    if p.pt < 0 or p.pt > 127:
        merr.fail(merr.FORMAT, "RTP : type de charge utile " + str(p.pt))
    b0 := (VERSION << 6) | (16 if p.extension != null else 0) | cc
    out := [b0, (128 if p.marker else 0) | p.pt] + _be(p.seq & 0xFFFF, 2) + _be(p.timestamp & 0xFFFFFFFF, 4) + _be(p.ssrc & 0xFFFFFFFF, 4)
    for c in p.csrc:
        out = out + _be(c, 4)
    if p.extension != null:
        data := p.extension[1]
        if len(data) % 4 != 0:
            merr.fail(merr.FORMAT, "RTP : extension de " + str(len(data)) + " octets (multiple de 4)")
        out = out + _be(p.extension[0], 2) + _be(len(data) // 4, 2) + data
    return out + p.payload

# Paquet RTP depuis un datagramme (octets) ; CorruptDataError s'il est invalide.
func decode(b):
    n := len(b)
    if n < 12:
        merr.corrupt("RTP", "paquet de " + str(n) + " octets (12 au moins)")
    if (b[0] >> 6) != VERSION:
        merr.corrupt("RTP", "version " + str(b[0] >> 6))
    padding := (b[0] & 32) != 0
    ext := (b[0] & 16) != 0
    cc := b[0] & 15
    at := 12 + 4 * cc
    if at > n:
        merr.corrupt("RTP", "liste CSRC tronquée")
    csrc := [_rbe(b, 12 + 4 * i, 4) for i in 0..cc]
    extension := null
    if ext:
        if at + 4 > n:
            merr.corrupt("RTP", "en-tête d'extension tronqué")
        words := _rbe(b, at + 2, 2)
        if at + 4 + 4 * words > n:
            merr.corrupt("RTP", "extension tronquée")
        extension = [_rbe(b, at, 2), b[at + 4:at + 4 + 4 * words]]
        at += 4 + 4 * words
    end := n
    if padding:
        pad := b[n - 1]
        if pad == 0 or at + pad > n:
            merr.corrupt("RTP", "bourrage de " + str(pad) + " octets invalide")
        end = n - pad
    return RtpPacket(b[1] & 127, _rbe(b, 2, 2), _rbe(b, 4, 4), _rbe(b, 8, 4), b[at:end], (b[1] & 128) != 0, csrc, extension)

# ------------------------------------------------------------------------------------------- G.711
# Loi µ (ITU-T G.711) : entier 16 bits -> octet.
func mulaw_encode(v):
    sign := 0
    x := v
    if x < 0:
        x = -x
        sign = 0x80
    if x > 32635:
        x = 32635
    x += 0x84
    exp := 7
    mask := 0x4000
    while exp > 0 and (x & mask) == 0:
        exp -= 1
        mask = mask >> 1
    mant := (x >> (exp + 3)) & 0x0F
    return (sign | (exp << 4) | mant) ^ 0xFF

func mulaw_decode(u):
    u = u ^ 0xFF
    t := (((u & 0x0F) << 3) + 0x84) << ((u & 0x70) >> 4)
    return (0x84 - t) if (u & 0x80) != 0 else (t - 0x84)

# Loi A (ITU-T G.711).
func alaw_encode(v):
    sign := 0x80
    x := v
    if x < 0:
        x = -x - 1
        sign = 0
    if x > 32767:
        x = 32767
    out := 0
    if x < 256:
        out = x >> 4
    else:
        exp := 1
        y := x >> 8
        while y > 1 and exp < 7:
            y = y >> 1
            exp += 1
        out = (exp << 4) | ((x >> (exp + 3)) & 0x0F)
    return (sign | out) ^ 0x55

func alaw_decode(a):
    a = a ^ 0x55
    t := (a & 0x0F) << 4
    seg := (a & 0x70) >> 4
    if seg == 0:
        t += 8
    elif seg == 1:
        t += 0x108
    else:
        t = (t + 0x108) << (seg - 1)
    return t if (a & 0x80) != 0 else -t

_MULAW := [mulaw_decode(i) for i in 0..256]
_ALAW := [alaw_decode(i) for i in 0..256]

# ------------------------------------------------------------------------------------------- charges utiles
func bytes_per_sample(codec):
    if codec == "L16":
        return 2
    if codec == "L24":
        return 3
    if codec == "PCMU" or codec == "PCMA":
        return 1
    merr.unsupported("charge utile RTP « " + str(codec) + " »", "codecs : " + _s.join(", ", CODECS))

func _q(x, scale):
    v := x
    if v > 1.0:
        v = 1.0
    elif v < -1.0:
        v = -1.0
    n := to_int(v * scale + (0.5 if v >= 0 else -0.5))
    if n > scale - 1:
        return scale - 1
    if n < -scale:
        return -scale
    return n

# Flottants entrelacés -> charge utile.
func pack(samples, codec):
    out := []
    if codec == "L16":
        for x in samples:
            v := _q(x, 32768) & 0xFFFF
            append(out, v >> 8)
            append(out, v & 255)
    elif codec == "L24":
        for x in samples:
            v := _q(x, 8388608) & 0xFFFFFF
            append(out, v >> 16)
            append(out, (v >> 8) & 255)
            append(out, v & 255)
    elif codec == "PCMU":
        for x in samples:
            append(out, mulaw_encode(_q(x, 32768)))
    elif codec == "PCMA":
        for x in samples:
            append(out, alaw_encode(_q(x, 32768)))
    else:
        bytes_per_sample(codec)
    return out

# Charge utile -> flottants entrelacés (octets en trop ignorés).
func unpack(payload, codec):
    out := []
    n := len(payload)
    if codec == "L16":
        k := 0
        while k + 2 <= n:
            v := (payload[k] << 8) | payload[k + 1]
            append(out, (v - 65536 if v >= 32768 else v) / 32768.0)
            k += 2
    elif codec == "L24":
        k := 0
        while k + 3 <= n:
            v := (payload[k] << 16) | (payload[k + 1] << 8) | payload[k + 2]
            append(out, (v - 16777216 if v >= 8388608 else v) / 8388608.0)
            k += 3
    elif codec == "PCMU":
        for u in payload:
            append(out, _MULAW[u] / 32768.0)
    elif codec == "PCMA":
        for a in payload:
            append(out, _ALAW[a] / 32768.0)
    else:
        bytes_per_sample(codec)
    return out

# Type de charge utile pour codec / fréquence / canaux : statique s'il existe, sinon dynamique (96).
func payload_type(codec, rate, channels):
    for pt in keys(STATIC):
        s := STATIC[pt]
        if s[0] == codec and s[1] == rate and s[2] == channels:
            return pt
    return DYNAMIC

# ------------------------------------------------------------------------------------------- SDP
func build_sdp(host, port, codec, rate, channels, pt=null, name="ALEX"):
    p := pt if pt != null else payload_type(codec, rate, channels)
    lines := ["v=0", "o=- 0 0 IN IP4 " + host, "s=" + name, "c=IN IP4 " + host, "t=0 0",
              "m=audio " + str(port) + " RTP/AVP " + str(p),
              "a=rtpmap:" + str(p) + " " + codec + "/" + str(rate) + ("/" + str(channels) if channels != 1 else "")]
    return _s.join("\r\n", lines) + "\r\n"

# Description SDP -> {"port", "pt", "codec", "rate", "channels", "host"} (premier média audio).
func parse_sdp(text):
    out := {"port": null, "pt": null, "codec": null, "rate": null, "channels": 1, "host": null}
    for raw in _s.split(_s.replace(text, "\r", ""), "\n"):
        line := _s.trim(raw)
        if _s.starts_with(line, "c=IN IP4 ") or _s.starts_with(line, "c=IN IP6 "):
            out["host"] = _s.split(_s.slice(line, 9), "/")[0]
        elif _s.starts_with(line, "m=audio ") and out["port"] == null:
            w := [x for x in _s.split(line, " ") if x != ""]
            if len(w) >= 4:
                out["port"] = to_int(w[1])
                out["pt"] = to_int(w[3])
        elif _s.starts_with(line, "a=rtpmap:") and out["pt"] != null:
            rest := _s.slice(line, 9)
            sp := _s.find(rest, " ")
            if sp > 0 and to_int(_s.slice(rest, 0, sp)) == out["pt"]:
                parts := _s.split(_s.slice(rest, sp + 1), "/")
                out["codec"] = _s.upper(parts[0])
                if len(parts) > 1:
                    out["rate"] = to_int(parts[1])
                if len(parts) > 2:
                    out["channels"] = to_int(parts[2])
    if out["pt"] == null:
        merr.corrupt("SDP", "aucun média audio (ligne m=audio)")
    if out["codec"] == null and out["pt"] in STATIC:
        s := STATIC[out["pt"]]
        out["codec"] = s[0]
        out["rate"] = s[1]
        out["channels"] = s[2]
    if out["codec"] == null:
        merr.corrupt("SDP", "type de charge utile dynamique " + str(out["pt"]) + " sans a=rtpmap")
    return out

# ------------------------------------------------------------------------------------------- émission
func _random32():
    return (_os.pid() * 2654435761 + to_int(_os.monotonic_time() * 1000003)) & 0xFFFFFFFF

class RtpPacketizer:
    func init(fmt, codec="L16", pt=null, max_payload=MAX_PAYLOAD, frames=null, ssrc=null):
        f := _af.named(fmt)
        bps := bytes_per_sample(codec)
        if (codec == "PCMU" or codec == "PCMA") and f.rate != 8000:
            merr.fail(merr.FORMAT, codec + " : 8000 Hz seulement (G.711)")
        self.format = _af.AudioFormat(f.rate, f.channels, "s16le")
        self.codec = codec
        self.pt = pt if pt != null else payload_type(codec, f.rate, f.channels)
        cap := max_payload // (bps * f.channels)
        # 20 ms par paquet (habituel en RTP), sans dépasser la charge utile maximale
        self.frames = frames if frames != null else (f.rate // 50 if f.rate // 50 < cap else cap)
        if self.frames < 1 or self.frames * bps * f.channels > 65000:
            merr.fail(merr.FORMAT, "RTP : " + str(self.frames) + " trames par paquet")
        self.ssrc = ssrc if ssrc != null else _random32()
        r := _random32()
        self.seq = r & 0xFFFF
        self.timestamp = (r * 69069) & 0xFFFFFFFF
        self.pending = []
        self.sent = 0
        self.first = true

    func packets(samples, final=false):
        out := []
        for x in samples:
            append(self.pending, x)
        n := self.frames * self.format.channels
        start := 0
        total := len(self.pending)
        while total - start >= n or (final and total - start > 0):
            take := n if total - start >= n else total - start
            chunk := self.pending[start:start + take]
            append(out, encode(RtpPacket(self.pt, self.seq, self.timestamp, self.ssrc, pack(chunk, self.codec), self.first)))
            self.first = false
            self.seq = (self.seq + 1) & 0xFFFF
            self.timestamp = (self.timestamp + take // self.format.channels) & 0xFFFFFFFF
            self.sent += 1
            start += take
        self.pending = self.pending[start:]
        return out

class RtpAudioSink:
    # fmt : fréquence et canaux du flux ; codec : L16 (défaut), L24, PCMU, PCMA (8 kHz).
    func init(host, port, fmt, codec="L16", pt=null, max_payload=MAX_PAYLOAD, frames=null, ssrc=null):
        self.host = host
        self.port = port
        self.pk = RtpPacketizer(fmt, codec, pt, max_payload, frames, ssrc)
        self.format = self.pk.format
        self.endpoint = _udp.open(4)
        self.closed = false

    func sdp(name="ALEX"):
        return build_sdp(self.host, self.port, self.pk.codec, self.format.rate, self.format.channels, self.pk.pt, name)

    func write(samples):
        if self.closed:
            merr.state("émetteur RTP fermé")
        for d in self.pk.packets(samples):
            self.endpoint.send_to(d, self.host, self.port)
        return len(samples)

    func drain():
        return null

    func packets_sent():
        return self.pk.sent

    func close():
        if self.closed:
            return
        for d in self.pk.packets([], true):
            self.endpoint.send_to(d, self.host, self.port)
        self.endpoint.close()
        self.closed = true

# ------------------------------------------------------------------------------------------- réception
class _RtpDepacketizer:
    func init(codec, rate, channels, pt, delay, capacity):
        self.codec = codec
        self.pt = pt
        self.format = _af.AudioFormat(rate, channels, "s16le") if rate != null else null
        self.buffer = jb.JitterBuffer(delay, capacity, "silence")
        self.pending = []
        self.ssrc = null
        self.cycles = 0
        self.max_seq = null
        self.invalid = 0
        self.foreign = 0
        self.ended = false

    # Numéro de séquence étendu (RFC 3550, annexe A.1) : cycles de 65536 comptés au bouclage.
    func _extend(seq):
        if self.max_seq == null:
            self.max_seq = seq
            return seq
        d := (seq - self.max_seq) & 0xFFFF
        if d < 0x8000:
            if seq < self.max_seq:
                self.cycles += 65536
            self.max_seq = seq
            return self.cycles + seq
        # ancien paquet (désordre) : peut appartenir au cycle précédent
        if seq > self.max_seq and self.cycles > 0:
            return self.cycles - 65536 + seq
        return self.cycles + seq

    func feed(b):
        p := null
        try:
            p = decode(b)
        catch e:
            self.invalid += 1
            return
        if self.pt != null and p.pt != self.pt:
            self.foreign += 1
            return
        if self.ssrc == null:
            self.ssrc = p.ssrc
            if self.pt == null:
                self.pt = p.pt
                if self.codec == null:
                    if not (p.pt in STATIC):
                        merr.fail(merr.FORMAT, "RTP : type dynamique " + str(p.pt) + " : donner le codec ou une description SDP")
                    s := STATIC[p.pt]
                    self.codec = s[0]
                    if self.format == null:
                        self.format = _af.AudioFormat(s[1], s[2], "s16le")
        elif p.ssrc != self.ssrc:
            self.foreign += 1
            return
        if self.format == null:
            merr.fail(merr.FORMAT, "RTP : fréquence et canaux inconnus (donner fmt ou une description SDP)")
        if self.buffer.silence == null and len(p.payload) > 0:
            self.buffer.silence = pack([0.0 for i in 0..len(p.payload) // bytes_per_sample(self.codec)], self.codec)
        self.buffer.push(jb.StreamPacket(self._extend(p.seq) % jb.WRAP, p.payload, p.timestamp, 0))

    func _take():
        p := self.buffer.pop()
        if p == null:
            return false
        for x in unpack(p.payload if p.payload != null else [], self.codec):
            append(self.pending, x)
        return true

    func finish():
        for p in self.buffer.drain():
            for x in unpack(p.payload if p.payload != null else [], self.codec):
                append(self.pending, x)
        self.ended = true

    func take(n):
        k := n if n < len(self.pending) else len(self.pending)
        out := self.pending[0:k]
        self.pending = self.pending[k:]
        return out

# Paramètres de réception depuis fmt / codec / description SDP.
func _params(fmt, codec, sdp_text):
    if sdp_text != null:
        d := parse_sdp(sdp_text)
        return [d["codec"], d["rate"], d["channels"], d["pt"]]
    rate := null
    ch := null
    if fmt != null:
        f := _af.named(fmt)
        rate = f.rate
        ch = f.channels
    if codec != null:
        bytes_per_sample(codec)
        if (codec == "PCMU" or codec == "PCMA") and rate == null:
            rate = 8000
            ch = 1
    return [codec, rate, ch, null]

class RtpPacketSource:
    func init(datagrams, fmt=null, codec=null, sdp_text=null, delay=3, capacity=64):
        pr := _params(fmt, codec, sdp_text)
        self.d = _RtpDepacketizer(pr[0], pr[1], pr[2], pr[3], delay, capacity)
        for b in datagrams:
            self.d.feed(b)
        self.format = self.d.format
        self.buffer = self.d.buffer
        self.d.finish()

    func read(frames):
        return self.d.take(frames * self.format.channels)

    func close():
        return null

class RtpAudioSource:
    # port : port UDP local (0 : choisi par le système, voir .port) ; fmt / codec / sdp_text : ce que porte le
    # flux (inutile pour les types statiques 0, 8, 10, 11) ; delay : paquets d'avance du tampon de gigue.
    func init(port, fmt=null, codec=null, sdp_text=null, delay=3, capacity=64, host="127.0.0.1", idle_timeout=2.0, start_timeout=5.0):
        pr := _params(fmt, codec, sdp_text)
        self.d = _RtpDepacketizer(pr[0], pr[1], pr[2], pr[3], delay, capacity)
        self.endpoint = _udp.bind(host, port)
        # tampon de réception du système agrandi : un émetteur qui envoie par rafales (ffmpeg -re envoie d'emblée
        # 0,5 s) déborderait sinon le tampon par défaut (8 Kio sous Windows) et des paquets seraient perdus
        try:
            self.endpoint.socket.set_option("receive_buffer", RECEIVE_BUFFER)
        catch e:
            pass
        self.port = self.endpoint.port()
        self.buffer = self.d.buffer
        self.idle_timeout = idle_timeout
        self.start_timeout = start_timeout
        self.format = self.d.format
        self.closed = false

    func _receive(timeout):
        try:
            dg := self.endpoint.receive(timeout)
            self.d.feed(dg.bytes())
            return true
        catch e:
            if e.type == "TimeoutError":
                return false
            raise(e)

    # Attend le premier paquet (source, format pour un type statique).
    func wait_start():
        while self.d.ssrc == null:
            if not self._receive(self.start_timeout):
                merr.fail(merr.DEVICE, "aucun flux RTP reçu sur le port " + str(self.port))
        self.format = self.d.format
        return self.format

    # Trames suivantes (flottants entrelacés) ; [] à la fin (aucun paquet depuis idle_timeout secondes).
    func read(frames):
        if self.d.ssrc == null:
            self.wait_start()
        n := frames * self.format.channels
        while len(self.d.pending) < n and not self.d.ended:
            if self.d._take():
                continue
            if not self._receive(self.idle_timeout):
                self.d.finish()
                break
        return self.d.take(n)

    func stats():
        s := self.buffer.stats()
        s["invalid"] = self.d.invalid
        s["foreign"] = self.d.foreign
        return s

    func close():
        if not self.closed:
            self.endpoint.close()
            self.closed = true
