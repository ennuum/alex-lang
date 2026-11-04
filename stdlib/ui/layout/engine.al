# ALEX UI V1.0 — Layout engine
# Compatible avec l'analyseur ALEX actuel : aucune reference de fonction
# vers une declaration placee plus bas dans le fichier.
from core use len
use ui.layout.geometry as geometry
use ui.layout.constraints as constraints
use ui.layout.alignment as alignment

func _margin(n):
    return n["layout"]["margin"]

func _padding(n):
    return n["layout"]["padding"]

func _outer_width(n):
    m := _margin(n)
    return n["width"] + m["left"] + m["right"]

func _outer_height(n):
    m := _margin(n)
    return n["height"] + m["top"] + m["bottom"]

func _position(n, x, y, width, height):
    m := _margin(n)
    n["x"] = x + m["left"]
    n["y"] = y + m["top"]
    n["width"] = width
    n["height"] = height
    return n

func measure(n, c):
    if n["kind"] == "scroll_view" and len(n["children"]) > 0:
        # Zone défilante : sa taille est CELLE QU'ON LUI A DONNÉE (intrinsic_*), pas celle de son contenu ;
        # les enfants sont mesurés sans limite verticale (ils débordent et défilent).
        p := _padding(n)
        inner_cw := c["max_width"]
        if inner_cw != null:
            inner_cw = inner_cw - p["left"] - p["right"]
        child_c := constraints.constraints(0.0, inner_cw, 0.0, null)
        for child in n["children"]:
            measure(child, child_c)
        s := constraints.constrain_size(c, n["intrinsic_width"], n["intrinsic_height"])
        n["measured_width"] = s["width"]
        n["measured_height"] = s["height"]
        return s
    if len(n["children"]) == 0:
        width := n["intrinsic_width"]
        height := n["intrinsic_height"]
        if width <= 0.0:
            width = n["width"]
        if height <= 0.0:
            height = n["height"]
        if n["max_width"] != null and width > n["max_width"]:
            width = n["max_width"]
        if n["max_height"] != null and height > n["max_height"]:
            height = n["max_height"]
        if width < n["min_width"]:
            width = n["min_width"]
        if height < n["min_height"]:
            height = n["min_height"]
        s := constraints.constrain_size(c, width, height)
        n["measured_width"] = s["width"]
        n["measured_height"] = s["height"]
        return s

    p := _padding(n)
    inner_cw := c["max_width"]
    inner_ch := c["max_height"]
    if inner_cw != null:
        inner_cw = inner_cw - p["left"] - p["right"]
    if inner_ch != null:
        inner_ch = inner_ch - p["top"] - p["bottom"]

    child_c := constraints.constraints(0.0, inner_cw, 0.0, inner_ch)
    direction := n["layout"]["direction"]
    gap := n["layout"]["gap"]
    total_w := 0.0
    total_h := 0.0
    max_w := 0.0
    max_h := 0.0
    count := 0

    for child in n["children"]:
        s := measure(child, child_c)
        if direction == "row":
            total_w = total_w + s["width"]
            if s["height"] > max_h:
                max_h = s["height"]
        elif direction == "stack":
            if s["width"] > max_w:
                max_w = s["width"]
            if s["height"] > max_h:
                max_h = s["height"]
        else:
            total_h = total_h + s["height"]
            if s["width"] > max_w:
                max_w = s["width"]
        count = count + 1

    if count > 1:
        if direction == "row":
            total_w = total_w + gap * (count - 1)
        elif direction != "stack":
            total_h = total_h + gap * (count - 1)

    width := max_w + p["left"] + p["right"]
    height := total_h + p["top"] + p["bottom"]
    if direction == "row":
        width = total_w + p["left"] + p["right"]
        height = max_h + p["top"] + p["bottom"]
    elif direction == "stack":
        width = max_w + p["left"] + p["right"]
        height = max_h + p["top"] + p["bottom"]

    result := constraints.constrain_size(c, width, height)
    n["measured_width"] = result["width"]
    n["measured_height"] = result["height"]
    return result

