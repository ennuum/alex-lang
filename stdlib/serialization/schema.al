# ALEX STANDARD LIBRARY — serialization.schema
#
# Schémas de données : décrire la forme attendue (types, champs obligatoires, bornes, motifs, valeurs
# permises, listes, objets imbriqués), VALIDER des données (liste d'erreurs avec leur chemin), les CONVERTIR
# depuis du texte (CSV, formulaires, variables d'environnement) et compléter les valeurs par défaut.
#
#   use serialization.schema as sch
#   utilisateur := sch.object({
#       "nom": sch.string(1, 50),
#       "age": sch.integer(0, 150),
#       "email": sch.string().pattern(".+@.+\\..+"),
#       "role": sch.enum_of(["admin", "membre"]).default("membre"),
#       "tags": sch.list_of(sch.string()).optional(),
#   }, ["nom", "age"])
#   print(utilisateur.validate({"nom": "", "age": 200}))
#   # ["nom : longueur 0 < 1", "age : 200 > 150"]
#   d := utilisateur.coerce({"nom": "Ada", "age": "36"})     # {"nom": "Ada", "age": 36, "role": "membre"}
#   utilisateur.check(d)                                      # ValidationError si invalide
#   print(utilisateur.is_valid(d), utilisateur.to_dict())     # description (documentation, échange)
#
# Types : any, string, integer, number, boolean, null_type, enum_of, list_of, dict_of, object, one_of, custom.
# Modificateurs : optional() (null accepté), default(v), pattern(re), describe(texte).
# Erreurs : ValidationError (check), SchemaError (schéma mal construit).

from core use len, type, to_int, to_float
from collections use append
use string as _s
use regex as _re

const VALIDATION := "ValidationError"
const SCHEMA := "SchemaError"

class Schema:
    func init(kind):
        self.kind = kind
        self.nullable = false
        self.has_default = false
        self.default_value = null
        self.description = ""
        self.min = null
        self.max = null
        self.regex = null
        self.values = null
        self.items = null
        self.fields = null
        self.required = []
        self.additional = true
        self.choices = null
        self.predicate = null
        self.message = null

    func optional():
        self.nullable = true
        return self

    func default(value):
        self.has_default = true
        self.default_value = value
        return self

    func pattern(p):
        if self.kind != "string":
            raise(SCHEMA, "pattern : réservé aux schémas string")
        self.regex = p
        return self

    func describe(text):
        self.description = text
        return self

    # Liste de messages « chemin : problème » ([] : valide).
    func validate(value, path="$"):
        out := []
        self._validate(value, path, out)
        return out

    func is_valid(value):
        return len(self.validate(value)) == 0

    func check(value):
        errs := self.validate(value)
        if len(errs) > 0:
            raise(VALIDATION, _s.join(" ; ", errs))
        return value

    func _validate(v, path, out):
        if type(v) == "null":
            if not self.nullable and self.kind != "any" and self.kind != "null":
                append(out, path + " : valeur requise (null)")
            return
        k := self.kind
        t := type(v)
        if k == "any":
            return
        if k == "null":
            append(out, path + " : null attendu (obtenu " + t + ")")
            return
        if k == "string":
            if t != "str":
                append(out, path + " : texte attendu (obtenu " + t + ")")
                return
            n := len(v)
            if self.min != null and n < self.min:
                append(out, path + " : longueur " + str(n) + " < " + str(self.min))
            if self.max != null and n > self.max:
                append(out, path + " : longueur " + str(n) + " > " + str(self.max))
            if self.regex != null and not _re.fullmatch(self.regex, v):
                append(out, path + " : ne correspond pas au motif " + self.regex)
            return
        if k == "integer" or k == "number":
            if t == "bool" or (t != "int" and (k == "integer" or t != "float")):
                append(out, path + " : " + _kind_label(k) + " attendu (obtenu " + t + ")")
                return
            if self.min != null and v < self.min:
                append(out, path + " : " + str(v) + " < " + str(self.min))
            if self.max != null and v > self.max:
                append(out, path + " : " + str(v) + " > " + str(self.max))
            return
        if k == "boolean":
            if t != "bool":
                append(out, path + " : booléen attendu (obtenu " + t + ")")
            return
        if k == "enum":
            for x in self.values:
                if x == v:
                    return
            append(out, path + " : " + str(v) + " n'est pas parmi " + str(self.values))
            return
        if k == "list":
            if t != "list":
                append(out, path + " : liste attendue (obtenu " + t + ")")
                return
            if self.min != null and len(v) < self.min:
                append(out, path + " : " + str(len(v)) + " éléments < " + str(self.min))
            if self.max != null and len(v) > self.max:
                append(out, path + " : " + str(len(v)) + " éléments > " + str(self.max))
            i := 0
            for x in v:
                self.items._validate(x, path + "[" + str(i) + "]", out)
                i += 1
            return
        if k == "dict":
            if t != "dict":
                append(out, path + " : dict attendu (obtenu " + t + ")")
                return
            for key in v:
                self.items._validate(v[key], path + "." + str(key), out)
            return
        if k == "object":
            if t != "dict":
                append(out, path + " : objet attendu (obtenu " + t + ")")
                return
            for r in self.required:
                if not (r in v):
                    append(out, path + "." + r + " : champ obligatoire absent")
            for key in v:
                if key in self.fields:
                    self.fields[key]._validate(v[key], path + "." + str(key), out)
                elif not self.additional:
                    append(out, path + "." + str(key) + " : champ inattendu")
            return
        if k == "one_of":
            for c in self.choices:
                if c.is_valid(v):
                    return
            append(out, path + " : ne correspond à aucune des formes permises")
            return
        if k == "custom":
            if not self.predicate(v):
                m := self.message
                if m == null:
                    m = "valeur refusée"
                append(out, path + " : " + m)
            return
        raise(SCHEMA, "schéma de genre inconnu '" + k + "'")

    # Convertit (texte -> nombre, booléen...) et complète les défauts ; ne lève pas : valider ensuite.
    func coerce(v):
        if type(v) == "null" or (type(v) == "str" and v == "" and self.kind != "string"):
            if self.has_default:
                return self.default_value
            return null
        k := self.kind
        t := type(v)
        if t == "str":
            s := _s.trim(v)
            if k == "integer":
                try:
                    return to_int(s)
                catch e:
                    return v
            if k == "number":
                try:
                    if _s.contains(s, ".") or _s.contains(s, "e") or _s.contains(s, "E"):
                        return to_float(s)
                    return to_int(s)
                catch e2:
                    return v
            if k == "boolean":
                l := _s.lower(s)
                if l == "true" or l == "1" or l == "oui" or l == "yes" or l == "vrai":
                    return true
                if l == "false" or l == "0" or l == "non" or l == "no" or l == "faux":
                    return false
                return v
            if k == "list" and self.items != null:
                return [self.items.coerce(x) for x in _s.split(s, ",")]
        if k == "list" and t == "list":
            return [self.items.coerce(x) for x in v]
        if k == "dict" and t == "dict":
            out := {}
            for key in v:
                out[key] = self.items.coerce(v[key])
            return out
        if k == "object" and t == "dict":
            out := {}
            for key in v:
                if key in self.fields:
                    out[key] = self.fields[key].coerce(v[key])
                else:
                    out[key] = v[key]
            for key in self.fields:
                f := self.fields[key]
                if not (key in out) and f.has_default:
                    out[key] = f.default_value
            return out
        return v

    func to_dict():
        d := {"type": self.kind}
        if self.nullable:
            d["optional"] = true
        if self.has_default:
            d["default"] = self.default_value
        if self.min != null:
            d["min"] = self.min
        if self.max != null:
            d["max"] = self.max
        if self.regex != null:
            d["pattern"] = self.regex
        if self.values != null:
            d["values"] = self.values
        if self.items != null:
            d["items"] = self.items.to_dict()
        if self.fields != null:
            fd := {}
            for k in self.fields:
                fd[k] = self.fields[k].to_dict()
            d["fields"] = fd
            d["required"] = self.required
        if self.description != "":
            d["description"] = self.description
        return d

