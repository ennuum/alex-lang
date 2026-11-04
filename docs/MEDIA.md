# Son, micro, caméra, calcul et rendu : `audio`, `microphone`, `camera`, `gpu`, `graphics`

Paquets pour les applications multimédias, au-dessus des inventaires de `hardware.*` :

```
use audio
use microphone
use camera
use graphics

la := audio.tone(440, 0.5)                        # AudioBuffer
audio.play(la)                                    # aplay / pw-play / paplay / ffplay
voix := microphone.record(3.0)                    # arecord / pw-record / parecord / ffmpeg
c := camera.open(640, 480)                        # ffmpeg (Video4Linux ; mire de test sans caméra)
img := c.read()                                   # VideoFrame
graphics.render_cube(320, 240, 0.6).save_ppm("cube.ppm")
```

- **audio** : formats PCM (u8, s16le, s24le, s32le, f32le), conversion de canaux et de fréquence, tampons,
  lecture EN CONTINU (le PCM est écrit sur l'entrée standard du lecteur), écriture WAV progressive,
  capture, mixeur (pistes, panoramique, solo, boucles, vumètres, limiteur), générateurs et effets (écho,
  réverbération de Schroeder, biquads, compresseur, enveloppe ADSR), estimation de hauteur.
- **microphone** : entrée par blocs (gain, porte de bruit, niveaux, rappels asynchrones), enregistrement
  à durée fixe, jusqu'au silence (détection d'activité vocale), vers WAV ; segments de parole.
- **camera** : formats (YUYV, NV12, MJPEG, RGB, gris ; liste `v4l2-ctl`), capture continue par ffmpeg
  (périphérique, mire `testsrc`, fichier), cadence mesurée, photo, vidéo ; images : conversions YUV ↔ RGB,
  recadrage, redimensionnement, miroir, luminosité, histogramme, détection de mouvement, PPM / PGM,
  octets RGBA pour `ui.canvas_put_pixels`.
- **gpu** : télémétrie des cartes (sysfs amdgpu / i915 / nouveau, `nvidia-smi`), mémoire de périphérique
  (tampons typés, capacité), calcul data-parallèle par noyaux sur une grille (série ou plusieurs fils :
  saxpy, réductions, matmul, convolution, histogramme). Un dorsal matériel (Vulkan / OpenCL) pourra se
  brancher sous la même API.
- **graphics** : pipeline de rendu LOGICIEL complet en Alex : surfaces RGBA + profondeur, tampons de
  sommets / indices / uniforms, textures (bilinéaire, mipmaps), shaders de sommets et de fragments en Alex,
  matrices 4x4, découpage par le plan proche, élimination des faces arrière, rastérisation par fonctions
  d'arêtes avec interpolation corrigée en perspective, profondeur, mélange, passes, tampons de commandes,
  chaîne d'images (fenêtre `ui`, fichiers, mémoire).

Bibliothèque de plus haut niveau (sondage, conteneurs, images, pipelines, lecteur) : docs/MULTIMEDIA.md.

Tests : `make test-media` (audio 47, microphone 14, caméra 26 avec une vraie capture ffmpeg, gpu 25,
graphics 37 vérifications).

## Paquet `audio`

### `audio`

```text
Son pour les applications :

| Module               | Contenu                                                                     |
|----------------------|-----------------------------------------------------------------------------|
| audio.audio_format   | AudioFormat (fréquence, canaux, u8 / s16le / s24le / s32le / f32le),        |
|                      | encode / decode, canaux, rééchantillonnage                                   |
| audio.audio_stream   | AudioBuffer, PlayerStream (lecture en continu), WavWriter, CaptureStream... |
| audio.audio_device   | périphériques ALSA, sortie / entrée par défaut                              |
| audio.audio_mixer    | Mixer : pistes, volume, panoramique, solo, boucle, vumètres                 |
| audio.audio_effects  | générateurs (sinus, carré, bruit, ADSR...), effets (écho, réverbération,    |
|                      | filtres, compresseur...), mesures (rms, crête, hauteur)                     |

  use audio
  la := audio.tone(440, 0.5)                   # AudioBuffer
  audio.save(la, "la.wav")
  audio.play(la)                               # HardwareError sans lecteur
  b := audio.load("voix.wav")
  print(b.describe(), audio.pitch(b))

Lecture : aplay, pw-play, paplay ou ffplay ; capture : arecord, pw-record, parecord ou ffmpeg.
```

API publique :

- `format(rate=44100, channels=1, sample_format="s16le")`
- `buffer(samples, fmt=null)`
- `tone(frequency, seconds, rate=44100, volume=0.5)`
- `silence(seconds, rate=44100)`
- `load(path)`
- `save(buf, path)`
- `play(source, device=null)`
- `type_is_str(x)`
- `mixer(fmt=null)`
- `devices()`
- `outputs()`
- `inputs()`
- `can_play()`
- `can_record()`
- `pitch(buf)`

### `audio.audio_device`

```text
Périphériques audio du système (Linux : ALSA /proc/asound, via hardware.audio) avec ouverture de flux :
sorties (haut-parleurs, casques, HDMI) et entrées (micros), périphérique par défaut, formats proposés,
outil de lecture / capture disponible.

  use audio.audio_device as ad
  for d in ad.outputs():
      print(d.describe())                      # « hw:0,0 HDA Intel PCH : ALC257 Analog (sortie) »
  out := ad.default_output().open(af.CD)       # audio_stream.PlayerStream
  out.write(echantillons)
  out.close()
```

API publique :

