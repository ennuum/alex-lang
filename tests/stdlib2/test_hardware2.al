# Tests : modules matériels ajoutés côté application :
# usb.usb_errors / usb_interface / usb_configuration, audio.audio_errors / audio_buffer / audio_output,
# microphone.microphone_errors / input_levels / capture_session, camera.camera_errors / camera_controls /
# camera_stream, gpu.gpu_errors / gpu_fence / gpu_queue, graphics.graphics_errors / vertex_layout / sampler /
# framebuffer / graphics_backend, hardware.hardware_errors / bus / device_resource.
# Le matériel est simulé par des fichiers (/sys, /dev, /proc sous une racine temporaire) et des sources en
# mémoire ; rien n'est inventé côté matériel réel (les diagnostics lisent la vraie machine).
from core use len, type
from collections use append
use check as t
use os
use io
use math
use thread
use process
use string
use usb.usb_descriptor as ud
use usb.usb_errors as uerr
use usb.usb_interface as uif
use usb.usb_configuration as ucfg
use audio.audio_format as af
use audio.audio_stream as ast
use audio.audio_errors as aerr
use audio.audio_buffer as ab
use audio.audio_output as ao
use microphone.microphone_errors as merr
use microphone.input_levels as lv
use microphone.capture_session as cs
use camera.video_frame as vf
use camera.camera_errors as cerr
use camera.camera_controls as cc
use camera.camera_stream as cst
use camera.camera_capture as cap
use camera.camera_format as cfmt
use gpu.gpu_device as gd
use gpu.gpu_errors as gerr
use gpu.gpu_fence as gfe
use gpu.gpu_queue as gq
use graphics
use graphics.buffer as gbuf
use graphics.texture as gt
use graphics.surface as gsu
use graphics.graphics_errors as gre
use graphics.vertex_layout as vl
use graphics.sampler as gsm
use graphics.framebuffer as gfb
use graphics.graphics_backend as gbk
use hardware._sys as hs
use hardware.hardware_errors as he
use hardware.bus as hb
use hardware.device_resource as dr

func dbl(x):
    return [v * 2 for v in x]

func near(a, b, eps=0.0001):
    d := a - b
    if d < 0:
        d = -d
    return d <= eps

