# ALEX UI V1.0 — Layout node / composition
use ui.widgets.widget as widget

func create(kind="container", x=0.0, y=0.0, width=0.0, height=0.0):
    # widget.create fournit déjà tous les champs de layout.
    return widget.create(kind,x,y,width,height)

func add(parent, child):
    return widget.add(parent,child)

func padding(node, left=0.0, top=0.0, right=0.0, bottom=0.0):
    node["layout"]["padding"] = {"left":left,"top":top,"right":right,"bottom":bottom}
    return node

func padding_all(node, value):
    return padding(node,value,value,value,value)

func margin(node, left=0.0, top=0.0, right=0.0, bottom=0.0):
    node["layout"]["margin"] = {"left":left,"top":top,"right":right,"bottom":bottom}
    return node

func margin_all(node, value):
    return margin(node,value,value,value,value)

func gap(node, value):
    node["layout"]["gap"] = value
    return node

func align(node, horizontal="start", vertical="start"):
    node["layout"]["alignment"] = {"horizontal":horizontal,"vertical":vertical}
    return node

func flex(node, value):
    node["flex"] = value
    return node

func basis(node, value):
    node["flex_basis"] = value
    return node

func direction(node, value):
    node["layout"]["direction"] = value
    return node

func row(node):
    return direction(node,"row")
func column(node):
    return direction(node,"column")
func stack(node):
    return direction(node,"stack")

func wrap(node, value=true):
    node["layout"]["wrap"] = value
    return node
