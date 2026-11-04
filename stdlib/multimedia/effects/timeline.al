# ALEX STANDARD LIBRARY — multimedia.effects.timeline
#
# Montage : pistes audio et vidéo, clips placés sur une ligne de temps.
#   AudioClip  échantillons (ou fichier décodé à la demande), début sur la ligne de temps, rognage (in / out),
#              gain (dB), fondus d'entrée / de sortie, effet optionnel (multimedia.effects.audio_effect) ;
#   VideoClip  image fixe, liste de VideoFrame ou fonction t -> Image ; début, durée, opacité, position,
#              transition d'entrée (crossfade / wipe / dissolve) avec le plan précédent ;
#   Timeline   mixage audio d'un intervalle (render_audio), image composée à l'instant t (render_frame),
#              durée, export (multimedia.recording.export).
#
#   use multimedia.effects.timeline as tl
#   t := tl.Timeline(48000, 2, 640, 360, 25)
#   t.add_audio(tl.AudioClip(voix, fmt_voix, 0.0, -3.0, 0.2, 0.5))
#   t.add_video(tl.VideoClip(titre, 0.0, 3.0))
#   t.add_video(tl.VideoClip(photo, 2.5, 5.0, "crossfade", 0.5))
#   son := t.render_audio(0.0, 8.0)
#   img := t.render_frame(2.75)
#
# Erreurs : FormatError (clip invalide).

from core use len, to_int, is_function
from collections use append
use math as _m
use audio.audio_format as _af
use multimedia.core.errors as merr
use multimedia.image.image as mi
use multimedia.image.resize as rs
use multimedia.video.compositor as comp
use multimedia.effects.transitions as tr
use multimedia.image.convert as _cv

