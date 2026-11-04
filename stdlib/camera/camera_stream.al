# ALEX STANDARD LIBRARY — camera.camera_stream
#
# Flux d'images au-dessus de n'importe quelle source qui a une méthode read() renvoyant un VideoFrame ou null :
# camera.camera_capture.CameraCapture (caméra réelle, fichier, mire ffmpeg), FrameListSource (images en
# mémoire, tests), ou un objet de l'utilisateur.
#   - file d'attente bornée avec politique de débordement : « drop_oldest » (temps réel, défaut),
#     « drop_newest », « block » (aucune perte, la source attend) ;
#   - cadence cible : images sautées pour tenir target_fps d'après leur horodatage ;
#   - chaîne de transformations (fonctions image → image : recadrage, miroir, réglages logiciels...) ;
#   - détecteur de mouvement (camera.video_frame.motion) avec rappel et délai de répit ;
#   - enregistrement en séquence PPM/PGM numérotée ;
#   - statistiques : images lues, livrées, perdues, sautées, cadence mesurée.
#
#   use camera.camera_capture as cap
#   use camera.camera_stream as cs
#   s := cs.CameraStream(cap.test_pattern(), 4)
#   s.target_fps = 10
#   s.add_transform((f) => f.mirror())
#   s.on_motion(0.02, (img, part) => print("mouvement : " + str(part)))
#   s.pump(30)                       # lit 30 images de la source
#   while not s.empty():
#       img := s.next()
#   print(s.stats())
#
# Erreurs : ArgumentError (politique ou taille invalide), CameraError (source fermée).

from core use len, type
from collections use append
use string as _s
use os as _os
use camera.video_frame as _vf

const DROP_OLDEST := "drop_oldest"
const DROP_NEWEST := "drop_newest"
const BLOCK := "block"

# Source d'images en mémoire (tests, rejouer une capture).
class FrameListSource:
    func init(frames, fps=30.0):
        self.frames = frames
        self.pos = 0
        self.fps = fps

    func read(timeout=10.0):
        if self.pos >= len(self.frames):
            return null
        f := self.frames[self.pos]
        if f.timestamp == 0.0 and self.pos > 0:
            f.timestamp = self.pos / self.fps
        f.index = self.pos
        self.pos += 1
        return f

    func close():
        self.pos = len(self.frames)

