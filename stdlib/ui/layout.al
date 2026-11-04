# ALEX UI V1.0 — Layout public facade
use ui.layout.geometry as geometry
use ui.layout.constraints as constraints
use ui.layout.alignment as alignment
use ui.layout.node as node
use ui.layout.engine as engine

const VERSION := "1.0.0"

func version():
    return VERSION
func size(w=0.0,h=0.0):
    return geometry.size(w,h)
func rect(x=0.0,y=0.0,w=0.0,h=0.0):
    return geometry.rect(x,y,w,h)
func edges(l=0.0,t=0.0,r=0.0,b=0.0):
    return geometry.edges(l,t,r,b)
func constraints_new(min_w=0.0,max_w=null,min_h=0.0,max_h=null):
    return constraints.constraints(min_w,max_w,min_h,max_h)
func tight(w,h):
    return constraints.tight(w,h)
func loose(w,h):
    return constraints.loose(w,h)
func alignment_new(h="start",v="start"):
    return alignment.alignment(h,v)
func start():
    return alignment.start()
func center():
    return alignment.center()
func end():
    return alignment.end()
func stretch():
    return alignment.stretch()
func container(kind="container",x=0.0,y=0.0,w=0.0,h=0.0):
    return node.create(kind,x,y,w,h)
func add(parent,child):
    return node.add(parent,child)
func padding(parent,l=0.0,t=0.0,r=0.0,b=0.0):
    return node.padding(parent,l,t,r,b)
func padding_all(parent,value):
    return node.padding_all(parent,value)
func margin(parent,l=0.0,t=0.0,r=0.0,b=0.0):
    return node.margin(parent,l,t,r,b)
func margin_all(parent,value):
    return node.margin_all(parent,value)
func gap(parent,value):
    return node.gap(parent,value)
func align(parent,h="start",v="start"):
    return node.align(parent,h,v)
func flex(child,value):
    return node.flex(child,value)
func basis(child,value):
    return node.basis(child,value)
func row(parent):
    return node.row(parent)
func column(parent):
    return node.column(parent)
func stack(parent):
    return node.stack(parent)
func wrap(parent,value=true):
    return node.wrap(parent,value)
func measure(root,c):
    return engine.measure(root,c)
func layout(root,x=0.0,y=0.0,w=null,h=null):
    return engine.layout(root,x,y,w,h)
func perform(root,w,h):
    return engine.perform(root,w,h)
