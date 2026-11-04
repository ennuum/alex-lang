# Tests : reflection.* (type_info, field_info, method_info, type_traits, type_registry, attributes, façade).
from core use len, type
from collections use append
use check as t
use reflection
use reflection.type_info as ti
use reflection.field_info as fi
use reflection.method_info as mi
use reflection.type_traits as tt
use reflection.type_registry as treg
use reflection.attributes as attr
use collections.array_list as al

interface Shape:
    func area()

class Base implements Shape:
    func init(name):
        self.name = name
        self._secret = 1
    func area():
        return 0
    func describe(prefix=""):
        return prefix + self.name

class Rect extends Base:
    func init(w, h):
        super.init("rect")
        self.w = w
        self.h = h
    func area():
        return self.w * self.h
    func scale(k):
        self.w = self.w * k
        self.h = self.h * k
        return self
    func __str__():
        return "Rect"

class Vec:
    func init(x):
        self.x = x
    func __add__(o):
        return Vec(self.x + o.x)
    func __len__():
        return 1
    func __call__(k):
        return self.x * k

r := Rect(2, 3)

# type_info
tr := ti.type_of(r)
t.eq(tr.name, "Rect", "name")
t.eq(tr.kind, "instance", "kind")
t.check(tr.is_class(), "is_class")
t.eq(tr.base_names(), ["Base"], "base_names")
t.eq(tr.interface_names(), ["Shape"], "interfaces héritées")
t.check(tr.has_method("describe"), "méthode héritée")
t.eq(tr.own_method_names(), ["__str__", "area", "init", "scale"], "own_method_names")
t.check(tr.is_subtype_of("Shape") and tr.is_subtype_of("Base"), "is_subtype_of")
t.check(not tr.is_subtype_of("Vec"), "pas sous-type")
t.eq(tr.method_arity("describe"), [0, 1], "method_arity")
t.eq(ti.type_of(42).kind, "int", "natif")
t.check(ti.type_of([1]).is_builtin(), "is_builtin")
t.eq(ti.type_named("Rect").name, "Rect", "type_named")
t.raises(() => ti.type_named("Inexistant"), "UnknownTypeError", "type inconnu")
t.eq([s.name for s in ti.type_named("Base").subtypes()], ["Rect"], "subtypes")
t.check(ti.type_named("Shape").is_interface(), "is_interface")
t.eq(ti.type_of(al.ArrayList()).interface_names(), ["Collection", "Sequence"], "type d'un module")

# field_info
t.eq(fi.names(r), ["_secret", "h", "name", "w"], "names")
t.eq(fi.names(r, false), ["h", "name", "w"], "names publics")
fs := fi.fields(r)
t.eq(fs[1].type, "int", "FieldInfo.type")
t.check(fs[0].is_private(), "is_private")
fi.set(r, "w", 10)
t.eq(r.w, 10, "set")
t.eq(fi.get(r, "h"), 3, "get")
t.eq(fi.get(r, "zz", 0), 0, "get défaut")
t.raises(() => fi.get(r, "zz"), "AttributeError", "get absent")
t.eq(fi.to_dict(r), {"h": 3, "name": "rect", "w": 10}, "to_dict")
nested := Base("n")
nested.child = Rect(1, 1)
t.eq(fi.to_dict(nested, false, true)["child"]["w"], 1, "to_dict deep")
r2 := Rect(0, 0)
fi.from_dict(r2, {"w": 10, "h": 3})
t.eq(r2.area(), 30, "from_dict")
t.check(fi.equals(r, r2), "equals après from_dict")
fi.copy_fields(r, r2)
t.check(fi.equals(r, r2), "copy_fields + equals")
r2.h = 9
t.eq(fi.diff(r, r2), [["h", 3, 9]], "diff")
t.check(fi.remove(r2, "h"), "remove")
t.check(not fi.has(r2, "h"), "has après remove")
t.raises(() => fi.names(5), "ReflectionError", "pas une instance")

# method_info
names := mi.names(r)
t.check("describe" in names and "scale" in names, "names héritées")
m := mi.get(r, "describe")
t.eq(m.declared_in, "Base", "declared_in")
t.check(m.is_inherited(), "is_inherited")
t.check(m.accepts(1) and not m.accepts(2), "accepts")
t.eq(mi.call(r, "describe", ">"), ">rect", "call")
t.raises(() => mi.call(r, "describe", 1, 2), "ArgumentError", "call arité")
t.raises(() => mi.call(r, "fly"), "AttributeError", "call absente")
f := mi.bound(r, "area")
t.eq(f(), 30, "bound")
t.eq(mi.special_methods(r), ["__str__"], "special_methods")
t.eq(mi.public_methods("Rect"), ["area", "scale", "describe"], "public_methods par nom")
t.check(mi.has_method("Base", "area"), "has_method par nom")

