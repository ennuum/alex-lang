# ALEX — construction et tests, sans compilateur C++.
#
# La chaîne d'outils est entièrement écrite en ALEX (docs/SELFHOST.md) : compilateur vers bytecode, compilateur
# natif (x86-64 Linux / Windows / UEFI / sans OS, ARM64 Linux / Windows), machine virtuelle, outils (test, fmt,
# doc, new, pkg, repl, debug, lsp, edit). Elle s'amorce depuis la graine versionnée bootstrap/ (alexvm, une VM
# exécutable, et alexc.albc, le compilateur en bytecode) :
#
#   make                 = make alex : build/alex (chaîne d'outils) et build/alexvm (VM), liens ./alexc et ./alex
#   make pure            amorçage complet depuis la graine, avec contrôle du point fixe (stage2 == stage3)
#   make seed            régénère la graine depuis build/ (après une évolution du compilateur ou du runtime)
#   make pure-windows    amorçage sous Windows depuis bootstrap/alexvm.exe (tools/selfhost/bootstrap.ps1)
#   make alex-windows    build/alex.exe et build/alexvm.exe (Windows x64), produits depuis Linux
#   make -k test         suite complète
#   make package         dist/ : archive .tar.gz et paquet .deb ; make installer-windows : archive .zip / setup.exe
#
# Le premier `make alex` amorce depuis la graine (quelques minutes) ; les suivants recompilent build/alex avec
# lui-même quand les sources du compilateur ou du runtime changent.

BUILD := build
ALEX := ./alex

# =======================================================================
# Versions du compilateur (voir docs/VERSIONS.md, tools/version.sh)
# =======================================================================
# Version de base : fichier VERSION (MAJEUR.MINEUR.CORRECTIF). Canal : CHANNEL=beta|stable ; il est MÉMORISÉ
# (build/.channel). À chaque construction de la chaîne d'outils, build/generated/alex_build_info.txt est regénéré
# (numéro de build suivant, date, empreinte des sources) et inscrit dans build/alex et build/alexvm.
#   stable : 1.2.0      bêta : 1.2.0-beta.<build>      (alex --version, alex version --json)
CHANNEL ?= $(shell cat $(BUILD)/.channel 2>/dev/null || echo beta)
BUILD_INFO := $(BUILD)/generated/alex_build_info.txt
VERSION_BASE := $(shell tr -d ' \t\r\n' < VERSION 2>/dev/null)

# Sources de la chaîne d'outils : compilateur, runtime natif et dynamique, VM, outils, préludes.
TOOLCHAIN_SRC := $(shell find src runtime tools/selfhost -name '*.al' 2>/dev/null) VERSION \
                 stdlib/io/io.al stdlib/os/os.al stdlib/string/string.al stdlib/json/json.al stdlib/collections/collections.al

.PHONY: FORCE alex pure seed alex-windows version version-bump version-set release clean
alex: $(BUILD)/alex $(BUILD)/alexvm
	@ln -sf $(BUILD)/alex alex
	@ln -sf $(BUILD)/alex alexc

$(BUILD)/.channel: FORCE
	@mkdir -p $(BUILD)
	@sh tools/version.sh check $(CHANNEL) >/dev/null
	@echo '$(CHANNEL)' | cmp -s - $@ || echo '$(CHANNEL)' > $@

# Compilateur qui construit build/alex : build/alex lui-même s'il existe, sinon build/alexc (amorçage).
STAGE0 := $(if $(wildcard $(BUILD)/alex),$(BUILD)/alex,$(BUILD)/alexc)

$(BUILD)/alexc:
	bash tools/selfhost/bootstrap.sh

$(BUILD)/alex: $(TOOLCHAIN_SRC) $(BUILD)/.channel | $(filter $(BUILD)/alexc,$(STAGE0))
	@sh tools/version.sh gen $(BUILD_INFO) $(CHANNEL) "$$($(STAGE0) version --short 2>/dev/null | sed 's/^/alex /')"
	ALEX_BUILD_INFO=$(BUILD_INFO) ALEX_EXE=$(CURDIR)/$(BUILD)/alex $(STAGE0) native --dynamic src/alexc.al -o $@.tmp
	@mv $@.tmp $@

