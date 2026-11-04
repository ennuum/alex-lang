# ALEX STANDARD LIBRARY — ui.dragdrop V0.5
# Win32 accepts file drops on every ALEX window.

func is_drop(event):
    return event != null and event["type"] == "drop"

func files(event):
    if not is_drop(event):
        return []
    data := event["data"]
    if data == null or data == "":
        return []
    return [data]

func path(event):
    if not is_drop(event):
        return null
    return event["data"]