func _kind_label(k):
    if k == "integer":
        return "entier"
    return "nombre"

func any():
    return Schema("any")

func string(min_len=null, max_len=null):
    s := Schema("string")
    s.min = min_len
    s.max = max_len
    return s

func integer(min=null, max=null):
    s := Schema("integer")
    s.min = min
    s.max = max
    return s

func number(min=null, max=null):
    s := Schema("number")
    s.min = min
    s.max = max
    return s

func boolean():
    return Schema("boolean")

func null_type():
    return Schema("null")

func enum_of(values):
    if type(values) != "list" or len(values) == 0:
        raise(SCHEMA, "enum_of : liste non vide de valeurs attendue")
    s := Schema("enum")
    s.values = values
    return s

func list_of(item, min_items=null, max_items=null):
    if not isinstance(item, Schema):
        raise(SCHEMA, "list_of : schéma d'élément attendu")
    s := Schema("list")
    s.items = item
    s.min = min_items
    s.max = max_items
    return s

func dict_of(value_schema):
    s := Schema("dict")
    s.items = value_schema
    return s

# fields : {nom: Schema} ; required : noms obligatoires ; additional=false : refuse les champs non décrits.
func object(fields, required=null, additional=true):
    s := Schema("object")
    for k in fields:
        if not isinstance(fields[k], Schema):
            raise(SCHEMA, "object : le champ '" + str(k) + "' n'a pas de schéma")
    s.fields = fields
    if required != null:
        s.required = required
    s.additional = additional
    return s

func one_of(choices):
    s := Schema("one_of")
    s.choices = choices
    return s

func custom(predicate, message=null):
    if type(predicate) != "function":
        raise(SCHEMA, "custom : prédicat (fonction) attendu")
    s := Schema("custom")
    s.predicate = predicate
    s.message = message
    return s

# Schéma deviné à partir d'un exemple de données.
func infer(sample):
    t := type(sample)
    if t == "str":
        return string()
    if t == "int":
        return integer()
    if t == "float":
        return number()
    if t == "bool":
        return boolean()
    if t == "null":
        return any()
    if t == "list":
        if len(sample) == 0:
            return list_of(any())
        return list_of(infer(sample[0]))
    if t == "dict":
        fields := {}
        req := []
        for k in sample:
            fields[k] = infer(sample[k])
            append(req, k)
        return object(fields, req)
    return any()
