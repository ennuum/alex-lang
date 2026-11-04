# Paquet camera : formats, conversions YUV / RGB, opérations sur les images, PPM / PGM, mouvement ; capture
# réelle par ffmpeg sur une mire de test (lavfi) : images, cadence, rappels async, photo, enregistrement.
from core use len
from collections use append
use os
use camera
use _native_net as _b
use camera.camera_format as cf
use camera.video_frame as vf
use camera.camera_capture as cc
use camera.camera_device as cd

ok := [0]
ko := [0]
func check(cond, label):
    if cond:
        ok[0] += 1
    else:
        ko[0] += 1
        print("ÉCHEC " + label)

func near(a, b, eps):
    d := a - b
    if d < 0:
        d = -d
    return d <= eps

f := cf.CameraFormat(640, 480, "yuyv422", 30)
check(f.frame_bytes() == 614400 and f.fourcc() == "YUYV" and f.describe() == "640x480 yuyv422 30 i/s", "format")
check(cf.CameraFormat(4, 4, "nv12").frame_bytes() == 24 and cf.from_fourcc("MJPG") == "mjpeg", "nv12, fourcc")
texte := "ioctl: VIDIOC_ENUM_FMT\n\t[0]: 'YUYV' (YUYV 4:2:2)\n\t\tSize: Discrete 640x480\n\t\t\tInterval: Discrete 0.033s (30.000 fps)\n\t\tSize: Discrete 1280x720\n\t\t\tInterval: Discrete 0.100s (10.000 fps)\n\t[1]: 'MJPG' (Motion-JPEG, compressed)\n\t\tSize: Discrete 1280x720\n\t\t\tInterval: Discrete 0.033s (30.000 fps)\n"
fs := cf.parse_v4l2_formats(texte)
check(len(fs) == 3 and fs[1].fps == 10 and fs[2].pixel_format == "mjpeg", "liste v4l2-ctl")
check(cf.closest(fs, 1280, 720).pixel_format == "mjpeg" and cf.closest(fs, 1280, 720, "yuyv422").fps == 10, "format le plus proche")

check(vf.yuv_to_rgb(235, 128, 128) == [255, 255, 255] and vf.yuv_to_rgb(16, 128, 128) == [0, 0, 0], "YUV blanc / noir")
rouge := vf.rgb_to_yuv(255, 0, 0)
r2 := vf.yuv_to_rgb(rouge[0], rouge[1], rouge[2])
check(r2[0] > 240 and r2[1] < 15 and r2[2] < 15, "aller-retour du rouge")
yuyv := vf.VideoFrame(2, 1, "yuyv422", [235, 128, 16, 128])
check(yuyv.valid() and yuyv.to_rgb().data == [255, 255, 255, 0, 0, 0], "YUYV -> RGB")
nv := vf.VideoFrame(2, 2, "nv12", [235, 16, 235, 16, 128, 128])
check(nv.to_rgb().pixel(1, 1) == [0, 0, 0] and nv.pixel(0, 1) == [255, 255, 255], "NV12 -> RGB")
check(vf.VideoFrame(1, 1, "bgr24", [1, 2, 3]).to_rgb().data == [3, 2, 1], "BGR -> RGB")
img := vf.solid(8, 6, 200, 100, 50)
img.data[3 * (2 * 8 + 3)] = 0
check(img.pixel(3, 2) == [0, 100, 50] and img.pixel(0, 0) == [200, 100, 50], "points")
check(img.crop(3, 2, 2, 2).pixel(0, 0) == [0, 100, 50], "recadrage")
check(img.resize(4, 3).width == 4 and len(img.resize(4, 3).data) == 36, "redimensionnement")
check(img.mirror().pixel(4, 2) == [0, 100, 50], "miroir")
check(near(vf.solid(2, 2, 255, 255, 255).brightness(), 255.0, 1.0) and vf.solid(2, 2, 0, 0, 0).histogram(4) == [4, 0, 0, 0], "luminosité, histogramme")
check(vf.motion(img, img) == 0.0 and vf.motion(img, vf.solid(8, 6, 0, 0, 0)) == 1.0, "mouvement")
check(_b.blen(img.to_rgba_bytes()) == 192, "RGBA pour un canvas")
chemin := os.tmp_dir() + "/alex_cam_" + str(os.pid()) + ".ppm"
img.save_ppm(chemin)
lu := camera.load(chemin)
check(lu.width == 8 and lu.height == 6 and lu.pixel(3, 2) == [0, 100, 50], "PPM relu")
img.save_pgm(chemin)
check(camera.load(chemin).pixel_format == "gray", "PGM relu")
os.remove(chemin)

if cc.ffmpeg_available():
    cap := cc.test_pattern(cf.CameraFormat(64, 48, "rgb24", 25))
    im := cap.grab(3)
    check(len(im) == 3 and im[0].valid() and im[2].index == 2, "trois images de la mire")
    check(im[0].brightness() > 20.0, "mire non noire")
    vus := []
    cap.on_frame((fr) => append(vus, fr.index))
    n := await cap.run(0.5)
    check(len(vus) >= 3 and n >= 6, "flux async : " + str(len(vus)) + " images")
    check(cap.measured_fps() > 1.0, "cadence mesurée")
    cap.close()
    g := cc.CameraCapture("testsrc", cf.CameraFormat(32, 24, "rgb24", 10), "gray", 2)
    a := g.read()
    b := g.read()
    check(a.pixel_format == "gray" and len(a.data) == 768 and g.read() == null, "niveaux de gris, fin du flux")
    g.close()
    one := cc.snapshot("testsrc", cf.CameraFormat(16, 16, "rgb24", 5), "yuyv422")
    check(one.valid() and one.to_rgb().width == 16, "photo en YUYV")
    video := os.tmp_dir() + "/alex_cam_" + str(os.pid()) + ".avi"
    cc.record("testsrc", video, 0.5, cf.CameraFormat(32, 24, "rgb24", 10))
    check(os.exists(video) and os.size(video) > 0, "enregistrement vidéo")
    os.remove(video)
else:
    print("ffmpeg absent : capture non testée")
check(len(cd.cameras()) >= 0, "inventaire")
# vraie caméra (ALEX_MEDIA_REAL=1 : allume la caméra) : une image de la caméra par défaut
if os.getenv("ALEX_MEDIA_REAL", "") == "1" and cc.ffmpeg_available() and camera.available():
    dev := cd.default()
    print("caméra réelle : " + dev.describe())
    photo := dev.snapshot(320, 240)
    check(photo != null and photo.valid() and photo.width == 320 and photo.height == 240, "image de la caméra réelle")
    print("  luminosité " + str(photo.brightness()))
print("caméra : " + str(ok[0]) + " OK, " + str(ko[0]) + " échecs")
