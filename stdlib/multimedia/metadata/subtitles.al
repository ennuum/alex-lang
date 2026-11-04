# ALEX STANDARD LIBRARY — multimedia.metadata.subtitles
#
# Sous-titres texte : lecture et écriture SubRip (.srt) et WebVTT (.vtt), décalage, changement d'échelle
# (conversion de cadence 25 <-> 23,976), contrôle (durées négatives, chevauchements), recherche des sous-titres
# actifs à un instant.
#
#   use multimedia.metadata.subtitles as subs
#   piste := subs.parse(texte)                     # détection SRT / WebVTT ; SubtitleTrack
#   for c in piste.cues:
#       print(c.start, c.end, c.text)
#   piste.shift(-1.5)                              # tout avance d'1,5 s (les instants restent >= 0)
#   piste.scale(25.0 / 23.976)                     # changement de cadence
#   print(subs.format_vtt(piste))
#   actifs := piste.at(62.3)                       # sous-titres affichés à 62,3 s
#   print(piste.problems())                        # ["#4 : fin avant le début", ...]
#
# Tolérant à l'écriture humaine (BOM, \r\n, lignes vides en trop, numéros manquants) mais strict sur les horodatages :
# une ligne « début --> fin » illisible lève CorruptDataError avec son numéro de ligne.
# Erreurs : CorruptDataError, LimitError (texte ou nombre de sous-titres), FormatError.

from core use len, type, to_int
from collections use append
use algorithm.sort as _sort
use string as _s
use io as _io
use multimedia.core.errors as merr
use multimedia.core.timestamp as ts
use multimedia.security.limits as lim

class Cue:
    func init(start, end, text, ident=null, settings=null):
        self.start = start
        self.end = end
        self.text = text
        self.ident = ident
        self.settings = settings

    func duration():
        return self.end - self.start

    func active(t):
        return t >= self.start and t < self.end

    # Texte sans balises (<i>, <b>, <c.classe>, {\an8}...).
    func plain_text():
        out := ""
        inside := false
        brace := false
        for c in _s.byte_unpack(self.text):
            if c == 60:
                inside = true
            elif c == 62 and inside:
                inside = false
            elif c == 123:
                brace = true
            elif c == 125 and brace:
                brace = false
            elif not inside and not brace:
                out = out + _s.byte_pack([c])
        return out

    func describe():
        return ts.format_clock(self.start) + " --> " + ts.format_clock(self.end) + " " + self.text

class SubtitleTrack:
    func init(cues=null, fmt=null):
        self.cues = cues if cues != null else []
        self.format = fmt
        self.header = null

    func add(start, end, text, ident=null):
        c := Cue(start, end, text, ident)
        append(self.cues, c)
        return c

    func sort_by_start():
        self.cues = _sort.sorted(self.cues, (c) => c.start)
        return self

    func at(t):
        return [c for c in self.cues if c.active(t)]

    # Prochain sous-titre qui commence après t (ou null).
    func next_after(t):
        best := null
        for c in self.cues:
            if c.start > t and (best == null or c.start < best.start):
                best = c
        return best

    func shift(seconds):
        for c in self.cues:
            c.start = c.start + seconds
            c.end = c.end + seconds
            if c.start < 0:
                c.start = 0.0
            if c.end < 0:
                c.end = 0.0
        return self

    func scale(factor):
        if factor <= 0:
            merr.fail(merr.FORMAT, "facteur d'échelle invalide : " + str(factor))
        for c in self.cues:
            c.start = c.start * factor
            c.end = c.end * factor
        return self

    func duration():
        m := 0.0
        for c in self.cues:
            if c.end > m:
                m = c.end
        return m

    func problems():
        out := []
        prev := null
        i := 1
        for c in self.cues:
            if c.end < c.start:
                append(out, "#" + str(i) + " : fin avant le début")
            elif c.end == c.start:
                append(out, "#" + str(i) + " : durée nulle")
            if len(_s.trim(c.text)) == 0:
                append(out, "#" + str(i) + " : texte vide")
            if prev != null and c.start < prev.end:
                append(out, "#" + str(i) + " : chevauche le précédent")
            prev = c
            i += 1
        return out

func _lines(text):
    t := text
    if _s.starts_with(t, "﻿"):
        t = _s.substring(t, 1, len(t))
    t = _s.replace(t, "\r\n", "\n")
    t = _s.replace(t, "\r", "\n")
    return _s.split(t, "\n")

