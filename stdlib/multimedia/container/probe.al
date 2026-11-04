# ALEX STANDARD LIBRARY — multimedia.container.probe
#
# Sondage d'un fichier multimédia : reconnaissance du conteneur par sa SIGNATURE (jamais par l'extension seule),
# pistes, durée, étiquettes, et indication honnête de ce qui est décodable ici.
#
#   analyse complète : WAV (PCM), FLAC, Ogg (FLAC, Vorbis, Opus, Speex, Theora), PNG, BMP, PNM, sous-titres SRT / WebVTT, listes M3U / PLS ;
#   en-têtes lus     : MP3 avec ID3v2 / ID3v1 (étiquettes),
#                      GIF et JPEG (dimensions) ;
#   reconnus         : MP4 / MOV / M4A, Matroska / WebM, AVI, AIFF, WebP, TIFF, MPEG-TS, MIDI.
# Un conteneur reconnu mais non analysé donne une MediaInfo sans piste décodable et un avertissement.
#
#   use multimedia.container.probe as probe
#   info := probe.probe("chanson.flac")
#   print(info.container, info.duration, info.decodable(), info.tags, info.warnings)
#   print(probe.identify(octets))              # "wav", "png", "flac", "mp4", ... ou null
#
# Erreurs : MediaError (fichier absent), LimitError, CorruptDataError (en-tête incohérent d'un format analysé).

from core use len
from collections use append
use io as _io
use os as _os
use string as _s
use multimedia.core.errors as merr
use multimedia.core.stream as ms
use multimedia.core.format as mf
use multimedia.security.limits as lim
use multimedia.container.demux as dmx
use multimedia.container.metadata as cmeta
use multimedia.image.decode as idec
use multimedia.image.metadata as imeta
use multimedia.metadata.subtitles as subs
use multimedia.metadata.tags as tg
use multimedia.backends.codecs.ffmpeg as _ff

const MIME := {"wav": "audio/wav", "flac": "audio/flac", "mp3": "audio/mpeg", "ogg": "audio/ogg",
    "mp4": "video/mp4", "matroska": "video/x-matroska", "webm": "video/webm", "avi": "video/x-msvideo",
    "aiff": "audio/aiff", "png": "image/png", "bmp": "image/bmp", "pnm": "image/x-portable-anymap",
    "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp", "tiff": "image/tiff", "srt": "application/x-subrip",
    "vtt": "text/vtt", "m3u": "audio/x-mpegurl", "pls": "audio/x-scpls", "mpegts": "video/mp2t", "midi": "audio/midi",
    "avif": "image/avif", "ico": "image/x-icon"}

func _is(b, at, text):
    t := _s.byte_unpack(text)
    if at + len(t) > len(b):
        return false
    for k in 0..len(t):
        if b[at + k] != t[k]:
            return false
    return true

func _text_start(b):
    # texte : début sans octet de contrôle (hors tabulation / retours)
    n := len(b) if len(b) < 512 else 512
    if n == 0:
        return ""
    for k in 0..n:
        c := b[k]
        if c < 9 or (c > 13 and c < 32 and c != 27):
            return null
    return _s.byte_pack([b[k] for k in 0..n])

# Nom du format d'après les premiers octets (au moins 16 conseillés, 512 pour les textes).
func identify(b):
    if _is(b, 0, "RIFF") and _is(b, 8, "WAVE"):
        return "wav"
    if _is(b, 0, "RIFF") and _is(b, 8, "AVI "):
        return "avi"
    if _is(b, 0, "RF64"):
        return "wav"
    if _is(b, 0, "fLaC"):
        return "flac"
    if _is(b, 0, "OggS"):
        return "ogg"
    if _is(b, 0, "ID3"):
        return "mp3"
    if len(b) >= 2 and b[0] == 255 and (b[1] & 0xE0) == 0xE0 and (b[1] & 0x06) != 0:
        return "mp3"
    if _is(b, 4, "ftyp"):
        return "mp4"
    if len(b) >= 4 and b[0] == 26 and b[1] == 69 and b[2] == 223 and b[3] == 163:
        if len(b) >= 40:
            for k in 0..len(b) - 4:
                if _is(b, k, "webm"):
                    return "webm"
        return "matroska"
    if _is(b, 0, "FORM") and (_is(b, 8, "AIFF") or _is(b, 8, "AIFC")):
        return "aiff"
    if _is(b, 0, "MThd"):
        return "midi"
    if len(b) >= 377 and b[0] == 0x47 and b[188] == 0x47 and b[376] == 0x47:
        return "mpegts"
    img := idec.detect(b)
    if img != null:
        return img
    t := _text_start(b)
    if t != null:
        tt := _s.trim(_s.replace(t, "﻿", ""))
        if _s.starts_with(tt, "WEBVTT"):
            return "vtt"
        if _s.starts_with(tt, "#EXTM3U"):
            return "m3u"
        if _s.starts_with(_s.lower(tt), "[playlist]"):
            return "pls"
        if _s.contains(tt, "-->"):
            return "srt"
    return null