$(BUILD)/alexvm: $(BUILD)/alex
	ALEX_BUILD_INFO=$(BUILD_INFO) $(BUILD)/alex vm -o $@.tmp
	@mv $@.tmp $@

# Amorçage complet depuis la graine (sans réutiliser build/), contrôle du point fixe, puis la chaîne finale.
pure:
	bash tools/selfhost/bootstrap.sh
	rm -f $(BUILD)/alex $(BUILD)/alexvm
	$(MAKE) alex

seed:
	bash tools/selfhost/bootstrap.sh --seed

# Amorçage sous Windows x64 depuis la graine bootstrap/alexvm.exe (sans binaire préexistant) : build/alexc.exe,
# build/alexvm.exe, point fixe. seed-windows régénère TOUTE la graine (bytecode, VM Linux et VM Windows).
.PHONY: pure-windows seed-windows
pure-windows:
	powershell -NoProfile -ExecutionPolicy Bypass -File tools/selfhost/bootstrap.ps1

seed-windows:
	powershell -NoProfile -ExecutionPolicy Bypass -File tools/selfhost/bootstrap.ps1 -Seed

# Chaîne pour Windows x64 : build/alex.exe (compilateur, mode dynamique) et build/alexvm.exe (machine virtuelle),
# produits sous Linux ; à copier ensemble à côté d'un dossier stdlib (ou ../lib/alex/stdlib) et de runtime/.
alex-windows: alex
	ALEX_BUILD_INFO=$(BUILD_INFO) ./alexc build --native --dynamic --windows --icon runtime/alex/windows/alex.ico src/alexc.al -o $(BUILD)/alex.exe
	ALEX_BUILD_INFO=$(BUILD_INFO) $(BUILD)/alex vm --windows -o $(BUILD)/alexvm.exe

# Version de base et canal courants ; incrément de la version de base (PART=major|minor|patch).
version:
	@echo "VERSION $(VERSION_BASE), canal $(CHANNEL)"
	@if [ -x ./alex ]; then ./alex --version; fi

version-bump:
	@sh tools/version.sh bump $(PART)

version-set:
	@sh tools/version.sh set $(V)

# Gestion des versions : script, identité inscrite dans les exécutables, CLI, bytecode, caches, manifestes.
test-version: alex
	sh tests/test_version.sh

# Publication : chaîne STABLE, suite de tests complète, puis paquets (dist/).
release:
	$(MAKE) CHANNEL=stable alex
	$(MAKE) CHANNEL=stable test
	$(MAKE) CHANNEL=stable package
.PHONY: test-native test-native-windows test-native-uefi test-native-aarch64 test-native-windows-arm64 test-kernel test-office test-version

.PHONY: test-hardware-ext test-media test-multimedia test-multimedia-display test-sysapp test-concurrency2 test-event-window test-window-x11 test-drivers test-drivers-kernel test-system-stack
.PHONY: test-pythonic test-builtins test-stdlib2 test-stdlib2-native test-gamedev test-gl
.PHONY: test-network test-concurrency test-io test-system test-hardware test-ui-view test-types test-dict-order test-exceptions test-trace test-standalone test-stdlib-pure test-path test-csv test-xml test-regex test-testing-logging test-crypto test-filesystem test-file test-time test-datetime test-string test-math test-sci test-sci2 test-lang test-oop test-closures test-comprehensions test-async test-channel test-json test-functional test-process test-ffi test-memory test-argparse test-runtime test-gc-vm test-ui-portable test-ui-x11

# Tests UI : headless (sans écran) puis X11 réel sous Xvfb.
# Tests du module math (ALEX pur) : suite d'exemples + intégration stdlib.
# string.chr / string.ord / string.slice.
# Modules ALEX purs : path, csv, xml, regex, testing, logging, filesystem, file (voir docs/PURE_MODULES.md).
test-path: alex
	./alex run tests/test_path.al

# Bibliothèque bureautique (stdlib/office) : socle, OOXML, PDF, OpenDocument, conversions et gabarits.
test-office: alex
	./alex run tests/office/test_office_base.al
	./alex run tests/office/test_zstd.al
	./alex run tests/office/test_office_ooxml.al
	./alex run tests/office/test_office_pdf.al
	./alex run tests/office/test_office_odf.al
	./alex run tests/office/test_office_convert.al

