# Matériel vu des applications : `hardware` (suite) et `usb`

Compléments au document HARDWARE.md : la façade `hardware`, les informations sur la machine, la carte
mémoire, les droits d'accès, l'inventaire des périphériques, et le paquet `usb` qui parle directement aux
périphériques USB par usbfs.

```
use hardware
use usb

print(hardware.summary())                      # machine, processeur, mémoire, périphériques
print(hardware.can_use("camera"))              # droits sur /dev/video*
print(usb.lsusb(true))                         # descripteurs complets lus dans /sys
d := usb.find(0x2341)                          # Arduino
h := d.open()                                  # usbfs (droits : hardware.permissions.udev_rule)
h.claim(0, true)
print(h.endpoint(0x81).read(64, 1000).data)
```

Tests : `make test-hardware-ext` (hardware 25, usb 20 vérifications ; l'USB est testé sur une copie
factice de /sys et /dev construite par `tests/usb/make_fake_usb.py`).

## Paquet `hardware`

### `hardware`

```text
Point d'entrée du matériel vu depuis une APPLICATION (système hôte, Linux surtout) :

| Module                     | Rôle                                                                     |
|----------------------------|--------------------------------------------------------------------------|
| hardware.hardware_info     | processeur, mémoire, micrologiciel, hyperviseur, noyau                   |
| hardware.device            | un périphérique de /sys (sous-système, pilote, nœud /dev, attributs)     |
| hardware.device_info       | sa description lisible (catégorie, fabricant, modèle)                    |
| hardware.device_manager    | inventaire, regroupements, suivi des branchements                        |
| hardware.memory_map        | carte de la mémoire physique et des projections d'un processus           |
| hardware.permissions       | droits sur les nœuds /dev, groupes, capacités, règles udev               |
| hardware.keyboard / mouse / screen / gpu / usb / audio / microphone / camera | inventaires spécialisés |

Pour écrire des PILOTES (noyau Alex ou machine simulée) : pci, interrupt, dma, driver, storage_driver,
network_driver, usb_driver, gpu_driver (docs/HARDWARE_DRIVERS.md).

  use hardware
  print(hardware.summary())                    # machine, processeur, mémoire, périphériques par catégorie
  for d in hardware.devices("réseau"):
      print(d.summary())
  print(hardware.can_use("camera"))
```

API publique :

- `info()`
- `cpu()`
- `memory()`
- `firmware()`
- `hypervisor()`
- `memory_map()`
- `manager(subsystems=null)`
- `devices(category=null)`
- `device(subsystem, name)`
- `census()`
- `can_use(category, want="rw")`
- `identity()`
- `summary()`

### `hardware.audio`

```text
Son : cartes et périphériques audio (Linux : ALSA, /proc/asound), fichiers WAV (lecture, écriture),
génération de sons (tone, silence, mix) et lecture par le lecteur du système (aplay, paplay, pw-play,
afplay sous macOS, ffplay).

Les échantillons sont des float de -1.0 à 1.0, entrelacés si plusieurs canaux ([g0, d0, g1, d1, ...]).

Exemple
  use hardware.audio as audio
  la := audio.tone(440, 0.5)                  # 0,5 s de la 440 Hz
  audio.write_wav("la.wav", la, 44100)
  audio.play("la.wav")                        # HardwareError si aucun lecteur ni sortie
  w := audio.read_wav("la.wav")
  print(w.rate, w.channels, w.duration())

Erreurs : HardwareError (pas de lecteur, échec de lecture), ArgumentError (WAV invalide, paramètres).
```

API publique :

- `cards()`
- class `AudioDevice(card, device, name)` : `alsa_name()`
- `devices()`
- `outputs()`
- `inputs()`
- `available()`
- `tone(frequency, seconds, rate=44100, volume=0.5)`
- `silence(seconds, rate=44100)`
- `mix(tracks)`
- `rms(samples)`
- `peak(samples)`
- class `Wav(samples, rate, channels, bits)` : `frames()`, `duration()`, `channel(index)`
- `encode_wav(samples, rate=44100, channels=1, bits=16)`
- `write_wav(path, samples, rate=44100, channels=1, bits=16)`
- `decode_wav(b)`
- `read_wav(path)`
- `player()`
- `play(source, rate=44100, channels=1, device=null, timeout=null)`
- `beep(frequency=880, seconds=0.15)`

### `hardware.camera`

