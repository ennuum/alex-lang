# ALEX STANDARD LIBRARY — web.html.forms
#
# Formulaires accessibles : <form>, champs typés, étiquettes reliées (for / id), aide et message d'erreur reliés
# par aria-describedby, cases à cocher et boutons radio groupés dans un <fieldset>, listes déroulantes avec
# groupes, jeton CSRF caché ; et l'inverse : lire les valeurs qu'un navigateur enverrait (form_data), ou
# remplir un formulaire avec des valeurs (fill).
#
#   use web.html.forms as fm
#   f := fm.form("/inscription", "post", [
#       fm.csrf_field(jeton),
#       fm.field("Courriel", fm.email("email", null, true), "Nous ne le partagerons pas."),
#       fm.field("Mot de passe", fm.password("mdp", true, 12)),
#       fm.select_field("Pays", "pays", [("fr", "France"), ("be", "Belgique")], "fr"),
#       fm.checkbox("cgu", "oui", false, "J'accepte les conditions"),
#       fm.submit("Créer mon compte"),
#   ])
#   fm.form_data(f)                    # [("csrf_token", …), ("pays", "fr")]  (cases non cochées omises)
#   fm.fill(f, {"email": "zoe@exemple.org", "cgu": true})
#   fm.set_error(f, "email", "Adresse déjà utilisée")   # aria-invalid + message relié
#
# Erreurs : HtmlError (type de champ inconnu, méthode invalide, champ introuvable).

from core use len, type
from collections use append, keys
use string as _s
use web.html.html_errors as _err
use web.html.element as _el
use web.html.element_factory as _f
use web.html.attribute_value as _av

const INPUT_TYPES := ["button", "checkbox", "color", "date", "datetime-local", "email", "file", "hidden", "image", "month", "number", "password", "radio", "range", "reset", "search", "submit", "tel", "text", "time", "url", "week"]
const METHODS := ["get", "post", "dialog"]
const ENCTYPES := ["application/x-www-form-urlencoded", "multipart/form-data", "text/plain"]

_counter := [0]

# Identifiant unique pour relier étiquettes et champs (« champ-email-3 »).
func auto_id(prefix="champ"):
    _counter[0] = _counter[0] + 1
    return prefix + "-" + str(_counter[0])

