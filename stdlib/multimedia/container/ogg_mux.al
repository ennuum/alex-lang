# ALEX STANDARD LIBRARY — multimedia.container.ogg_mux
#
# Écriture Ogg (RFC 3533) en ALEX pur :
#   - OggPageWriter : pages d'un flux logique, pour n'importe quel codec — découpage des paquets en segments de
#     255 octets (paquet de taille multiple de 255 terminé par un segment nul), paquet qui déborde sur la page
#     suivante (drapeau « continued »), granule de la page (celle du dernier paquet terminé, -1 si aucun), début et
#     fin de flux (BOS / EOS), CRC-32 Ogg ; pages d'environ 4 Kio ;
#   - OggFlacMuxer : Ogg FLAC (correspondance FLAC vers Ogg 1.0 de Xiph) — premier paquet « \x7FFLAC » + STREAMINFO
#     seul sur la page BOS, VORBIS_COMMENT, puis une trame FLAC par paquet (granule = échantillons écoulés) ;
#     STREAMINFO définitif (durée, MD5) réécrit dans la page BOS à la fermeture.
# Relu par multimedia.container.ogg (décodage au bit près) et par ffmpeg.
#
#   use multimedia.container.ogg_mux as om
#   m := om.OggFlacMuxer("sortie.oga", af.AudioFormat(44100, 2, "s16le"), tags)
#   m.write_samples(flottants_entrelaces)      # même interface que container.mux.WavMuxer
#   m.close()                                  # renvoie le nombre de trames FLAC
#   om.write_ogg_flac("x.oga", flottants, af.CD)
#
# Erreurs : FormatError (format), StateError (écriture après close).

from core use len, to_int
from collections use append
use io as _io
use os as _os
use string as _s
use multimedia.core.errors as merr
use multimedia.metadata.tags as tg
use multimedia.container.ogg as _ogg
use multimedia.codec.audio.flac_encoder as _fe
from multimedia.codec.audio.flac_encoder use FlacWriter

const PAGE_TARGET := 4096

func _le(v, n):
    return [(v >> (8 * i)) & 255 for i in 0..n]

# Page complète (octets) : drapeaux (1 continued, 2 BOS, 4 EOS), granule (-1 : aucun paquet terminé).
func build_page(serial, seq, granule, flags, segments, body):
    g := _le(granule, 8) if granule >= 0 else [255 for i in 0..8]
    out := _s.byte_unpack("OggS") + [0, flags] + g + _le(serial, 4) + _le(seq, 4) + [0, 0, 0, 0] + [len(segments)] + segments + body
    crc := _ogg.page_crc(out, 0, len(out))
    out[22] = crc & 255
    out[23] = (crc >> 8) & 255
    out[24] = (crc >> 16) & 255
    out[25] = (crc >> 24) & 255
    return out

# Numéro de série d'un nouveau flux logique (distinct d'un programme à l'autre ; aucune exigence cryptographique).
func new_serial():
    return (_os.pid() * 2654435761 + to_int(_os.monotonic_time() * 1000000)) & 0x7FFFFFFF

class OggPageWriter:
    # sink(octets) reçoit chaque page terminée.
    func init(sink, serial=null, target=PAGE_TARGET):
        self.sink = sink
        self.serial = serial if serial != null else new_serial()
        self.target = target
        self.seq = 0
        self.segments = []
        self.body = []
        self.granule = -1
        self.continued = false
        self.pages = 0
        self.closed = false

    func _page(eos, continues):
        flags := 0
        if self.continued:
            flags = flags | 1
        if self.seq == 0:
            flags = flags | 2
        if eos:
            flags = flags | 4
        p := build_page(self.serial, self.seq, self.granule, flags, self.segments, self.body)
        self.sink(p)
        self.seq += 1
        self.pages += 1
        self.segments = []
        self.body = []
        self.granule = -1
        self.continued = continues

    # Ajoute un paquet (octets) dont la fin correspond à la granule `granule` ; flush : termine la page après lui.
    func packet(data, granule, flush=false):
        if self.closed:
            merr.state("flux Ogg fermé")
        n := len(data)
        pos := 0
        while true:
            if len(self.segments) == 255:
                self._page(false, true)              # le paquet continue sur la page suivante
            seg := n - pos
            if seg > 255:
                seg = 255
            append(self.segments, seg)
            for k in pos..pos + seg:
                append(self.body, data[k])
            pos += seg
            if seg < 255:
                break
        self.granule = granule
        if flush or len(self.body) >= self.target:
            self._page(false, false)

    # Termine la page en cours (s'il y a des segments).
    func flush():
        if len(self.segments) > 0:
            self._page(false, false)

    # Dernière page, marquée EOS (vide si tout a déjà été écrit ; granule = celle du dernier paquet).
    func close(last_granule):
        if self.closed:
            return self.pages
        if len(self.segments) == 0:
            self.granule = last_granule
        self._page(true, false)
        self.closed = true
        return self.pages

# Premier paquet Ogg FLAC : 0x7F « FLAC » 1.0, nombre de paquets d'en-tête suivants, « fLaC », STREAMINFO.
func flac_first_packet(streaminfo, header_packets=1):
    return [0x7F] + _s.byte_unpack("FLAC") + [1, 0, (header_packets >> 8) & 255, header_packets & 255] + _s.byte_unpack("fLaC") + _fe._block_header(0, 34, false) + streaminfo

class OggFlacMuxer extends FlacWriter:
    func init(path, fmt, tags=null, block_size=_fe.DEFAULT_BLOCK, md5=true, serial=null):
        self._setup(fmt, block_size, md5)
        self.path = path
        self.tags = tags if tags != null else tg.Tags()
        self.granule = 0
        _io.write_bytes(path, [])
        self.pw = OggPageWriter((p) => _io.write_bytes_at(path, p, null), serial)
        first := flac_first_packet(self.core.info())
        self.pw.packet(first, 0, true)              # seul sur la page BOS (taille fixe : réécrite à la fermeture)
        vc := _fe._vorbis_comment(self.tags)
        self.pw.packet(_fe._block_header(4, len(vc), true) + vc, 0, true)

    func _put(frames):
        for f in frames:
            self.granule += f[1]
            self.pw.packet(f[0], self.granule)

    func close():
        if self.closed:
            return self.core.frames
        self._put(self.core.finish())
        self.pw.close(self.granule)
        # page BOS définitive : même taille, STREAMINFO complet (durée, tailles de trame, MD5)
        bos := build_page(self.pw.serial, 0, 0, 2, [51], flac_first_packet(self.core.info()))
        _io.write_bytes_at(self.path, bos, 0)
        self.closed = true
        return self.core.frames

# Écrit d'un coup des flottants entrelacés en Ogg FLAC ; renvoie le nombre de trames.
func write_ogg_flac(path, samples, fmt, tags=null, md5=true):
    m := OggFlacMuxer(path, fmt, tags, _fe.DEFAULT_BLOCK, md5)
    m.write_samples(samples)
    return m.close()
