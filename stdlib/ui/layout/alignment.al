# ALEX UI V1.0 — Alignment helpers

func alignment(horizontal="start", vertical="start"):
    return {"horizontal":horizontal, "vertical":vertical}

func start():
    return alignment("start","start")
func center():
    return alignment("center","center")
func end():
    return alignment("end","end")
func stretch():
    return alignment("stretch","stretch")

func offset_x(a, available, child):
    if a == "center":
        return (available-child) * 0.5
    if a == "end":
        return available-child
    return 0.0

func offset_y(a, available, child):
    if a == "center":
        return (available-child) * 0.5
    if a == "end":
        return available-child
    return 0.0
