# ALEX STANDARD LIBRARY — ui.icon
# V0.7 — Professional icon subsystem
#
# The compiler does not know about icons.  Icon handles are opaque native
# resources owned by the UI runtime.
#
# Supported resource families depend on the active backend.  The Windows
# backend supplied with this package supports PNG/JPEG/BMP/ICO and built-in
# Fluent/Segoe icon glyphs.

from core use type
use _native_ui as _ui_native

const VERSION := "0.7.0"
const DEFAULT_SIZE := 20
const MIN_SIZE := 8
const MAX_SIZE := 256

func version():
    return VERSION

func _require_handle(name, handle):
    if type(handle) != "int":
        raise("TypeError", "ui.icon." + name + "() : handle doit être un int")

func _normalize_size(size):
    if size == null:
        return DEFAULT_SIZE
    if type(size) != "int":
        raise("TypeError", "ui.icon : size doit être un int")
    if size < MIN_SIZE or size > MAX_SIZE:
        raise("ArgumentError", "ui.icon : size doit être compris entre 8 et 256")
    return size

# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

func load(path, size=DEFAULT_SIZE):
    if type(path) != "str":
        raise("TypeError", "ui.icon.load() : path doit être une str")
    size = _normalize_size(size)
    handle := _ui_native.icon_load(path, size)
    _require_handle("load", handle)
    return {"handle": handle, "source": path, "kind": "file", "size": size}

func from_file(path, size=DEFAULT_SIZE):
    return load(path, size)

func from_builtin(name, size=DEFAULT_SIZE):
    if type(name) != "str":
        raise("TypeError", "ui.icon.from_builtin() : name doit être une str")
    size = _normalize_size(size)
    handle := _ui_native.icon_builtin(name, size)
    _require_handle("from_builtin", handle)
    return {"handle": handle, "source": name, "kind": "builtin", "size": size}

func _handle(icon):
    if type(icon) == "int":
        return icon
    if icon == null or type(icon) != "dict":
        raise("TypeError", "ui.icon : icône invalide")
    handle := icon["handle"]
    _require_handle("handle", handle)
    return handle

# ---------------------------------------------------------------------------
# Widget / window integration
# ---------------------------------------------------------------------------

func set(widget_handle, icon, size=null, position="left"):
    _require_handle("set", widget_handle)
    handle := _handle(icon)
    if size == null:
        size = DEFAULT_SIZE
    size = _normalize_size(size)
    if type(position) != "str":
        raise("TypeError", "ui.icon.set() : position doit être une str")
    if position != "left" and position != "right" and position != "top" and position != "bottom" and position != "center":
        raise("ArgumentError", "ui.icon.set() : position invalide")
    return _ui_native.widget_set_icon(widget_handle, handle, size, position)

func remove(widget_handle):
    _require_handle("remove", widget_handle)
    return _ui_native.widget_remove_icon(widget_handle)

func resize(icon, size):
    handle := _handle(icon)
    size = _normalize_size(size)
    new_handle := _ui_native.icon_resize(handle, size)
    _require_handle("resize", new_handle)
    return {"handle": new_handle, "source": icon["source"], "kind": icon["kind"], "size": size}

func destroy(icon):
    handle := _handle(icon)
    return _ui_native.icon_destroy(handle)

func set_window(window_handle, icon, size=32):
    _require_handle("set_window", window_handle)
    handle := _handle(icon)
    size = _normalize_size(size)
    return _ui_native.window_set_icon(window_handle, handle, size)

# ---------------------------------------------------------------------------
# Named professional icons
# ---------------------------------------------------------------------------

func home(size=DEFAULT_SIZE):
    return from_builtin("home", size)

func settings(size=DEFAULT_SIZE):
    return from_builtin("settings", size)

func user(size=DEFAULT_SIZE):
    return from_builtin("user", size)

func search(size=DEFAULT_SIZE):
    return from_builtin("search", size)

func menu(size=DEFAULT_SIZE):
    return from_builtin("menu", size)

func close(size=DEFAULT_SIZE):
    return from_builtin("close", size)

func check(size=DEFAULT_SIZE):
    return from_builtin("check", size)

func add(size=DEFAULT_SIZE):
    return from_builtin("add", size)

func remove_icon(size=DEFAULT_SIZE):
    return from_builtin("remove", size)

func edit(size=DEFAULT_SIZE):
    return from_builtin("edit", size)

func save(size=DEFAULT_SIZE):
    return from_builtin("save", size)

func delete(size=DEFAULT_SIZE):
    return from_builtin("delete", size)

func folder(size=DEFAULT_SIZE):
    return from_builtin("folder", size)

func file(size=DEFAULT_SIZE):
    return from_builtin("file", size)

func download(size=DEFAULT_SIZE):
    return from_builtin("download", size)

func upload(size=DEFAULT_SIZE):
    return from_builtin("upload", size)

func refresh(size=DEFAULT_SIZE):
    return from_builtin("refresh", size)

func info(size=DEFAULT_SIZE):
    return from_builtin("info", size)

func warning(size=DEFAULT_SIZE):
    return from_builtin("warning", size)

func error(size=DEFAULT_SIZE):
    return from_builtin("error", size)

func lock(size=DEFAULT_SIZE):
    return from_builtin("lock", size)

func unlock(size=DEFAULT_SIZE):
    return from_builtin("unlock", size)

func eye(size=DEFAULT_SIZE):
    return from_builtin("eye", size)

func star(size=DEFAULT_SIZE):
    return from_builtin("star", size)

func heart(size=DEFAULT_SIZE):
    return from_builtin("heart", size)

func calendar(size=DEFAULT_SIZE):
    return from_builtin("calendar", size)

func clock(size=DEFAULT_SIZE):
    return from_builtin("clock", size)

func mail(size=DEFAULT_SIZE):
    return from_builtin("mail", size)

func phone(size=DEFAULT_SIZE):
    return from_builtin("phone", size)

func link(size=DEFAULT_SIZE):
    return from_builtin("link", size)

func play(size=DEFAULT_SIZE):
    return from_builtin("play", size)

func pause(size=DEFAULT_SIZE):
    return from_builtin("pause", size)

func stop(size=DEFAULT_SIZE):
    return from_builtin("stop", size)

func arrow_left(size=DEFAULT_SIZE):
    return from_builtin("arrow_left", size)

func arrow_right(size=DEFAULT_SIZE):
    return from_builtin("arrow_right", size)

func chevron_down(size=DEFAULT_SIZE):
    return from_builtin("chevron_down", size)

func more(size=DEFAULT_SIZE):
    return from_builtin("more", size)