- class `AudioDevice(info)` : `is_default()`, `alsa_name(plug=true)`, `open(fmt=null)`, `open_input(fmt=null)`, `describe()`
- `devices()`
- `outputs()`
- `inputs()`
- `default_output()`
- `default_input()`
- `player_available()`
- `recorder_available()`
- `cards()`

### `audio.audio_effects`

```text
Générateurs et effets sur des échantillons flottants (-1.0..1.0, entrelacés si plusieurs canaux) :
  - générateurs : sine, square, sawtooth, triangle, noise (bruit blanc reproductible), silence, chirp
    (balayage de fréquence), envelope ADSR ;
  - effets : gain (dB ou facteur), normalize, fade_in / fade_out, reverse, echo (retard + réinjection),
    reverb (réverbération de Schroeder : 4 filtres en peigne + 2 passe-tout), lowpass / highpass / bandpass
    (biquads RBJ), compressor, limiter (écrêtage doux), distortion, tremolo, pan (mono -> stéréo), mix
    (sec / traité), concat, speed (rééchantillonnage) ;
  - mesures : rms, peak, db, zero_crossings, estimate_pitch (autocorrélation).

  use audio.audio_effects as fx
  la := fx.sine(440, 1.0, 44100)
  la = fx.envelope(la, 44100, 0.01, 0.1, 0.7, 0.2)
  son := fx.reverb(fx.echo(la, 44100, 0.25, 0.4), 44100, 0.5)
  print(fx.estimate_pitch(la, 44100))           # ~440
```

API publique :

- `sine(frequency, seconds, rate=44100, amplitude=0.5, phase=0.0)`
- `square(frequency, seconds, rate=44100, amplitude=0.5, duty=0.5)`
- `sawtooth(frequency, seconds, rate=44100, amplitude=0.5)`
- `triangle(frequency, seconds, rate=44100, amplitude=0.5)`
- `noise(seconds, rate=44100, amplitude=0.3, seed=12345)`
- `silence(seconds, rate=44100, channels=1)`
- `chirp(f0, f1, seconds, rate=44100, amplitude=0.5)`
- `envelope(samples, rate, attack, decay, sustain, release, channels=1)`
- `db_to_gain(db)`
- `gain_to_db(g)`
- `gain(samples, factor)`
- `gain_db(samples, db)`
- `normalize(samples, level=0.95)`
- `fade_in(samples, rate, seconds, channels=1)`
- `fade_out(samples, rate, seconds, channels=1)`
- `reverse(samples, channels=1)`
- `concat(parts)`
- `mix(dry, wet_samples, wet)`
- `pan(mono, position)`
- `tremolo(samples, rate, frequency=5.0, depth=0.5)`
- `distortion(samples, drive=5.0)`
- `limiter(samples, threshold=0.9)`
- `compressor(samples, rate, threshold_db=-18.0, ratio=4.0, attack=0.01, release=0.1, makeup_db=0.0)`
- `echo(samples, rate, delay=0.3, feedback=0.4, wet=0.5, channels=1)`
- `reverb(samples, rate, room=0.5, wet=0.3)`
- class `Biquad(b0, b1, b2, a1, a2)` : `process(x)`, `run(samples)`
- `lowpass(samples, rate, cutoff, q=0.7071)`
- `highpass(samples, rate, cutoff, q=0.7071)`
- `bandpass(samples, rate, center, q=1.0)`
- `speed(samples, factor)`
- `rms(samples)`
- `peak(samples)`
- `db(samples)`
- `zero_crossings(samples)`
- `estimate_pitch(samples, rate, fmin=50.0, fmax=2000.0)`

### `audio.audio_format`

```text
Formats audio PCM et conversions :
  - AudioFormat : fréquence d'échantillonnage, nombre de canaux, format d'échantillon (« u8 », « s16le »,
    « s24le », « s32le », « f32le »), taille d'une trame, débit, noms pour les outils (aplay, ffmpeg) ;
  - encode / decode : échantillons flottants (-1.0..1.0, entrelacés) <-> octets (list[int]) ;
  - convert_channels (mono <-> stéréo, réduction / extension), resample (interpolation linéaire),
    frames <-> secondes.

  use audio.audio_format as af
  f := af.AudioFormat(48000, 2, "s16le")
  octets := af.encode(echantillons, f)
  retour := af.decode(octets, f)
  mono := af.convert_channels(stereo, 2, 1)
  x := af.resample(mono, 48000, 16000)

Erreurs : ArgumentError (format inconnu, paramètres).
```

API publique :

- `sample_size(sample_format)`
- class `AudioFormat(rate=44100, channels=1, sample_format="s16le")` : `sample_bytes()`, `frame_bytes()`, `bytes_per_second()`, `bits()`, `frames_for(seconds)`, `seconds_for(frames)`, `alsa_name()`, `ffmpeg_name()`, `pulse_name()`, `equals(other)`, `describe()`
- `encode(samples, fmt)`
- `decode(data, fmt)`
- `convert_channels(samples, from_channels, to_channels)`
- `resample(samples, from_rate, to_rate, channels=1)`
- `duration(samples, rate, channels=1)`
- `named(name)`

### `audio.audio_mixer`

```text
Table de mixage : des pistes (tampons ou sources) avec volume, panoramique, sourdine, solo, départ décalé
et boucle ; le mixeur produit le mélange stéréo (ou mono) bloc par bloc, avec un volume général, un limiteur
pour éviter l'écrêtage et des vumètres (crête, efficace) par piste et au total.

  use audio.audio_mixer as am
  m := am.Mixer(af.CD)
  batterie := m.add("batterie", tampon_batterie)
  voix := m.add("voix", tampon_voix, 0.8, -0.3)   # volume 0.8, un peu à gauche
  voix.start = 2.0                                # entre à 2 s
  m.master = 0.9
  sortie := m.render()                            # AudioBuffer complet
  flux := m.render_block(1024)                    # ou bloc par bloc (lecture en continu)
```