```text
Caméras (Linux : Video4Linux, /sys/class/video4linux et /dev/videoN) et capture d'une image ou d'une courte
vidéo par l'outil du système (ffmpeg, ou fswebcam pour une image).

Une webcam USB expose souvent deux nœuds (image et métadonnées) : cameras() ne garde que ceux qui
capturent l'image (index 0 de chaque périphérique), all_nodes() les liste tous.

Exemple
  use hardware.camera as camera
  c := camera.primary()
  if c != null:
      camera.capture("photo.jpg", c, 1280, 720)

Erreurs : HardwareError (aucune caméra, aucun outil, échec de capture).
```

API publique :

- class `Camera(node)`
- `all_nodes()`
- `cameras()`
- `available()`
- `primary()`
- `tool()`
- `capture(path, camera=null, width=null, height=null, timeout=20)`
- `record(path, seconds, camera=null, width=null, height=null)`

### `hardware.device`

```text
Un périphérique tel que le noyau Linux le publie dans /sys : chemin, sous-système (pci, usb, block, net,
input, sound, drm...), pilote, nœud /dev, attributs, identifiants, parent et enfants dans l'arbre des
périphériques.

  use hardware.device as device
  for d in device.by_subsystem("net"):
      print(d.name, d.driver, d.attribute("address"))        # eth0 virtio_net 52:54:00:12:34:56
  d := device.from_class("block", "sda")
  print(d.devnode, d.major_minor(), d.parent().subsystem)   # /dev/sda (8, 0) scsi

Lecture seule, sans droits particuliers. ALEX_HW_ROOT (ou hardware._sys.set_root) fait lire une copie de /sys.
Hors Linux, les listes sont vides.

Erreurs : ArgumentError (périphérique absent pour from_path / from_class).
```

API publique :

- class `Device(syspath)` : `attribute(attr)`, `attribute_int(attr)`, `attributes()`, `major_minor()`, `vendor_id()`, `product_id()`, `real_path()`, `parent()`, `children()`, `describe()`, `to_dict()`
- `from_path(syspath)`
- `from_class(cls, name)`
- `by_subsystem(subsystem)`
- `classes()`
- `buses()`
- `from_devnode(node)`

### `hardware.device_info`

```text
Description lisible d'un périphérique (hardware.device.Device) : catégorie (stockage, réseau, affichage,
entrée, son, USB, pont...), noms du fabricant et du modèle (tables PCI / USB : pci.pci_ids), et résumé.

  use hardware.device_info as di
  info := di.describe(d)                 # DeviceInfo
  print(info.category, info.vendor, info.model, info.summary())
  print(di.category_of("net"))           # « réseau »

Les catégories s'appuient sur le sous-système et, pour PCI et USB, sur la classe déclarée.
```

API publique :

- `category_of(subsystem)`
- class `DeviceInfo(device, category, vendor, model, class_name)` : `summary()`, `to_dict()`
- `describe(d)`

### `hardware.device_manager`

```text
Inventaire des périphériques et suivi des branchements : liste par sous-système ou catégorie, recherche,
regroupement par pilote, et détection des ajouts / retraits (comparaison d'instantanés, en tâche async).

  use hardware.device_manager as dm
  m := dm.DeviceManager()
  for d in m.list("input"):
      print(d.describe())
  print(m.by_driver())                     # {"virtio_net": [...], ...}
  m.on("added", (d) => print("branché :", d.describe()))
  m.on("removed", (d) => print("retiré :", d.describe()))
  await m.watch(60, 1.0)                    # 60 s, un instantané par seconde

Sous-systèmes suivis par défaut : usb, input, block, net, sound, video4linux, drm, hidraw, tty.
```

API publique :

- class `DeviceManager(subsystems=null)` : `on(event_type, fn)`, `list(subsystem)`, `all()`, `by_category(category)`, `find(predicate)`, `find_by_name(name)`, `by_driver()`, `refresh()`, `watch(duration=null, interval=1.0)`
- `manager(subsystems=null)`

### `hardware.gpu`

```text
Cartes graphiques : contrôleurs d'affichage du bus PCI (classe 0x03) et cartes DRM du noyau
(Linux : /sys/bus/pci/devices, /sys/class/drm). Pour chacune : fabricant, identifiants, pilote, carte DRM
et nœud de rendu (/dev/dri/renderD*), mémoire vidéo quand le pilote la publie (amdgpu).

Exemple
  use hardware.gpu as gpu
  for g in gpu.gpus():
      print(g.vendor, g.device_id_hex(), g.driver, g.card)
```

