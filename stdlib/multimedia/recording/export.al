# ALEX STANDARD LIBRARY — multimedia.recording.export
#
# Export vers des fichiers :
#   transcode(entrée, sortie, fmt)    tout fichier lisible (natif ou ffmpeg) -> WAV, FLAC, Ogg FLAC (intégrés) ou
#                                     autre format (ffmpeg), par blocs, avec conversion de fréquence / canaux et
#                                     étiquettes ;
#   export_audio(échantillons, fmt, sortie)
#   export_timeline(timeline, sortie, audio_sortie=null)   montage -> vidéo (ffmpeg) + son, ou son seul ;
#   export_frames(images, dossier, motif)                  suite d'images PNG / BMP / PPM.
# Progression par rappel, annulation, limites.
#
#   use multimedia.recording.export as ex
#   ex.transcode("concert.flac", "concert.opus", af.AudioFormat(48000, 2, "f32le"))
#   ex.export_timeline(t, "montage.mp4")
#
# Erreurs : celles des démultiplexeurs / encodeurs, CancelledError.

from core use len, to_int
use os as _os
use string as _s
use audio.audio_format as _af
use multimedia.core.errors as merr
use multimedia.core.cancellation as mc
use multimedia.container.demux as dmx
use multimedia.recording.recorder as rec
use multimedia.audio.resampler as rsm
use multimedia.image.encode as enc
use multimedia.backends.codecs.ffmpeg as ff

func transcode(src, dst, fmt=null, progress=null, token=null, block=8192):
    d := dmx.open(src)
    try:
        sfmt := d.format
        out := fmt if fmt != null else _af.AudioFormat(sfmt.rate, sfmt.channels, "s16le")
        w := rec.open_destination(dst, out, d.tags)
        r := rsm.Resampler(sfmt.rate, out.rate, out.channels) if sfmt.rate != out.rate else null
        total := d.frames
        done := 0
        while true:
            mc.check(token)
            f := d.read_frame(block)
            if f.eos:
                break
            x := f.data
            if sfmt.channels != out.channels:
                x = _af.convert_channels(x, sfmt.channels, out.channels)
            if r != null:
                x = r.process(x)
            w.write_samples(x)
            done += f.frames()
            if progress != null and total > 0:
                progress(1.0 * done / total)
        if r != null:
            tail := r.flush()
            want := (done * r.up + r.down - 1) // r.down
            have := r.out_total - len(tail) // out.channels
            keep := (want - have) * out.channels
            if keep > 0:
                w.write_samples([tail[k] for k in 0..(keep if keep < len(tail) else len(tail))])
        w.close()
        return {"frames_in": done, "path": dst}
    finally:
        d.close()

func export_audio(samples, fmt, dst, tags=null):
    w := rec.open_destination(dst, _af.named(fmt), tags)
    w.write_samples(samples)
    return w.close()

func export_frames(images, folder, pattern="image_%05d.png"):
    if not _os.isdir(folder):
        _os.mkdir(folder)
    paths := []
    i := 0
    for img in images:
        n := str(i)
        while len(n) < 5:
            n = "0" + n
        p := folder + "/" + _s.replace(pattern, "%05d", n)
        enc.save(img, p)
        paths = paths + [p]
        i += 1
    return paths

# Montage -> fichier. Vidéo (extension .mp4, .webm, .mkv...) : images rendues à la cadence de la ligne de temps
# et son mixé (ffmpeg). Fichier audio (.wav, .flac, .opus...) : le son seul.
func export_timeline(timeline, dst, token=null, progress=null):
    low := _s.lower(dst)
    audio_only := _s.ends_with(low, ".wav") or _s.ends_with(low, ".flac") or _s.ends_with(low, ".opus") or _s.ends_with(low, ".mp3") or _s.ends_with(low, ".ogg") or _s.ends_with(low, ".m4a")
    fmt := _af.AudioFormat(timeline.rate, timeline.channels, "f32le")
    son := timeline.render_audio()
    if audio_only:
        return {"path": dst, "frames": export_audio(son, fmt, dst)}
    tmp := _os.tmp_dir() + "/alex_montage_" + str(_os.pid()) + ".wav"
    export_audio(son, _af.AudioFormat(timeline.rate, timeline.channels, "s16le"), tmp)
    try:
        v := ff.VideoEncoder(dst, timeline.width, timeline.height, timeline.fps, null, tmp)
        times := timeline.frame_times()
        k := 0
        for t in times:
            mc.check(token)
            v.write(timeline.render_frame(t))
            k += 1
            if progress != null:
                progress(1.0 * k / len(times))
        v.close()
        return {"path": dst, "frames": k}
    finally:
        if _os.exists(tmp):
            _os.remove(tmp)
