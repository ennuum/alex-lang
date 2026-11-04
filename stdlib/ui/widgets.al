# ALEX UI V0.9 — Widgets public facade
use ui.widgets.modern as modern
use ui.widgets.widget as widget
use ui.widgets.theme as theme
use ui.layout as layout
use ui.canvas as canvas

const VERSION := "1.0.0"
func version():
    return VERSION
func button(text,x=0.0,y=0.0,width=120.0,height=40.0):
    return modern.button_new(text,x,y,width,height)
func label(text,x=0.0,y=0.0,width=200.0,height=28.0):
    return modern.label_new(text,x,y,width,height)
func card(x=0.0,y=0.0,width=280.0,height=160.0):
    return modern.card_new(x,y,width,height)
func checkbox(text,checked=false,x=0.0,y=0.0,width=180.0,height=32.0):
    return modern.checkbox_new(text,checked,x,y,width,height)
func text_field(value="",placeholder="",x=0.0,y=0.0,width=260.0,height=40.0):
    return modern.text_field_new(value,placeholder,x,y,width,height)
func progress(value=0.0,x=0.0,y=0.0,width=240.0,height=8.0):
    return modern.progress_new(value,x,y,width,height)
func modern_theme():
    return theme.modern()
func draw(root,c,t=null):
    # Frame complète : begin -> fond -> arbre de widgets -> end.
    # (draw_tree ne dessine que l'arbre, pour qui gère begin/end lui-même.)
    if t == null:
        t = theme.modern()
    canvas.begin(c)
    canvas.clear(c,{"r":18,"g":20,"b":25,"a":255})
    modern.draw_tree(root,c,t)
    canvas.end(c)
    return null
func dispatch(root,event):
    return modern.dispatch(root,event)

func layout_tree(root,width,height):
    return layout.perform(root,width,height)
