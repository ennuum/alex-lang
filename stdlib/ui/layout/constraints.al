# ALEX UI V1.0 — Box constraints
use ui.layout.geometry as geometry

func constraints(min_width=0.0, max_width=null, min_height=0.0, max_height=null):
    return {
        "min_width":min_width, "max_width":max_width,
        "min_height":min_height, "max_height":max_height
    }

func loose(width=0.0, height=0.0):
    return constraints(0.0,width,0.0,height)

func tight(width, height):
    return constraints(width,width,height,height)

func unbounded(min_width=0.0, min_height=0.0):
    return constraints(min_width,null,min_height,null)

func constrain_width(c, value):
    result := geometry.clamp(value,c["min_width"], value if c["max_width"] == null else c["max_width"])
    return result

func constrain_height(c, value):
    result := geometry.clamp(value,c["min_height"], value if c["max_height"] == null else c["max_height"])
    return result

func constrain_size(c, width, height):
    return geometry.size(constrain_width(c,width),constrain_height(c,height))