class CameraStream:
    func init(source, capacity=8, policy=DROP_OLDEST):
        if capacity < 1:
            raise("ArgumentError", "CameraStream : capacité >= 1 attendue")
        if policy != DROP_OLDEST and policy != DROP_NEWEST and policy != BLOCK:
            raise("ArgumentError", "CameraStream : politique inconnue « " + str(policy) + " » (drop_oldest, drop_newest, block)")
        self.source = source
        self.capacity = capacity
        self.policy = policy
        self.queue = []
        self.transforms = []
        self.target_fps = null
        self._last_kept = null
        self._prev = null
        self._motion = null
        self._last_motion = null
        self._recording = null
        self.read_count = 0
        self.delivered = 0
        self.dropped = 0
        self.skipped = 0
        self.first_ts = null
        self.last_ts = null
        self.ended = false
        self.closed = false

    func add_transform(fn):
        append(self.transforms, fn)
        return self

    # fn(image, part) appelée quand la part de pixels changés dépasse threshold ; cooldown secondes de répit.
    func on_motion(threshold, fn, cooldown=0.0, pixel_threshold=25):
        self._motion = [threshold, fn, cooldown, pixel_threshold]
        return self

    # Enregistre chaque image retenue dans dir/prefixNNNNNN.ppm (ou .pgm si gray).
    func record_to(dir, prefix="frame", gray=false):
        if not _os.isdir(dir):
            _os.mkdir_all(dir)
        self._recording = {"dir": dir, "prefix": prefix, "gray": gray, "count": 0, "files": []}
        return self

    func stop_recording():
        r := self._recording
        self._recording = null
        if r == null:
            return []
        return r["files"]

    func _keep(f):
        if self.target_fps == null or self.target_fps <= 0:
            return true
        if self._last_kept == null:
            return true
        return f.timestamp - self._last_kept >= (1.0 / self.target_fps) - 0.000001

    func _process(f):
        img := f
        for t in self.transforms:
            img = t(img)
        m := self._motion
        if m != null:
            if self._prev != null:
                part := _vf.motion(self._prev, img, m[3])
                if part >= m[0]:
                    if self._last_motion == null or img.timestamp - self._last_motion >= m[2]:
                        self._last_motion = img.timestamp
                        cb := m[1]
                        cb(img, part)
            self._prev = img
        r := self._recording
        if r != null:
            num := str(r["count"])
            while len(num) < 6:
                num = "0" + num
            path := r["dir"] + "/" + r["prefix"] + num
            if r["gray"]:
                path += ".pgm"
                img.save_pgm(path)
            else:
                path += ".ppm"
                img.save_ppm(path)
            r["count"] += 1
            append(r["files"], path)
        return img

    func _enqueue(img):
        if len(self.queue) >= self.capacity:
            if self.policy == DROP_OLDEST:
                self.queue = [self.queue[i] for i in 1..len(self.queue)]
                self.dropped += 1
            elif self.policy == DROP_NEWEST:
                self.dropped += 1
                return false
            else:
                return false
        append(self.queue, img)
        return true

    # Lit au plus n images de la source (toutes jusqu'à la fin si n est null). En politique « block »,
    # s'arrête quand la file est pleine. Renvoie le nombre d'images lues.
    func pump(n=null, timeout=10.0):
        if self.closed:
            raise("CameraError", "CameraStream fermé")
        k := 0
        while (n == null or k < n) and not self.ended:
            if self.policy == BLOCK and len(self.queue) >= self.capacity:
                break
            f := self.source.read(timeout)
            if f == null:
                self.ended = true
                break
            k += 1
            self.read_count += 1
            if self.first_ts == null:
                self.first_ts = f.timestamp
            self.last_ts = f.timestamp
            if not self._keep(f):
                self.skipped += 1
                continue
            self._last_kept = f.timestamp
            self._enqueue(self._process(f))
        return k

    func empty():
        return len(self.queue) == 0

    func size():
        return len(self.queue)

    # Image suivante de la file ; si elle est vide, lit la source (null à la fin du flux).
    func next():
        if len(self.queue) == 0 and not self.ended and not self.closed:
            while len(self.queue) == 0 and not self.ended:
                self.pump(1)
        if len(self.queue) == 0:
            return null
        f := self.queue[0]
        self.queue = [self.queue[i] for i in 1..len(self.queue)]
        self.delivered += 1
        return f

    # Image la plus récente ; vide la file (affichage temps réel).
    func latest():
        if len(self.queue) == 0:
            return self.next()
        f := self.queue[len(self.queue) - 1]
        self.dropped += len(self.queue) - 1
        self.delivered += 1
        self.queue = []
        return f

    # Appelle fn(image) pour chaque image jusqu'à la fin ou max_frames ; renvoie le nombre traité.
    func each(fn, max_frames=null):
        n := 0
        while max_frames == null or n < max_frames:
            f := self.next()
            if f == null:
                break
            fn(f)
            n += 1
        return n

    func measured_fps():
        if self.first_ts == null or self.last_ts == null or self.last_ts <= self.first_ts:
            return 0.0
        return (self.read_count - 1) / (self.last_ts - self.first_ts)

    func stats():
        return {"read": self.read_count, "delivered": self.delivered, "dropped": self.dropped,
                "skipped": self.skipped, "queued": len(self.queue), "fps": self.measured_fps(), "ended": self.ended}

    func close():
        if self.closed:
            return
        self.closed = true
        self.queue = []
        src := self.source
        try:
            src.close()
        catch e:
            self.closed = true

    func __enter__():
        return self

    func __exit__(a, b, c):
        self.close()

# Images synthétiques : un carré blanc qui se déplace sur fond gris (tests du détecteur de mouvement).
func moving_square(width, height, count, size=8, fps=30.0):
    out := []
    i := 0
    while i < count:
        data := []
        x0 := (i * 4) % (width - size)
        y := 0
        while y < height:
            x := 0
            while x < width:
                v := 64
                if x >= x0 and x < x0 + size and y >= 2 and y < 2 + size:
                    v = 255
                append(data, v)
                append(data, v)
                append(data, v)
                x += 1
            y += 1
        append(out, _vf.VideoFrame(width, height, "rgb24", data, i, i / fps))
        i += 1
    return out