class AudioClip:
    func init(samples, fmt, start=0.0, gain_db=0.0, fade_in=0.0, fade_out=0.0, trim_in=0.0, trim_out=null, effect=null):
        if start < 0 or fade_in < 0 or fade_out < 0:
            merr.fail(merr.FORMAT, "clip audio : valeurs négatives")
        self.samples = samples
        self.format = _af.named(fmt)
        self.start = start
        self.gain = _m.pow(10.0, gain_db / 20.0)
        self.fade_in = fade_in
        self.fade_out = fade_out
        self.trim_in = trim_in
        total := 1.0 * (len(samples) // self.format.channels) / self.format.rate
        self.trim_out = trim_out if trim_out != null else total
        if self.trim_out > total:
            self.trim_out = total
        if self.trim_in >= self.trim_out:
            merr.fail(merr.FORMAT, "clip audio vide après rognage")
        self.effect = effect

    func duration():
        return self.trim_out - self.trim_in

    func end():
        return self.start + self.duration()

    # Échantillons du clip convertis au format de sortie, gain et fondus appliqués.
    func rendered(rate, channels):
        ch := self.format.channels
        a := to_int(self.trim_in * self.format.rate) * ch
        b := to_int(self.trim_out * self.format.rate) * ch
        x := [self.samples[k] for k in a..b]
        if ch != channels:
            x = _af.convert_channels(x, ch, channels)
        if self.format.rate != rate:
            x = _af.resample(x, self.format.rate, rate, channels)
        if self.effect != null:
            x = self.effect.process(x)
        n := len(x) // channels
        fi := to_int(self.fade_in * rate)
        fo := to_int(self.fade_out * rate)
        out := []
        for i in 0..n:
            g := self.gain
            if fi > 0 and i < fi:
                g = g * (i + 0.5) / fi
            if fo > 0 and i >= n - fo:
                g = g * (n - i - 0.5) / fo
            for c in 0..channels:
                append(out, x[i * channels + c] * g)
        return out

class VideoClip:
    func init(source, start=0.0, duration=null, transition=null, transition_time=0.0, opacity=1.0, x=0, y=0, fit=true):
        self.source = source
        self.start = start
        self.dur = duration
        self.transition = transition
        self.transition_time = transition_time
        self.opacity = opacity
        self.x = x
        self.y = y
        self.fit = fit
        if transition != null and not (transition in ["crossfade", "wipe", "dissolve", "slide"]):
            merr.fail(merr.FORMAT, "transition inconnue : " + str(transition))

    func duration():
        if self.dur != null:
            return self.dur
        if is_function(self.source):
            merr.fail(merr.FORMAT, "clip vidéo fonction : durée obligatoire")
        try:
            n := len(self.source)
            if n == 0:
                return 0.0
            last := self.source[n - 1]
            return last.pts + last.duration - self.source[0].pts
        catch e:
            return 5.0

    func end():
        return self.start + self.duration()

    func active(t):
        return t >= self.start and t < self.end()

    # Image du clip à l'instant t (temps de la ligne), ou null.
    func image_at(t):
        local := t - self.start
        if is_function(self.source):
            return self.source(local)
        try:
            w := self.source.width
            return self.source
        catch e:
            frames := self.source
            best := null
            for f in frames:
                if f.pts - frames[0].pts <= local + 1e-9:
                    best = f
            return best.image if best != null else null

class Timeline:
    func init(rate=48000, channels=2, width=640, height=360, fps=25, background=null):
        self.rate = rate
        self.channels = channels
        self.width = width
        self.height = height
        self.fps = fps
        self.background = background if background != null else [0, 0, 0]
        self.audio = []
        self.video = []

    func add_audio(clip):
        append(self.audio, clip)
        return clip

    func add_video(clip):
        append(self.video, clip)
        return clip

    func duration():
        m := 0.0
        for c in self.audio:
            if c.end() > m:
                m = c.end()
        for c in self.video:
            if c.end() > m:
                m = c.end()
        return m

    # Mixage de [start, end) : somme des clips, écrêtée à -1..1.
    func render_audio(start=0.0, end=null):
        e := end if end != null else self.duration()
        n := to_int((e - start) * self.rate + 0.5)
        out := [0.0 for i in 0..n * self.channels]
        for c in self.audio:
            if c.end() <= start or c.start >= e:
                continue
            x := c.rendered(self.rate, self.channels)
            off := to_int((c.start - start) * self.rate + 0.5)
            for i in 0..len(x) // self.channels:
                j := off + i
                if j < 0 or j >= n:
                    continue
                for ch in 0..self.channels:
                    out[j * self.channels + ch] = out[j * self.channels + ch] + x[i * self.channels + ch]
        return [(1.0 if v > 1.0 else (-1.0 if v < -1.0 else v)) for v in out]

    func _fit(img):
        if img.width == self.width and img.height == self.height:
            return img
        return rs.resize(img, self.width, self.height)

    # Image composée à l'instant t : clips actifs dans l'ordre d'ajout ; transition d'entrée avec le plan dessous.
    func render_frame(t):
        base := mi.new(self.width, self.height, "rgb", self.background)
        for c in self.video:
            if not c.active(t):
                continue
            img := c.image_at(t)
            if img == null:
                continue
            if c.fit:
                img = self._fit(img)
            if img.mode != "rgb":
                img = _to_rgb(img)
            if c.transition != null and c.transition_time > 0 and t - c.start < c.transition_time:
                p := (t - c.start) / c.transition_time
                if c.transition == "crossfade":
                    img = tr.crossfade(base, img, p)
                elif c.transition == "wipe":
                    img = tr.wipe(base, img, p)
                elif c.transition == "dissolve":
                    img = tr.dissolve(base, img, p)
                else:
                    img = tr.slide(base, img, p)
            if c.opacity >= 1.0 and c.fit:
                base = img
            else:
                cm := comp.Compositor(self.width, self.height, self.background)
                cm.add("dessous", base, 0, 0, 1.0, 0)
                cm.add("clip", img, c.x, c.y, c.opacity, 1)
                base = cm.render()
        return base

    func frame_times(start=0.0, end=null):
        e := end if end != null else self.duration()
        n := to_int((e - start) * self.fps + 0.5)
        return [start + 1.0 * i / self.fps for i in 0..n]

func _to_rgb(img):
    return _cv.to_mode(img, "rgb")