func layout(n, x=0.0, y=0.0, width=null, height=null):
    if width == null:
        width = n["measured_width"]
    if height == null:
        height = n["measured_height"]

    _position(n, x, y, width, height)
    if len(n["children"]) == 0:
        return n

    p := _padding(n)
    inner_x := n["x"] + p["left"]
    inner_y := n["y"] + p["top"]
    inner_w := width - p["left"] - p["right"]
    inner_h := height - p["top"] - p["bottom"]
    gap := n["layout"]["gap"]
    direction := n["layout"]["direction"]
    a := n["layout"]["alignment"]

    if direction == "row" and n["layout"]["wrap"]:
        cursor_x := inner_x
        cursor_y := inner_y
        line_h := 0.0
        for child in n["children"]:
            cw := child["measured_width"]
            ch := child["measured_height"]
            if cursor_x > inner_x and cursor_x + cw > inner_x + inner_w:
                cursor_x = inner_x
                cursor_y = cursor_y + line_h + gap
                line_h = 0.0
            _position(child, cursor_x, cursor_y, cw, ch)
            layout(child, child["x"], child["y"], child["width"], child["height"])
            cursor_x = cursor_x + cw + gap
            if ch > line_h:
                line_h = ch
        return n

    if direction == "row":
        fixed := 0.0
        flex_total := 0.0
        count := 0
        for child in n["children"]:
            if child["flex"] > 0.0:
                flex_total = flex_total + child["flex"]
            else:
                basis := child["flex_basis"]
                if basis == null:
                    basis = child["measured_width"]
                fixed = fixed + basis
            count = count + 1
        available := inner_w - fixed - gap * (count - 1)
        if available < 0.0:
            available = 0.0
        cursor := inner_x
        for child in n["children"]:
            basis := child["flex_basis"]
            if basis == null:
                basis = child["measured_width"]
            if child["flex"] > 0.0 and flex_total > 0.0:
                basis = available * child["flex"] / flex_total
            child_h := child["measured_height"]
            if a["vertical"] == "stretch":
                child_h = inner_h
            yy := inner_y + alignment.offset_y(a["vertical"], inner_h, child_h)
            _position(child, cursor, yy, basis, child_h)
            layout(child, child["x"], child["y"], child["width"], child["height"])
            cursor = cursor + basis + gap
        return n

    if direction == "stack":
        for child in n["children"]:
            child_w := child["measured_width"]
            child_h := child["measured_height"]
            if a["horizontal"] == "stretch":
                child_w = inner_w
            if a["vertical"] == "stretch":
                child_h = inner_h
            xx := inner_x + alignment.offset_x(a["horizontal"], inner_w, child_w)
            yy := inner_y + alignment.offset_y(a["vertical"], inner_h, child_h)
            _position(child, xx, yy, child_w, child_h)
            layout(child, child["x"], child["y"], child["width"], child["height"])
        return n

    fixed := 0.0
    flex_total := 0.0
    count := 0
    for child in n["children"]:
        if child["flex"] > 0.0:
            flex_total = flex_total + child["flex"]
        else:
            basis := child["flex_basis"]
            if basis == null:
                basis = child["measured_height"]
            fixed = fixed + basis
        count = count + 1

    available := inner_h - fixed - gap * (count - 1)
    if available < 0.0:
        available = 0.0
    cursor := inner_y
    for child in n["children"]:
        basis := child["flex_basis"]
        if basis == null:
            basis = child["measured_height"]
        if child["flex"] > 0.0 and flex_total > 0.0:
            basis = available * child["flex"] / flex_total
        child_w := child["measured_width"]
        if a["horizontal"] == "stretch":
            child_w = inner_w
        xx := inner_x + alignment.offset_x(a["horizontal"], inner_w, child_w)
        _position(child, xx, cursor, child_w, basis)
        layout(child, child["x"], child["y"], child["width"], child["height"])
        cursor = cursor + basis + gap
    return n

func perform(root, width, height):
    c := constraints.tight(width, height)
    measure(root, c)
    return layout(root, 0.0, 0.0, width, height)