API publique :

- `vendor_name(vendor_id)`
- class `Gpu()` : `vendor_id_hex()`, `device_id_hex()`
- `gpus()`
- `available()`
- `primary()`

### `hardware.hardware_info`

```text
Ce que la machine EST : processeur(s) (fabricant, modèle, cœurs, fils, fréquence, caches, jeux d'instructions),
mémoire (totale, disponible, échange), micrologiciel et carte mère (DMI : fabricant, produit, BIOS), noyau,
virtualisation (hyperviseur), zones NUMA. Linux : /proc/cpuinfo, /proc/meminfo, /sys/devices/system,
/sys/class/dmi/id ; ailleurs, ce que os.system_info() donne.

  use hardware.hardware_info as hi
  c := hi.cpu()
  print(c.model, c.cores, c.threads, c.mhz, c.has("avx2"))
  m := hi.memory()
  print(m.total_mib(), m.available_mib(), m.used_percent())
  print(hi.summary())                          # texte de quelques lignes

Toutes les valeurs absentes valent null. Lecture seule, sans droits (le numéro de série DMI exige root : null).
ALEX_HW_ROOT (ou hardware._sys.set_root) fait lire une copie de /proc et /sys (tests).
```

API publique :

- class `CacheInfo(level, kind, size_kib, shared_by)` : `describe()`
- class `CpuInfo()` : `has(flag)`, `x86_level()`, `virtualization()`, `describe()`, `to_dict()`
- `parse_cpuinfo(text)`
- `cpu()`
- class `MemoryInfo(values)` : `used()`, `used_percent()`, `total_mib()`, `available_mib()`, `swap_used()`, `describe()`, `to_dict()`
- `parse_meminfo(text)`
- `memory()`
- `numa_nodes()`
- class `FirmwareInfo()` : `chassis()`, `describe()`
- `firmware()`
- `hypervisor()`
- `kernel()`
- `load_average()`
- class `HardwareInfo()` : `describe()`, `to_dict()`
- `info()`
- `summary()`

### `hardware.keyboard`

```text
Claviers branchés (Linux : /proc/bus/input/devices) et lecture de leurs touches au niveau du matériel
(/dev/input/eventN) : appuis ET relâchements, toutes les touches (Maj, Ctrl, Fn...), même sans terminal.
La lecture exige les droits sur /dev/input (root ou groupe « input »), sinon HardwareError.

Pour lire une touche dans le terminal (cas courant, sans droits particuliers) : read_terminal_key(), qui
est io.console.read_key.

Exemple
  use hardware.keyboard as keyboard
  for k in keyboard.keyboards():
      print(k.name, k.path)
  kb := keyboard.open()
  e := kb.read(5.0)          # KeyEvent : e.key ("a", "enter", "left_shift"...), e.action ("press"...)
  kb.close()

Erreurs : HardwareError (aucun clavier, droits, plateforme).
```

API publique :

- class `Keyboard(info)` : `open()`
- `keyboards()`
- `available()`
- `key_name(code)`
- class `KeyEvent(key, code, action, time)` : `pressed()`
- class `KeyboardReader(path)` : `read(timeout=null)`, `close()`
- `open(device=null)`
- `read_terminal_key(timeout=null)`

### `hardware.memory_map`

```text
Cartes de la mémoire :
  - PHYSIQUE : zones de RAM utilisable, réservées, ACPI, ROM, fenêtres des périphériques (Linux :
    /sys/firmware/memmap = table e820 du micrologiciel, /proc/iomem = arbre des ressources ; les adresses de
    /proc/iomem ne sont lisibles que par root, sinon elles valent 0 et seule la table e820 sert) ;
  - D'UN PROCESSUS : ses projections (code, tas, pile, bibliothèques, fichiers ; /proc/<pid>/maps).

MemoryMap sert aussi à bâtir sa propre carte (noyau, simulateur, chargeur) : ajouter des zones, réserver une
plage, allouer des cadres alignés dans la RAM libre, fusionner, interroger.

  use hardware.memory_map as mm
  m := mm.physical()
  print(m.describe())
  print(m.total("ram") // 1048576, "Mio de RAM")
  r := m.find(0xB8000)                         # zone qui contient l'adresse
  for p in mm.process_maps():                  # projections du processus courant
      print(p.describe())

  carte := mm.MemoryMap()
  carte.add(0, 0x9FC00, "ram")
  carte.add(0x100000, 0x7F00000, "ram")
  carte.reserve(0x100000, 0x400000, "noyau")
  a := carte.allocate(0x10000, 4096)           # 64 Kio alignés sur 4 Kio, pris dans la RAM libre

Types de zone : "ram", "reserved", "acpi", "acpi_nvs", "unusable", "persistent", "rom", "mmio", "kernel",
"allocated", ou tout autre nom choisi.

Erreurs : ArgumentError (zone invalide), MemoryError (allocation impossible).
```