API publique :

- class `Track(name, buffer, volume=1.0, pan=0.0)` : `gains()`
- class `Mixer(fmt=null)` : `add(name, source, volume=1.0, pan=0.0)`, `track(name)`, `remove(name)`, `duration()`, `render()`, `render_block(frames)`, `rewind()`, `play_to(stream, block=4096)`, `describe()`
- `type_of_list(x)`

### `audio.audio_stream`

```text
Tampons et flux audio :
  - AudioBuffer : échantillons flottants (entrelacés) + format ; durée, canaux, extrait, conversion de format,
    lecture / écriture WAV, octets PCM ;
  - flux de SORTIE (write(échantillons), drain(), close()) :
      PlayerStream    lecture en continu par le lecteur du système (aplay, pw-play, paplay, ffplay) qui
                      reçoit le PCM brut sur son entrée standard ;
      WavWriter       écriture progressive d'un fichier WAV (en-tête complété à la fermeture) ;
      MemorySink      accumule en mémoire (tests, traitement) ;
  - flux d'ENTRÉE (read(trames) -> échantillons, ou [] à la fin) :
      CaptureStream   capture en continu par l'outil du système (arecord, pw-record, parecord, ffmpeg) ;
      WavReader       lecture d'un fichier WAV par morceaux ;
      MemorySource    échantillons en mémoire.

  use audio.audio_stream as st
  use audio.audio_format as af
  out := st.open_output(af.CD)                 # PlayerStream (HardwareError sans lecteur)
  out.write(echantillons)
  out.close()
  w := st.WavWriter("sortie.wav", af.VOICE)
  w.write(voix)
  w.close()
```

API publique :

- class `AudioBuffer(samples, fmt)` : `frames()`, `duration()`, `channel(i)`, `slice(start, stop=null)`, `append_buffer(other)`, `convert(fmt)`, `to_bytes()`, `save_wav(path)`, `describe()`
- `from_bytes(data, fmt)`
- `load_wav(path)`
- class `MemorySink(fmt)` : `write(samples)`, `drain()`, `close()`, `buffer()`
- class `WavWriter(path, fmt)` : `write(samples)`, `drain()`, `close()`
- `player_command(fmt, device=null, tool=null)`
- `capture_command(fmt, device=null, tool=null)`
- class `PlayerStream(fmt, device=null, command=null)` : `write(samples)`, `drain()`, `close()`, `stop()`
- `open_output(fmt=null, device=null)`
- class `MemorySource(samples, fmt)` : `read(frames)`, `close()`
- class `WavReader(path)` : `read(frames)`, `close()`
- class `CaptureStream(fmt, device=null, command=null)` : `read(frames, timeout=null)`, `close()`
- `open_input(fmt=null, device=null)`

## Paquet `microphone`

### `microphone`

```text
Le microphone pour les applications :

| Module                       | Contenu                                                              |
|------------------------------|----------------------------------------------------------------------|
| microphone.microphone_info   | micros présents (ALSA), défaut, recherche par nom                    |
| microphone.audio_input       | AudioInput : lecture par blocs, gain, porte de bruit, niveaux, async |
| microphone.capture           | Recorder : durée fixe, jusqu'au silence, vers WAV ; segments         |

  use microphone
  if microphone.available():
      b := microphone.record(3.0)              # 3 s, 16 kHz mono (audio_stream.AudioBuffer)
      b.save_wav("note.wav")
      print(microphone.level(b))               # dBFS

Capture par arecord, pw-record, parecord ou ffmpeg (HardwareError si aucun n'est installé).
```

API publique :

- `microphones()`
- `default()`
- `available()`
- `open(fmt=null, device=null)`
- `recorder(fmt=null, device=null)`
- `record(seconds, fmt=null, device=null)`
- `record_to_wav(path, seconds, fmt=null, device=null)`
- `level(buf)`

### `microphone.audio_input`

```text
Une entrée audio ouverte : lecture par blocs depuis un micro (outil de capture du système) ou depuis une autre
source (fichier WAV, mémoire, commande), gain numérique, porte de bruit, mesure de niveau (crête, efficace,
dBFS) et rappels par bloc ; boucle asynchrone (asyncio) pour traiter le son pendant que l'application tourne.

  use microphone.audio_input as ai
  entree := ai.AudioInput(af.VOICE)                # micro par défaut ; AudioInput(fmt, "plughw:1,0")
  fichier := ai.AudioInput(null, null, ast.WavReader("voix.wav"))
  entree.on_block((bloc) => print(entree.level_db()))
  await entree.run(5.0)                            # 5 s de capture, rappel à chaque bloc
  bloc := entree.read(1600)                        # ou lecture directe (0,1 s à 16 kHz)
  entree.close()
```

API publique :

- class `AudioInput(fmt=null, device=null, stream=null, block_frames=null)` : `set_gain_db(db)`, `on_block(fn)`, `read(frames=null, timeout=null)`, `level_db()`, `peak_db()`, `elapsed()`, `stop()`, `run(duration=null)`, `close()`

### `microphone.capture`

