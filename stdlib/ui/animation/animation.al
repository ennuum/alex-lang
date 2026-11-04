# ALEX STANDARD LIBRARY — ui.animation V0.6
# High-level animation engine. Pure ALEX; uses monotonic time and sleep from os.

from core use type, to_int, clamp
use os as _os
use ui.widget as _widget
use ui.animation.easing as _easing

const DEFAULT_FPS := 60

func _positive_number(value, name):
    if type(value) != "int" and type(value) != "float":
        raise("TypeError", name + " doit être un nombre")
    if value <= 0:
        raise("ArgumentError", name + " doit être > 0")

func _positive_int(value, name):
    if type(value) != "int":
        raise("TypeError", name + " doit être un int")
    if value <= 0:
        raise("ArgumentError", name + " doit être > 0")

func _non_negative_int(value, name):
    if type(value) != "int":
        raise("TypeError", name + " doit être un int")
    if value < 0:
        raise("ArgumentError", name + " doit être >= 0")

func _round_int(value):
    return to_int(value + 0.5)

func _lerp(a, b, t):
    return a + (b - a) * t

func _frame_count(duration, fps):
    count := to_int(duration * fps)
    if count < 1:
        count = 1
    return count

func _sleep_frame(frame_seconds):
    if frame_seconds > 0:
        _os.sleep(frame_seconds)

func create(widget, property, from_value, to_value, duration=0.3, easing="ease_out", fps=DEFAULT_FPS, repeat=0, yoyo=false):
    if type(widget) != "int":
        raise("TypeError", "ui.animation.create() : widget doit être un handle int")
    if type(property) != "str":
        raise("TypeError", "ui.animation.create() : property doit être une str")
    _positive_number(duration, "duration")
    if fps == null:
        fps = DEFAULT_FPS
    if repeat == null:
        repeat = 0
    if yoyo == null:
        yoyo = false
    _positive_int(fps, "fps")
    _non_negative_int(repeat, "repeat")
    if type(yoyo) != "bool":
        raise("TypeError", "yoyo doit être un bool")
    if property != "x" and property != "y" and property != "width" and property != "height":
        raise("ArgumentError", "ui.animation.create() : propriété non supportée")
    return {
        "widget": widget,
        "property": property,
        "from": from_value,
        "to": to_value,
        "duration": duration,
        "easing": easing,
        "fps": fps,
        "repeat": repeat,
        "yoyo": yoyo,
        "state": "idle"
    }

func _apply(widget, property, value, current_x, current_y, current_width, current_height):
    if property == "x":
        _widget.set_position(widget, _round_int(value), current_y)
        return null
    if property == "y":
        _widget.set_position(widget, current_x, _round_int(value))
        return null
    if property == "width":
        _widget.set_size(widget, _round_int(value), current_height)
        return null
    if property == "height":
        _widget.set_size(widget, current_width, _round_int(value))
        return null
    return null

func play(animation):
    if type(animation) != "dict":
        raise("TypeError", "ui.animation.play() : animation doit être un dict")

    widget := animation["widget"]
    property := animation["property"]
    start_value := animation["from"]
    end_value := animation["to"]
    duration := animation["duration"]
    fps := animation["fps"]
    repeat := animation["repeat"]
    yoyo := animation["yoyo"]
    easing := _easing.resolve(animation["easing"])

    if type(start_value) != "int" and type(start_value) != "float":
        raise("TypeError", "ui.animation.play() : from doit être un nombre")
    if type(end_value) != "int" and type(end_value) != "float":
        raise("TypeError", "ui.animation.play() : to doit être un nombre")

    # Capture a stable companion dimension so position/size updates don't erase it.
    current_x := 0
    current_y := 0
    current_width := 100
    current_height := 30
    animation["state"] = "running"

    cycles := repeat + 1
    cycle := 0
    reverse := false
    while cycle < cycles:
        frame := 0
        frames := _frame_count(duration, fps)
        while frame <= frames:
            t := frame / frames
            if reverse:
                t = 1 - t
            eased := easing(t)
            value := _lerp(start_value, end_value, eased)
            _apply(widget, property, value, current_x, current_y, current_width, current_height)
            frame = frame + 1
            if frame <= frames:
                _sleep_frame(1 / fps)
        cycle = cycle + 1
        if yoyo:
            reverse = not reverse
        else:
            reverse = false
    animation["state"] = "finished"
    return animation

func move(widget, from_x, from_y, to_x, to_y, duration=0.3, easing="ease_out", fps=DEFAULT_FPS):
    _positive_number(duration, "duration")
    if fps == null:
        fps = DEFAULT_FPS
    _positive_int(fps, "fps")
    frames := _frame_count(duration, fps)
    ease := _easing.resolve(easing)
    frame := 0
    while frame <= frames:
        t := ease(frame / frames)
        x := _round_int(_lerp(from_x, to_x, t))
        y := _round_int(_lerp(from_y, to_y, t))
        _widget.set_position(widget, x, y)
        frame = frame + 1
        if frame <= frames:
            _sleep_frame(1 / fps)
    return widget

func resize(widget, from_width, from_height, to_width, to_height, duration=0.3, easing="ease_out", fps=DEFAULT_FPS):
    _positive_number(duration, "duration")
    if fps == null:
        fps = DEFAULT_FPS
    frames := _frame_count(duration, fps)
    ease := _easing.resolve(easing)
    frame := 0
    while frame <= frames:
        t := ease(frame / frames)
        width := _round_int(_lerp(from_width, to_width, t))
        height := _round_int(_lerp(from_height, to_height, t))
        if width < 1:
            width = 1
        if height < 1:
            height = 1
        _widget.set_size(widget, width, height)
        frame = frame + 1
        if frame <= frames:
            _sleep_frame(1 / fps)
    return widget

func pulse(widget, min_width, min_height, max_width, max_height, duration=0.18, cycles=2, easing="ease_in_out", fps=DEFAULT_FPS):
    _non_negative_int(cycles, "cycles")
    i := 0
    while i < cycles:
        resize(widget, min_width, min_height, max_width, max_height, duration, easing, fps)
        resize(widget, max_width, max_height, min_width, min_height, duration, easing, fps)
        i = i + 1
    return widget

func state(animation):
    if type(animation) != "dict":
        raise("TypeError", "ui.animation.state() : animation doit être un dict")
    return animation["state"]

func reset(animation):
    if type(animation) != "dict":
        raise("TypeError", "ui.animation.reset() : animation doit être un dict")
    animation["state"] = "idle"
    return animation
