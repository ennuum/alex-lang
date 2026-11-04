# ALEX STANDARD LIBRARY — multimedia.video.frame
#
# Image vidéo horodatée : une multimedia.image.Image (gray / rgb / rgba) + pts (secondes), durée, numéro, image clé.
# Passerelles avec les images de la caméra (camera.video_frame.VideoFrame) et les Frame des pipelines.
#
#   use multimedia.video.frame as vfr
#   f := vfr.VideoFrame(img, 1.25, 0.04, 31)
#   print(f.describe(), f.end())                  # « 64x48 rgb à 00:00:01.250 » 1.29
#   g := vfr.from_camera(camera.read())           # camera.video_frame.VideoFrame -> VideoFrame
#   pf := f.to_pipeline()                         # multimedia.core.buffer.Frame (genre « video »)

use multimedia.core.errors as merr
use multimedia.core.timestamp as ts
use multimedia.core.buffer as mb
use multimedia.image.image as mi

class VideoFrame:
    func init(image, pts=0.0, duration=0.0, index=0, keyframe=true):
        if image == null:
            merr.fail(merr.FORMAT, "image vidéo absente")
        self.image = image
        self.pts = pts
        self.duration = duration
        self.index = index
        self.keyframe = keyframe
        self.eos = false

    func width():
        return self.image.width

    func height():
        return self.image.height

    func end():
        return self.pts + self.duration

    func with_image(img):
        return VideoFrame(img, self.pts, self.duration, self.index, self.keyframe)

    func to_pipeline():
        f := mb.Frame("video", self.image, null, ts.from_seconds(self.pts, ts.MICROS), self.duration)
        f.meta["index"] = self.index
        return f

    func describe():
        return self.image.describe() + " à " + ts.format_clock(self.pts)

func from_image(img, pts=0.0, duration=0.0, index=0):
    return VideoFrame(img, pts, duration, index)

# camera.video_frame.VideoFrame (tout format de points) -> VideoFrame rgb.
func from_camera(cf, duration=0.0):
    return VideoFrame(mi.from_video_frame(cf), cf.timestamp, duration, cf.index)

# Image décodée par l'adaptateur ffmpeg (meta « pts », « index ») -> VideoFrame.
func from_decoded(img, fps):
    pts := img.meta["pts"] if "pts" in img.meta else 0.0
    idx := img.meta["index"] if "index" in img.meta else 0
    return VideoFrame(img, pts, 1.0 / fps if fps > 0 else 0.0, idx)

# Vrai si x est un VideoFrame (sinon : Image ou autre).
func is_frame(x):
    try:
        y := x.image
        z := x.pts
        return true
    catch e:
        return false

class EndOfVideo:
    func init():
        self.eos = true

END := EndOfVideo()
