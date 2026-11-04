# ALEX STANDARD LIBRARY — multimedia.video.capture
#
# Capture d'images vidéo, toujours sous forme de VideoFrame (Image rgb + pts) :
#   - « camera »  caméra réelle par le paquet camera (ffmpeg / Video4Linux) ;
#   - « pattern » mire de test animée de ffmpeg (sans caméra) ;
#   - « file »    images d'un fichier vidéo (adaptateur ffmpeg) ;
#   - « fake »    multimedia.testing.fake_device.FakeCamera (tests, sans aucun outil).
# Bornée (nombre d'images, durée), annulable, avec mesure de cadence.
#
#   use multimedia.video.capture as vcap
#   c := vcap.VideoCapture("pattern", 320, 240, 15)
#   f := c.read()                             # VideoFrame, ou null à la fin
#   for f in c.frames(30):                    # au plus 30 images
#       ...
#   c.close()
#
# Erreurs : DeviceError (caméra absente : jamais remplacée en silence par une mire), UnsupportedError,
# CancelledError.

from core use len
from collections use append
use multimedia.core.errors as merr
use multimedia.core.cancellation as mc
use multimedia.video.frame as vfr
use multimedia.video.frame_rate as fr
use multimedia.image.image as mi
use multimedia.testing.fake_device as fake
use multimedia.backends.codecs.ffmpeg as ff
use camera as _cam

const SOURCES := ["camera", "pattern", "file", "fake"]

class VideoCapture:
    func init(source="camera", width=320, height=240, fps=15, path=null, limit=null):
        if not (source in SOURCES):
            merr.fail(merr.FORMAT, "source de capture inconnue : " + str(source))
        self.source = source
        self.width = width
        self.height = height
        self.fps = fps
        self.limit = limit
        self.count = 0
        self.meter = fr.FpsMeter(30, fps)
        self.closed = false
        self.dev = null
        if source == "fake":
            self.dev = fake.FakeCamera(width, height, fps, "gradient", limit)
        elif source == "file":
            if path == null:
                merr.fail(merr.FORMAT, "source « file » : chemin exigé")
            self.dev = ff.VideoDecoder(path, width, height, fps)
        elif source == "pattern":
            self.dev = ff.PatternSource(width, height, fps, "testsrc", _seconds_for(limit, fps))
        else:
            try:
                self.dev = _cam.open(width, height, false)
            catch e:
                merr.fail(merr.DEVICE, "caméra inaccessible : " + e.message)

    func _raw():
        if self.source == "fake":
            img := self.dev.read()
            if img == null:
                return null
            return vfr.VideoFrame(img, img.meta["timestamp"], 1.0 / self.fps, img.meta["index"])
        if self.source == "file" or self.source == "pattern":
            img := self.dev.read()
            if img == null:
                return null
            return vfr.from_decoded(img, self.fps)
        cf := self.dev.read()
        if cf == null:
            return null
        return vfr.VideoFrame(mi.from_video_frame(cf), 1.0 * self.count / self.fps, 1.0 / self.fps, self.count)

    func read():
        if self.closed:
            merr.state("capture fermée")
        if self.limit != null and self.count >= self.limit:
            return null
        f := self._raw()
        if f == null:
            return null
        self.meter.tick(f.pts)
        self.count += 1
        return f

    func frames(n=null, token=null):
        out := []
        while n == null or len(out) < n:
            mc.check(token)
            f := self.read()
            if f == null:
                break
            append(out, f)
        return out

    func close():
        if self.closed:
            return
        self.closed = true
        try:
            self.dev.close()
        catch e:
            self.closed = true

func _seconds_for(limit, fps):
    if limit == null:
        return null
    return (limit + 1.0) / fps
