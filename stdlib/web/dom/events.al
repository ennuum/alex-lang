# ALEX STANDARD LIBRARY — web.dom.events
#
# Aides aux événements : abonnement avec désabonnement renvoyé, délégation par sélecteur, émission
# d'événements applicatifs, et SIMULATION d'interactions utilisateur réalistes pour les tests (clic avec
# pointerdown / mousedown / focus / mouseup / click, survol, saisie caractère par caractère avec keydown /
# beforeinput / input / keyup, touches spéciales — Entrée envoie le formulaire, Tab déplace le focus —,
# sélection d'option, changement de valeur).
#
#   use web.dom.events as evs
#   stop := evs.on(bouton, "click", (e) => print("clic"))
#   evs.delegate(liste, "click", "li[data-id]", (e, li) => print(li.dataset.get("id")))
#   evs.fire(element, "panier:ajout", {"id": 42})     # CustomEvent bouillonnant ; renvoie false si annulé
#   evs.click(bouton)                                 # suite complète d'événements + action par défaut
#   evs.type_text(champ, "Bonjour")                   # champ.value() == "Bonjour", événements input émis
#   evs.press_key(champ, "Enter")                     # envoi implicite du formulaire
#   evs.select_option(liste_deroulante, "fr")
#   stop()                                            # désabonnement
#
# Erreurs : DomError (cible non élément pour une simulation).

from core use len, type
from collections use append
use string as _s
use web.dom.dom_errors as _err
use web.dom.event as _ev
use web.dom.custom_event as _ce
use web.dom.keyboard_event as _ke
use web.dom.mouse_event as _me
use web.dom.pointer_event as _pe
use web.dom.input_event as _ie
use web.dom.event_target as _et

# Abonne fn ; renvoie une fonction sans argument qui désabonne.
func on(target, event_type, fn, options=null):
    target.add_event_listener(event_type, fn, options)
    capture := options == true or (type(options) == "dict" and "capture" in options and options["capture"])
    return () => target.remove_event_listener(event_type, fn, capture)

func once(target, event_type, fn):
    return on(target, event_type, fn, {"once": true})

# Délégation : fn(événement, élément correspondant) pour les événements nés sous root et dont la cible a un
# ancêtre (ou elle-même) correspondant au sélecteur.
func delegate(root, event_type, selector, fn):
    handler := (e) => _delegate_call(root, selector, fn, e)
    root.add_event_listener(event_type, handler)
    return () => root.remove_event_listener(event_type, handler)

func _delegate_call(root, selector, fn, e):
    t := e.target
    if t == null or t.node_type != 1:
        t = t.parent_element() if t != null and t.node_type == 3 else null
    if t == null:
        return
    m := t.closest(selector)
    if m != null and root.contains(m):
        fn(e, m)

# Émet un CustomEvent ; renvoie false si un écouteur l'a annulé.
func fire(target, event_type, detail=null, bubbles=true, cancelable=true):
    return target.dispatch_event(_ce.CustomEvent(event_type, {"detail": detail, "bubbles": bubbles, "cancelable": cancelable}))

# Promesse simple : enregistre et renvoie la liste des événements reçus d'un type (pour les tests).
func record(target, event_type):
    out := []
    target.add_event_listener(event_type, (e) => append(out, e))
    return out

func _require_element(el, fn):
    if el == null or el.node_type != 1:
        _err.dom_error(fn, "élément attendu")

func _trusted(target, e):
    return _et.dispatch(target, e, true)

func _center(el):
    r := el.get_bounding_client_rect()
    return (r.x + r.width / 2, r.y + r.height / 2)