func _slug(name):
    out := []
    for c in _s.lower(str(name)):
        if (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '-' or c == '_':
            append(out, str(c))
        else:
            append(out, "-")
    return _s.join("", out)

# <form> ; method : get, post (dialog) ; enctype « multipart/form-data » si un champ fichier est présent (auto).
func form(action, method="post", children=null, attributes=null, enctype=null, novalidate=false):
    m := _s.lower(method)
    if not (m in METHODS):
        _err.html_error("forms.form", "méthode de formulaire invalide « " + str(method) + " » (get, post, dialog)")
    if enctype != null and not (enctype in ENCTYPES):
        _err.html_error("forms.form", "enctype invalide « " + str(enctype) + " »")
    f := _el.Element("form", _f.merge_attributes({"action": action, "method": m, "enctype": enctype, "novalidate": novalidate}, attributes), children)
    if enctype == null and f.find("input[type=file]") != null:
        f.set("enctype", "multipart/form-data")
    return f

# <input> générique.
func input_element(kind, name=null, value=null, attributes=null):
    if not (kind in INPUT_TYPES):
        _err.html_error("forms.input", "type de champ inconnu « " + str(kind) + " »")
    return _el.Element("input", _f.merge_attributes({"type": kind, "name": name, "value": value}, attributes))

func text(name, value=null, required=false, attributes=null, placeholder=null, maxlength=null):
    return input_element("text", name, value, _f.merge_attributes({"required": required, "placeholder": placeholder, "maxlength": maxlength}, attributes))

func email(name, value=null, required=false, attributes=null):
    return input_element("email", name, value, _f.merge_attributes({"required": required, "autocomplete": "email"}, attributes))

# Mot de passe ; new_password : autocomplete « new-password » (sinon « current-password »).
func password(name, new_password=false, minlength=null, required=true, attributes=null):
    return input_element("password", name, null, _f.merge_attributes({"required": required, "minlength": minlength, "autocomplete": "new-password" if new_password else "current-password"}, attributes))

func number(name, value=null, min=null, max=null, step=null, attributes=null):
    return input_element("number", name, value, _f.merge_attributes({"min": min, "max": max, "step": step}, attributes))

func range(name, value=null, min=0, max=100, step=1, attributes=null):
    return input_element("range", name, value, _f.merge_attributes({"min": min, "max": max, "step": step}, attributes))

func date(name, value=null, min=null, max=null, attributes=null):
    return input_element("date", name, value, _f.merge_attributes({"min": min, "max": max}, attributes))

func url(name, value=null, attributes=null):
    return input_element("url", name, value, attributes)

func tel(name, value=null, attributes=null):
    return input_element("tel", name, value, _f.merge_attributes({"autocomplete": "tel"}, attributes))

func search(name="q", value=null, attributes=null, placeholder=null):
    return input_element("search", name, value, _f.merge_attributes({"placeholder": placeholder}, attributes))

func color(name, value="#000000", attributes=null):
    return input_element("color", name, value, attributes)

func hidden(name, value):
    return input_element("hidden", name, str(value))

# Champ fichier ; accept : liste de types / extensions (« image/* », « .pdf »).
func file(name, accept=null, multiple=false, attributes=null):
    return input_element("file", name, null, _f.merge_attributes({"accept": accept, "multiple": multiple}, attributes))

# Jeton anti-CSRF caché.
func csrf_field(token, name="csrf_token"):
    return hidden(name, token)

func textarea(name, value="", rows=4, cols=null, attributes=null, required=false):
    return _el.Element("textarea", _f.merge_attributes({"name": name, "rows": rows, "cols": cols, "required": required}, attributes), [str(value)] if value != "" and value != null else null)

# Liste déroulante. options : liste de valeurs, de paires (valeur, libellé), ou dict groupe -> options (optgroup).
# selected : valeur (ou liste de valeurs si multiple).
func select(name, options, selected=null, multiple=false, attributes=null, placeholder=null):
    s := _el.Element("select", _f.merge_attributes({"name": name, "multiple": multiple}, attributes))
    if placeholder != null:
        s.append(_el.Element("option", {"value": "", "disabled": true, "selected": selected == null}, placeholder))
    if type(options) == "dict":
        for g in keys(options):
            grp := _el.Element("optgroup", {"label": g})
            _add_options(grp, options[g], selected)
            s.append(grp)
    else:
        _add_options(s, options, selected)
    return s

func _is_selected(value, selected):
    if selected == null:
        return false
    if type(selected) == "list" or type(selected) == "tuple":
        for x in selected:
            if str(x) == value:
                return true
        return false
    return str(selected) == value

func _add_options(parent, options, selected):
    for o in options:
        v := o
        label := o
        if type(o) == "tuple" or type(o) == "list":
            v = o[0]
            label = o[1]
        sv := str(v)
        parent.append(_el.Element("option", {"value": sv, "selected": _is_selected(sv, selected)}, str(label)))

func datalist(id, values):
    d := _el.Element("datalist", {"id": id})
    for v in values:
        d.append(_el.Element("option", {"value": str(v)}))
    return d

func label(content, for_id=null, attributes=null):
    return _el.Element("label", _f.merge_attributes({"for": for_id}, attributes), content)

func button(content, kind="button", attributes=null, name=null, value=null):
    if not (kind in ["button", "submit", "reset"]):
        _err.html_error("forms.button", "type de bouton invalide « " + str(kind) + " »")
    return _el.Element("button", _f.merge_attributes({"type": kind, "name": name, "value": value}, attributes), content)

func submit(content="Envoyer", attributes=null, name=null, value=null):
    return button(content, "submit", attributes, name, value)

func reset(content="Réinitialiser", attributes=null):
    return button(content, "reset", attributes)

func output(name, for_ids=null, content=null):
    return _el.Element("output", {"name": name, "for": for_ids}, content)

# Groupe de champs titré (<fieldset><legend>).
func fieldset(legend, children=null, attributes=null):
    return _el.Element("fieldset", attributes, [_el.Element("legend", null, legend)] + _el.to_nodes(children))

# Champ complet : <div class="field"><label for>…</label>champ<p id="…-aide">aide</p><p id="…-erreur">…</p></div>.
# L'id du champ est créé s'il manque ; aide et erreur sont reliées par aria-describedby.
func field(label_text, control, help=null, error=null, attributes=null):
    id := control.get("id")
    if id == null:
        id = auto_id("champ-" + _slug(control.get("name", control.tag)))
        control.set("id", id)
    wrapper := _el.Element("div", _f.merge_attributes({"class": "field"}, attributes))
    wrapper.append(label(label_text, id))
    wrapper.append(control)
    described := []
    if help != null:
        hid := id + "-aide"
        wrapper.append(_el.Element("p", {"id": hid, "class": "field-help"}, help))
        append(described, hid)
    if error != null:
        eid := id + "-erreur"
        wrapper.append(_el.Element("p", {"id": eid, "class": "field-error", "role": "alert"}, error))
        append(described, eid)
        control.set("aria-invalid", "true")
    if len(described) > 0:
        control.set("aria-describedby", _s.join(" ", described))
    return wrapper

func select_field(label_text, name, options, selected=null, help=null):
    return field(label_text, select(name, options, selected), help)

# Case à cocher avec son étiquette (l'étiquette entoure le champ : pas besoin d'id).
func checkbox(name, value="on", checked=false, label_text=null, attributes=null):
    box := input_element("checkbox", name, value, _f.merge_attributes({"checked": checked}, attributes))
    if label_text == null:
        return box
    return _el.Element("label", null, [box, " ", label_text])

# Groupe de boutons radio dans un <fieldset> ; options : valeurs ou paires (valeur, libellé).
func radio_group(legend, name, options, selected=null, required=false):
    fs := _el.Element("fieldset", null, [_el.Element("legend", null, legend)])
    for o in options:
        v := o
        lab := o
        if type(o) == "tuple" or type(o) == "list":
            v = o[0]
            lab = o[1]
        r := input_element("radio", name, str(v), {"checked": selected != null and str(selected) == str(v), "required": required})
        fs.append(_el.Element("label", null, [r, " ", str(lab)]))
    return fs

# Groupe de cases à cocher (même nom, plusieurs valeurs).
func checkbox_group(legend, name, options, checked=null):
    fs := _el.Element("fieldset", null, [_el.Element("legend", null, legend)])
    for o in options:
        v := o
        lab := o
        if type(o) == "tuple" or type(o) == "list":
            v = o[0]
            lab = o[1]
        fs.append(checkbox(name, str(v), _is_selected(str(v), checked), str(lab)))
    return fs

# ---------------------------------------------------------------- lecture et remplissage

# Paires (nom, valeur) qu'un navigateur enverrait à la soumission (algorithme « constructing the entry list »,
# simplifié) : champs désactivés, sans nom, cases non cochées, boutons et fichiers exclus.
func form_data(form_element):
    out := []
    for e in form_element.find_all("input, select, textarea"):
        name := e.get("name")
        if name == null or name == "" or e.has("disabled") or e.closest("fieldset[disabled]") != null:
            continue
        if e.tag == "input":
            t := _s.lower(e.get("type", "text"))
            if t in ["submit", "reset", "button", "image", "file"]:
                continue
            if t == "checkbox" or t == "radio":
                if e.has("checked"):
                    append(out, (name, e.get("value", "on")))
                continue
            append(out, (name, e.get("value", "")))
        elif e.tag == "select":
            opts := e.find_all("option")
            chosen := []
            for o in opts:
                if o.has("selected") and not o.has("disabled"):
                    append(chosen, o)
            if len(chosen) == 0 and not e.has("multiple") and len(opts) > 0:
                append(chosen, opts[0])
            for o in chosen:
                append(out, (name, o.get("value") if o.get("value") != null else _s.trim(o.text_content())))
        else:
            append(out, (name, e.text_content()))
    return out

# Remplit les champs avec values (dict nom -> valeur ; liste pour plusieurs cases / options) ; renvoie le nombre de
# champs modifiés. Les mots de passe ne sont jamais réécrits.
func fill(form_element, values):
    n := 0
    for e in form_element.find_all("input, select, textarea"):
        name := e.get("name")
        if name == null or not (name in values):
            continue
        v := values[name]
        if e.tag == "input":
            t := _s.lower(e.get("type", "text"))
            if t == "password" or t == "file":
                continue
            if t == "checkbox" or t == "radio":
                on := false
                if v == true:
                    on = true
                elif v != false and v != null:
                    on = _is_selected(e.get("value", "on"), v)
                e.set("checked", on)
            else:
                e.set("value", str(v) if v != null else null)
            n += 1
        elif e.tag == "select":
            for o in e.find_all("option"):
                ov := o.get("value") if o.get("value") != null else _s.trim(o.text_content())
                o.set("selected", _is_selected(ov, v))
            n += 1
        else:
            e.set_text(str(v) if v != null else "")
            n += 1
    return n

# Marque un champ en erreur : aria-invalid, message relié par aria-describedby (créé après le champ).
func set_error(form_element, name, message):
    e := form_element.find("[name=\"" + name + "\"]")
    if e == null:
        _err.html_error("forms.set_error", "champ « " + name + " » introuvable")
    id := e.get("id")
    if id == null:
        id = auto_id("champ-" + _slug(name))
        e.set("id", id)
    eid := id + "-erreur"
    old := form_element.find("#" + eid)
    if old != null:
        old.set_text(message)
    else:
        msg := _el.Element("p", {"id": eid, "class": "field-error", "role": "alert"}, message)
        e.parent.insert_after(msg, e)
        d := _av.split_tokens(e.get("aria-describedby", ""))
        if not (eid in d):
            append(d, eid)
        e.set("aria-describedby", _s.join(" ", d))
    e.set("aria-invalid", "true")
    return e

# Retire les erreurs posées par set_error / field.
func clear_errors(form_element):
    for p in form_element.find_all("p.field-error"):
        p.remove()
    for e in form_element.find_all("[aria-invalid]"):
        e.remove_attribute("aria-invalid")
        d := []
        for t in _av.split_tokens(e.get("aria-describedby", "")):
            if not _s.ends_with(t, "-erreur"):
                append(d, t)
        e.set("aria-describedby", _s.join(" ", d) if len(d) > 0 else null)
    return form_element
