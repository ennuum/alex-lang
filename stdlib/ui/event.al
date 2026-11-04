from core use len
# ALEX STANDARD LIBRARY — ui.event
use _native_ui as _native

func poll(window_handle):
    return _native.window_poll(window_handle)

func type(event):
    if event == null:
        return "none"
    return event["type"]

func window(event):
    if event == null:
        return null
    return event["window"]

func widget(event):
    if event == null:
        return null
    return event["widget"]

func is(event, event_type):
    return type(event) == event_type
func is_close(event):
    return is(event, "close")
func is_button(event):
    return is(event, "button")
func is_change(event):
    return is(event, "change")
func is_check(event):
    return is(event, "check")
func is_radio(event):
    return is(event, "radio")
func is_key_down(event):
    return is(event, "key_down")

func loop(window_handle, on_event):
    if on_event == null:
        raise("TypeError", "ui.event.loop() : callback requis")
    _native.window_show(window_handle)
    running := true
    while running:
        event := _native.window_poll(window_handle)
        if event != null:
            if is_close(event):
                running = false
            on_event(event)
    _native.window_close(window_handle)
    return null

func data(event):
    if event == null:
        return null
    return event["data"]
func is_shortcut(event):
    return is(event, "shortcut")
func is_drop(event):
    return is(event, "drop")
func is_command(event):
    return is(event, "command")
