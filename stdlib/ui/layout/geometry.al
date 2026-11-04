# ALEX UI V1.0 — Geometry primitives

func size(width=0.0, height=0.0):
    return {"width":width, "height":height}

func offset(x=0.0, y=0.0):
    return {"x":x, "y":y}

func rect(x=0.0, y=0.0, width=0.0, height=0.0):
    return {"x":x, "y":y, "width":width, "height":height}

func edges(left=0.0, top=0.0, right=0.0, bottom=0.0):
    return {"left":left, "top":top, "right":right, "bottom":bottom}

func edge_uniform(value=0.0):
    return edges(value,value,value,value)

func rect_inset(r, e):
    return rect(
        r["x"] + e["left"],
        r["y"] + e["top"],
        r["width"] - e["left"] - e["right"],
        r["height"] - e["top"] - e["bottom"]
    )

func clamp(value, minimum, maximum):
    if value < minimum:
        return minimum
    if value > maximum:
        return maximum
    return value
