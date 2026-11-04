# ALEX STANDARD LIBRARY — ui.view.widgets (interne)
#
# Registre des composants : genre (« button », « table »...) → comportement (classe de ui.view.w*).

from collections use contains_key
use ui.view.wbase as _b
use ui.view.wbasic as _wb
use ui.view.wedit as _we
use ui.view.wdata as _wd
use ui.view.wstruct as _ws
use ui.view.wcode as _wc
use ui.view.wextra as _wx

_KINDS := {}

func _register():
    _KINDS["column"] = _b.Flex(false)
    _KINDS["row"] = _b.Flex(true)
    _KINDS["text"] = _wb.Text()
    _KINDS["button"] = _wb.Button()
    _KINDS["separator"] = _wb.Separator()
    _KINDS["spacer"] = _wb.Spacer()
    _KINDS["checkbox"] = _wb.Checkbox()
    _KINDS["radio"] = _wb.Radio()
    _KINDS["progress"] = _wb.Progress()
    _KINDS["panel"] = _wb.Panel()
    _KINDS["scroll"] = _wb.Scroll()
    _KINDS["input"] = _we.Input()
    _KINDS["textarea"] = _we.TextArea()
    _KINDS["select"] = _we.Select()
    _KINDS["popup_list"] = _we.PopupList()
    _KINDS["slider"] = _we.Slider()
    _KINDS["spinbox"] = _we.Spinbox()
    _KINDS["list_view"] = _wd.ListView()
    _KINDS["table"] = _wd.Table()
    _KINDS["tree"] = _wd.Tree()
    _KINDS["tabs"] = _ws.Tabs()
    _KINDS["split"] = _ws.Split()
    _KINDS["dialog"] = _ws.Dialog()
    _KINDS["menu_bar"] = _ws.MenuBar()
    _KINDS["menu_popup"] = _ws.MenuPopup()
    _KINDS["code_editor"] = _wc.CodeEditor()
    _KINDS["image"] = _wx.Image()
    _KINDS["canvas"] = _wx.Canvas()
    _KINDS["design_surface"] = _wx.DesignSurface()

_register()

func get(kind):
    if not contains_key(_KINDS, kind):
        raise("ArgumentError", "ui.view : composant inconnu '" + str(kind) + "'")
    return _KINDS[kind]