API publique :

- class `Region(start, end, kind, name=null)` : `size()`, `contains(addr)`, `overlaps(start, end)`, `usable()`, `describe()`, `to_dict()`
- class `MemoryMap()` : `add(start, size, kind, name=null)`, `remove(start, size)`, `reserve(start, size, name="reserved", kind="reserved")`, `merge()`, `find(addr)`, `kind_at(addr)`, `by_kind(kind)`, `total(kind="ram")`, `ram_end()`, `holes(limit=null)`, `allocate(size, align=PAGE, name="allocated", minimum=PAGE)`, `release(addr, size=null)`, `copy()`, `describe()`, `to_list()`
- `firmware_map()`
- `parse_iomem(text)`
- `iomem()`
- `iomem_readable()`
- `physical()`
- `device_windows()`
- class `Mapping(start, end, perms, offset, device, inode, path)` : `size()`, `readable()`, `writable()`, `executable()`, `shared()`, `kind()`, `describe()`
- `parse_maps(text)`
- `process_maps(pid=null)`
- `process_usage(pid=null)`

### `hardware.microphone`

```text
Microphones et entrées audio (Linux : ALSA, /proc/asound) et enregistrement dans un fichier WAV par
l'outil du système (arecord, pw-record, parecord, ffmpeg, ou sox « rec »). Le WAV obtenu se lit avec
hardware.audio.read_wav ; level() en donne le niveau.

Exemple
  use hardware.microphone as mic
  if mic.available():
      mic.record("voix.wav", 3)              # 3 secondes, 16 kHz mono
      print(mic.level("voix.wav"))           # niveau efficace 0..1

Erreurs : HardwareError (aucun outil d'enregistrement, échec), ArgumentError (paramètres).
```

API publique :

- `microphones()`
- `available()`
- `recorder()`
- `record(path, seconds, rate=16000, channels=1, device=null)`
- `level(path)`

### `hardware.mouse`

```text
Souris et pavés tactiles branchés (Linux : /proc/bus/input/devices) et lecture de leurs mouvements, boutons
et molette au niveau du matériel (/dev/input/eventN). Les mouvements sont RELATIFS (dx, dy en « comptes »
du capteur) : la position du pointeur à l'écran appartient à l'interface graphique (module ui).
La lecture exige les droits sur /dev/input (root ou groupe « input »), sinon HardwareError.

Exemple
  use hardware.mouse as mouse
  m := mouse.open()
  e := m.read(5.0)       # MouseEvent : e.dx, e.dy, e.wheel, e.buttons ({"left": true} = appui)
  m.close()
```

API publique :

- class `Mouse(info)` : `open()`
- `mice()`
- `available()`
- class `MouseEvent(time)` : `moved()`
- class `MouseReader(path)` : `read(timeout=null)`, `close()`
- `open(device=null)`

### `hardware.permissions`

```text
Qui a le droit de toucher à quel matériel ? Sous Linux, l'accès aux périphériques passe par les nœuds de /dev
(propriétaire, groupe, bits rwx), par les groupes de l'utilisateur (video, audio, input, dialout, plugdev,
disk, render, kvm...) et par les capacités du processus (CAP_SYS_RAWIO pour les ports, CAP_NET_ADMIN...).
Ce module répond à « puis-je ? », explique « pourquoi pas ? » et propose le correctif (groupe à rejoindre,
règle udev à installer).

  use hardware.permissions as perm
  print(perm.current().describe())             # uid, groupes, root, capacités
  a := perm.check("/dev/video0")
  if not a.allowed("rw"):
      print(a.explain())                       # « /dev/video0 appartient au groupe video ; ... usermod -aG video ... »
  print(perm.check_category("camera"))         # tous les nœuds d'une catégorie
  print(perm.udev_rule(0x0483, 0x5740))        # règle pour un périphérique USB (vendeur, produit)

Hors Linux (ou POSIX), check renvoie seulement l'existence et os.access.

Erreurs : ArgumentError (catégorie inconnue).
```