```text
Enregistrer : durée fixe, jusqu'au silence (détection d'activité vocale par l'énergie, avec temps de
maintien), vers un fichier WAV pendant la capture, ou découpage d'un enregistrement en segments de parole.

  use microphone.capture as cap
  r := cap.Recorder(af.VOICE)                       # micro par défaut
  b := r.record(3.0)                                # AudioBuffer de 3 s
  b = r.record_until_silence(10.0, 0.8)             # au plus 10 s, s'arrête après 0,8 s de silence
  r.record_to_wav("note.wav", 5.0)
  for seg in cap.split_on_silence(b):               # [début, fin] en secondes
      print(seg)
```

API publique :

- class `Recorder(fmt=null, device=null, stream=null)` : `record(seconds)`, `record_until_silence(max_seconds, silence=0.8, wait_speech=true)`, `record_to_wav(path, seconds)`, `close()`
- `split_on_silence(buf, threshold_db=-40.0, block=0.02, min_gap=0.3)`

### `microphone.microphone_info`

```text
Les microphones de la machine (Linux : entrées ALSA de /proc/asound) : nom, carte, périphérique, nom ALSA,
pilote de la carte, branchement USB, et le micro par défaut du système (serveur de son).

  use microphone.microphone_info as mi
  for m in mi.microphones():
      print(m.describe())                 # « plughw:1,0 USB Audio (carte 1, snd-usb-audio, USB) »
  m := mi.default()
```

API publique :

- class `MicrophoneInfo(card, device, name)` : `is_default()`, `alsa_name(plug=true)`, `describe()`
- `microphones()`
- `default()`
- `available()`
- `find(text)`

## Paquet `camera`

### `camera`

```text
Caméras pour les applications :

| Module                   | Contenu                                                                   |
|--------------------------|---------------------------------------------------------------------------|
| camera.camera_device     | caméras présentes, formats proposés, ouverture                            |
| camera.camera_capture    | capture en continu (ffmpeg), mire de test, photo, enregistrement vidéo    |
| camera.camera_format     | CameraFormat (taille, format des points, cadence), v4l2-ctl               |
| camera.video_frame       | VideoFrame : conversions YUV / RGB, recadrage, mouvement, PPM / PGM       |

  use camera
  c := camera.open()                         # caméra par défaut, 640x480 (mire de test si aucune)
  img := c.read()
  img.save_ppm("photo.ppm")
  c.close()

Capture : ffmpeg (HardwareError s'il est absent).
```

API publique :

- `cameras()`
- `available()`
- `open(width=640, height=480, fallback_pattern=true)`
- `snapshot(width=640, height=480)`
- `test_pattern(width=320, height=240)`
- `load(path)`

### `camera.camera_capture`

```text
Capture d'images en continu : ffmpeg lit la caméra (Video4Linux, ou une mire de test « lavfi », ou un fichier
vidéo) et livre des images brutes de taille fixe sur sa sortie standard ; CameraCapture les découpe en
VideoFrame (numéro, instant), mesure la cadence réelle, et propose : une image (snapshot), n images, un
flux asynchrone avec rappel par image, et l'enregistrement direct d'une vidéo.

  use camera.camera_capture as cc
  use camera.camera_format as cf
  cap := cc.CameraCapture("/dev/video0", cf.CameraFormat(640, 480, "rgb24", 30))
  img := cap.read()                         # VideoFrame (null à la fin du flux)
  cap.on_frame((f) => traiter(f))
  await cap.run(5.0)                        # 5 s d'images, rappel à chaque image
  cap.close()
  mire := cc.test_pattern(cf.QVGA)          # sans caméra : mire animée de ffmpeg

Erreurs : HardwareError (ffmpeg absent, caméra inaccessible).
```

API publique :

- `ffmpeg_available()`
- `input_args(source, fmt)`
- class `CameraCapture(source, fmt=null, output="rgb24", max_frames=null)` : `read(timeout=10.0)`, `grab(n)`, `measured_fps()`, `on_frame(fn)`, `stop()`, `run(duration=null)`, `close()`
- `test_pattern(fmt=null, output="rgb24", pattern="testsrc")`
- `snapshot(source, fmt=null, output="rgb24")`
- `record(source, path, seconds, fmt=null)`

### `camera.camera_device`

```text
Les caméras de la machine (Linux : Video4Linux, via hardware.camera) : nom, nœud /dev/videoN, pilote, bus,
formats proposés (v4l2-ctl --list-formats-ext s'il est installé), choix d'un format proche de la taille
voulue, ouverture d'une capture.

  use camera.camera_device as cd
  for c in cd.cameras():
      print(c.describe())                 # « /dev/video0 Integrated Camera (uvcvideo, usb) »
      for f in c.formats():
          print(f.describe())             # « 1280x720 mjpeg 30 i/s »
  cap := cd.default().open(1280, 720)     # camera_capture.CameraCapture
```

API publique :

- class `CameraDevice(info)` : `formats()`, `best_format(width, height, pixel_format=null)`, `open(width=640, height=480, output="rgb24")`, `snapshot(width=640, height=480)`, `describe()`
- `cameras()`
- `default()`
- `available()`

### `camera.camera_format`

```text
Formats d'image d'une caméra : dimensions, format des points (« rgb24 », « bgr24 », « rgba », « gray »,
« yuyv422 », « nv12 », « mjpeg »), images par seconde ; taille d'une image brute, noms Video4Linux (fourcc)
et ffmpeg, résolutions courantes, et lecture de la liste « v4l2-ctl --list-formats-ext ».

  use camera.camera_format as cf
  f := cf.CameraFormat(640, 480, "yuyv422", 30)
  print(f.frame_bytes(), f.fourcc(), f.describe())     # 614400 YUYV « 640x480 yuyv422 30 i/s »
  formats := cf.parse_v4l2_formats(texte)
```

