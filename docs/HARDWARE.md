# Matériel : `hardware.keyboard`, `mouse`, `screen`, `gpu`, `usb`, `audio`, `microphone`, `camera`

```
use hardware.screen as screen
use hardware.usb as usb
use hardware.audio as audio

s := screen.primary()
print(s.model, s.resolution, s.diagonal_inches())         # DELL U2720Q [3840, 2160] 27.0
for d in usb.devices(false):
    print(d.id(), d.name(), d.classes)                    # 046d:c52b Logitech USB Receiver [hid]
audio.write_wav("la.wav", audio.tone(440, 0.5))
audio.play("la.wav")
```

| Module | Rôle |
|---|---|
| `hardware.keyboard` | `keyboards()` → `Keyboard` (`name`, `path`, `phys`, `vendor_id`, `product_id`, `bus`), `available()`, `open(clavier)` → lecteur dont `read(délai)` renvoie un `KeyEvent` (`key`, `code`, `action` = `press` / `release` / `repeat`, `time`, `pressed()`), `key_name(code)`, `read_terminal_key(délai)` (= `io.console.read_key`) |
| `hardware.mouse` | `mice()` → `Mouse` (`name`, `path`, `touchpad`...), `available()`, `open(souris)` → lecteur dont `read(délai)` renvoie un `MouseEvent` (`dx`, `dy`, `wheel`, `hwheel`, `buttons` {`left`: true...}, `moved()`) |
| `hardware.screen` | `outputs()` / `screens()` (branchés) / `primary()` → `Screen` (`name`, `card`, `connected`, `enabled`, `resolution`, `modes`, `width_mm`, `height_mm`, `manufacturer`, `model`, `serial`, `year`, `diagonal_inches()`, `dpi()`), `framebuffers()`, `parse_edid(octets)`, `parse_xrandr(texte)` |
| `hardware.gpu` | `gpus()` / `primary()` → `Gpu` (`slot`, `vendor`, `vendor_id`, `device_id`, `kind`, `driver`, `card`, `render_node`, `boot_vga`, `vram`), `vendor_name(id)` |
| `hardware.usb` | `devices(hubs)` → `UsbDevice` (`id()`, `name()`, `vendor_id`, `product_id`, `manufacturer`, `product`, `serial`, `bus`, `address`, `node()`, `speed_mbps`, `usb_version`, `classes`, `driver`, `max_power_ma`, `is_hub()`), `find(fabricant, produit)`, `by_class("hid")`, `class_name(code)` |
| `hardware.audio` | `cards()`, `devices()` / `outputs()` / `inputs()` → `AudioDevice` (`alsa_name()`, `playback`, `capture`) ; sons `tone`, `silence`, `mix`, `rms`, `peak` ; WAV `write_wav`, `read_wav` → `Wav` (`samples`, `rate`, `channels`, `bits`, `frames()`, `duration()`, `channel(i)`), `encode_wav`, `decode_wav` ; `play(fichier ou échantillons)`, `player()`, `beep()` |
| `hardware.microphone` | `microphones()`, `available()`, `recorder()`, `record(fichier, secondes, fréquence, canaux, périphérique)`, `level(fichier)` |
| `hardware.camera` | `cameras()` / `all_nodes()` / `primary()` → `Camera` (`node`, `path`, `name`, `index`, `driver`, `bus`), `tool()`, `capture(fichier, caméra, largeur, hauteur)`, `record(fichier, secondes...)` |

## Principes

- **Source des informations** : l'inventaire vient de ce que Linux publie : `/sys/class/drm`,
  `/sys/bus/pci/devices`, `/sys/bus/usb/devices`, `/sys/class/video4linux`, `/sys/class/graphics`,
  `/proc/bus/input/devices` et `/proc/asound`. Sur une autre plateforme, ou si ces fichiers sont absents
  (conteneur, machine virtuelle), les listes sont vides et `available()` vaut `false`. Aucune erreur n'est
  levée. `hardware.screen` interroge en plus `xrandr` quand `/sys/class/drm` est vide et qu'un affichage X
  est ouvert.
- **Événements bruts** (`keyboard.open`, `mouse.open`) : les nœuds `/dev/input/eventN` (interface evdev) sont
  lus directement. Le programme reçoit chaque appui et relâchement, toutes les touches et les mouvements
  relatifs de la souris, même sans terminal ni interface graphique. Il faut les droits sur `/dev/input` (root
  ou groupe `input`), sinon `HardwareError` avec l'indication. Lectures non bloquantes avec délai : `null`
  après le délai.
- **EDID** : fabricant (code à 3 lettres), nom et numéro de série de l'écran, année, taille physique,
  et mode préféré quand le pilote ne publie pas de modes.
- **Son** : les échantillons sont des `float` de -1 à 1, entrelacés par canal. Les WAV en PCM entier
  8/16/24/32 bits et flottant 32 bits (y compris `WAVE_FORMAT_EXTENSIBLE`) sont lus. L'écriture se fait en PCM
  entier. La lecture et l'enregistrement passent par les outils du système : `pw-play`, `paplay`, `aplay`,
  `afplay` ou `ffplay` pour lire ; `arecord`, `pw-record`, `parecord`, `ffmpeg` ou `rec` pour enregistrer.
- **Caméra** : la capture passe par `ffmpeg` (v4l2) ou `fswebcam`. `cameras()` ne garde que les nœuds d'image
  (`index` 0), pas les nœuds de métadonnées des webcams UVC.
- **Erreurs** : `HardwareError` (aucun périphérique, droits, outil absent, échec de l'outil), `ArgumentError`
  (paramètres, WAV invalide).
- **Tests et outils** : `hardware._sys.set_root(dossier)` ou la variable `ALEX_HW_ROOT` font lire une copie
  de `/sys`, `/proc` et `/dev` au lieu du vrai système.

Ajouts au module natif `_native_fd` : `open_device(chemin, écriture)` (ouverture non bloquante d'un
périphérique) et `readlink(chemin)` (pilote d'un périphérique).

## Tests

`make test-hardware` : `tests/hardware/test_hardware.al` (59 vérifications). Le test construit une copie de
`/sys`, `/proc` et `/dev` avec :

- un clavier, une souris et un bouton d'alimentation, qui doit être écarté ;
- des événements evdev encodés ;
- deux sorties vidéo, dont un écran avec un EDID complet ;
- trois cartes graphiques (PCI et DRM seul) ;
- trois périphériques USB et deux cartes son ;
- quatre nœuds vidéo.

Il vérifie aussi les WAV (aller-retour 8 à 32 bits, stéréo, flottant), puis le vrai système.
