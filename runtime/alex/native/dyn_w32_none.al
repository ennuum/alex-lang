# alex: native
# Hors Windows : pas de backend Win32 (dyn_w32.al n'est compilé que pour les exécutables Windows).
func __w32_open() -> int:
    return 0
func __w32_create(b: int, id: int, title: str, w: int, h: int, resizable: bool):
    return
func __w32_destroy(b: int, id: int):
    return
func __w32_show(b: int, id: int, on: bool):
    return
func __w32_title(b: int, id: int, t: str):
    return
func __w32_resize(b: int, id: int, w: int, h: int):
    return
func __w32_move(b: int, id: int, x: int, y: int):
    return
func __w32_cursor(b: int, id: int, name: str):
    return
func __w32_present(b: int, id: int, f: int):
    return
func __w32_pump(c: int, b: int, block: bool):
    return
func __w32_wait(b: int, ms: int):
    return
func __w32_position(b: int, id: int, out: int) -> bool:
    return false
func __w32_screen(b: int, out: int):
    return
func __w32_dpi(b: int) -> int:
    return 96
func __w32_set_state(b: int, id: int, state: str) -> bool:
    return false
func __w32_hints(b: int, id: int, resizable: bool, decorated: bool, topmost: bool, opacity: float, minW: int, minH: int, maxW: int, maxH: int, cw: int, ch: int):
    return
func __w32_focus(b: int, id: int):
    return
func __w32_clip_set(b: int, text: str) -> bool:
    return false
func __w32_clip_get(b: int) -> int:
    return 0
