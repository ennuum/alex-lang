# ALEX UI V1.0 — Widget composition helpers
use ui.widgets.widget as widget
use ui.layout as layout

func root(kind="root",width=800.0,height=600.0):
    r := layout.container(kind,0.0,0.0,width,height)
    r["layout"]["direction"] = "column"
    return r

func mount(parent,child):
    return layout.add(parent,child)
func row(parent):
    return layout.row(parent)
func column(parent):
    return layout.column(parent)
func padding(parent,value):
    return layout.padding_all(parent,value)
func gap(parent,value):
    return layout.gap(parent,value)
func flex(child,value):
    return layout.flex(child,value)
func align(parent,h="start",v="start"):
    return layout.align(parent,h,v)
func layout_tree(root_node,width,height):
    return layout.perform(root_node,width,height)
