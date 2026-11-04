# ALEX STANDARD LIBRARY — multimedia.playback.subtitles
#
# Affichage synchronisé des sous-titres pendant la lecture : à chaque position, SubtitleDisplay indique le texte à
# montrer et ce qui a changé (apparitions, disparitions), avec un décalage réglable (sous-titres en avance ou en
# retard sur le son) et le passage instantané après une recherche.
#
#   use multimedia.playback.subtitles as psub
#   aff := psub.SubtitleDisplay(subs.load("film.srt"))
#   aff.delay = 0.5                           # sous-titres affichés 0,5 s plus tard
#   ch := aff.update(lecteur.position())      # {"text": "...", "shown": [Cue], "hidden": [Cue]}
#   if len(ch["shown"]) > 0 or len(ch["hidden"]) > 0:
#       redessiner(ch["text"])

from core use len
from collections use append
use string as _s

class SubtitleDisplay:
    func init(track, delay=0.0, plain=true):
        self.track = track
        self.delay = delay
        self.plain = plain
        self.visible = []

    func _text(cues):
        parts := []
        for c in cues:
            append(parts, c.plain_text() if self.plain else c.text)
        return _s.join("\n", parts)

    func update(position):
        t := position - self.delay
        now := self.track.at(t)
        shown := [c for c in now if not (c in self.visible)]
        hidden := [c for c in self.visible if not (c in now)]
        self.visible = now
        return {"text": self._text(now), "shown": shown, "hidden": hidden, "time": t}

    func text():
        return self._text(self.visible)

    func reset():
        self.visible = []