API publique :

- `bytes_per_pixel_x2(pixel_format)`
- class `CameraFormat(width=640, height=480, pixel_format="rgb24", fps=30)` : `pixels()`, `frame_bytes()`, `size_text()`, `fourcc()`, `ffmpeg_name()`, `aspect()`, `with_pixel_format(p)`, `describe()`
- `from_fourcc(code)`
- `parse_v4l2_formats(text)`
- `closest(formats, width, height, pixel_format=null)`

### `camera.video_frame`

```text
Une image vidéo : dimensions, format des points, octets (list[int]), numéro et instant de capture ;
conversions (YUYV / NV12 / BGR / gris -> RGB, RGBA pour ui.canvas), accès aux points, recadrage,
redimensionnement (plus proche voisin), miroir, niveaux de gris, luminosité moyenne, histogramme,
différence entre deux images (détection de mouvement), écriture / lecture PPM et PGM.

  use camera.video_frame as vf
  rgb := image.to_rgb()                       # VideoFrame en rgb24
  print(rgb.pixel(10, 10))                    # [r, g, b]
  petit := rgb.resize(160, 120)
  petit.save_ppm("photo.ppm")
  if vf.motion(avant, apres) > 0.02:          # proportion de points qui ont changé
      print("mouvement")
  canvas_put_pixels(c, 0, 0, w, h, rgb.to_rgba_bytes())
```

API publique :

- `yuv_to_rgb(y, u, v)`
- `rgb_to_yuv(r, g, b)`
- class `VideoFrame(width, height, pixel_format, data, index=0, timestamp=0.0)` : `format()`, `valid()`, `to_rgb()`, `pixel(x, y)`, `to_gray()`, `to_rgba_bytes()`, `crop(x, y, w, h)`, `resize(w, h)`, `mirror()`, `brightness()`, `histogram(bins=16)`, `save_ppm(path)`, `save_pgm(path)`, `describe()`
- `load_pnm(path)`
- `motion(a, b, threshold=25)`
- `solid(width, height, r, g, b)`

## Paquet `gpu`

### `gpu`

```text
Cartes graphiques et calcul parallèle pour les applications :

| Module            | Contenu                                                                         |
|-------------------|---------------------------------------------------------------------------------|
| gpu.gpu_info      | modèle, pilote, VRAM, charge, température, fréquences (sysfs, nvidia-smi)       |
| gpu.gpu_device    | GpuDevice : carte + calcul + mémoire (logiciel si pas de dorsal matériel)       |
| gpu.gpu_memory    | GpuMemory / GpuBuffer : tampons typés, upload / download, capacité              |
| gpu.gpu_compute   | ComputeDevice : noyaux sur une grille, saxpy, matmul, convolution, histogramme  |

  use gpu
  for g in gpu.list():
      print(g.describe())
  dev := gpu.device()
  print(dev.compute.dot([1.0, 2.0], [3.0, 4.0]))       # 11.0
  dev.close()

Le rendu graphique (contextes, tampons, textures, shaders, pipeline) est dans le paquet graphics ; les
pilotes de carte d'un noyau Alex dans gpu_driver.
```

API publique :

- `list()`
- `primary()`
- `available()`
- `len_of(xs)`
- `device(backend="threads", workers=null)`
- `compute(backend="threads", workers=null)`

### `gpu.gpu_compute`

```text
Calcul data-parallèle « façon GPU » : un NOYAU (kernel) est appliqué à une grille d'indices découpée en
groupes de travail ; le ComputeDevice exécute les groupes en série ou EN PARALLÈLE sur les cœurs du
processeur (thread.thread_pool). Le même code tournera sur un vrai GPU quand un dorsal (Vulkan / OpenCL)
sera branché : l'API ne change pas.

Un noyau est une fonction de PREMIER NIVEAU d'un module : kernel(début, fin, arg1, arg2...) qui renvoie la
list des résultats des indices [début, fin). Ses arguments sont copiés vers les fils.

  use gpu.gpu_compute as gc
  func carre(debut, fin, xs):                        # premier niveau
      return [xs[i] * xs[i] for i in debut..fin]
  if thread.is_main():
      dev := gc.ComputeDevice("threads", 4)
      r := dev.dispatch(carre, 1000, [donnees], 256)  # 1000 éléments, groupes de 256
      y := dev.saxpy(2.0, x, y0)                       # noyaux fournis : saxpy, add, scale, dot, sum,
      c := dev.matmul(a, b, n, m, p)                   # matmul, convolve2d, map_lut, histogram
      dev.shutdown()

Dorsaux : "serial" (un seul fil, toujours disponible), "threads" (ThreadPool).
```

API publique :

- `k_saxpy(start, stop, a, x, y)`
- `k_add(start, stop, x, y)`
- `k_mul(start, stop, x, y)`
- `k_scale(start, stop, a, x)`
- `k_sum(start, stop, x)`
- `k_dot(start, stop, x, y)`
- `k_matmul(start, stop, a, b, m, p)`
- `k_convolve(start, stop, img, w, h, kern, kw, kh)`
- `k_lut(start, stop, x, table)`
- `k_histogram(start, stop, x, bins)`
- class `ComputeDevice(backend="threads", workers=null)` : `name()`, `dispatch(kernel, n, args, group=null)`, `saxpy(a, x, y)`, `add(x, y)`, `mul(x, y)`, `scale(a, x)`, `sum(x)`, `dot(x, y)`, `matmul(a, b, n, m, p)`, `convolve2d(img, w, h, kern, kw, kh)`, `map_lut(x, table)`, `histogram(x, bins)`, `shutdown()`, `describe()`

