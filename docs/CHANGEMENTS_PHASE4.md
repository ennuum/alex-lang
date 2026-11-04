# Phase 4 : applications système, matériel, pilotes

Objectif : que l'on puisse écrire en Alex aussi bien des **applications** (programmes système, interfaces,
son, image), que des **programmes bas niveau** et un **système d'exploitation** (pilotes de périphériques).
Les 153 modules de l'arborescence demandée sont implémentés et testés.

## Nouveaux paquets

| Domaine | Paquets | Documentation | Tests |
|---|---|---|---|
| Programmes système | `process` (command, environment, exit_code, process_info, process_manager), `pipe`, `signal`, `ipc` | SYSAPP.md | `make test-sysapp` |
| Concurrence | `atomic`, `mutex`, `synchronization`, `thread`, `future`, `async` | CONCURRENCY2.md | `make test-concurrency2` |
| Interfaces | `event`, `window`, `keyboard`, `mouse` | EVENT_WINDOW.md | `make test-event-window`, `make test-window-x11` |
| Matériel (applications) | `hardware` (hardware, device, device_info, device_manager, hardware_info, memory_map, permissions), `usb` | HARDWARE_APPS.md | `make test-hardware-ext` |
| Multimédia | `audio`, `microphone`, `camera`, `gpu`, `graphics` | MEDIA.md | `make test-media` |
| Bas niveau | `pci`, `interrupt`, `dma`, `driver` ; machine simulée `hw`, `hw.sim_pci`, `hw.sim_apic` | DRIVERS.md | `make test-drivers` |
| Pilotes (noyau) | `storage_driver` (ATA, AHCI, NVMe), `network_driver` (e1000), `usb_driver` (UHCI, HID, stockage), `gpu_driver` (Bochs) | DRIVERS.md | `make test-drivers-kernel` (QEMU) |

`make test-system-stack` lance tous ces tests ; ils font aussi partie de `make test`.

## Runtime natif (C++)

- `_native_sync` (nouveau) : atomiques (entiers, références, attente / réveil), mutex (récursifs, délais),
  verrous lecture / écriture, verrous tournants, sémaphores, conditions, barrières, loquets, `once`,
  événements ; mémoire partagée POSIX (lecture / écriture typées, atomiques et futex dans la mémoire
  partagée), files de messages POSIX, sémaphores nommés.
- `_native_hwsim` (nouveau) : RAM simulée (pages creuses), allocation de pages, accès atomiques.
- `_native_fd` : `poll`, `file_kind`, `inotify_*`, `stat`, `ids`, `user_name`, `group_name`, `group_id`,
  `group_members`, ioctl usbfs (`usb_claim`, `usb_release`, `usb_detach`, `usb_reset`, `usb_clear_halt`,
  `usb_control`, `usb_bulk`), noms errno étendus.
- `_native_net` : sockets Unix (chemins et noms abstraits), `socketpair`.
- `_native_thread` : services de fils (`spawn_service`) pour les réserves de fils ; arrêt propre.
- `ui` : position, états, styles, focus et liste des fenêtres, relâchement des touches, injection, dépôt
  de pixels RGBA dans un canvas ; X11 (EWMH) et Win32.

## Compilateur et langage

- Modules de la bibliothèque compilables en natif (`# alex: native`, docs/NATIVE.md).
- Littéraux `0x…`, `0b…`, `0o…` et séparateurs `_` ; champs de classe déclarés `nom: Type` ; mot-clé en
  tête d'un chemin de module (`use async as aio`).
- Correction : l'alias d'un module natif importé (`use _native_x as _n`) était partagé entre modules ; il
  est désormais propre à chaque module (format des caches `.meta` passé en version 6).
- Vérification des types : une classe importée est acceptée là où l'une de ses interfaces est attendue.

## Limites connues

- USB : UHCI seulement (pas d'OHCI / EHCI / xHCI), pas de concentrateurs externes ; pas de transferts
  isochrones.
- Réseau : e1000 seulement (pas de virtio-net) ; pilotes de stockage et de réseau en scrutation.
- `gpu` / `graphics` : calcul et rendu logiciels (processeur, plusieurs fils) ; l'API est prête pour un dorsal
  Vulkan / OpenCL.
- Son, micro, caméra : passent par les outils du système (aplay / pw-play / paplay / ffplay, arecord /
  pw-record / parecord / ffmpeg) ; aucune bibliothèque C n'est liée.
