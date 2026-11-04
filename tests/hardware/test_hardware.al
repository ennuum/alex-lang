# Test des modules hardware.* sur une copie construite de /sys, /proc et /dev (hardware._sys.set_root), puis
# sur le vrai système (aucune erreur, listes éventuellement vides).

from core use len, type
from collections use append, contains_key
use string as s
use os
use file
use process
use filesystem as fs
use hardware._sys as hw
use hardware._input as evdev
use hardware.keyboard as keyboard
use hardware.mouse as mouse
use hardware.screen as screen
use hardware.gpu as gpu
use hardware.usb as usb
use hardware.audio as audio
use hardware.microphone as mic
use hardware.camera as camera

stats := [0, 0]
notes := []

func check_eq(actual, expected, label):
    if actual == expected:
        stats[0] = stats[0] + 1
    else:
        stats[1] = stats[1] + 1
        append(notes, f"{label} : obtenu {actual}, attendu {expected}")

func check(cond, label):
    check_eq(cond, true, label)

func error_of(f):
    try:
        f()
    catch e:
        return e.type
    return "aucune erreur"

func close_to(a, b, eps):
    d := a - b
    if d < 0:
        d = -d
    return d <= eps

func put(root, path, text):
    fs.ensure_parent(root + path)
    file.write(root + path, text)

func link(root, path, target):
    fs.ensure_parent(root + path)
    process.run("ln", ["-s", target, root + path])

func edid():
    b := [0 for i in 0..128]
    header := [0, 255, 255, 255, 255, 255, 255, 0]
    for i in 0..8:
        b[i] = header[i]
    b[8] = 16                 # « DEL »
    b[9] = 172
    b[10] = 177
    b[11] = 160
    b[17] = 30                # 2020
    b[21] = 60
    b[22] = 34
    b[54] = 2                 # mode détaillé : 1920 x 1080, 597 x 336 mm
    b[55] = 58
    b[56] = 128
    b[58] = 112
    b[59] = 56
    b[61] = 64
    b[66] = 85
    b[67] = 80
    b[68] = 33
    b[75] = 252               # nom de l'écran
    name := "DELL U2720Q\n"
    for i in 0..len(name):
        b[77 + i] = s.ord(name[i])
    b[93] = 255               # numéro de série
    serial := "ABC123\n"
    for i in 0..len(serial):
        b[95 + i] = s.ord(serial[i])
    return b

func events(list_of):
    out := []
    t := 0
    for e in list_of:
        t += 1
        for byte in evdev.encode(e[0], e[1], e[2], 1700000000, t * 1000):
            append(out, byte)
    return out