### `gpu.gpu_device`

```text
Un périphérique graphique / de calcul pour l'application : la carte (gpu.gpu_info) quand il y en a une, et
le moyen d'y calculer (gpu.gpu_compute.ComputeDevice) et d'y placer des données (gpu.gpu_memory.GpuMemory).
Sans carte, ou sans dorsal matériel, le périphérique « logiciel » (processeur, plusieurs fils) est fourni.

  use gpu.gpu_device as gd
  dev := gd.default()
  print(dev.describe())
  buf := dev.memory.upload([1.0, 2.0])
  r := dev.compute.scale(3.0, buf.download())
  dev.close()
```

API publique :

- class `GpuDevice(info=null, backend="threads", workers=null)` : `is_software()`, `name()`, `describe()`, `close()`
- `devices(backend="threads", workers=null)`
- `default(backend="threads", workers=null)`
- `software(workers=null)`

### `gpu.gpu_info`

```text
Informations et télémétrie des cartes graphiques (Linux) : modèle (table PCI), pilote, mémoire vidéo totale
et utilisée, charge, fréquences, température, puissance, version du pilote — lues dans /sys/class/drm
(amdgpu, i915 / xe, nouveau, virtio) et ses capteurs hwmon, ou par « nvidia-smi » pour le pilote NVIDIA.
Les valeurs inconnues valent null.

  use gpu.gpu_info as gi
  for g in gi.gpus():
      print(g.describe())                 # « NVIDIA GeForce RTX 3060 (nvidia 550.54) : 12 Gio, 31 °C, 3 % »
  print(gi.gpus()[0].refresh().temperature)
```

API publique :

- class `GpuInfo(hw)` : `name()`, `refresh()`, `vram_free()`, `describe()`
- `parse_nvidia_line(line)`
- `gpus()`
- `primary()`

### `gpu.gpu_memory`

```text
Mémoire d'un périphérique de calcul : tampons typés (float32, int32, uint8...) avec forme (dimensions),
copie vers le périphérique (upload) et retour (download), réserve qui compte les octets alloués et refuse
au-delà de la capacité (comme une vraie VRAM), statistiques.

  use gpu.gpu_memory as gm
  mem := gm.GpuMemory(256 * 1048576)
  a := mem.upload([1.0, 2.0, 3.0, 4.0], "float32", [2, 2])
  b := mem.zeros("float32", [2, 2])
  print(a.get(1, 0), a.size_bytes())       # 3.0 16
  x := a.download()                        # list (copie)
  mem.free(a)
```

API publique :

- `dtype_size(dtype)`
- class `GpuBuffer(memory, dtype, shape, data, id)` : `count()`, `size_bytes()`, `get(i, j=0)`, `set(i, j, v)`, `download()`, `write(values)`, `reshape(shape)`, `describe()`
- class `GpuMemory(capacity)` : `allocate(dtype, shape, fill=0)`, `zeros(dtype, shape)`, `upload(values, dtype="float32", shape=null)`, `free(b)`, `available()`, `live()`, `describe()`

## Paquet `graphics`

### `graphics`

```text
Rendu 2D / 3D pour les applications, sur un pipeline LOGICIEL écrit en Alex (aucun pilote nécessaire) :

| Module                    | Contenu                                                                   |
|---------------------------|---------------------------------------------------------------------------|
| graphics.context          | Context : création des objets, soumission, statistiques                   |
| graphics.surface          | Surface : couleurs RGBA + profondeur, mélange, PPM, octets pour ui        |
| graphics.buffer           | VertexLayout, VertexBuffer, IndexBuffer, UniformBuffer, cube, quad        |
| graphics.texture          | Texture : échantillonnage (plus proche / bilinéaire), mipmaps, motifs     |
| graphics.shader           | Shader (sommets + fragments en Alex), matrices 4x4, shaders fournis       |
| graphics.pipeline         | Pipeline : découpage, élimination, rastérisation, profondeur, mélange     |
| graphics.render_pass      | RenderPass : effacement, viewport, dessins                                |
| graphics.command_buffer   | CommandBuffer : enregistrement puis exécution                             |
| graphics.swapchain        | Swapchain : images multiples, présentation (fenêtre ui, fichiers, mémoire)|

  use graphics
  img := graphics.render_triangle(160, 120)         # Surface : triangle coloré
  img.save_ppm("triangle.ppm")
  img = graphics.render_cube(160, 120, 0.6)          # cube éclairé, tourné de 0,6 rad

Les cartes d'un noyau Alex se pilotent avec gpu_driver ; le calcul parallèle est dans gpu.
```

API publique :

- `context()`
- `surface(width, height)`
- `rgba(r, g, b, a=1.0)`
- `render_triangle(width, height)`
- `render_cube(width, height, angle)`

### `graphics.buffer`

```text
Tampons de données du rendu :
  - VertexLayout : description d'un sommet (attributs nommés et leur nombre de composantes, ex. position 3,
    couleur 4, uv 2) ;
  - VertexBuffer : sommets entrelacés (flottants) suivant un layout ; vertex(i) -> list d'attributs ;
  - IndexBuffer : indices de sommets (triangles indexés) ;
  - UniformBuffer : valeurs constantes pour un appel de dessin (matrices, couleurs, lumière) par nom.

  lay := VertexLayout([["position", 3], ["color", 4]])
  vb := VertexBuffer(lay, [0.0, 0.5, 0.0, 1.0, 0.0, 0.0, 1.0,  -0.5, -0.5, 0.0, 0.0, 1.0, 0.0, 1.0, ...])
  ib := IndexBuffer([0, 1, 2])
  u := UniformBuffer({"mvp": m})
```