# Clic complet : pointerdown, mousedown, focus, pointerup, mouseup, click (+ action par défaut).
func click(el, button=0):
    _require_element(el, "events.click")
    if el.disabled():
        return false
    c := _center(el)
    opts := {"client_x": c[0], "client_y": c[1], "button": button, "pointer_type": "mouse"}
    _trusted(el, _pe.PointerEvent("pointerdown", _with(opts, {"buttons": _me.buttons_mask(button)})))
    down_ok := _trusted(el, _me.MouseEvent("mousedown", _with(opts, {"buttons": _me.buttons_mask(button), "detail": 1})))
    if down_ok:
        f := el
        while f != null and f.node_type == 1 and not f.is_focusable():
            f = f.parent_element()
        if f != null and f.node_type == 1:
            f.focus()
        elif el.owner_document != null:
            el.owner_document.set_focus(null)
    el.set_state("active", true)
    _trusted(el, _pe.PointerEvent("pointerup", opts))
    _trusted(el, _me.MouseEvent("mouseup", _with(opts, {"detail": 1})))
    el.set_state("active", false)
    if button != 0:
        if button == 2:
            _trusted(el, _me.MouseEvent("contextmenu", opts))
        else:
            _trusted(el, _me.MouseEvent("auxclick", opts))
        return true
    return el.click()

func double_click(el):
    click(el)
    click(el)
    c := _center(el)
    return _trusted(el, _me.MouseEvent("dblclick", {"client_x": c[0], "client_y": c[1], "detail": 2}))

func _with(base, extra):
    out := {}
    for k in base:
        out[k] = base[k]
    for k in extra:
        out[k] = extra[k]
    return out

# Survol (on=true) ou sortie : états :hover et événements pointerover / mouseover / mouseenter (ou inverse).
func hover(el, on=true):
    _require_element(el, "events.hover")
    c := _center(el)
    opts := {"client_x": c[0], "client_y": c[1]}
    if on:
        el.set_state("hover", true)
        _trusted(el, _pe.PointerEvent("pointerover", opts))
        _trusted(el, _pe.PointerEvent("pointerenter", opts))
        _trusted(el, _me.MouseEvent("mouseover", opts))
        _trusted(el, _me.MouseEvent("mouseenter", opts))
    else:
        el.set_state("hover", false)
        _trusted(el, _pe.PointerEvent("pointerout", opts))
        _trusted(el, _pe.PointerEvent("pointerleave", opts))
        _trusted(el, _me.MouseEvent("mouseout", opts))
        _trusted(el, _me.MouseEvent("mouseleave", opts))

func _is_text_field(el):
    if el.local_name == "textarea":
        return true
    if el.local_name == "input":
        return not (el.input_type() in ["checkbox", "radio", "submit", "button", "reset", "image", "file", "hidden", "range", "color"])
    return el.has_attribute("contenteditable")

func _edit(el, input_type, data):
    if el.has_attribute("readonly") or el.disabled():
        return false
    if not _trusted(el, _ie.InputEvent("beforeinput", {"data": data, "input_type": input_type, "cancelable": true})):
        return false
    if el.has_attribute("contenteditable"):
        cur := el.text_content()
        r := _ie.apply(cur, len(cur), len(cur), input_type, data)
        el.set_text_content(r[0])
    else:
        v := el.value()
        r := _ie.apply(v, len(v), len(v), input_type, data)
        el.set_value(r[0])
    _trusted(el, _ie.InputEvent("input", {"data": data, "input_type": input_type}))
    return true

# Saisie caractère par caractère (focus, puis keydown / keypress / beforeinput / input / keyup) ; change au blur.
func type_text(el, text, blur_after=false):
    _require_element(el, "events.type_text")
    if not _is_text_field(el):
        _err.dom_error("events.type_text", "« " + el.local_name + " » n'est pas un champ de saisie")
    el.focus()
    start := el.value() if not el.has_attribute("contenteditable") else el.text_content()
    for ch in str(text):
        c := str(ch)
        if c == "\n":
            press_key(el, "Enter")
            continue
        if not _trusted(el, _ke.key_event("keydown", c)):
            continue
        _trusted(el, _ke.key_event("keypress", c))
        _edit(el, _ie.INSERT_TEXT, c)
        _trusted(el, _ke.key_event("keyup", c))
    end := el.value() if not el.has_attribute("contenteditable") else el.text_content()
    if blur_after:
        el.blur()
        if end != start:
            _trusted(el, _ev.Event("change", true, false))
    return end