func probe(path, limits=null):
    l := lim.of(limits)
    if not _os.isfile(path):
        merr.fail(merr.MEDIA, "fichier introuvable : " + str(path))
    size := _os.size(path)
    l.check_file_size(size)
    head := _io.read_bytes(path, 0, size if size < 65536 else 65536)
    kind := identify(head)
    if kind == null:
        info := ms.MediaInfo(path, "inconnu", size)
        info.warn("format non reconnu (signature inconnue)")
        return info
    if kind == "wav":
        d := dmx.WavDemuxer(path, l)
        d.close()
        return d.info
    info := ms.MediaInfo(path, kind, size)
    info.mime = MIME[kind] if kind in MIME else null
    if kind == "png" or kind == "bmp" or kind == "pnm" or kind == "gif" or kind == "jpeg":
        m := imeta.inspect(head if kind != "pnm" else _io.read_bytes(path))
        if m["width"] != null:
            l.check_dimensions(m["width"], m["height"])
        st := ms.StreamInfo(0, "image", kind)
        if m["width"] != null:
            st.format = mf.VideoFormat(m["width"], m["height"], "rgba32" if m["color"] == "rgba" else "rgb24")
        st.frames = 1
        st.decodable = kind in idec.SUPPORTED
        info.add_stream(st)
        info.tags = tg.Tags(m["text"]).to_dict()
        if not st.decodable:
            info.warn(kind + " : dimensions lues, décodage non pris en charge ici")
        return info
    if kind == "srt" or kind == "vtt":
        track := subs.load(path, l)
        st := ms.StreamInfo(0, "subtitle", "subrip" if kind == "srt" else "webvtt")
        st.duration = track.duration()
        st.frames = len(track.cues)
        st.decodable = true
        info.add_stream(st)
        return info
    if kind == "m3u" or kind == "pls":
        info.warn("liste de lecture : utiliser multimedia.playback.playlist")
        return info
    if kind == "flac" or kind == "ogg":
        d := dmx.open(path, l, "native_only")
        d.close()
        if kind == "ogg" and _ff.available():
            # pistes non FLAC : décodables par l'adaptateur système
            for st in d.info.streams:
                if not st.decodable and (st.kind == "audio" or st.kind == "video"):
                    st.decodable = true
            d.info.warnings = [w for w in d.info.warnings if not _s.contains(w, "non pris en charge ici")]
            if not d.info.decodable() or len(d.info.streams) > 0:
                d.info.warn("pistes non FLAC décodées par l'adaptateur système ffmpeg")
        return d.info
    if kind == "mp3":
        t := tg.Tags()
        id3 := cmeta.read_id3v2(head)
        if id3 != null:
            t.update(id3[0])
        if size >= 128:
            v1 := cmeta.read_id3v1(_io.read_bytes(path, size - 128, 128))
            if v1 != null:
                t.merge_missing(v1)
        if _ff.available():
            fi := _ff.probe(path, l)
            fi.container = "mp3"
            fi.mime = info.mime
            fi.tags = t.to_dict() if not t.is_empty() else fi.tags
            return fi
        st := ms.StreamInfo(0, "audio", "mp3")
        info.add_stream(st)
        info.tags = t.to_dict()
        info.warn("mp3 : étiquettes lues, décodage non pris en charge ici (installer ffmpeg)")
        return info
    if _ff.available():
        fi := _ff.probe(path, l)
        fi.container = kind
        fi.mime = info.mime
        return fi
    info.warn(kind + " : conteneur reconnu, analyse des pistes non prise en charge ici (installer ffmpeg)")
    return info

# Sondage tolérant d'une liste de fichiers : [MediaInfo ou null, erreur ou null] par fichier.
func probe_many(paths, limits=null):
    out := []
    for p in paths:
        try:
            append(out, [probe(p, limits), null])
        catch e:
            append(out, [null, e.type + " : " + e.message])
    return out