API publique :

- class `VertexLayout(attributes)` : `has(name)`, `offset(name)`, `size(name)`, `describe()`
- class `VertexBuffer(layout, data)` : `count()`, `vertex(i)`, `attribute(i, name)`, `update(data)`
- class `IndexBuffer(indices)` : `count()`, `max_index()`
- class `UniformBuffer(values=null)` : `set(name, value)`, `get(name, fallback=null)`, `names()`
- `fullscreen_quad()`
- `cube()`

### `graphics.command_buffer`

```text
Tampon de commandes de rendu (comme Vulkan / Metal) : on ENREGISTRE la suite des opérations d'une image,
puis on la SOUMET d'un coup (graphics.context.Context.submit) ; le même tampon peut être rejoué. Commandes :
begin_pass / end_pass, bind_pipeline, bind_vertices, bind_indices, set_uniform, set_viewport, draw,
copy_surface (blit d'une surface dans une autre), callback (code Alex arbitraire, ex. mise à jour d'un
uniform animé).

  cb := CommandBuffer()
  cb.begin_pass(cible, gs.rgba(0, 0, 0))
  cb.bind_pipeline(p)
  cb.bind_vertices(vb)
  cb.set_uniform("mvp", mvp)
  cb.draw()
  cb.end_pass()
  ctx.submit(cb)
```

API publique :

- class `CommandBuffer(label="commandes")` : `begin_pass(target, clear_color=0xFF000000, load="clear")`, `end_pass()`, `bind_pipeline(p)`, `bind_vertices(vb)`, `bind_indices(ib)`, `set_uniform(name, value)`, `set_viewport(x, y, w, h)`, `draw()`, `copy_surface(src, dst, x, y, blend=true)`, `callback(fn)`, `finish()`, `reset()`, `count()`
- `execute(cb)`

### `graphics.context`

```text
Contexte de rendu : le point d'entrée qui crée les objets (surfaces, tampons, textures, pipelines,
tampons de commandes, chaîne d'images) et exécute les soumissions, avec des statistiques par image.
Le moteur est LOGICIEL (pipeline en Alex) : il fonctionne partout, sans pilote, en VM comme dans une
application ; les mêmes objets serviront à un dorsal matériel.

  use graphics.context as gctx
  ctx := gctx.Context()
  sc := ctx.swapchain(320, 240)
  p := ctx.pipeline(sh.vertex_color())
  cb := ctx.commands()
  ...
  ctx.submit(cb)
  sc.present()
```

API publique :

- class `Context(name="logiciel")` : `surface(width, height, depth=true)`, `vertex_buffer(layout, data)`, `index_buffer(indices)`, `uniforms(values=null)`, `texture(width, height, pixels=null)`, `pipeline(shader, topology="triangles")`, `render_pass(target, load="clear")`, `commands(label="commandes")`, `swapchain(width, height, images=2, presenter=null)`, `submit(cb)`, `describe()`

### `graphics.pipeline`

```text
Pipeline graphique logiciel (comme celui d'une carte, en Alex) :
  1. nuanceur de sommets (graphics.shader) pour chaque sommet ;
  2. assemblage : triangles (listes, ou indexés), lignes, points ;
  3. découpage par le plan proche (w > 0), division perspective, transformation vers la fenêtre ;
  4. élimination des faces arrière (sens trigonométrique = face avant) ;
  5. rastérisation par fonctions d'arêtes au centre des points, interpolation des varyings CORRIGÉE en
     perspective ;
  6. test et écriture de profondeur, nuanceur de fragments, mélange (aucun, alpha, additif).

  p := Pipeline(sh.vertex_color())
  p.cull = "back"
  p.blend = "alpha"
  stats := p.draw(surface, vb, null, uniforms)      # dict triangles, fragments, rejected, culled

Les statistiques du dernier dessin sont dans p.stats.
```

API publique :

- class `Pipeline(shader, topology="triangles")` : `draw(surface, vb, ib=null, uniforms=null, viewport=null)`
- `type_is_list(x)`

### `graphics.render_pass`

```text
Passe de rendu : une cible (graphics.surface.Surface), ce qu'on fait de son contenu au début (effacer à une
couleur / profondeur, ou conserver) et la zone de dessin (viewport, ciseaux) ; les dessins de la passe s'y
accumulent ; à la fin, statistiques cumulées.

  rp := RenderPass(surface)
  rp.clear_color = gs.rgba(0.1, 0.1, 0.15)
  rp.begin()
  rp.draw(pipeline, vb, null, uniforms)
  rp.end()
  print(rp.totals)
```

API publique :

- class `RenderPass(target, load="clear")` : `begin()`, `draw(pipeline, vb, ib=null, uniforms=null)`, `end()`, `describe()`

### `graphics.shader`

