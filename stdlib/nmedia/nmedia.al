# alex: native
# alex: intrinsics
# NOVA (édition bureau) — décodage audio et vidéo par les décodeurs du système, version Linux : même interface que
# nmedia_windows.al. Pas encore de décodeur du système branché (supported() rend false) : seuls le WAV, le
# Motion-JPEG et le GIF animé sont lus, par NOVA lui-même.
from core use len

func supported() -> bool:
    return false

class Video:
    ok: bool := false
    error: str := ""
    width: int := 0
    height: int := 0
    duration: int := 0
    frame: int := 0

func open_video(src: str, max_width: int) -> Video:
    v := Video()
    v.error = "décodeurs du système non pris en charge sous Linux"
    return v

func next_frame(v: Video) -> int:
    return -1

func seek(v: Video, ms: int):
    pass

func write_frame(fd: int, v: Video, pts: int) -> bool:
    return false

func close(v: Video):
    pass

func audio_to_wav(src: str, dest: str) -> int:
    return -1

class Picture:
    width: int := 0
    height: int := 0
    addr: int := 0
    size: int := 0

func decode_image(data: str) -> Picture:
    return Picture()

# Copie n octets de la chaîne s (à partir de off) à l'adresse dst (image en mémoire).
func copy_bytes(dst: int, s: str, off: int, n: int):
    p := __str_addr(s)
    if off < 0 or off + n > __load64(p):
        return
    __copy(dst, p + 8 + off, n)
