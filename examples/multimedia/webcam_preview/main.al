# Aperçu caméra : quelques images de la webcam (ou de la mire ffmpeg sans caméra), avec cadence mesurée et
# détection de mouvement, enregistrées en PNG.
#   alex run examples/multimedia/webcam_preview/main.al -- [nombre_images]
from core use len, to_int
use os
use camera.video_frame as cvf
use multimedia.video.capture as vcap
use multimedia.video.device as vd
use multimedia.image.encode as enc
use multimedia.image.image as mi

a := os.args()
count := to_int(a[0]) if len(a) > 0 else 10
src := "camera" if vd.available() else "pattern"
print("source : " + src + ("" if src == "camera" else " (aucune caméra : " + str(vd.diagnose()["advice"]) + ")"))
c := vcap.VideoCapture(src, 160, 120, 10, null, count)
prev := null
for f in c.frames():
    if prev != null:
        m := cvf.motion(mi.to_video_frame(prev), mi.to_video_frame(f.image))
        print("image " + str(f.index) + " : mouvement " + str(to_int(m * 100)) + " %")
    prev = f.image
enc.save(prev, os.tmp_dir() + "/alex_webcam.png")
print("cadence mesurée : " + str(c.meter.fps()) + " i/s ; dernière image : " + os.tmp_dir() + "/alex_webcam.png")
c.close()