```text
Shaders en Alex et mathématiques 3D :
  - vecteurs (list de 3 / 4 flottants) et matrices 4x4 (list de 16 flottants, ligne par ligne, vecteurs en
    colonne) : identity, mul, translate, scale, rotate_x / y / z, perspective, orthographic, look_at,
    transform, normal_matrix, dot, cross, normalize ;
  - Shader : un nuanceur de SOMMETS vertex(attributs, uniforms) -> [position (x, y, z, w), varyings] et un
    nuanceur de FRAGMENTS fragment(varyings, uniforms) -> [r, g, b, a] (0..1) ou null (fragment rejeté) ;
    les varyings (list de flottants) sont interpolés en perspective entre les sommets ;
  - shaders fournis : couleur par sommet, couleur unie, texture (avec teinte), éclairage de Lambert
    (lumière directionnelle + ambiante, texture facultative), profondeur (gris).

  use graphics.shader as sh
  mvp := sh.mul(sh.perspective(1.0, 4.0 / 3.0, 0.1, 100.0), sh.look_at([0.0, 0.0, 3.0], [0.0, 0.0, 0.0], [0.0, 1.0, 0.0]))
  prog := sh.vertex_color()
  func mon_fragment(v, u):
      return [v[0], 0.0, 1.0 - v[0], 1.0]
  perso := sh.Shader(sh.vs_vertex_color, mon_fragment, 4, "perso")
```

API publique :

- `dot(a, b)`
- `cross(a, b)`
- `length(a)`
- `normalize(a)`
- `sub(a, b)`
- `add(a, b)`
- `scale3(a, s)`
- `identity()`
- `mul(a, b)`
- `chain(ms)`
- `translate(x, y, z)`
- `scale(x, y, z)`
- `rotate_x(a)`
- `rotate_y(a)`
- `rotate_z(a)`
- `perspective(fovy, aspect, near, far)`
- `orthographic(left, right, bottom, top, near, far)`
- `look_at(eye, target, up)`
- `transform(m, v)`
- `transform_dir(m, v)`
- class `Shader(vertex, fragment, varyings, name="shader")`
- `vs_vertex_color(attrs, u)`
- `fs_vertex_color(v, u)`
- `vertex_color()`
- `vs_position(attrs, u)`
- `fs_solid(v, u)`
- `solid()`
- `vs_textured(attrs, u)`
- `fs_textured(v, u)`
- `textured()`
- `vs_lit(attrs, u)`
- `fs_lit(v, u)`
- `lit()`
- `vs_depth(attrs, u)`
- `fs_depth(v, u)`
- `depth()`

### `graphics.surface`

```text
Surface de rendu : tampon de couleurs (points RGBA empaquetés 0xAARRGGBB) et tampon de profondeur
(flottants, 1.0 = le plus loin) de largeur x hauteur ; effacement, lecture / écriture de points, mélange
alpha, copie, comparaison, export (octets RGBA pour ui.canvas_put_pixels, PPM) et conversion en
camera.video_frame.VideoFrame.

  use graphics.surface as gs
  s := gs.Surface(320, 240)
  s.clear(gs.rgba(0.1, 0.1, 0.2, 1.0))
  s.set_pixel(10, 10, gs.pack(255, 0, 0, 255))
  s.save_ppm("image.ppm")
```

API publique :

- `pack(r, g, b, a=255)`
- `rgba(r, g, b, a=1.0)`
- `unpack(c)`
- `to_floats(c)`
- `blend_over(dst, src)`
- `blend_add(dst, src)`
- class `Surface(width, height, depth=true)` : `clear(color=0xFF000000)`, `clear_depth(value=1.0)`, `pixel(x, y)`, `set_pixel(x, y, c)`, `fill_rect(x, y, w, h, c)`, `draw_surface(src, dx, dy, blend=true)`, `copy()`, `diff(other, tolerance=0)`, `count(c)`, `checksum()`, `to_rgba_bytes()`, `to_rgb_list()`, `save_ppm(path)`, `describe()`

### `graphics.swapchain`

```text
Chaîne d'images à présenter : plusieurs surfaces (double / triple tampon) ; on dessine dans l'image acquise
pendant que la précédente est montrée, puis on la PRÉSENTE à une destination :
  - WindowPresenter : un canvas d'une fenêtre du module ui (ui.canvas_put_pixels, X11 / sans écran) ;
  - FilePresenter : une image PPM par présentation (séquence « image_0001.ppm »...) ;
  - MemoryPresenter : garde la dernière image (tests, capture d'écran) ;
avec mesure de la cadence (images par seconde) et limite facultative.

  sc := Swapchain(320, 240, 2, MemoryPresenter())
  s := sc.acquire()
  ...dessiner dans s...
  sc.present()
  print(sc.fps())
```

API publique :

- class `MemoryPresenter()` : `present(surface)`
- class `FilePresenter(prefix)` : `present(surface)`
- class `WindowPresenter(ui_module, canvas, x=0, y=0)` : `present(surface)`
- class `Swapchain(width, height, images=2, presenter=null, depth=true)` : `acquire()`, `present()`, `fps()`, `resize(width, height)`

### `graphics.texture`

```text
Textures : images RGBA (points empaquetés comme graphics.surface) échantillonnées par coordonnées (u, v)
dans 0..1 : filtrage au plus proche ou bilinéaire, répétition ou bord étiré, mipmaps (réductions par 2) et
choix du niveau ; création depuis une Surface, une camera.video_frame.VideoFrame, une liste de points, ou
des motifs (damier, dégradé).

  use graphics.texture as gt
  t := gt.checkerboard(64, 64, 8, 0xFFFFFFFF, 0xFF000000)
  t.filter = "linear"
  c := t.sample(0.25, 0.75)                     # [r, g, b, a] (0..1)
```

API publique :

- class `Texture(width, height, pixels=null)` : `get(x, y)`, `set(x, y, c)`, `sample(u, v)`, `build_mipmaps()`, `level(texels_per_pixel)`, `to_surface()`
- `from_surface(s)`
- `from_frame(frame)`
- `checkerboard(width, height, cell, a, b)`
- `gradient(width, height, a, b)`
- `solid(width, height, c)`