test-csv: alex
	./alex run tests/test_csv.al

test-xml: alex
	./alex run tests/test_xml.al

test-regex: alex
	./alex run tests/test_regex.al

test-testing-logging: alex
	./alex run tests/test_testing_logging.al

test-crypto: alex
	./alex run tests/test_crypto.al

test-filesystem: alex
	./alex run tests/test_filesystem.al

test-file: alex
	./alex run tests/test_file.al

test-stdlib-pure: test-string test-json test-path test-csv test-xml test-regex test-testing-logging test-crypto test-filesystem test-file test-time test-datetime

test-time: alex
	./alex run tests/test_time.al

test-datetime: alex
	./alex run tests/test_datetime.al

test-string: alex
	./alex run tests/test_string_chr_ord_slice.al

test-math: alex
	./alex run examples/math_test_suite.al
	sh examples/run_math_examples.sh
	./alex run tests/test_pure_stdlib.al

# Bibliothèque scientifique (Phase 1 : constants, complex, units, random) + intégration inter-modules.
test-sci: alex
	./alex run tests/test_constants.al
	./alex run tests/test_units.al
	./alex run tests/test_science_integration.al

# Fonctionnalités du langage : hissage, struct/enum exportés entre fichiers, arguments nommés qualifiés.
test-lang: alex
	./alex run tests/lang/test_language.al
	./alex run tests/lang/test_syntax_ui.al

# Bibliothèque scientifique (Phase 2 : array, linalg, stats, numeric, calculus) + intégration inter-modules.
# Les fichiers tests/test_<module>.al sont GÉNÉRÉS par tools/sci/tests/gen_test_<module>.py (valeurs de référence NumPy/SciPy/SymPy).
test-sci2: alex
	./alex run tests/test_array.al
	./alex run tests/test_linalg.al
	./alex run tests/test_stats.al
	./alex run tests/test_numeric.al
	./alex run tests/test_calculus.al
	./alex run tests/test_science2_integration.al

# Backend natif (docs/NATIVE.md) : parité VM / exécutable natif, diagnostics du sous-ensemble.
test-native: alex
	sh tests/native/run_native_tests.sh

# Cible Windows du natif (alexc build --native --windows, docs/NATIVE.md « Windows ») : les mêmes programmes que
# test-native, compilés en PE32+ (contrat binaire vérifié par tests/native/pe_check.al) puis exécutés sur un vrai
# Windows (MSYS2 / Git Bash : make test-native-windows) ou par WINRUN (par exemple WINRUN=wine).
test-native-windows: alex
	sh tests/native/run_windows_tests.sh

# Cible UEFI du natif (alexc build --native --uefi, docs/NATIVE.md « UEFI ») : programmes de test-native acceptés
# sans OS, contrat PE32+ vérifié (tests/native/pe_check.al) ; exécutés si EFIRUN désigne un lanceur (QEMU + OVMF).
.PHONY: test-native-uefi
test-native-uefi: alex
	sh tests/native/run_uefi_tests.sh

# Cible ARM64 du natif (alexc build --native --target linux-aarch64, docs/NATIVE.md « ARM64 ») : les mêmes
# programmes que test-native, exécutés par l'émulateur AArch64 écrit en ALEX (stdlib/outils/a64emu.al,
# tests/native/aarch64/a64run.al) ; A64RUN=qemu-aarch64 pour un autre émulateur, A64RUN= sur une machine ARM64.
test-native-aarch64: alex
	sh tests/native/run_aarch64_tests.sh

# Windows ARM64 (alexc build --native --windows --arm64) : la suite de test-native-windows (structure des PE ARM64 ;
# exécution si WINRUN désigne un lanceur Windows ARM64).
test-native-windows-arm64: alex
	WIN_ARCH=arm64 sh tests/native/run_windows_tests.sh

