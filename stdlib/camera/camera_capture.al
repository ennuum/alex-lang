# ALEX STANDARD LIBRARY — camera.camera_capture
#
# Capture d'images en continu : ffmpeg lit la caméra (Video4Linux, ou une mire de test « lavfi », ou un fichier
# vidéo) et livre des images brutes de taille fixe sur sa sortie standard ; CameraCapture les découpe en
# VideoFrame (numéro, instant), mesure la cadence réelle, et propose : une image (snapshot), n images, un
# flux asynchrone avec rappel par image, et l'enregistrement direct d'une vidéo.
#
#   use camera.camera_capture as cc
#   use camera.camera_format as cf
#   cap := cc.CameraCapture("/dev/video0", cf.CameraFormat(640, 480, "rgb24", 30))
#   img := cap.read()                         # VideoFrame (null à la fin du flux)
#   cap.on_frame((f) => traiter(f))
#   await cap.run(5.0)                        # 5 s d'images, rappel à chaque image
#   cap.close()
#   mire := cc.test_pattern(cf.QVGA)          # sans caméra : mire animée de ffmpeg
#
# Erreurs : HardwareError (ffmpeg absent, caméra inaccessible).

from core use len, to_int
from collections use append
use asyncio
use process
use string as _s
use hardware._sys as _sys
use _native_net as _b
use camera.camera_format as cf
use camera.video_frame as vf

func ffmpeg_available():
    return process.which("ffmpeg") != null

func _cat(a, b):
    out := [x for x in a]
    for x in b:
        append(out, x)
    return out

# Arguments d'entrée de ffmpeg pour une source : chemin /dev/videoN, « video=... » (caméra DirectShow sous
# Windows), « testsrc » / « smptebars » (mire), ou fichier vidéo.
func input_args(source, fmt):
    size := fmt.size_text()
    if source == "testsrc" or source == "smptebars" or source == "testsrc2" or source == "rgbtestsrc":
        return ["-f", "lavfi", "-i", source + "=size=" + size + ":rate=" + str(fmt.fps)]
    if _s.starts_with(source, "video="):
        # Windows, DirectShow : taille et cadence natives de la caméra (une taille qu'elle ne propose pas ferait
        # échouer l'ouverture) ; la mise à l'échelle -vf donne la taille demandée.
        return ["-f", "dshow", "-rtbufsize", "64M", "-i", source]
    if _is_device(source):
        a := ["-f", "v4l2", "-video_size", size, "-framerate", str(fmt.fps)]
        if fmt.pixel_format == "mjpeg" or fmt.pixel_format == "yuyv422" or fmt.pixel_format == "nv12":
            a = _cat(a, ["-input_format", fmt.ffmpeg_name()])
        return _cat(a, ["-i", source])
    return ["-re", "-i", source]

func _is_device(source):
    return len(source) > 10 and source[0] == '/' and source[1] == 'd' and source[4] == '/' and source[5] == 'v'

class CameraCapture:
    # source : chemin du périphérique, « testsrc » (mire), ou fichier ; fmt : CameraFormat demandé ;
    # output : format des points livrés (« rgb24 » par défaut, « gray », « yuyv422 »...).
    func init(source, fmt=null, output="rgb24", max_frames=null):
        if not ffmpeg_available():
            _sys.fail("camera", "ffmpeg est nécessaire pour la capture")
        self.source = source
        self.format = fmt if fmt != null else cf.VGA
        self.output = output
        self.out_format = cf.CameraFormat(self.format.width, self.format.height, output, self.format.fps)
        args := _cat(["-loglevel", "error", "-nostdin"], input_args(source, self.format))
        args = _cat(args, ["-vf", "scale=" + str(self.format.width) + ":" + str(self.format.height)])
        if max_frames != null:
            args = _cat(args, ["-frames:v", str(max_frames)])
        args = _cat(args, ["-f", "rawvideo", "-pix_fmt", output, "-"])
        self.args = args
        self.proc = process.Command("ffmpeg").args(args).stdin("null").stdout("pipe").stderr("pipe").spawn()
        self.pending = ""
        self.count = 0
        self.started = asyncio.now()
        self.callbacks = []
        self.stopped = false
        self.ended = false

    # Image suivante (VideoFrame), ou null à la fin du flux / après timeout secondes.
    func read(timeout=10.0):
        need := self.out_format.frame_bytes()
        while _b.blen(self.pending) < need and not self.ended:
            chunk := self.proc.read("stdout", need - _b.blen(self.pending), timeout)
            if chunk == null:
                return null
            if chunk == "":
                self.ended = true
                break
            self.pending = self.pending + chunk
        if _b.blen(self.pending) < need:
            if self.count == 0:
                err := self.proc.read("stderr", 4096, 0.2)
                _sys.fail("camera", "aucune image de " + self.source + (" : " + err if err != null and err != "" else ""))
            return null
        raw := _b.bslice(self.pending, 0, need)
        self.pending = _b.bslice(self.pending, need, _b.blen(self.pending))
        f := vf.VideoFrame(self.format.width, self.format.height, self.output, _b.to_bytes(raw), self.count, asyncio.now() - self.started)
        self.count += 1
        return f

    func grab(n):
        out := []
        while len(out) < n:
            f := self.read()
            if f == null:
                break
            append(out, f)
        return out

    # Images par seconde mesurées depuis l'ouverture.
    func measured_fps():
        t := asyncio.now() - self.started
        if t <= 0:
            return 0.0
        return self.count / t

    func on_frame(fn):
        append(self.callbacks, fn)

    func stop():
        self.stopped = true

    async func run(duration=null):
        start := asyncio.now()
        while not self.stopped:
            if duration != null and asyncio.now() - start >= duration:
                break
            f := self.read()
            if f == null:
                break
            for fn in self.callbacks:
                fn(f)
            await asyncio.sleep(0)
        return self.count

    func close():
        self.proc.stop(0.5)

# Mire de test animée (ffmpeg lavfi) : une « caméra » toujours disponible.
func test_pattern(fmt=null, output="rgb24", pattern="testsrc"):
    return CameraCapture(pattern, fmt if fmt != null else cf.QVGA, output)

# Une seule image depuis source.
func snapshot(source, fmt=null, output="rgb24"):
    c := CameraCapture(source, fmt, output, 1)
    try:
        return c.read()
    finally:
        c.close()

# Enregistre seconds secondes de source dans path (codec choisi par ffmpeg selon l'extension).
func record(source, path, seconds, fmt=null):
    f := fmt if fmt != null else cf.VGA
    args := _cat(["-loglevel", "error", "-nostdin", "-y"], input_args(source, f))
    args = _cat(args, ["-t", str(seconds), path])
    r := process.Command("ffmpeg").args(args).run(null, seconds + 30)
    if r.code != 0:
        _sys.fail("camera", "enregistrement impossible : " + r.stderr)
    return path