if thread.is_main():
    tmp := os.tmp_dir() + "/alex_test_hw2_" + str(os.pid())
    os.mkdir_all(tmp)

    # -------------------------------------------------------------- usb
    raw := [9, 2, 75, 0, 2, 1, 0, 0x80, 50,
            8, 11, 0, 2, 2, 2, 1, 0,
            9, 4, 0, 0, 1, 2, 2, 1, 0,
            5, 0x24, 0, 0x10, 0x01,
            5, 0x24, 1, 0, 1,
            4, 0x24, 2, 2,
            5, 0x24, 6, 0, 1,
            7, 5, 0x83, 3, 8, 0, 16,
            9, 4, 1, 0, 2, 0x0A, 0, 0, 0,
            7, 5, 0x02, 2, 64, 0, 0,
            7, 5, 0x81, 2, 64, 0, 0]
    t.eq(len(raw), 75, "usb : descripteur de test complet")
    conf := ucfg.parse(raw)
    t.eq(len(conf.associations), 1, "usb_configuration : association d'interfaces")
    t.eq([conf.associations[0].first_interface, conf.associations[0].count], [0, 2], "usb_configuration : interfaces associées")
    t.eq(conf.max_power_ma(), 100, "usb_configuration : courant demandé")
    t.check(conf.power_ok("high") and conf.power_ok("full", true), "usb_configuration : budget d'alimentation")
    t.check(conf.has_class(ud.CLASS_CDC) and conf.has_class(ud.CLASS_CDC_DATA), "usb_configuration : classes présentes")
    t.eq(conf.association_of(1).first_interface, 0, "usb_configuration : association d'une interface")
    t.raises(() => ucfg.parse([9, 1, 0]), "ArgumentError", "usb_configuration : descripteur invalide")
    comm := uif.find(conf.descriptor, ud.CLASS_CDC)
    t.eq(comm.cdc_union(), [0, [1]], "usb_interface : union CDC")
    t.eq(comm.cdc_acm_capabilities(), 2, "usb_interface : capacités ACM")
    t.eq(comm.cdc_call_management(), {"capabilities": 0, "data_interface": 1}, "usb_interface : gestion d'appel")
    t.eq(comm.cdc_version(), "1.10", "usb_interface : version CDC")
    irq := comm.endpoint(ud.EP_INTERRUPT, true)
    t.eq(uif.bandwidth(irq, "full"), 8 * 1000 // 16, "usb_interface : bande passante interruption (pleine vitesse)")
    t.eq(uif.bandwidth(irq, "high"), 8 * 8000 // 32768, "usb_interface : bande passante interruption (haute vitesse)")
    dat := uif.get(conf.descriptor, 1)
    t.check(dat.endpoint(ud.EP_BULK, true) != null and dat.endpoint(ud.EP_BULK, false) != null, "usb_interface : points d'accès bloc")
    t.eq(uif.bandwidth(dat.endpoint(ud.EP_BULK, true)), 0, "usb_interface : bloc non réservé")
    t.eq(len(uif.functions(conf.descriptor)), 2, "usb_interface : fonctions")
    t.eq(uerr.from_errno("EPIPE")["type"], "UsbStall", "usb_errors : EPIPE")
    t.eq(uerr.from_errno("EBUSY")["retry"], "detach", "usb_errors : EBUSY")
    t.raises(() => uerr.raise_errno("EACCES", "ouverture"), "UsbAccessError", "usb_errors : EACCES")
    t.eq(uerr.errno_in("libusb: erreur [ETIMEDOUT]"), "ETIMEDOUT", "usb_errors : errno dans un message")
    rule := uerr.udev_rule(0x046d, 0xc52b)
    t.check(rule != null and type(rule) == "str" and len(rule) > 20, "usb_errors : règle udev")

    # -------------------------------------------------------------- audio
    aerr.check_format(48000, 2, "s16le")
    t.raises(() => aerr.check_format(100, 2), "AudioFormatError", "audio_errors : fréquence invalide")
    t.raises(() => aerr.check_frames([0.0, 0.0, 0.0], 2), "AudioBufferError", "audio_errors : trames incomplètes")
    q := aerr.check_samples([0.0, 1.0, -1.0, 0.5, 1.0e40])
    t.eq([q["clipped"], q["non_finite"], q["silent"]], [2, 1, false], "audio_errors : qualité des échantillons")
    rb := ab.RingBuffer(4, 2, 48000)
    t.eq(rb.write([1, 1, 2, 2, 3, 3]), 3, "audio_buffer : écriture")
    t.eq(rb.read(2), [1, 1, 2, 2], "audio_buffer : lecture")
    rb.write([4, 4, 5, 5, 6, 6, 7, 7])
    t.eq(rb.overruns, 1, "audio_buffer : débordement (drop_oldest)")
    t.eq(rb.read(10, true), [4, 4, 5, 5, 6, 6, 7, 7] + [0.0 for i in 0..12], "audio_buffer : la plus ancienne trame perdue, silence de complément")
    t.eq(rb.underruns, 1, "audio_buffer : sous-alimentation")
    strict := ab.RingBuffer(1, 1, 8000, "error")
    strict.write([0.1])
    t.raises(() => strict.write([0.2]), "AudioBufferError", "audio_buffer : politique error")
    rk := ab.Reblocker(4, 1)
    blocks := rk.push([1, 2, 3, 4, 5, 6])
    t.eq(blocks, [[1, 2, 3, 4]], "audio_buffer : reblocage")
    t.eq(rk.flush(), [5, 6, 0.0, 0.0], "audio_buffer : vidage complété")
    t.eq(ab.deinterleave([1, 2, 3, 4], 2), [[1, 3], [2, 4]], "audio_buffer : désentrelacement")
    t.eq(ab.interleave([[1, 3], [2, 4]]), [1, 2, 3, 4], "audio_buffer : entrelacement")
    fmt := af.AudioFormat(8000, 1, "s16le")
    sink := ast.MemorySink(fmt)
    out := ao.AudioOutput(sink, fmt, 100)
    out.set_volume_db(-6.0)
    t.check(near(out.volume_db(), -6.0), "audio_output : volume en dB")
    out.enqueue([1.0 for i in 0..250])
    t.eq(out.queued_frames(), 250, "audio_output : file")
    t.eq(out.play_all(), 250, "audio_output : tout écrit")
    t.eq(out.blocks_written, 3, "audio_output : blocs de 100 trames")
    t.check(near(sink.samples[0], math.pow(10.0, -6.0 / 20.0)), "audio_output : gain appliqué")
    out2 := ao.AudioOutput(ast.MemorySink(fmt), fmt, 50)
    out2.add_effect((b) => [x * 0.0 for x in b])
    out2.play([0.5 for i in 0..50])
    t.eq(out2.sinks[0].samples[10], 0.0, "audio_output : effet appliqué")
    t.raises(() => out2.enqueue(ast.AudioBuffer([0.0, 0.0], af.CD)), "AudioFormatError", "audio_output : format incompatible")
    out2.close()
    t.raises(() => out2.pump(), "AudioError", "audio_output : sortie fermée")

    # -------------------------------------------------------------- microphone
    t.eq(lv.to_db(1.0), 0.0, "input_levels : 0 dB pleine échelle")
    t.eq(lv.to_db(0.0), -100.0, "input_levels : plancher")
    m := lv.LevelMeter(16000)
    quiet := [0.001 * math.sin(i * 0.3) for i in 0..1600]
    loud := [0.5 * math.sin(i * 0.3) for i in 0..1600]
    k := 0
    while k < 20:
        m.feed(quiet)
        k += 1
    t.check(not m.is_speech(), "input_levels : silence")
    m.feed(loud)
    t.check(m.is_speech() and m.rms_db > -10.0, "input_levels : parole détectée")
    t.check(m.snr_db() > 30.0, "input_levels : rapport signal / bruit")
    t.check(len(lv.bar(-18.0, 20)) > 20, "input_levels : barre de niveau")
    t.eq(merr.check_recording([])["problem"], "enregistrement vide", "microphone_errors : vide")
    t.check(merr.check_recording([0.0 for i in 0..100])["problem"] != null, "microphone_errors : silence")
    t.check(merr.check_recording(loud)["ok"], "microphone_errors : enregistrement correct")
    t.check(type(merr.diagnose()["ok"]) == "bool", "microphone_errors : diagnostic de la machine")
    voice := af.VOICE
    src := ast.MemorySource([0.0 for i in 0..8000] + [0.4 * math.sin(i * 0.2) for i in 0..16000] + [0.0 for i in 0..32000], voice)
    sess := cs.CaptureSession(src, voice)
    states := []
    sess.on_state((st) => append(states, st))
    sess.stop_on_silence = 1.0
    sess.wav_path = tmp + "/note.wav"
    sess.start()
    sess.mark("début")
    r := sess.run_until_done()
    t.eq(r["reason"], "silence", "capture_session : arrêt sur silence après la parole")
    t.check(r["duration"] >= 2.4 and r["duration"] < 3.0, "capture_session : durée " + str(r["duration"]))
    t.eq(len(r["markers"]), 1, "capture_session : repère")
    t.check(os.exists(tmp + "/note.wav"), "capture_session : fichier WAV")
    t.check("recording" in states and "stopped" in states, "capture_session : états")
    t.check(len(sess.segments()) >= 1, "capture_session : segments de parole")
    s2 := cs.CaptureSession(ast.MemorySource([0.1 for i in 0..16000], voice), voice)
    s2.max_duration = 0.5
    s2.start()
    t.eq(s2.run_until_done()["reason"], "durée maximale", "capture_session : durée maximale")
    t.raises(() => cs.CaptureSession(ast.MemorySource([], voice), voice).stop(), "CaptureError", "capture_session : arrêt sans démarrage")

    # -------------------------------------------------------------- camera
    t.eq(cerr.from_message("Device or resource busy"), "CameraBusy", "camera_errors : occupée")
    t.eq(cerr.from_message("open /dev/video0: Permission denied"), "CameraUnavailable", "camera_errors : droits")
    t.eq(cerr.check_frame(vf.solid(4, 4, 0, 0, 0))["problem"], "image noire (obturateur fermé, cache, éclairage)", "camera_errors : image noire")
    t.check(not cerr.check_frame(vf.solid(4, 4, 100, 100, 100))["ok"], "camera_errors : image uniforme")
    dg := cerr.diagnose()
    t.check(type(dg["devices"]) == "list" and type(dg["ffmpeg"]) == "bool", "camera_errors : diagnostic de la machine")
    ctl_text := "                     brightness 0x00980900 (int)    : min=0 max=255 step=1 default=128 value=140\n   white_balance_automatic 0x0098090c (bool)   : default=1 value=1\n            power_line_frequency 0x00980918 (menu)   : min=0 max=2 default=1 value=1\n\t\t\t\t0: Disabled\n\t\t\t\t1: 50 Hz\n\t\t\t\t2: 60 Hz\n   exposure_time_absolute 0x009a0902 (int)    : min=3 max=2047 step=1 default=250 value=250 flags=inactive\n"
    calls := []
    func runner(args):
        append(calls, args)
        if args[0] == "--list-ctrls-menus":
            return ctl_text
        return "brightness: 150\n"
    ctl := cc.CameraControls("/dev/video0", runner)
    t.eq(ctl.names(), ["brightness", "white_balance_automatic", "power_line_frequency", "exposure_time_absolute"], "camera_controls : contrôles v4l2")
    t.eq(ctl.control("power_line_frequency").menu, {0: "Disabled", 1: "50 Hz", 2: "60 Hz"}, "camera_controls : menu")
    ctl.set("brightness", 150)
    t.eq(ctl.get("brightness"), 150, "camera_controls : lecture")
    t.raises(() => ctl.set("brightness", 300), "ControlError", "camera_controls : hors limites")
    t.raises(() => ctl.set("exposure_time_absolute", 300), "ControlError", "camera_controls : contrôle inactif")
    t.raises(() => ctl.set("zoom", 1), "ControlError", "camera_controls : contrôle inconnu")
    t.eq(ctl.reset_all(), 1, "camera_controls : retour aux valeurs par défaut")
    t.eq(calls[len(calls) - 1], ["--set-ctrl=brightness=128"], "camera_controls : commande v4l2-ctl")
    sw := cc.SoftwareControls()
    sw.brightness = 20
    t.eq(sw.apply(vf.solid(2, 1, 100, 100, 100)).data, [120, 120, 120, 120, 120, 120], "camera_controls : luminosité logicielle")
    gains := sw.auto_white_balance(vf.solid(2, 2, 100, 50, 150))
    t.check(near(gains[0], 1.0) and near(gains[1], 2.0), "camera_controls : balance des blancs « monde gris »")
    sw2 := cc.SoftwareControls()
    sw2.saturation = 0.0
    g_ := sw2.apply(vf.solid(1, 1, 200, 0, 0)).data
    t.check(g_[0] == g_[1] and g_[1] == g_[2], "camera_controls : désaturation")
    frames := cst.moving_square(32, 12, 10)
    st := cst.CameraStream(cst.FrameListSource(frames), 3)
    hits := []
    st.on_motion(0.01, (img, part) => append(hits, img.index))
    t.eq(st.pump(), 10, "camera_stream : images lues")
    t.eq([st.stats()["dropped"], st.stats()["queued"]], [7, 3], "camera_stream : file bornée (drop_oldest)")
    t.eq(hits, [1, 2, 3, 4, 5, 6, 7, 8, 9], "camera_stream : mouvement détecté")
    t.eq(st.next().index, 7, "camera_stream : les plus récentes gardées")
    s3 := cst.CameraStream(cst.FrameListSource(cst.moving_square(32, 12, 10)), 20)
    s3.target_fps = 10
    s3.pump()
    t.eq([s3.stats()["skipped"], s3.size()], [6, 4], "camera_stream : cadence cible")
    t.check(near(s3.measured_fps(), 30.0, 0.01), "camera_stream : cadence mesurée")
    s4 := cst.CameraStream(cst.FrameListSource(cst.moving_square(16, 8, 5)), 2, cst.BLOCK)
    s4.add_transform((f) => f.mirror())
    s4.record_to(tmp + "/seq", "img")
    t.eq(s4.pump(), 2, "camera_stream : politique block")
    t.eq(s4.each((f) => f.width, null), 5, "camera_stream : parcours complet")
    t.eq(len(s4.stop_recording()), 5, "camera_stream : séquence enregistrée")
    t.check(os.exists(tmp + "/seq/img000004.ppm"), "camera_stream : fichiers PPM numérotés")
    t.raises(() => cst.CameraStream(cst.FrameListSource([]), 1, "jeter"), "ArgumentError", "camera_stream : politique inconnue")
    if cap.ffmpeg_available():
        live := cst.CameraStream(cap.CameraCapture("testsrc", cfmt.CameraFormat(64, 48, "rgb24", 25), "rgb24", 6), 8)
        live.pump()
        t.eq(live.stats()["read"], 6, "camera_stream : mire ffmpeg")
        live.close()

    # -------------------------------------------------------------- gpu
    t.eq(gerr.classify("NVRM: Xid 79, GPU has fallen off the bus"), "DeviceLost", "gpu_errors : périphérique perdu")
    t.eq(gerr.classify("CUDA error: out of memory"), "OutOfDeviceMemory", "gpu_errors : mémoire")
    t.check(gerr.is_recoverable("MemoryError") and not gerr.is_recoverable("DeviceLost"), "gpu_errors : récupérable")
    t.check(type(gerr.diagnose()["ok"]) == "bool", "gpu_errors : diagnostic de la machine")
    dev := gd.software(2)
    x := dev.memory.upload([1.0, 2.0, 3.0])
    y := dev.memory.upload([1.0, 1.0, 1.0])
    o := dev.memory.zeros("float32", [3])
    qd := gq.GpuQueue(dev, "deferred")
    res := []
    cl := gq.CommandList("calcul").dispatch("saxpy", [x, y], o, [2.0]).read(o, res).dispatch("dot", [x, y], null).dispatch(dbl, [x], o).read(o, res)
    f := qd.submit(cl)
    t.check(not f.is_signaled() and qd.depth() == 1, "gpu_queue : exécution différée")
    f.wait(5.0)
    t.eq(res, [3.0, 5.0, 7.0, 2.0, 4.0, 6.0], "gpu_queue : saxpy puis noyau de l'utilisateur")
    t.eq(qd.results_of(f), [6.0], "gpu_queue : résultat scalaire")
    t.raises(() => cl.fill(o, 1), "QueueError", "gpu_queue : liste déjà soumise")
    t.raises(() => gq.CommandList().dispatch("fft", [x], o), "QueueError", "gpu_queue : opération inconnue")
    tl := gfe.Timeline()
    q2 := gq.GpuQueue(dev, "deferred")
    fa := q2.submit(gq.CommandList("attend").wait(tl, 1).fill(o, 9))
    t.raises(() => fa.wait(0.05), "FenceTimeout", "gpu_fence : délai dépassé")
    gq.GpuQueue(dev).submit(gq.CommandList("signale").signal(tl, 1))
    fa.wait(1.0)
    t.eq(o.download(), [9.0, 9.0, 9.0], "gpu_fence : timeline entre files")
    t.raises(() => tl.signal(0), "ArgumentError", "gpu_fence : timeline décroissante")
    fb := qd.submit(gq.CommandList("mauvaise").copy(x, dev.memory.zeros("float32", [2])).fill(y, 0))
    t.raises(() => fb.wait(), "ArgumentError", "gpu_queue : erreur de commande relancée par la barrière")
    t.eq(y.download(), [0.0, 0.0, 0.0], "gpu_queue : les commandes suivantes continuent")
    fc := qd.submit(gq.CommandList("perdue").fill(x, 1))
    qd.lose()
    t.raises(() => fc.wait(), "DeviceLost", "gpu_queue : périphérique perdu")
    t.raises(() => qd.submit(gq.CommandList()), "DeviceLost", "gpu_queue : file inutilisable")
    t.eq(gq.clone(gq.GpuQueue(dev), o).download(), [9.0, 9.0, 9.0], "gpu_queue : copie de tampon")
    t.eq(gfe.wait_any([gfe.Fence(), gfe.signaled_fence()]), 1, "gpu_fence : wait_any")
    seen := []
    gfe.Fence().on_signal((z) => append(seen, 1))
    sig := gfe.Fence()
    sig.on_signal((z) => append(seen, 2))
    sig.signal()
    t.eq(seen, [2], "gpu_fence : rappel à la signalisation")
    dev.close()

    # -------------------------------------------------------------- graphics
    vb := gbuf.VertexBuffer(gbuf.POSITION_COLOR, [0.0, 0.8, 0.0, 1.0, 0.0, 0.0, 1.0, -0.8, -0.8, 0.0, 0.0, 1.0, 0.0, 1.0, 0.8, -0.8, 0.0, 0.0, 0.0, 1.0, 1.0])
    t.eq(gre.check_draw(vb), [], "graphics_errors : dessin valide")
    t.eq(len(gre.check_draw(vb, gbuf.IndexBuffer([0, 1, 1, 0, 5, 2, 0]))), 3, "graphics_errors : indices, compte, dégénéré")
    t.raises(() => gre.require_valid(vb, gbuf.IndexBuffer([0, 1, 9])), "FormatError", "graphics_errors : require_valid")
    t.raises(() => gre.check_attributes(gbuf.POSITION, ["position", "uv"]), "ShaderError", "graphics_errors : attribut manquant")
    lay := vl.parse("position:float32x3, color:unorm8x4")
    t.eq(lay.stride, 16, "vertex_layout : pas en octets")
    by := lay.pack([[0.0, 1.0, -2.5, 1.0, 0.0, 0.5, 1.0]])
    back := lay.unpack(by)
    t.check(back[0][0:3] == [0.0, 1.0, -2.5] and near(back[0][5], 128 / 255.0), "vertex_layout : aller-retour unorm8")
    h16 := vl.TypedLayout([["p", "float16x2"], ["n", "snorm8x4"], ["i", "sint32"]])
    t.eq(h16.stride, 12, "vertex_layout : demi-flottants et entiers")
    hb_ := h16.unpack(h16.pack([[1.5, -0.333, 0.5, -1.0, 0.0, 1.0, -7]]))[0]
    t.check(hb_[0] == 1.5 and near(hb_[1], -0.333, 0.001) and hb_[3] == -1.0 and hb_[6] == -7.0, "vertex_layout : float16 / snorm8 / sint32")
    t.eq(vl.bits_f16(vl.f16_bits(65504.0)), 65504.0, "vertex_layout : plus grand float16")
    t.eq(lay.interleave({"position": [1, 2, 3, 4, 5, 6], "color": [1, 0, 0, 1, 0, 1, 0, 1]}), [[1, 2, 3, 1, 0, 0, 1], [4, 5, 6, 0, 1, 0, 1]], "vertex_layout : entrelacement")
    t.raises(() => vl.parse("position:float64x3"), "FormatError", "vertex_layout : format inconnu")
    t.eq(lay.vertex_buffer(back).count(), 1, "vertex_layout : vers le pipeline logiciel")
    tex := gt.checkerboard(4, 4, 1, gsu.rgba(1.0, 1.0, 1.0), gsu.rgba(0.0, 0.0, 0.0))
    smp := gsm.Sampler("nearest", "nearest", "none", "clamp")
    t.eq(smp.sample(tex, -0.5, 0.1), [1.0, 1.0, 1.0, 1.0], "sampler : clamp")
    smp.wrap_u = "border"
    smp.border = [1.0, 0.0, 0.0, 1.0]
    t.eq(smp.sample(tex, -0.5, 0.1), [1.0, 0.0, 0.0, 1.0], "sampler : couleur de bord")
    smp.wrap_u = "mirror"
    t.eq(smp.sample(tex, -0.1, 0.1), smp.sample(tex, 0.1, 0.1), "sampler : miroir")
    tex.build_mipmaps()
    tri := gsm.Sampler("linear", "linear", "linear")
    gray := tri.sample(tex, 0.5, 0.5, 2.0)
    t.check(near(gray[0], 0.498, 0.01), "sampler : mipmap le plus petit = gris moyen")
    t.eq(tri.lod_for(tex, 0.5, 0.1), 1.0, "sampler : niveau de détail")
    t.raises(() => gsm.Sampler("cubic"), "ArgumentError", "sampler : filtre inconnu")
    fbo := gfb.Framebuffer(4, 4, 1, true, true, 4)
    fbo.target(0).fill_rect(0, 0, 4, 8, gsu.rgba(1.0, 1.0, 1.0))
    t.eq(fbo.resolve(0).pixel(1, 1), gsu.rgba(1.0, 1.0, 1.0), "framebuffer : résolution (plein)")
    t.eq(fbo.resolve(0).pixel(3, 3), 0, "framebuffer : résolution (vide)")
    fbo.stencil_rect(0, 0, 2, 2, 1)
    redsurf := gsu.Surface(8, 8, false)
    redsurf.clear(gsu.rgba(1.0, 0.0, 0.0))
    t.eq(fbo.masked_copy(redsurf, 1), 16, "framebuffer : copie sous gabarit")
    t.raises(() => fbo.attach(1, gsu.Surface(3, 3)), "FramebufferError", "framebuffer : attachement de mauvaise taille")
    t.raises(() => gfb.Framebuffer(4, 4, 1, true, false, 2), "FramebufferError", "framebuffer : échantillons invalides")
    t.eq(gfb.encode(redsurf, 16, 0)[0:2], [0, 248], "framebuffer : RGB565")
    t.eq(gfb.encode(redsurf, 32, 0)[0:4], [0, 0, 255, 255], "framebuffer : XRGB8888 (B, G, R, X)")
    fbroot := tmp + "/fbroot"
    os.mkdir_all(fbroot + "/dev")
    os.mkdir_all(fbroot + "/sys/class/graphics/fb0")
    io.write_file(fbroot + "/dev/fb0", "")
    io.write_file(fbroot + "/sys/class/graphics/fb0/virtual_size", "4,2\n")
    io.write_file(fbroot + "/sys/class/graphics/fb0/bits_per_pixel", "16\n")
    io.write_file(fbroot + "/sys/class/graphics/fb0/stride", "10\n")
    io.write_file(fbroot + "/sys/class/graphics/fb0/name", "simplefb\n")
    hs.set_root(fbroot)
    fdev := gfb.FbDevice("/dev/fb0")
    t.eq(fdev.describe(), "/dev/fb0 (simplefb) 4x2 16 bits, ligne 10 octets", "framebuffer : /dev/fb0 décrit par sysfs")
    t.eq(fdev.show(redsurf), 20, "framebuffer : écriture dans le framebuffer")
    fbb := io.read_bytes(fbroot + "/dev/fb0")
    t.eq([len(fbb), fbb[0], fbb[1], fbb[8]], [20, 0, 248, 0], "framebuffer : RGB565 et marge de ligne")
    t.eq(gfb.devices(), ["/dev/fb0"], "framebuffer : liste des framebuffers")
    t.eq(gbk.select(["drm", "fbdev", "software"]).name, "fbdev", "graphics_backend : choix du premier disponible")
    t.check(not gbk.get("drm").available(), "graphics_backend : drm jamais simulé")
    sc := gbk.get("fbdev").swapchain(4, 2)
    sc.acquire().clear(gsu.rgba(0.0, 1.0, 0.0))
    sc.present()
    fbb2 := io.read_bytes(fbroot + "/dev/fb0")
    t.eq([fbb2[0], fbb2[1]], [0xE0, 0x07], "graphics_backend : image verte présentée sur /dev/fb0")
    hs.set_root("")
    t.raises(() => gbk.get("vulkan"), "BackendUnavailable", "graphics_backend : dorsal inconnu")
    t.check(gbk.get("software").available() and gbk.get("headless").available(), "graphics_backend : dorsaux logiciels")
    hd := gbk.HeadlessBackend(tmp + "/frames")
    hsc := hd.swapchain(8, 8)
    hsc.acquire().clear(gsu.rgba(0.0, 0.0, 1.0))
    hsc.present()
    t.eq(len(os.list_dir(tmp + "/frames")), 1, "graphics_backend : image PPM présentée")
    t.check(graphics.render_triangle(8, 8).checksum() != 0, "graphics : pipeline toujours fonctionnel")

    # -------------------------------------------------------------- hardware
    root := tmp + "/hwroot"
    base := "/sys/devices/pci0000:00"
    devs := {"0000:00:02.0": base + "/0000:00:02.0", "0000:00:1c.0": base + "/0000:00:1c.0", "0000:02:00.0": base + "/0000:00:1c.0/0000:02:00.0"}
    for n in devs:
        os.mkdir_all(root + devs[n])
        io.write_file(root + devs[n] + "/uevent", "PCI_SLOT_NAME=" + n + "\n")
    os.mkdir_all(root + "/sys/bus/pci/devices")
    os.mkdir_all(root + "/sys/bus/pci/drivers/bochs-drm")
    os.mkdir_all(root + "/sys/bus/usb/devices")
    os.mkdir_all(root + "/proc")
    io.write_file(root + "/sys/bus/pci/drivers/bochs-drm/bind", "")
    io.write_file(root + "/sys/bus/pci/drivers/bochs-drm/unbind", "")
    io.write_file(root + "/sys/bus/pci/drivers_autoprobe", "1\n")
    for n in devs:
        symlink("../../../devices/pci0000:00" + string_rest(devs[n], base), root + "/sys/bus/pci/devices/" + n)
    symlink("../../../bus/pci/drivers/bochs-drm", root + devs["0000:00:02.0"] + "/driver")
    symlink("../../../../devices/pci0000:00/0000:00:02.0", root + "/sys/bus/pci/drivers/bochs-drm/0000:00:02.0")
    io.write_file(root + devs["0000:00:02.0"] + "/resource", "0x00000000fd000000 0x00000000fdffffff 0x0000000000042208\n0x0000000000000000 0x0000000000000000 0x0000000000000000\n0x00000000febf0000 0x00000000febf0fff 0x0000000000040200\n0x0000000000000000 0x0000000000000000 0x0000000000000000\n0x0000000000000000 0x0000000000000000 0x0000000000000000\n0x0000000000000000 0x0000000000000000 0x0000000000000000\n0x00000000000c0000 0x00000000000dffff 0x0000000000046200\n")
    io.write_file(root + devs["0000:00:02.0"] + "/irq", "11\n")
    io.write_file(root + devs["0000:00:02.0"] + "/local_cpulist", "0-3\n")
    io.write_file(root + devs["0000:02:00.0"] + "/resource", "0x000000000000c000 0x000000000000c01f 0x0000000000040101\n0x00000000fd800000 0x00000000fd80ffff 0x0000000000140204\n")
    os.mkdir_all(root + devs["0000:02:00.0"] + "/msi_irqs/24")
    os.mkdir_all(root + devs["0000:02:00.0"] + "/msi_irqs/25")
    io.write_file(root + "/proc/iomem", "00000000-00000fff : Reserved\nfd000000-fdffffff : 0000:00:02.0\n  fd000000-fdffffff : bochs-drm\nfebf0000-febf0fff : 0000:00:02.0\n")
    io.write_file(root + "/proc/ioports", "c000-c01f : 0000:02:00.0\n")
    hs.set_root(root)
    t.eq(hb.names(), ["pci", "usb"], "bus : bus présents")
    pci := hb.get("pci")
    t.eq(pci.device_names(), ["0000:00:02.0", "0000:00:1c.0", "0000:02:00.0"], "bus : périphériques")
    t.eq(pci.driver_of("0000:00:02.0"), "bochs-drm", "bus : pilote lié")
    t.eq(pci.bound_to("bochs-drm"), ["0000:00:02.0"], "bus : périphériques d'un pilote")
    t.eq(pci.unbound(), ["0000:00:1c.0", "0000:02:00.0"], "bus : sans pilote")
    t.check(pci.autoprobe(), "bus : sonde automatique")
    t.eq(pci.tree(), [[0, "0000:00:02.0", "bochs-drm"], [0, "0000:00:1c.0", null], [1, "0000:02:00.0", null]], "bus : topologie (pont)")
    t.eq(pci.bind("0000:02:00.0", "bochs-drm"), "echo 0000:02:00.0 | sudo tee /sys/bus/pci/drivers/bochs-drm/bind", "bus : liaison manuelle")
    t.eq(io.read_file(root + "/sys/bus/pci/drivers/bochs-drm/bind"), "0000:02:00.0", "bus : écrit dans sysfs")
    t.raises(() => pci.unbind("0000:02:00.0"), "BusError", "bus : rien à délier")
    t.raises(() => pci.rescan(), "BusError", "bus : rescan absent")
    t.raises(() => hb.get("isa"), "BusError", "bus : bus inconnu")
    rs := dr.of_device("/sys/bus/pci/devices/0000:00:02.0")
    t.eq([r.name for r in rs.resources], ["BAR0", "BAR2", "ROM"], "device_resource : BAR et ROM")
    t.check(rs.resources[0].prefetchable() and rs.resources[0].size() == 16777216, "device_resource : BAR0 16 Mio préchargeable")
    t.check(rs.resources[2].read_only(), "device_resource : ROM en lecture seule")
    t.eq([rs.irq, rs.local_cpus], [11, "0-3"], "device_resource : interruption et processeurs")
    rs2 := dr.of_device(pci.device("0000:02:00.0"))
    t.check(rs2.resources[0].kind == "io" and rs2.resources[1].is64(), "device_resource : E/S et 64 bits")
    t.eq(rs2.msi, [24, 25], "device_resource : vecteurs MSI")
    cl1 := dr.claims(rs)
    t.eq(cl1[0]["claimed_by"], ["0000:00:02.0", "bochs-drm"], "device_resource : revendication /proc/iomem")
    t.eq(dr.claims(rs2)[0]["claimed_by"], ["0000:02:00.0"], "device_resource : revendication /proc/ioports")
    t.eq(len(dr.conflicts([rs, rs2])), 1, "device_resource : recouvrement")
    t.eq(he.diagnose("/dev/video0")["exists"], false, "hardware_errors : nœud absent")
    t.raises(() => he.require_access("/dev/video0"), "HardwareUnavailable", "hardware_errors : require_access")
    os.mkdir_all(root + "/dev")
    io.write_file(root + "/dev/ttyUSB0", "")
    t.eq(he.diagnose("/dev/ttyUSB0")["exists"], true, "hardware_errors : nœud présent")
    hs.set_root("")
    t.eq(he.classify("open: Permission denied"), "HardwareAccessDenied", "hardware_errors : EACCES")
    t.eq(he.classify("Device or resource busy"), "HardwareBusy", "hardware_errors : EBUSY")
    t.eq(he.classify("No such device"), "HardwareUnavailable", "hardware_errors : ENODEV")
    t.check(he.is_hardware_error("BusError") and not he.is_hardware_error("IOError"), "hardware_errors : types")

    os.rmdir(tmp, true)
    t.summary("test_hardware2")

func symlink(target, path):
    r := process.run("ln", ["-s", target, path])
    if r.code != 0:
        raise("IOError", "ln -s " + target + " : " + r.stderr)

func string_rest(full, prefix):
    return full[len(prefix):len(full)]