# Efface puis saisit (comme un remplissage de formulaire), avec change final.
func fill(el, text):
    _require_element(el, "events.fill")
    el.focus()
    old := el.value()
    el.set_value("")
    _trusted(el, _ie.InputEvent("input", {"input_type": _ie.DELETE_BY_CUT}))
    type_text(el, text)
    if el.value() != old:
        _trusted(el, _ev.Event("change", true, false))
    return el.value()

# Touche spéciale ou caractère, avec modificateurs (« Ctrl+A » accepté) et actions par défaut principales.
func press_key(el, key, modifiers=null):
    _require_element(el, "events.press_key")
    e := _ke.from_shortcut(key) if _s.contains(key, "+") and len(key) > 1 else _ke.key_event("keydown", key, modifiers)
    if not _trusted(el, e):
        _trusted(el, _ke.KeyboardEvent("keyup", {"key": e.key, "ctrl_key": e.ctrl_key, "shift_key": e.shift_key, "alt_key": e.alt_key, "meta_key": e.meta_key}))
        return false
    k := e.key
    doc := el.owner_document
    if k == "Enter":
        if el.local_name == "input" and _is_text_field(el):
            f := el.form()
            if f != null:
                sub := null
                for c in f.elements():
                    if (c.local_name == "button" and (c.get_attribute("type") == null or c.get_attribute("type") == "submit")) or (c.local_name == "input" and c.input_type() == "submit"):
                        sub = c
                        break
                if sub != null:
                    sub.click()
                else:
                    f.request_submit()
        elif el.local_name == "textarea" or el.has_attribute("contenteditable"):
            _edit(el, _ie.INSERT_LINE_BREAK, null)
        elif el.local_name in ["button", "a", "summary"]:
            el.click()
    elif k == " " and el.local_name in ["button", "summary"] or (k == " " and el.local_name == "input" and el.input_type() in ["checkbox", "radio", "button", "submit"]):
        el.click()
    elif k == "Tab" and doc != null:
        doc.focus_next(e.shift_key)
    elif k == "Backspace" and _is_text_field(el):
        _edit(el, _ie.DELETE_BACKWARD, null)
    elif k == "Delete" and _is_text_field(el):
        _edit(el, _ie.DELETE_FORWARD, null)
    elif len(k) == 1 and _is_text_field(el) and not e.ctrl_key and not e.meta_key:
        _edit(el, _ie.INSERT_TEXT, k)
    elif k == "Escape" and doc != null:
        d := el.closest("dialog[open]")
        if d != null:
            d.remove_attribute("open")
            _trusted(d, _ev.Event("close"))
    _trusted(el, _ke.KeyboardEvent("keyup", {"key": k, "ctrl_key": e.ctrl_key, "shift_key": e.shift_key, "alt_key": e.alt_key, "meta_key": e.meta_key}))
    return true

# Choisit l'option de valeur donnée d'un <select> (input puis change).
func select_option(select, value):
    _require_element(select, "events.select_option")
    found := false
    for o in select.options():
        if o.value() == str(value):
            o.set_selected(true)
            found = true
    if not found:
        _err.dom_error("events.select_option", "aucune option de valeur « " + str(value) + " »")
    _trusted(select, _ev.Event("input", true, false, true))
    _trusted(select, _ev.Event("change", true, false))

# Fixe une valeur (comme un script ou une saisie collée) puis émet input et change.
func change_value(el, value):
    el.set_value(value)
    _trusted(el, _ie.InputEvent("input", {"input_type": _ie.INSERT_REPLACEMENT, "data": str(value)}))
    _trusted(el, _ev.Event("change", true, false))

func submit(form):
    return form.request_submit()