API publique :

- class `Identity()` : `is_root()`, `group_names()`, `in_group(name_or_gid)`, `has_capability(cap)`, `capability_names()`, `describe()`
- `current()`
- class `Access(path, ident)` : `rights()`, `allowed(want="r")`, `granted_by(want="r")`, `missing_group(want="rw")`, `describe()`, `explain(want="rw")`
- `check(path)`
- `can_read(path)`
- `can_write(path)`
- `nodes(category)`
- class `CategoryReport(category, accesses, group)` : `present()`, `usable(want="rw")`, `describe()`
- `check_category(category)`
- `report()`
- `can_access_ports()`
- `udev_rule(vendor_id, product_id=null, group="plugdev", mode="0660", subsystem="usb")`

### `hardware.screen`

```text
Écrans physiques : sorties vidéo de la carte graphique (Linux : /sys/class/drm), avec état (branché,
allumé), modes (résolutions), et, d'après l'EDID de l'écran, fabricant, modèle et taille physique.
Sans /sys/class/drm (machine virtuelle, autre système), xrandr est interrogé s'il est disponible. Les
tampons d'image du noyau (/dev/fb*) sont listés par framebuffers().

Pour une fenêtre et son contenu, voir le module ui ; pour le terminal, io.console.size().

Exemple
  use hardware.screen as screen
  s := screen.primary()
  if s != null:
      print(s.name, s.resolution, s.model, s.diagonal_inches())
```

API publique :

- class `Screen(name)` : `diagonal_inches()`, `dpi()`
- `parse_edid(edid)`
- `parse_xrandr(text)`
- `outputs()`
- `screens()`
- `primary()`
- `available()`
- `framebuffers()`

### `hardware.usb`

```text
Périphériques USB branchés (Linux : /sys/bus/usb/devices) : identifiants fabricant / produit, noms, numéro
de série, bus et adresse, vitesse, classe (clavier, stockage, audio, caméra...) et nœud /dev/bus/usb.

Exemple
  use hardware.usb as usb
  for d in usb.devices():
      print(d.id(), d.product, d.classes, d.speed_mbps)
  cle := usb.find("0781")              # premier périphérique SanDisk, ou null
```

API publique :

- `class_name(code)`
- class `UsbDevice(sysname)` : `id()`, `is_hub()`, `node()`, `name()`
- `devices(hubs=true)`
- `find(vendor_id, product_id=null)`
- `by_class(name)`
- `available()`

## Paquet `usb`

### `usb`

```text
USB depuis une application (Linux) :

| Module               | Contenu                                                                       |
|----------------------|-------------------------------------------------------------------------------|
| usb.usb_descriptor   | descripteurs (périphérique, configuration, interface, point d'accès, HID,     |
|                      | chaînes), paquets SETUP standard — aussi utilisé par les pilotes du noyau     |
| usb.usb_device       | UsbDevice (/sys : identifiants, configurations), UsbHandle (usbfs)            |
| usb.usb_endpoint     | Endpoint : lecture / écriture, message complet, levée du blocage              |
| usb.usb_transfer     | contrôle, bloc, interruption ; TransferResult                                 |
| usb.usb_hub          | concentrateurs, ports, arbre                                                  |
| usb.usb_discovery    | recherche, attente d'un branchement, Watcher                                  |

  use usb
  print(usb.lsusb())                         # comme la commande lsusb
  d := usb.find(0x2341)                      # Arduino
  h := usb.open(d)

Droits : l'accès direct (open) exige le droit d'écriture sur /dev/bus/usb/BBB/DDD (règle udev :
hardware.permissions.udev_rule). Pilotes du noyau Alex : usb_driver.
```

API publique :

- `devices(hubs=true)`
- `find(vendor_id, product_id=null)`
- `by_class(cls)`
- `open(device)`
- `tree()`
- `available()`
- `lsusb(verbose=false)`

### `usb.usb_descriptor` (natif)

