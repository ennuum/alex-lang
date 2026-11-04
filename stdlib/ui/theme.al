# ALEX STANDARD LIBRARY — ui.theme V0.4

use ui.color as _color
use ui.font as _font
use ui.style as _style

func modern_dark():
    base := _style.style(_color.SLATE_900, _color.SLATE_100, _font.normal("Segoe UI", 10), 8, 0, 8)
    return {
        "name": "modern-dark",
        "window": base,
        "surface": _style.style(_color.SLATE_800, _color.SLATE_100, _font.normal("Segoe UI", 10), 8, 0, 8),
        "button": _style.style(_color.VIOLET_600, _color.WHITE, _font.semibold("Segoe UI", 10), 8, 4, 6),
        "input": _style.style(_color.SLATE_950, _color.SLATE_100, _font.normal("Segoe UI", 10), 6, 4, 5),
        "muted": _style.style(_color.SLATE_800, _color.SLATE_400, _font.normal("Segoe UI", 9), 4, 0, 4),
        "accent": _color.VIOLET_400,
        "success": _color.GREEN_500,
        "danger": _color.RED_500
    }

func modern_light():
    base := _style.style(_color.WHITE, _color.SLATE_900, _font.normal("Segoe UI", 10), 8, 0, 8)
    return {
        "name": "modern-light",
        "window": base,
        "surface": _style.style(_color.SLATE_100, _color.SLATE_900, _font.normal("Segoe UI", 10), 8, 0, 8),
        "button": _style.style(_color.VIOLET_600, _color.WHITE, _font.semibold("Segoe UI", 10), 8, 4, 6),
        "input": _style.style(_color.WHITE, _color.SLATE_900, _font.normal("Segoe UI", 10), 6, 4, 5),
        "muted": _style.style(_color.SLATE_100, _color.SLATE_600, _font.normal("Segoe UI", 9), 4, 0, 4),
        "accent": _color.VIOLET_600,
        "success": _color.GREEN_500,
        "danger": _color.RED_500
    }

func high_contrast():
    return {
        "name": "high-contrast",
        "window": _style.style(_color.BLACK, _color.WHITE, _font.bold("Segoe UI", 11), 8, 0, 0),
        "surface": _style.style(_color.BLACK, _color.WHITE, _font.bold("Segoe UI", 11), 8, 0, 0),
        "button": _style.style(_color.WHITE, _color.BLACK, _font.bold("Segoe UI", 11), 8, 4, 0),
        "input": _style.style(_color.BLACK, _color.WHITE, _font.bold("Segoe UI", 11), 6, 4, 0),
        "muted": _style.style(_color.BLACK, _color.WHITE, _font.bold("Segoe UI", 10), 4, 0, 0),
        "accent": _color.WHITE,
        "success": _color.WHITE,
        "danger": _color.WHITE
    }

func theme(name="modern-dark", options=null):
    if name == null:
        name = "modern-dark"
    if name == "modern-dark":
        return modern_dark()
    if name == "modern-light":
        return modern_light()
    if name == "high-contrast":
        return high_contrast()
    raise("ArgumentError", "ui.theme() : thème inconnu: " + name)