func _timing(line, lineno, what):
    p := _s.find(line, "-->")
    if p < 0:
        return null
    a := _s.trim(_s.substring(line, 0, p))
    rest := _s.trim(_s.substring(line, p + 3, len(line)))
    settings := null
    sp := _s.find(rest, " ")
    b := rest
    if sp >= 0:
        b = _s.substring(rest, 0, sp)
        settings = _s.trim(_s.substring(rest, sp + 1, len(rest)))
    try:
        return [ts.parse_clock(a), ts.parse_clock(b), settings]
    catch e:
        merr.corrupt(what, "ligne " + str(lineno) + " : horodatage illisible « " + line + " »")

func _check_size(text, limits):
    l := lim.of(limits)
    l.check("max_text_bytes", _s.byte_len(text))
    return l

func _count(track, l):
    l.check("max_cues", len(track.cues))

func parse_srt(text, limits=null):
    l := _check_size(text, limits)
    track := SubtitleTrack([], "srt")
    lines := _lines(text)
    i := 0
    n := len(lines)
    while i < n:
        line := _s.trim(lines[i])
        if len(line) == 0:
            i += 1
            continue
        ident := null
        tm := _timing(line, i + 1, "SRT")
        if tm == null:
            ident = line
            i += 1
            if i >= n:
                break
            tm = _timing(_s.trim(lines[i]), i + 1, "SRT")
            if tm == null:
                merr.corrupt("SRT", "ligne " + str(i + 1) + " : « début --> fin » attendu après le numéro " + ident)
        i += 1
        body := []
        while i < n and len(_s.trim(lines[i])) > 0:
            append(body, _s.trim(lines[i]))
            i += 1
        c := track.add(tm[0], tm[1], _s.join("\n", body), ident)
        _count(track, l)
    return track

func parse_vtt(text, limits=null):
    l := _check_size(text, limits)
    lines := _lines(text)
    if len(lines) == 0 or not _s.starts_with(_s.trim(lines[0]), "WEBVTT"):
        merr.corrupt("WebVTT", "première ligne « WEBVTT » absente")
    track := SubtitleTrack([], "vtt")
    track.header = _s.trim(lines[0])
    i := 1
    n := len(lines)
    # en-têtes jusqu'à la première ligne vide
    while i < n and len(_s.trim(lines[i])) > 0:
        i += 1
    while i < n:
        line := _s.trim(lines[i])
        if len(line) == 0:
            i += 1
            continue
        if _s.starts_with(line, "NOTE") or _s.starts_with(line, "STYLE") or _s.starts_with(line, "REGION"):
            while i < n and len(_s.trim(lines[i])) > 0:
                i += 1
            continue
        ident := null
        tm := _timing(line, i + 1, "WebVTT")
        if tm == null:
            ident = line
            i += 1
            if i >= n:
                break
            tm = _timing(_s.trim(lines[i]), i + 1, "WebVTT")
            if tm == null:
                merr.corrupt("WebVTT", "ligne " + str(i + 1) + " : « début --> fin » attendu")
        i += 1
        body := []
        while i < n and len(_s.trim(lines[i])) > 0:
            append(body, _s.trim(lines[i]))
            i += 1
        c := track.add(tm[0], tm[1], _s.join("\n", body), ident)
        c.settings = tm[2]
        _count(track, l)
    return track

func detect(text):
    t := _s.trim(text)
    if _s.starts_with(t, "﻿"):
        t = _s.trim(_s.substring(t, 1, len(t)))
    if _s.starts_with(t, "WEBVTT"):
        return "vtt"
    if _s.contains(t, "-->"):
        return "srt"
    return null

func parse(text, limits=null):
    f := detect(text)
    if f == "vtt":
        return parse_vtt(text, limits)
    if f == "srt":
        return parse_srt(text, limits)
    merr.fail(merr.UNSUPPORTED, "multimédia : format de sous-titres non reconnu (SRT ou WebVTT attendus)")

func load(path, limits=null):
    return parse(_io.read_file(path), limits)

func format_srt(track):
    out := []
    i := 1
    for c in track.cues:
        append(out, str(i))
        append(out, ts.format_clock(c.start, ",") + " --> " + ts.format_clock(c.end, ","))
        append(out, c.text)
        append(out, "")
        i += 1
    return _s.join("\n", out)

func format_vtt(track):
    out := ["WEBVTT", ""]
    for c in track.cues:
        if c.ident != null and len(c.ident) > 0:
            append(out, c.ident)
        line := ts.format_clock(c.start) + " --> " + ts.format_clock(c.end)
        if c.settings != null and len(c.settings) > 0:
            line = line + " " + c.settings
        append(out, line)
        append(out, c.text)
        append(out, "")
    return _s.join("\n", out)

func save(track, path):
    if _s.ends_with(_s.lower(path), ".vtt"):
        _io.write_file(path, format_vtt(track))
    else:
        _io.write_file(path, format_srt(track))