func build(root):
    put(root, "/proc/bus/input/devices", "I: Bus=0011 Vendor=0001 Product=0001 Version=ab41\nN: Name=\"AT Translated Set 2 keyboard\"\nP: Phys=isa0060/serio0/input0\nS: Sysfs=/devices/platform/i8042/serio0/input/input0\nU: Uniq=\nH: Handlers=sysrq kbd event0 leds \nB: PROP=0\nB: EV=120013\nB: KEY=402000000 3803078f800d001 feffffdfffefffff fffffffffffffffe\nB: MSC=10\nB: LED=7\n\nI: Bus=0003 Vendor=046d Product=c52b Version=0111\nN: Name=\"Logitech USB Receiver Mouse\"\nP: Phys=usb-0000:00:14.0-1/input1\nS: Sysfs=/devices/pci0000:00/usb1/1-1/input/input5\nU: Uniq=\nH: Handlers=mouse0 event1 \nB: PROP=0\nB: EV=17\nB: KEY=ffff0000 0 0 0 0\nB: REL=1943\nB: MSC=10\n\nI: Bus=0019 Vendor=0000 Product=0001 Version=0000\nN: Name=\"Power Button\"\nP: Phys=LNXPWRBN/button/input0\nS: Sysfs=/devices/LNXSYSTM:00/LNXPWRBN:00/input/input2\nU: Uniq=\nH: Handlers=kbd event2 \nB: PROP=0\nB: EV=3\nB: KEY=10000000000000 0\n")
    fs.ensure_dir(root + "/dev/input")
    file.write_bytes(root + "/dev/input/event0", events([[4, 4, 30], [1, 30, 1], [0, 0, 0], [1, 30, 2], [1, 30, 0], [0, 0, 0], [1, 42, 1], [1, 999, 1]]))
    file.write_bytes(root + "/dev/input/event1", events([[2, 0, 5], [2, 1, -3], [0, 0, 0], [1, 272, 1], [0, 0, 0], [2, 8, -1], [0, 0, 0], [0, 0, 0], [1, 272, 0], [2, 0, 1], [0, 0, 0]]))
    # Écrans et carte graphique.
    put(root, "/sys/class/drm/card0-HDMI-A-1/status", "connected\n")
    put(root, "/sys/class/drm/card0-HDMI-A-1/enabled", "enabled\n")
    put(root, "/sys/class/drm/card0-HDMI-A-1/modes", "1920x1080\n1280x720\n1920x1080\n1024x768i\n")
    file.write_bytes(root + "/sys/class/drm/card0-HDMI-A-1/edid", edid())
    put(root, "/sys/class/drm/card0-DP-1/status", "disconnected\n")
    put(root, "/sys/class/drm/card0-DP-1/modes", "")
    put(root, "/sys/class/drm/card0-DP-1/edid", "")
    fs.ensure_dir(root + "/sys/class/drm/card0")
    put(root, "/sys/class/drm/card1/device/uevent", "DRIVER=vc4-drm\nOF_NAME=gpu\n")
    fs.ensure_dir(root + "/sys/class/drm/card1/device/drm/renderD129")
    gp := "/sys/bus/pci/devices/0000:01:00.0"
    put(root, gp + "/class", "0x030000\n")
    put(root, gp + "/vendor", "0x10de\n")
    put(root, gp + "/device", "0x2484\n")
    put(root, gp + "/boot_vga", "1\n")
    fs.ensure_dir(root + gp + "/drm/card0")
    fs.ensure_dir(root + gp + "/drm/renderD128")
    link(root, gp + "/driver", "../../../bus/pci/drivers/nvidia")
    put(root, "/sys/bus/pci/devices/0000:00:02.0/class", "0x038000\n")
    put(root, "/sys/bus/pci/devices/0000:00:02.0/vendor", "0x8086\n")
    put(root, "/sys/bus/pci/devices/0000:00:02.0/device", "0x9a49\n")
    put(root, "/sys/bus/pci/devices/0000:00:02.0/mem_info_vram_total", "268435456\n")
    put(root, "/sys/bus/pci/devices/0000:00:1f.3/class", "0x040300\n")
    put(root, "/sys/class/graphics/fb0/name", "simpledrmdrmfb\n")
    put(root, "/sys/class/graphics/fb0/virtual_size", "1920,1080\n")
    put(root, "/sys/class/graphics/fb0/bits_per_pixel", "32\n")
    # USB.
    u := "/sys/bus/usb/devices/"
    for kv in [["idVendor", "1d6b"], ["idProduct", "0002"], ["bDeviceClass", "09"], ["busnum", "1"], ["devnum", "1"], ["speed", "480"], ["product", "EHCI Host Controller"], ["version", " 2.00"]]:
        put(root, u + "usb1/" + kv[0], kv[1] + "\n")
    put(root, u + "1-0:1.0/bInterfaceClass", "09\n")
    for kv in [["idVendor", "046d"], ["idProduct", "c52b"], ["bDeviceClass", "00"], ["busnum", "1"], ["devnum", "2"], ["speed", "12"], ["manufacturer", "Logitech"], ["product", "USB Receiver"], ["version", " 2.00"], ["bMaxPower", "98mA"]]:
        put(root, u + "1-1/" + kv[0], kv[1] + "\n")
    put(root, u + "1-1:1.0/bInterfaceClass", "03\n")
    put(root, u + "1-1:1.1/bInterfaceClass", "03\n")
    link(root, u + "1-1/driver", "../../../../bus/usb/drivers/usb")
    for kv in [["idVendor", "0781"], ["idProduct", "5581"], ["bDeviceClass", "00"], ["busnum", "2"], ["devnum", "13"], ["speed", "5000"], ["manufacturer", "SanDisk"], ["product", "Ultra"], ["serial", "4C530001"], ["version", " 3.20"]]:
        put(root, u + "2-3/" + kv[0], kv[1] + "\n")
    put(root, u + "2-3:1.0/bInterfaceClass", "08\n")
    # Son.
    put(root, "/proc/asound/cards", " 0 [PCH            ]: HDA-Intel - HDA Intel PCH\n                      HDA Intel PCH at 0xf7f10000 irq 32\n 1 [Webcam         ]: USB-Audio - HD Webcam C270\n                      HD Webcam C270 at usb-0000:00:14.0-2, high speed\n")
    put(root, "/proc/asound/pcm", "00-00: ALC892 Analog : ALC892 Analog : playback 1 : capture 1\n00-03: HDMI 0 : HDMI 0 : playback 1\n01-00: USB Audio : USB Audio : capture 1\n")
    # Caméras.
    for n in [["video0", "HD Webcam C270", "0"], ["video1", "HD Webcam C270", "1"], ["video10", "Autre caméra", "0"], ["video2", "Capture", "0"]]:
        put(root, "/sys/class/video4linux/" + n[0] + "/name", n[1] + "\n")
        put(root, "/sys/class/video4linux/" + n[0] + "/index", n[2] + "\n")
    link(root, "/sys/class/video4linux/video0/device/driver", "../../../bus/usb/drivers/uvcvideo")
    link(root, "/sys/class/video4linux/video0/device/subsystem", "../../../bus/usb")