# Réseau (stdlib/network, docs/NETWORK.md) : sockets, DNS, TCP, UDP en boucle locale ; HTTP contre un serveur
# Python, curl et un serveur Alex dans un processus fils (parties ignorées si python3 / curl sont absents) ;
# modules purs (encodages, URI, IP, en-têtes, XML/HTML, protobuf...) ; client et serveur HTTP/1.1, XML-RPC contre
# Python, gRPC contre Go (si `go` est présent), SMTP / POP3 / IMAP / FTP contre des serveurs de référence Python.
test-network: alex
	./alex run tests/network/test_network.al
	./alex run tests/network/test_http.al
	./alex run tests/network/test_tls.al
	./alex run tests/network/test_websocket.al
	./alex run tests/network/test_network_utils.al
	./alex run tests/network/test_network_system.al
	./alex run tests/network/test_http_client.al
	./alex run tests/network/test_http_server.al
	./alex run tests/network/test_xmlrpc.al
	./alex run tests/network/test_grpc.al
	./alex run tests/network/test_mail_ftp.al

# Concurrence (stdlib/concurrency, docs/CONCURRENCY.md) : primitives des tâches async, fils parallèles isolés.
test-concurrency: alex
	./alex run tests/concurrency/test_concurrency.al
	./alex run tests/concurrency/test_thread.al

# Entrées-sorties (stdlib/io, docs/IO.md) : flux, tubes anonymes et nommés, pipeline, console ; la saisie
# interactive (read_key, read_password) passe par un pseudo-terminal (ignorée si python3 est absent).
test-io: alex
	./alex run tests/io/test_io.al
	@if command -v python3 >/dev/null 2>&1; then python3 tests/io/console_pty.py ./alex; else echo "console (pty) : ignoré (python3 absent)"; fi

# Système (stdlib/system, docs/SYSTEM.md) : signaux (gestionnaires, attente, envoi), environnement,
# informations sur la machine, façades process / filesystem / time, memory.virtual.
test-system: alex
	./alex run tests/system/test_system.al

# Matériel (stdlib/hardware, docs/HARDWARE.md) : inventaire sur une copie construite de /sys, /proc et /dev
# (claviers, souris, écrans + EDID, cartes graphiques, USB, son, caméras), événements evdev, fichiers WAV.
test-hardware: alex
	./alex run tests/hardware/test_hardware.al

# Matériel vu des applications (docs/HARDWARE.md, docs/MEDIA.md) : informations, carte mémoire, droits, USB
# (copie factice de /sys), son, micro, caméra (mire ffmpeg), calcul « GPU », rendu logiciel.
test-hardware-ext: alex
	sh tests/run_checked.sh tests/hardware/test_hardware_ext.al tests/usb/test_usb.al

test-media: alex
	sh tests/run_checked.sh tests/media/test_audio.al tests/media/test_microphone.al tests/media/test_camera.al tests/media/test_gpu.al tests/media/test_graphics.al

# Bibliothèque multimédia (docs/MULTIMEDIA.md) : cœur, images, conteneurs, pipeline, lecture, fichiers hostiles.
test-multimedia: alex
	sh tests/run_checked.sh tests/multimedia/test_core.al tests/multimedia/test_image.al tests/multimedia/test_container.al tests/multimedia/test_flac.al tests/multimedia/test_flac_encode.al tests/multimedia/test_ogg.al tests/multimedia/test_ogg_mux.al tests/multimedia/test_video.al tests/multimedia/test_audio_ext.al tests/multimedia/test_streaming.al tests/multimedia/test_rtp.al tests/multimedia/test_system.al tests/multimedia/test_pipeline.al tests/multimedia/test_playback.al tests/multimedia/test_malformed.al

# Capture d'écran réelle sous un affichage virtuel (Xvfb requis : paquet xvfb).
test-multimedia-display: alex
	xvfb-run -a -s "-screen 0 320x240x24" sh tests/run_checked.sh tests/multimedia/test_screen.al

# Programmes système (docs/SYSAPP.md) : process, pipe, signal, ipc.
test-sysapp: alex
	./alex run tests/sysapp/test_process_pipe_signal_ipc.al

# Concurrence (docs/CONCURRENCY2.md) : atomic, mutex, synchronization, thread, future, async.
test-concurrency2: alex
	./alex run tests/concurrency2/test_concurrency_pkgs.al

