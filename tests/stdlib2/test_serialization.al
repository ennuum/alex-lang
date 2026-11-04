# Tests : serialization.* (serializer, deserializer, json, xml, csv, binary, message_pack, schema, façade).
from core use len, type
from collections use append
use check as t
use os
use filesystem as fs
use string
use serialization
use serialization.serializer as ser
use serialization.deserializer as des
use serialization.json as sj
use serialization.xml as sx
use serialization.csv as sc
use serialization.binary as bin
use serialization.message_pack as mp
use serialization.schema as sch
use reflection.type_registry as treg

class Point:
    func init(x, y):
        self.x = x
        self.y = y
        self._cache = 0

class Ligne:
    func init(nom, n):
        self.nom = nom
        self.n = n

class Commande:
    func init(id, lignes):
        self.id = id
        self.lignes = lignes

class Temp:
    func init(c):
        self.c = c
    func to_data():
        return {"celsius": self.c}
    func from_data(d):
        self.c = d["celsius"]

class Node:
    func init():
        self.next = null

# serializer
s := ser.Serializer()
t.eq(s.to_data(Point(1, 2)), {"__type__": "Point", "x": 1, "y": 2}, "instance")
t.eq(ser.plain(Point(1, 2)), {"x": 1, "y": 2}, "plain")
t.eq(s.to_data((1, 2)), [1, 2], "tuple")
t.eq(ser.Serializer("__type__", false, true).to_data((1, 2)), {"__tuple__": [1, 2]}, "keep_tuples")
t.eq(s.to_data(Temp(20)), {"__type__": "Temp", "celsius": 20}, "to_data()")
s.register("Ligne", (l) => l.nom + "x" + str(l.n))
t.eq(s.to_data(Ligne("a", 2)), {"__type__": "Ligne", "value": "ax2"}, "encodeur enregistré")
n1 := Node()
n1.next = n1
t.raises(() => s.to_data(n1), "SerializationError", "cycle")
t.raises(() => s.to_data({1: "a"}), "SerializationError", "clé non texte")
t.eq(ser.Serializer("__type__", false, false, true).to_data({1: "a"}), {"1": "a"}, "string_keys")
t.raises(() => s.to_data((x) => x), "SerializationError", "fonction")

# deserializer
d := des.Deserializer()
d.register("Point", () => Point(0, 0))
d.register("Temp", () => Temp(0))
p := d.from_data({"__type__": "Point", "x": 3, "y": 4})
t.eq([p.x, p.y], [3, 4], "reconstruction")
t.eq(d.from_data({"__type__": "Temp", "celsius": 5}).c, 5, "from_data()")
t.raises(() => d.from_data({"__type__": "Inconnu"}), "DeserializationError", "strict")
t.eq(des.Deserializer(null, "__type__", false).from_data({"__type__": "X", "a": 1}), {"a": 1}, "non strict")
reg := treg.TypeRegistry()
reg.register("Point", () => Point(0, 0))
t.eq(des.Deserializer(reg).from_data({"__type__": "Point", "x": 9, "y": 9}).x, 9, "via TypeRegistry")
t.eq(d.from_data({"__tuple__": [1, 2]}), (1, 2), "tuple")
d.register_decoder("Ligne", (v) => Ligne(v, 0))
t.eq(d.from_data({"__type__": "Ligne", "value": "abc"}).nom, "abc", "décodeur")

# json
codec := sj.Codec()
codec.register("Commande", () => Commande(0, []))
codec.register("Ligne", () => Ligne("", 0))
c := Commande(42, [Ligne("stylo", 2), Ligne("cahier", 1)])
txt := codec.dumps(c)
back := codec.loads(txt)
t.eq(back.id, 42, "json aller-retour")
t.eq(back.lignes[1].nom, "cahier", "json imbriqué")
t.check(string.contains(sj.dumps({"a": 1}, false), "\"a\""), "dumps")
t.eq(sj.loads(sj.dumps({"a": [1, 2]}, false))["a"], [1, 2], "loads")
lines := sj.dumps_lines([{"n": 1}, {"n": 2}])
t.eq(sj.loads_lines(lines), [{"n": 1}, {"n": 2}], "JSON Lines")
tmp := fs.make_temp_dir()
codec.dump_file(os.join(tmp, "c.json"), c)
t.eq(codec.load_file(os.join(tmp, "c.json")).lignes[0].n, 2, "fichier")
strict := sj.Codec().with_schema(sch.object({"id": sch.integer()}, ["id"]))
t.raises(() => strict.loads("{\"id\": \"x\"}"), "ValidationError", "schéma json")

# xml
xt := sx.dumps(Point(1, 2), "point")
t.check(string.contains(xt, "<x type=\"int\">1</x>"), "xml contenu")
xc := sx.Codec()
xc.register("Point", () => Point(0, 0))
xp := xc.loads(xt)
t.eq([xp.x, xp.y], [1, 2], "xml aller-retour")
t.eq(sx.loads(sx.dumps({"a": [1, "b", null, true, 1.5], "clé à espace": 2})), {"a": [1, "b", null, true, 1.5], "clé à espace": 2}, "xml données")

# csv
csv_text := sc.dumps([Ligne("stylo", 2), Ligne("cahier", 10)])
t.eq(csv_text, "n,nom\n2,stylo\n10,cahier\n", "csv dumps (champs triés)")
t.eq(sc.loads(csv_text), [{"nom": "stylo", "n": 2}, {"nom": "cahier", "n": 10}], "csv devine")
schema := sch.object({"nom": sch.string(), "n": sch.integer(0)})
objs := sc.loads(csv_text, schema, () => Ligne("", 0))
t.eq(objs[1].n, 10, "csv objets")
t.raises(() => sc.loads("nom,n\nx,-3\n", schema), "ValidationError", "csv schéma")
t.eq(sc.guess("3.25"), 3.25, "guess float")
t.eq(sc.dumps([{"a": 1}], ["a", "b"]), "a,b\n1,\n", "colonnes choisies")