func test_fixture(root):
    build(root)
    hw.set_root(root)

    # Clavier.
    ks := keyboard.keyboards()
    check_eq([k.name for k in ks], ["AT Translated Set 2 keyboard"], "keyboards (bouton d'alimentation exclu)")
    check_eq([ks[0].path, ks[0].bus, keyboard.available()], ["/dev/input/event0", 17, true], "Keyboard : nœud, bus")
    kb := keyboard.open()
    seq := []
    e := kb.read(1.0)
    while e != null:
        append(seq, e.key + ":" + e.action)
        e = kb.read(1.0)
    kb.close()
    check_eq(seq, ["a:press", "a:repeat", "a:release", "left_shift:press"], "lecture des touches (evdev)")
    check_eq([keyboard.key_name(28), keyboard.key_name(103), keyboard.key_name(500)], ["enter", "up", "key_500"], "key_name")
    check_eq(error_of(() => keyboard.open("/dev/input/absent")), "HardwareError", "open : nœud absent")

    # Souris.
    ms := mouse.mice()
    check_eq([m.name for m in ms], ["Logitech USB Receiver Mouse"], "mice")
    mr := mouse.open(ms[0])
    r1 := mr.read(1.0)
    r2 := mr.read(1.0)
    r3 := mr.read(1.0)
    r4 := mr.read(1.0)
    check_eq([r1.dx, r1.dy, r1.moved()], [5, -3, true], "souris : mouvement")
    check_eq(r2.buttons, {"left": true}, "souris : appui")
    check_eq(r3.wheel, -1, "souris : molette")
    check_eq([r4.buttons, r4.dx], [{"left": false}, 1], "souris : relâchement + mouvement")
    check_eq(mr.read(0.1), null, "souris : fin")
    mr.close()

    # Écrans.
    outs := screen.outputs()
    check_eq([o.name for o in outs], ["DP-1", "HDMI-A-1"], "outputs")
    sc := screen.primary()
    check_eq([sc.name, sc.card, sc.connected, sc.enabled, sc.resolution, sc.modes], ["HDMI-A-1", "card0", true, true, [1920, 1080], [[1920, 1080], [1280, 720], [1024, 768]]], "écran : état et modes")
    check_eq([sc.manufacturer, sc.model, sc.serial, sc.year, sc.product_code, sc.width_mm, sc.height_mm], ["DEL", "DELL U2720Q", "ABC123", 2020, 41137, 597, 336], "écran : EDID")
    check_eq([sc.diagonal_inches(), sc.dpi()], [27.0, 82], "écran : diagonale, dpi")
    check_eq(len(screen.screens()), 1, "screens : branchés seulement")
    check_eq(screen.parse_edid([1, 2, 3]), null, "parse_edid invalide")
    check_eq(screen.framebuffers(), [{"name": "simpledrmdrmfb", "device": "/dev/fb0", "width": 1920, "height": 1080, "bits": 32}], "framebuffers")
    xr := screen.parse_xrandr("Screen 0: minimum 8 x 8, current 2560 x 1440, maximum 32767 x 32767\neDP-1 connected primary 2560x1440+0+0 (normal left inverted right x axis y axis) 309mm x 174mm\n   2560x1440     60.00*+  48.00\n   1920x1080     60.01    59.97\nHDMI-1 disconnected (normal left inverted right x axis y axis)\n")
    check_eq([[x.name, x.connected, x.enabled, x.resolution, x.modes, x.width_mm] for x in xr], [["eDP-1", true, true, [2560, 1440], [[2560, 1440], [1920, 1080]], 309], ["HDMI-1", false, false, null, [], null]], "parse_xrandr")

    # Cartes graphiques.
    gs := gpu.gpus()
    check_eq([[g.slot, g.vendor, g.device_id_hex(), g.driver, g.card, g.render_node, g.boot_vga, g.kind] for g in gs], [["0000:00:02.0", "Intel", "9a49", null, null, null, false, "display"], ["0000:01:00.0", "NVIDIA", "2484", "nvidia", "card0", "/dev/dri/renderD128", true, "vga"], [null, null, null, "vc4-drm", "card1", "/dev/dri/renderD129", false, null]], "gpus")
    check_eq([gs[0].vram, gpu.primary().vendor, gpu.vendor_name(4098)], [268435456, "NVIDIA", "AMD"], "gpu : vram, primary, vendor_name")

    # USB.
    ds := usb.devices()
    check_eq([[d.sysname, d.id(), d.name(), d.classes, d.speed_mbps, d.node()] for d in ds], [["1-1", "046d:c52b", "Logitech USB Receiver", ["hid"], 12, "/dev/bus/usb/001/002"], ["2-3", "0781:5581", "SanDisk Ultra", ["mass_storage"], 5000, "/dev/bus/usb/002/013"], ["usb1", "1d6b:0002", "EHCI Host Controller", ["hub"], 480, "/dev/bus/usb/001/001"]], "usb.devices")
    check_eq([ds[0].driver, ds[0].max_power_ma, ds[0].usb_version, ds[1].serial, ds[2].is_hub()], ["usb", 98, "2.00", "4C530001", true], "usb : détails")
    check_eq([usb.find(1921).product, usb.find("046d", "c52b").product, usb.find(1, 2)], ["Ultra", "USB Receiver", null], "usb.find")
    check_eq([d.sysname for d in usb.by_class("hid")], ["1-1"], "usb.by_class")
    check_eq(len(usb.devices(false)), 2, "usb : sans concentrateurs")

    # Son, micro, caméra.
    check_eq(audio.cards(), [{"index": 0, "id": "PCH", "driver": "HDA-Intel", "name": "HDA Intel PCH"}, {"index": 1, "id": "Webcam", "driver": "USB-Audio", "name": "HD Webcam C270"}], "audio.cards")
    check_eq([[d.alsa_name(), d.name, d.playback, d.capture] for d in audio.devices()], [["hw:0,0", "ALC892 Analog", true, true], ["hw:0,3", "HDMI 0", true, false], ["hw:1,0", "USB Audio", false, true]], "audio.devices")
    check_eq([[d.alsa_name() for d in audio.outputs()], [d.alsa_name() for d in mic.microphones()]], [["hw:0,0", "hw:0,3"], ["hw:0,0", "hw:1,0"]], "outputs / microphones")
    cs := camera.cameras()
    check_eq([[c.node, c.path, c.name] for c in cs], [["video0", "/dev/video0", "HD Webcam C270"], ["video2", "/dev/video2", "Capture"], ["video10", "/dev/video10", "Autre caméra"]], "cameras (ordre numérique, sans métadonnées)")
    check_eq([cs[0].driver, cs[0].bus, len(camera.all_nodes()), camera.primary().node], ["uvcvideo", "usb", 4, "video0"], "camera : détails")
    hw.set_root("")