```text
Descripteurs USB (spécification USB 2.0, chapitre 9) à partir de leurs octets (list[int]) : périphérique,
configuration (avec ses interfaces, réglages alternatifs, points d'accès, descripteurs HID et de classe),
chaînes (UTF-16LE), et paquets de requête de contrôle (SETUP) standard. Commun aux applications (usbfs,
usb.usb_device) et aux pilotes du noyau (usb_driver).

  use usb.usb_descriptor as ud
  dev := ud.parse_device(octets_18)
  print(dev.vendor, dev.product, ud.class_name(dev.device_class))
  cfg := ud.parse_configuration(octets_config)
  for itf in cfg.interfaces:
      for ep in itf.endpoints:
          print(ep.describe())                   # « EP 0x81 entrée interruption 8 octets / 10 ms »
  setup := ud.get_descriptor(ud.DT_DEVICE, 0, 18)   # 8 octets de la requête

Compilable en natif (# alex: native).
```

API publique :

- `class_name(c: int)`
- `bcd_text(v: int)`
- class `DeviceDescriptor()` : `id_text()`, `describe()`
- `parse_device(b: list[int])`
- class `EndpointDescriptor(address: int, attributes: int, max_packet: int, interval: int)` : `number()`, `is_in()`, `transfer_type()`, `packet_size()`, `describe()`
- `transfer_name(t: int)`
- class `InterfaceDescriptor(number: int, alternate: int, iclass: int, subclass: int, protocol: int)` : `endpoint(kind: int, input: bool)`, `is_boot_keyboard()`, `is_boot_mouse()`, `describe()`
- class `ConfigurationDescriptor()` : `self_powered()`, `remote_wakeup()`, `find_interface(n: int)`, `find_class(c: int)`, `describe()`
- `parse_configuration(b: list[int])`
- `configuration_length(b: list[int])`
- `parse_string(b: list[int])`
- `parse_languages(b: list[int])`
- class `SetupPacket(request_type: int, request: int, value: int, index: int, length: int)` : `is_in()`, `to_bytes()`, `describe()`
- `get_descriptor(kind: int, index: int, length: int)`
- `get_string(index: int, language: int, length: int)`
- `set_address(address: int)`
- `set_configuration(value: int)`
- `set_interface(iface: int, alternate: int)`
- `get_status()`
- `clear_halt(endpoint: int)`
- `hid_set_protocol(iface: int, protocol: int)`
- `hid_set_idle(iface: int, duration: int)`
- `hid_get_report_descriptor(iface: int, length: int)`

### `usb.usb_device`

```text
Un périphérique USB branché (Linux : /sys/bus/usb/devices/<bus>-<port...>) : identifiants, chaînes, vitesse,
position (bus, ports), descripteurs COMPLETS lus dans le fichier « descriptors » de /sys (sans droits
particuliers), configuration active, interfaces et pilotes du noyau qui les tiennent ; et son ouverture par
usbfs (UsbHandle) pour lui parler directement : réclamer une interface (en détachant le pilote du noyau si
demandé), transferts de contrôle, points d'accès, réinitialisation.

  use usb.usb_device as udev
  d := udev.from_sysname("1-1.2")
  print(d.describe())
  print(d.configuration().describe())        # interfaces et points d'accès
  h := d.open()                              # UsbError si /dev/bus/usb/... est inaccessible (droits)
  h.claim(0, true)                           # détache usbhid, par exemple
  ep := h.endpoint(0x81)
  print(ep.read(8, 1000).data)
  h.close()

ALEX_HW_ROOT (hardware._sys.set_root) fait lire une copie de /sys (tests).
```

API publique :

- class `UsbDevice(sysname)` : `id()`, `name()`, `node()`, `is_hub()`, `is_root_hub()`, `port_path()`, `parent_sysname()`, `configurations()`, `configuration()`, `interfaces()`, `interface_driver(n)`, `classes()`, `open()`, `describe()`, `describe_full()`
- `from_sysname(sysname)`
- class `UsbHandle(device)` : `claim(n, detach=false)`, `release(n)`, `control(setup, data=null, timeout_ms=1000)`, `string(index)`, `set_configuration(value)`, `set_interface(n, alternate)`, `endpoint(address)`, `reset()`, `close()`

### `usb.usb_discovery`

