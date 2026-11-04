# ALEX STANDARD LIBRARY — camera
#
# Caméras pour les applications :
#
# | Module                   | Contenu                                                                   |
# |--------------------------|---------------------------------------------------------------------------|
# | camera.camera_device     | caméras présentes, formats proposés, ouverture                            |
# | camera.camera_capture    | capture en continu (ffmpeg), mire de test, photo, enregistrement vidéo    |
# | camera.camera_format     | CameraFormat (taille, format des points, cadence), v4l2-ctl               |
# | camera.video_frame       | VideoFrame : conversions YUV / RGB, recadrage, mouvement, PPM / PGM       |
#
#   use camera
#   c := camera.open()                         # caméra par défaut, 640x480 (mire de test si aucune)
#   img := c.read()
#   img.save_ppm("photo.ppm")
#   c.close()
#
# Capture : ffmpeg (HardwareError s'il est absent).

use camera.camera_device as cd
use camera.camera_capture as cc
use camera.camera_format as cf
use camera.video_frame as vf

func cameras():
    return cd.cameras()

func available():
    return cd.available()

# Capture sur la caméra par défaut ; fallback_pattern : mire de test s'il n'y a pas de caméra.
func open(width=640, height=480, fallback_pattern=true):
    d := cd.default()
    if d != null:
        return d.open(width, height)
    if fallback_pattern:
        return cc.test_pattern(cf.CameraFormat(width, height, "rgb24", 30))
    raise("HardwareError", "camera : aucune caméra")

func snapshot(width=640, height=480):
    d := cd.default()
    if d == null:
        raise("HardwareError", "camera : aucune caméra")
    return d.snapshot(width, height)

func test_pattern(width=320, height=240):
    return cc.test_pattern(cf.CameraFormat(width, height, "rgb24", 30))

func load(path):
    return vf.load_pnm(path)