func test_wav(tmp):
    la := audio.tone(440, 0.25, 8000, 0.5)
    check_eq(len(la), 2000, "tone : nombre d'échantillons")
    check(close_to(audio.rms(la), 0.5 / 1.41421356, 0.01) and close_to(audio.peak(la), 0.5, 0.001), "tone : niveau")
    p := tmp + "/la.wav"
    audio.write_wav(p, la, 8000)
    check_eq(file.size(p), 44 + 4000, "write_wav : taille")
    w := audio.read_wav(p)
    check_eq([w.rate, w.channels, w.bits, w.frames(), w.duration()], [8000, 1, 16, 2000, 0.25], "read_wav : en-tête")
    worst := 0.0
    for i in 0..len(la):
        d := la[i] - w.samples[i]
        if d < 0:
            d = -d
        if d > worst:
            worst = d
    check(worst < 0.0001, "WAV 16 bits : aller-retour")
    for bits in [8, 24, 32]:
        w2 := audio.decode_wav(audio.encode_wav([0.0, 0.5, -0.5, 1.0, -1.0], 8000, 1, bits))
        ok := w2.bits == bits
        tol := 0.01
        if bits > 8:
            tol = 0.00001
        for k in 0..5:
            if not close_to(w2.samples[k], [0.0, 0.5, -0.5, 1.0, -1.0][k], tol):
                ok = false
        check(ok, f"WAV {bits} bits : aller-retour")
    st := audio.decode_wav(audio.encode_wav([0.1, -0.1, 0.2, -0.2], 22050, 2))
    check_eq([st.channels, st.frames(), [x > 0 for x in st.channel(0)], [x < 0 for x in st.channel(1)]], [2, 2, [true, true], [true, true]], "WAV stéréo")
    check_eq(audio.mix([[0.8, 0.5], [0.8]]), [1.0, 0.5], "mix borné")
    check_eq(len(audio.silence(0.5, 8000)), 4000, "silence")
    check_eq(error_of(() => audio.decode_wav([1, 2, 3])), "ArgumentError", "WAV invalide")
    check_eq(error_of(() => audio.encode_wav([0.0], 8000, 2)), "ArgumentError", "canaux incohérents")
    check_eq(error_of(() => audio.tone(440, 1, 10)), "ArgumentError", "fréquence d'échantillonnage")
    # WAV flottant 32 bits fabriqué à la main (format 3) : 0.5 = 0x3F000000, -1.0 = 0xBF800000.
    hdr := audio.encode_wav([0.0, 0.0], 8000, 1, 32)
    hdr[20] = 3
    data := [0, 0, 0, 63, 0, 0, 128, 191]
    for k in 0..8:
        hdr[44 + k] = data[k]
    check_eq(audio.decode_wav(hdr).samples, [0.5, -1.0], "WAV flottant 32 bits")
    check(close_to(mic.level(p), audio.rms(la), 0.001), "microphone.level")

func test_real_system():
    # Sur la vraie machine : aucune erreur, des listes (vides dans un conteneur).
    for f in [keyboard.keyboards, mouse.mice, screen.outputs, screen.framebuffers, gpu.gpus, usb.devices, audio.cards, audio.devices, camera.cameras]:
        check_eq(type(f()), "list", "système réel : liste")
    check(type(keyboard.available()) == "bool" and type(mic.available()) == "bool", "système réel : available")
    if not keyboard.available():
        check_eq(error_of(() => keyboard.open()), "HardwareError", "aucun clavier : HardwareError")
    if not camera.available():
        check_eq(error_of(() => camera.capture("/tmp/x.jpg")), "HardwareError", "aucune caméra : HardwareError")

func main():
    tmp := fs.make_temp_dir("alex_hw_")
    try:
        test_fixture(tmp + "/racine")
        test_wav(tmp)
        test_real_system()
    finally:
        hw.set_root("")
        fs.remove_tree(tmp)
    print(f"hardware : {stats[0]} vérifications OK, {stats[1]} échec(s)")
    for n in notes:
        print("  ÉCHEC " + n)
    if stats[1] > 0:
        raise("TestError", "test_hardware : échecs")

main()