# type_traits
t.check(tt.is_integral(3) and tt.is_floating(2.5) and not tt.is_numeric("3"), "numériques")
t.check(not tt.is_hashable([1]) and tt.is_hashable((1, 2)), "is_hashable")
t.check(tt.is_iterable("abc") and tt.is_iterable(al.ArrayList()), "is_iterable")
t.check(tt.has_len(Vec(1)), "has_len")
t.check(tt.is_comparable(1, 2.0) and not tt.is_comparable(1, "a"), "is_comparable")
t.check(tt.supports(Vec(1), "__add__") and tt.supports(3, "__add__"), "supports")
t.check(tt.is_callable(Vec(2)) and tt.is_callable((x) => x), "is_callable")
t.check(tt.implements(r, "Shape") and tt.implements(3, "int"), "implements")
t.eq([tt.category(1), tt.category("a"), tt.category([1]), tt.category({}), tt.category(r)], ["number", "text", "sequence", "mapping", "object"], "category")
t.check(tt.same_type(Rect(1, 1), r) and not tt.same_type(r, Vec(1)), "same_type")

# type_registry
reg := treg.TypeRegistry()
reg.register("Rect", (w, h) => Rect(w, h), {"version": 2})
p := reg.create("Rect", 2, 5)
t.eq(p.area(), 10, "create")
t.eq(reg.meta("Rect")["version"], 2, "meta")
reg.alias("R", "Rect")
t.eq(reg.create("R", 1, 1).area(), 1, "alias")
t.eq(reg.type_name_of(p), "Rect", "type_name_of")
t.eq(reg.create_from({"type": "Rect", "args": [3, 3]}).area(), 9, "create_from")
t.raises(() => reg.create("Cercle"), "UnknownTypeError", "inconnu")
t.raises(() => reg.register("Rect", (x) => x), "ReflectionError", "doublon")
t.eq(reg.find((mt) => "version" in mt), ["Rect"], "find")
t.check(reg.unregister("Rect") and not reg.contains("R"), "unregister + alias")
t.check(not ("Shape" in treg.subtypes_of("Shape")), "subtypes_of exclut lui-même")
t.check("Rect" in treg.subtypes_of("Shape"), "subtypes_of")
t.check("Rect" in treg.known_types(), "known_types")
treg.register("Vec", (x) => Vec(x))
t.eq(treg.create("Vec", 4).x, 4, "registre global")

# attributes
attr.set_type("Rect", "table", "rects")
attr.set_field("Rect", "w", "unit", "cm")
attr.set_method(r, "scale", "pure", false)
t.eq(attr.get_type(r, "table"), "rects", "get_type par instance")
t.eq(attr.get_field("Rect", "w", "unit"), "cm", "get_field")
t.eq(attr.get_method("Rect", "scale", "pure"), false, "get_method")
t.eq(attr.fields_with("Rect", "unit"), ["w"], "fields_with")
t.eq(attr.types_with("table"), ["Rect"], "types_with")
t.raises(() => attr.get_type("Rect", "absent"), "KeyError", "attribut absent")
t.eq(attr.get_type("Rect", "absent", 0), 0, "défaut")

@attr.tag("route", "/accueil")
func accueil():
    return "ok"
t.eq(attr.of_function(accueil)["route"], "/accueil", "décorateur")
t.eq(accueil(), "ok", "fonction décorée inchangée")

# façade
t.eq(reflection.class_name(r), "Rect", "class_name")
t.eq(reflection.class_name(3), "int", "class_name natif")
t.check(reflection.has_field(r, "w") and reflection.has_method(r, "area"), "has_*")
t.eq(reflection.call(r, "area"), 30, "call")
t.check(reflection.is_instance_of(r, "Shape"), "is_instance_of")
t.eq(reflection.describe(Base("x")), "Base { name: \"x\" }", "describe")
ins := reflection.inspect(r)
t.eq(ins["base"], "Base", "inspect base")
t.eq(ins["fields"]["w"], 10, "inspect fields")

t.summary("reflection")
