# ALEX STANDARD LIBRARY — ui.canvas
# V0.8 — Canvas & 2D Rendering Engine
from core use type
use _native_ui as _ui_native

const VERSION := "0.8.0"

func version():
    return VERSION

func _handle(canvas, name):
    if type(canvas) != "dict" or type(canvas["handle"]) != "int":
        raise("TypeError", "ui.canvas." + name + "() : canvas invalide")
    return canvas["handle"]

func create(window):
    if type(window) != "int":
        if type(window) == "dict":
            window = window["handle"]
        else:
            raise("TypeError", "ui.canvas.create() : fenêtre invalide")
    h := _ui_native.canvas_create(window)
    if type(h) != "int" or h == 0:
        raise("RuntimeError", "ui.canvas.create() : impossible de créer le canvas")
    return {"handle":h,"window":window}

func destroy(canvas):
    return _ui_native.canvas_destroy(_handle(canvas,"destroy"))

func resize(canvas):
    return _ui_native.canvas_resize(_handle(canvas,"resize"))

func save_png(canvas, path):
    # Backends portables (x11, headless) : enregistre le contenu du canvas en PNG.
    return _ui_native.canvas_save_png(_handle(canvas,"save_png"), path)

func begin(canvas):
    return _ui_native.canvas_begin(_handle(canvas,"begin"))

func end(canvas):
    return _ui_native.canvas_end(_handle(canvas,"end"))

func clear(canvas, color):
    _handle(canvas,"clear")
    return _ui_native.canvas_clear(canvas["handle"], color["r"], color["g"], color["b"], color["a"])


func _width(paint):
    if paint["kind"] == "stroke":
        return paint["width"]
    return 0.0

func fill_rect(canvas,x,y,w,h,paint):
    return _ui_native.canvas_fill_rect(_handle(canvas,"fill_rect"),x,y,w,h,paint["kind"],paint["color"]["r"],paint["color"]["g"],paint["color"]["b"],paint["color"]["a"],paint["opacity"])

func stroke_rect(canvas,x,y,w,h,paint):
    return _ui_native.canvas_stroke_rect(_handle(canvas,"stroke_rect"),x,y,w,h,paint["color"]["r"],paint["color"]["g"],paint["color"]["b"],paint["color"]["a"],paint["opacity"],paint["width"])

func round_rect(canvas,x,y,w,h,radius,paint):
    return _ui_native.canvas_round_rect(_handle(canvas,"round_rect"),x,y,w,h,radius,paint["kind"],paint["color"]["r"],paint["color"]["g"],paint["color"]["b"],paint["color"]["a"],paint["opacity"],_width(paint))

func circle(canvas,cx,cy,radius,paint):
    return _ui_native.canvas_circle(_handle(canvas,"circle"),cx,cy,radius,paint["kind"],paint["color"]["r"],paint["color"]["g"],paint["color"]["b"],paint["color"]["a"],paint["opacity"],_width(paint))

func ellipse(canvas,cx,cy,rx,ry,paint):
    return _ui_native.canvas_ellipse(_handle(canvas,"ellipse"),cx,cy,rx,ry,paint["kind"],paint["color"]["r"],paint["color"]["g"],paint["color"]["b"],paint["color"]["a"],paint["opacity"],_width(paint))

func line(canvas,x1,y1,x2,y2,paint):
    return _ui_native.canvas_line(_handle(canvas,"line"),x1,y1,x2,y2,paint["color"]["r"],paint["color"]["g"],paint["color"]["b"],paint["color"]["a"],paint["opacity"],paint["width"] if paint["kind"] == "stroke" else 1.0)

func path(canvas,path,paint):
    return _ui_native.canvas_path(_handle(canvas,"path"),path["handle"],paint["kind"],paint["color"]["r"],paint["color"]["g"],paint["color"]["b"],paint["color"]["a"],paint["opacity"],_width(paint))

func text(canvas,value,x,y,paint,font="Segoe UI",size=16.0):
    return _ui_native.canvas_text(_handle(canvas,"text"),value,x,y,paint["color"]["r"],paint["color"]["g"],paint["color"]["b"],paint["color"]["a"],paint["opacity"],font,size)

func image(canvas,image,x,y,w=null,h=null,opacity=1.0):
    if w == null:
        w = 0.0
    if h == null:
        h = 0.0
    return _ui_native.canvas_image(_handle(canvas,"image"),image["handle"],x,y,w,h,opacity)

# Partie (sx, sy, sw, sh) d'une image dessinée dans (x, y, w, h) : feuilles de sprites, atlas, tuiles. Les
# découpes sont gardées en cache dans l'image (clé = zone) : la première coûte une copie, les suivantes rien.
func image_region(canvas,image,sx,sy,sw,sh,x,y,w=null,h=null,opacity=1.0):
    if not ("_crops" in image):
        image["_crops"] = {}
    key := str(sx) + "," + str(sy) + "," + str(sw) + "," + str(sh)
    crops := image["_crops"]
    if not (key in crops):
        crops[key] = _ui_native.image_crop(image["handle"],sx,sy,sw,sh)
    ww := w if w != null else sw
    hh := h if h != null else sh
    return _ui_native.canvas_image(_handle(canvas,"image_region"),crops[key],x,y,ww,hh,opacity)

func clip_rect(canvas,x,y,w,h):
    return _ui_native.canvas_clip_rect(_handle(canvas,"clip_rect"),x,y,w,h)

func reset_clip(canvas):
    return _ui_native.canvas_reset_clip(_handle(canvas,"reset_clip"))

func transform(canvas,matrix):
    return _ui_native.canvas_set_transform(_handle(canvas,"transform"),matrix["m11"],matrix["m12"],matrix["m21"],matrix["m22"],matrix["dx"],matrix["dy"])

func reset_transform(canvas):
    return _ui_native.canvas_reset_transform(_handle(canvas,"reset_transform"))

func shadow_round_rect(canvas,x,y,w,h,radius,shadow,paint):
    return _ui_native.canvas_shadow_round_rect(_handle(canvas,"shadow_round_rect"),x,y,w,h,radius,shadow["color"]["r"],shadow["color"]["g"],shadow["color"]["b"],shadow["opacity"],shadow["blur"],shadow["offset_x"],shadow["offset_y"],paint["color"]["r"],paint["color"]["g"],paint["color"]["b"],paint["color"]["a"],paint["opacity"])

func linear_gradient_rect(canvas,x,y,w,h,gradient):
    return _ui_native.canvas_linear_gradient_rect(_handle(canvas,"linear_gradient_rect"),x,y,w,h,gradient["x1"],gradient["y1"],gradient["x2"],gradient["y2"],gradient["start"]["r"],gradient["start"]["g"],gradient["start"]["b"],gradient["start"]["a"],gradient["end"]["r"],gradient["end"]["g"],gradient["end"]["b"],gradient["end"]["a"],gradient["opacity"])

# Opacité globale (0..1) appliquée à tous les dessins suivants (ghost de glisser-déposer, fondus).
func set_opacity(canvas,value):
    return _ui_native.canvas_set_opacity(_handle(canvas,"set_opacity"),value)