# Événements et fenêtres (docs/EVENT_WINDOW.md) : event, window, keyboard, mouse (sans écran), puis X11 réel.
test-event-window: alex
	ALEX_UI_BACKEND=headless ./alex run tests/window/test_event_window.al

test-window-x11: alex
	sh tests/window/run_x11_window.sh

# Pilotes (docs/DRIVERS.md) dans la machine simulée de la VM (hw.sim_pci, hw.sim_apic), puis sous QEMU.
test-drivers: alex
	sh tests/run_checked.sh tests/drivers/test_pci_sim.al tests/drivers/test_interrupt_sim.al tests/drivers/test_dma_sim.al tests/drivers/test_driver_sim.al tests/drivers/test_storage_sim.al tests/drivers/test_network_sim.al tests/drivers/test_gpu_sim.al

test-drivers-kernel: alex
	sh tests/drivers/run_kernel_drivers.sh

# Bibliothèque standard complétée (docs/STDLIB_COMPLETION.md) : tous les tests tests/stdlib2 (format
# « N OK, M échecs »), puis les modules de pilotes compilés en natif (--freestanding et natif = VM).
test-stdlib2: alex
	ALEX_UI_BACKEND=headless sh tests/run_checked.sh tests/stdlib2/test_*.al

test-stdlib2-native: alex
	sh tests/stdlib2/native_drivers.sh

# Encodeurs d'images et vignettes (stdlib/image/encode.al, natif seulement) : PNG, JPEG, orientation Exif.
.PHONY: test-image-native
test-image-native: alex
	sh tests/native/image/run.sh

# Outillage (docs/SDK.md) : serveur de langage `alex lsp` (session JSON-RPC réelle).
test-lsp: alex
	python3 tests/tooling/lsp_test.py ./alex

# Débogueur (protocole 2), exécuteur de tests, modèles de projets, mise en forme, documentation, profileur.
test-tooling: test-lsp
	python3 tests/tooling/debug_test.py ./alex
	python3 tests/tooling/tools_test.py ./alex
	python3 tests/tooling/dap_test.py ./alex

test-system-stack: test-sysapp test-concurrency2 test-event-window test-hardware-ext test-media test-drivers test-drivers-kernel

# Interfaces (docs/UI_VIEW.md) : couche terminal bas niveau (tui.*), composants ui.view dans un terminal
# virtuel, dans un vrai pseudo-terminal (python3 ; écran relu par pyte s'il est installé), dans une fenêtre
# hors écran (captures), puis dans une vraie fenêtre X11 (Xvfb ; ignoré si absent).
test-ui-view: alex
	./alex run tests/tui/test_tui.al
	./alex run tests/ui_view/test_view_tui.al
	./alex run tests/ui_view/test_code_editor.al
	@if command -v python3 >/dev/null 2>&1; then python3 tests/ui_view/tui_pty.py ./alex && python3 tests/ui_view/edit_pty.py ./alex; else echo "ui.view (pty) : ignoré (python3 absent)"; fi
	ALEX_UI_BACKEND=headless ./alex run tests/ui_view/test_view_gui.al
	ALEX_UI_BACKEND=headless sh tests/run_checked.sh tests/ui_view/test_ide_widgets.al
	sh tests/ui_view/run_x11_view.sh

# Mode --freestanding sous QEMU (ignoré si qemu-system-x86_64 est absent).
test-kernel: alex
	sh tests/native/run_kernel_tests.sh

# Types graduels (docs/TYPES.md) : diagnostics statiques, alex check, vérifications runtime.
test-types: alex
	sh tests/lang/run_types_test.sh

# Dictionnaires : ordre d'insertion (docs/RUNTIME.md V-order).
test-dict-order: alex
	./alex run tests/lang/test_dict_order.al
	ALEX_GC_STRESS=3 ALEX_GC_POISON=1 ./alex run tests/lang/test_dict_order.al

# Exceptions : catch typés/multiples, finally, relance raise(e), e.trace (docs/RUNTIME.md §7).
test-exceptions: alex
	./alex run tests/lang/test_exceptions.al

# Trace de pile d'une exception non capturée (CLI) : méthode, lambda, fonction, module ; code de sortie 1.
test-trace: alex
	sh tests/lang/run_trace_test.sh