```text
Trouver des périphériques USB : liste complète, recherche par identifiants, par classe d'interface, par
numéro de série, par prédicat ; attente d'un branchement ; suivi des branchements / retraits (async).

  use usb.usb_discovery as disc
  for d in disc.devices():
      print(d.describe())
  cle := disc.find(0x0781)                       # premier SanDisk
  claviers := disc.by_class(ud.CLASS_HID)
  d := await disc.wait_for(0x2341, 0x0043, 30)    # Arduino Uno, 30 s au plus (null sinon)
  w := disc.Watcher()
  w.on("added", (d) => print("branché", d.describe()))
  await w.run(60)
```

API publique :

- `devices(hubs=true)`
- `find(vendor_id, product_id=null)`
- `find_all(vendor_id, product_id=null)`
- `by_serial(serial)`
- `by_class(cls)`
- `matching(predicate)`
- `wait_for(vendor_id, product_id=null, timeout=null, interval=0.5)`
- class `Watcher(interval=0.5)` : `on(event_type, fn)`, `check()`, `stop()`, `run(duration=null)`

### `usb.usb_endpoint`

```text
Un point d'accès d'une interface réclamée (UsbHandle.claim) : lecture / écriture selon son type (bloc,
interruption), avec la taille de paquet du descripteur ; lecture d'un message complet (jusqu'à un paquet
court) ; levée du blocage (STALL).

  h := dev.open()
  h.claim(0)
  ep := h.endpoint(0x81)                     # Endpoint
  r := ep.read(64, 500)                      # TransferResult
  out := h.endpoint(0x02)
  out.write([1, 2, 3])

Erreurs : ArgumentError (sens inversé). Les transferts renvoient un TransferResult (usb.usb_transfer).
```

API publique :

- class `Endpoint(handle, descriptor)` : `is_in()`, `kind_name()`, `read(length=null, timeout_ms=1000)`, `write(data, timeout_ms=1000)`, `read_message(max_bytes=65536, timeout_ms=1000)`, `clear_halt()`, `describe()`

### `usb.usb_hub`

```text
Concentrateurs USB et topologie : contrôleurs racines (usb1, usb2...), concentrateurs, nombre de ports, ce
qui est branché sur chaque port, état des ports (Linux : /sys/.../<hub>-portN : connect_type, over_current,
disable), et arbre complet comme « lsusb -t ».

  use usb.usb_hub as hub
  for h in hub.hubs():
      print(h.describe())                    # « usb1 : concentrateur racine, 12 ports (2 occupés) »
      for p in h.ports():
          print(p.number, p.device_name())
  print(hub.tree())
```

API publique :

- class `Port(hub, number)` : `occupied()`, `device_name()`
- class `UsbHub(device)` : `is_root()`, `child_sysname(n)`, `ports()`, `used()`, `describe()`
- `hubs()`
- `root_hubs()`
- `tree()`

### `usb.usb_transfer`

```text
Transferts USB depuis une APPLICATION (Linux, usbfs : /dev/bus/usb/BBB/DDD, sans pilote du noyau pour
l'interface utilisée) : contrôle (requête SETUP + données), bloc (bulk), interruption ; délais ; résultat
avec octets reçus, nombre envoyé, ou erreur (nom errno : ETIMEDOUT, EPIPE = point d'accès bloqué (STALL),
ENODEV = débranché, EACCES = droits : voir hardware.permissions.udev_rule).

  use usb.usb_transfer as ut
  use usb.usb_descriptor as ud
  r := ut.control(fd, ud.get_descriptor(ud.DT_DEVICE, 0, 18), null, 1000)
  if r.ok:
      print(r.data)                              # list[int]
  r = ut.bulk_out(fd, 0x02, [0x55, 0x53, 0x42, 0x43], 1000)
  r = ut.interrupt_in(fd, 0x81, 8, 100)          # ETIMEDOUT si rien n'arrive

Les fonctions ne lèvent pas d'erreur : regarder r.ok / r.error. raise_for(r) la lève (UsbError).
```

API publique :

- class `TransferResult(kind, endpoint)` : `timed_out()`, `stalled()`, `disconnected()`, `describe()`
- `control(fd, setup, data=null, timeout_ms=1000)`
- `bulk_in(fd, endpoint, length, timeout_ms=1000)`
- `bulk_out(fd, endpoint, data, timeout_ms=1000)`
- `interrupt_in(fd, endpoint, length, timeout_ms=1000)`
- `interrupt_out(fd, endpoint, data, timeout_ms=1000)`
- `raise_for(r)`
- `get_descriptor(fd, kind, index, length, timeout_ms=1000)`
- `get_string(fd, index, timeout_ms=1000)`