# binary
val := {"id": 7, "neg": -300, "tags": ["a", "é"], "ok": true, "x": 1.5, "rien": null, "big": 9007199254740993}
bb := bin.dumps(val)
t.check(bin.is_binary(bb), "en-tête")
t.eq(bin.loads(bb), val, "binaire aller-retour")
t.eq(bin.loads(bin.dumps(bin.binary([0, 255, 7])), null).to_list(), [0, 255, 7], "Binary")
bp := bin.loads(bin.dumps(Point(5, 6)), d)
t.eq(bp.y, 6, "binaire objets")
t.check(bin.size_of([1, 2, 3]) < 16, "compact")
t.raises(() => bin.loads("XXXXX"), "FormatError", "en-tête invalide")
t.raises(() => bin.loads(string.byte_slice(bb, 0, 12)), "FormatError", "tronqué")
bin.dump_file(os.join(tmp, "e.bin"), val)
t.eq(bin.load_file(os.join(tmp, "e.bin")), val, "fichier binaire")

# message_pack
m := mp.packb({"compact": true, "schema": 0})
t.eq(mp.hex(m), "82 a7 63 6f 6d 70 61 63 74 c3 a6 73 63 68 65 6d 61 00", "msgpack spec")
t.eq(mp.unpackb(m), {"compact": true, "schema": 0}, "msgpack aller-retour")
for v in [0, 127, 128, 255, 256, 65535, 65536, 4294967296, -1, -32, -33, -128, -129, -32768, -32769, -2147483649, 1.25, "", "x" * 40, "y" * 300, [1] * 20, null, false]:
    t.eq(mp.unpackb(mp.packb(v)), v, "msgpack " + str(v)[:12])
t.eq(mp.hex(mp.packb(-1)), "ff", "fixint négatif")
t.eq(mp.hex(mp.packb(200)), "cc c8", "uint8")
t.eq(mp.hex(mp.packb(1.5)), "cb 3f f8 00 00 00 00 00 00", "float64")
t.eq(mp.unpackb(string.byte_pack([202, 63, 192, 0, 0])), 1.5, "float32 lu")
t.eq(mp.unpackb(mp.packb(mp.binary([1, 2]))).to_list(), [1, 2], "bin")
ex := mp.unpackb(mp.packb(mp.Ext(5, "abcd")))
t.eq([ex.code, ex.data], [5, "abcd"], "ext")
t.eq(mp.unpack_stream(mp.packb(1) + mp.packb("a")), [1, "a"], "flux")
t.eq(mp.loads(mp.dumps(Point(1, 2)), d).x, 1, "msgpack objets")
t.raises(() => mp.unpackb(string.byte_pack([193])), "FormatError", "0xc1")
t.raises(() => mp.unpackb(string.byte_pack([207, 255, 0, 0, 0, 0, 0, 0, 0])), "FormatError", "uint64 trop grand")

# schema
user := sch.object({"nom": sch.string(1, 50), "age": sch.integer(0, 150), "email": sch.string().pattern(".+@.+\\..+").optional(), "role": sch.enum_of(["admin", "membre"]).default("membre"), "tags": sch.list_of(sch.string()).optional()}, ["nom", "age"])
t.eq(user.validate({"nom": "", "age": 200}), ["$.nom : longueur 0 < 1", "$.age : 200 > 150"], "validate")
t.eq(user.validate({"age": 1}), ["$.nom : champ obligatoire absent"], "obligatoire")
cd := user.coerce({"nom": "Ada", "age": "36"})
t.eq(cd, {"nom": "Ada", "age": 36, "role": "membre"}, "coerce + défaut")
t.check(user.is_valid(cd), "valide")
t.check(not user.is_valid({"nom": "a", "age": 1, "email": "pas-un-mail"}), "motif")
t.check(not user.is_valid({"nom": "a", "age": 1, "role": "chef"}), "enum")
t.check(not user.is_valid({"nom": "a", "age": 1.5}), "entier")
t.check(sch.number().is_valid(1.5) and sch.number().is_valid(2), "number")
t.check(not sch.integer().is_valid(true), "bool n'est pas un entier")
t.check(sch.one_of([sch.integer(), sch.string()]).is_valid("x"), "one_of")
t.check(not sch.custom((v) => v % 2 == 0, "pair attendu").is_valid(3), "custom")
closed := sch.object({"a": sch.integer()}, null, false)
t.eq(closed.validate({"a": 1, "b": 2}), ["$.b : champ inattendu"], "additional=false")
t.eq(sch.boolean().coerce("oui"), true, "coerce booléen")
t.eq(sch.list_of(sch.integer()).coerce("1,2,3"), [1, 2, 3], "coerce liste")
inf := sch.infer({"a": 1, "b": ["x"]})
t.check(inf.is_valid({"a": 2, "b": []}) and not inf.is_valid({"a": "z", "b": []}), "infer")
t.eq(user.to_dict()["fields"]["age"]["max"], 150, "to_dict")
t.raises(() => user.check({}), "ValidationError", "check")
t.raises(() => sch.enum_of([]), "SchemaError", "enum vide")

# façade
serialization.register("Point", () => Point(0, 0))
for f in serialization.formats():
    rp := serialization.loads(serialization.dumps(Point(7, 8), f), f)
    t.eq([rp.x, rp.y], [7, 8], "façade " + f)
dc := serialization.deep_copy([Point(1, 1)])
t.eq(dc[0].x, 1, "deep_copy")

fs.remove_tree(tmp)
t.summary("serialization")