# Exécutables autonomes (alexc build --standalone, docs/STANDALONE.md) + recherche de la stdlib hors du dépôt.
test-standalone: alex
	sh tests/app/run_standalone_test.sh

# Fonctions imbriquées, lambdas et fermetures (capture par référence, hissage, boucles, modules).
test-closures: alex
	./alex run tests/lang/test_closures.al

# Compréhensions de liste et de dictionnaire (docs/COMPREHENSIONS.md).
test-comprehensions: alex
	./alex run tests/lang/test_comprehensions.al

# Fonctionnalités à la Python : in, tranches, indices négatifs, séquences, déstructuration, assert, del (docs/PYTHONIC.md).
test-pythonic: alex
	./alex run tests/lang/test_pythonic.al

# Builtins implicites (len, abs, sorted, range, ... et méthodes de list/dict/str sans import, docs/PYTHONIC.md).
test-builtins: alex
	./alex run tests/lang/test_builtins.al

# async/await, tâches, futurs, annulation, délais (docs/ASYNC.md).
test-async: alex
	./alex run tests/lang/test_async.al

# Canaux (stdlib/channel, ALEX pur sur les futurs d'asyncio) : tampon, rendez-vous, fermeture, annulation, select (docs/CHANNELS.md).
test-channel: alex
	./alex run tests/lang/test_channel.al

# JSON (stdlib/json, ALEX pur) : parse, stringify, erreurs, aller-retour, fichiers (docs/JSON.md).
test-json: alex
	./alex run tests/test_json.al

# Programmation fonctionnelle (stdlib/functional, ALEX pur) : map/filter/reduce, tri stable, combinatoire, Seq (docs/FUNCTIONAL.md).
test-functional: alex
	./alex run tests/test_functional.al

# Modules de jeu (stdlib/math3d, mesh, scene, physics [+ physics2d, spatial], ecs, gameloop, ai ; ALEX purs, docs/GAMEDEV.md) :
# 10 suites dans tests/gamedev ; chacune échoue (code de sortie non nul) à la première vérification fausse.
test-gamedev: alex
	for t in tests/gamedev/test_*.al; do ./alex run $$t || exit 1; done

# Rendu OpenGL réel (gl, gl.window, gl.render) sous un serveur X virtuel (Xvfb + Mesa).
test-gl: alex
	xvfb-run -a -s "-screen 0 1024x768x24" ./alex run tests/gamedev/test_gl.al
	xvfb-run -a -s "-screen 0 1024x768x24" ./alex run tests/gamedev/test_gl2d.al
	xvfb-run -a -s "-screen 0 1024x768x24" ./alex run tests/gamedev/test_gl_assets.al

# Orienté objet de bout en bout : class, extends, super, implements, isinstance, classes exportées entre fichiers.
test-oop: alex
	./alex run tests/lang/test_oop.al

# Processus fils (pipes, délais, signaux, groupes) et FFI C (libc/libm, buffers).
# POSIX / x86-64 ou arm64 ; les suites s'ignorent d'elles-mêmes ailleurs.
test-process: alex
	./alex run tests/process/test_process.al

test-ffi: alex
	./alex run tests/ffi/test_ffi.al

# Gestion mémoire hybride (stdlib/memory : buffer, memory_view, reference, alloc/free/pointer sous unsafe,
# virtual_memory) : 498 vérifications (docs/MEMORY.md). POSIX 64 bits little-endian ; s'ignore ailleurs.
test-memory: alex
	./alex run tests/memory/test_memory.al

# argparse + cli (stdlib/argparse, stdlib/cli) : 561 vérifications, dont 222 analyses et 10 aides comparées à
# l'argparse de Python (tests/argparse/reference.json, régénéré par tools/argparse/gen_reference.py).
# Sous-processus : binaire ./alex (ALEX_BIN pour le changer) ; bash/zsh/groff sont utilisés s'ils existent.
test-argparse: alex
	ALEX_BIN=./alex ./alex run tests/argparse/test_argparse.al

test-ui-portable: alex
	ALEX_UI_BACKEND=headless ./alex run tests/ui/test_ui_headless.al
	./alex run tests/test_defaults.al
	ALEX_UI_BACKEND=headless ./alex run tests/ui/test_state_ui.al
	./alex run tests/ui/test_state.al
	ALEX_UI_BACKEND=headless ./alex run tests/ui/test_tween.al
	./alex run tests/ui/test_gesture.al
	ALEX_UI_BACKEND=headless ./alex run tests/ui/test_edit.al
	ALEX_UI_BACKEND=headless ./alex run tests/ui/test_interact.al
	ALEX_UI_BACKEND=headless ./alex run tests/ui/test_interact2.al
	ALEX_UI_BACKEND=headless ./alex run tests/ui/test_interact_draw.al
test-ui-x11: alex
	sh tests/ui/run_x11_test.sh
	sh tests/ui/run_x11_gestures.sh

# Chaîne d'outils écrite en ALEX (docs/SELFHOST.md) :
#   test-selfhost   point fixe de l'auto-compilation (bytecode) et table de référence, sous-ensemble rapide
#   test-golden     table de référence complète : bytecode et exécutables de chaque cible, octet pour octet
#                   (tests/selfhost/golden.tsv, enregistrée avec le compilateur de référence)
#   test-alexc      commandes (repl, fmt, new, doc, test, pkg, debug, lsp) : sorties de référence (tests/alexc/golden)
.PHONY: test-selfhost test-golden test-alexc
test-selfhost: alex
	sh tests/selfhost/run_selfhost.sh

test-golden: alex
	bash tests/selfhost/golden.sh ./alex

test-alexc: alex
	bash tests/alexc/golden.sh ./alex

test-runtime: alex
	./alex run tests/lang/test_runtime.al

# Ramasse-miettes : charge normale, puis collecte très fréquente + mode poison (toute racine oubliée plante de
# façon déterministe).
test-gc-vm: alex
	./alex run tests/lang/test_gc.al
	ALEX_GC_STRESS=5 ALEX_GC_POISON=1 ./alex run tests/lang/test_gc.al

test-ui: alex
	./alex run tests/test_ui.al

test: test-selfhost test-alexc test-tooling test-ui-x11 test-window-x11 test-network test-concurrency test-io test-system test-hardware test-hardware-ext test-media test-multimedia test-sysapp test-concurrency2 test-event-window test-drivers test-drivers-kernel test-stdlib2 test-stdlib2-native test-ui-view test-runtime test-gc-vm test-ui test-ui-portable test-math test-sci test-lang test-types test-native test-native-windows test-native-uefi test-native-aarch64 test-native-windows-arm64 test-kernel test-dict-order test-exceptions test-trace test-standalone test-oop test-closures test-comprehensions test-pythonic test-builtins test-async test-channel test-json test-functional test-stdlib-pure test-office test-version test-process test-ffi test-memory test-argparse test-gamedev
	./alex run tests/test_pure_stdlib.al
	./alex run tests/test_os.al

clean:
	rm -f alex alexc
	rm -rf $(BUILD)/generated $(BUILD)/alex $(BUILD)/alexvm $(BUILD)/alex.exe $(BUILD)/alexvm.exe $(BUILD)/*.tmp
	find stdlib tests examples -name '*.albc' -newer VERSION -delete 2>/dev/null || true

# Retour à l'état de la graine (build/ entier, y compris l'amorçage).
distclean: clean
	rm -rf $(BUILD) dist

# =======================================================================
# Distribution
# =======================================================================
# Distribution installable d'ALEX (archive .tar.gz + paquet .deb) : voir tools/package.sh, docs/ECOSYSTEME.md.
#   bin/alex, bin/alexvm    lib/alex/{stdlib,runtime,templates}    share/...
package: alex
	sh tools/package.sh $$(./alex version --short)

dist-clean:
	rm -rf dist

# Installeur Windows : alex.exe + alexvm.exe (produits depuis Linux) et bibliothèque ->
# dist/alex-<version>-windows-x86_64.zip (install.cmd) et, si Inno Setup est disponible, l'installeur .exe.
.PHONY: package installer-windows test-installer dist-clean distclean
test-installer:
	sh tests/test_windows_installer.sh
installer-windows: alex-windows
	sh tools/package-windows.sh windows-x86_64
