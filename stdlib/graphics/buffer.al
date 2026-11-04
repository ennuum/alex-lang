# ALEX STANDARD LIBRARY — graphics.buffer
#
# Tampons de données du rendu :
#   - VertexLayout : description d'un sommet (attributs nommés et leur nombre de composantes, ex. position 3,
#     couleur 4, uv 2) ;
#   - VertexBuffer : sommets entrelacés (flottants) suivant un layout ; vertex(i) -> list d'attributs ;
#   - IndexBuffer : indices de sommets (triangles indexés) ;
#   - UniformBuffer : valeurs constantes pour un appel de dessin (matrices, couleurs, lumière) par nom.
#
#   lay := VertexLayout([["position", 3], ["color", 4]])
#   vb := VertexBuffer(lay, [0.0, 0.5, 0.0, 1.0, 0.0, 0.0, 1.0,  -0.5, -0.5, 0.0, 0.0, 1.0, 0.0, 1.0, ...])
#   ib := IndexBuffer([0, 1, 2])
#   u := UniformBuffer({"mvp": m})

from core use len, to_float
from collections use append, contains_key, keys

class VertexLayout:
    # attributes : list de [nom, composantes].
    func init(attributes):
        self.attributes = attributes
        self.stride = 0
        self.offsets = {}
        for a in attributes:
            self.offsets[a[0]] = self.stride
            self.stride += a[1]

    func has(name):
        return contains_key(self.offsets, name)

    func offset(name):
        return self.offsets[name]

    func size(name):
        for a in self.attributes:
            if a[0] == name:
                return a[1]
        raise("ArgumentError", "VertexLayout : pas d'attribut '" + name + "'")

    func describe():
        t := ""
        for a in self.attributes:
            if t != "":
                t = t + ", "
            t = t + a[0] + "[" + str(a[1]) + "]"
        return t

POSITION := VertexLayout([["position", 3]])
POSITION_COLOR := VertexLayout([["position", 3], ["color", 4]])
POSITION_UV := VertexLayout([["position", 3], ["uv", 2]])
POSITION_NORMAL_UV := VertexLayout([["position", 3], ["normal", 3], ["uv", 2]])

class VertexBuffer:
    func init(layout, data):
        if len(data) % layout.stride != 0:
            raise("ArgumentError", "VertexBuffer : " + str(len(data)) + " valeurs ne font pas un nombre entier de sommets de " + str(layout.stride))
        self.layout = layout
        self.data = [to_float(x) for x in data]

    func count():
        return len(self.data) // self.layout.stride

    # Attributs du sommet i : list de list (dans l'ordre du layout).
    func vertex(i):
        base := i * self.layout.stride
        out := []
        for a in self.layout.attributes:
            o := base + self.layout.offsets[a[0]]
            append(out, [self.data[o + k] for k in 0..a[1]])
        return out

    func attribute(i, name):
        o := i * self.layout.stride + self.layout.offset(name)
        return [self.data[o + k] for k in 0..self.layout.size(name)]

    func update(data):
        self.data = [to_float(x) for x in data]

class IndexBuffer:
    func init(indices):
        self.indices = indices

    func count():
        return len(self.indices)

    func max_index():
        m := -1
        for i in self.indices:
            if i > m:
                m = i
        return m

class UniformBuffer:
    func init(values=null):
        self.values = values if values != null else {}

    func set(name, value):
        self.values[name] = value
        return self

    func get(name, fallback=null):
        if contains_key(self.values, name):
            return self.values[name]
        return fallback

    func names():
        return keys(self.values)

# Sommets d'un rectangle plein écran (deux triangles) avec uv : utile pour les effets en post-traitement.
func fullscreen_quad():
    return VertexBuffer(POSITION_UV, [-1.0, -1.0, 0.0, 0.0, 1.0,
                                      1.0, -1.0, 0.0, 1.0, 1.0,
                                      1.0, 1.0, 0.0, 1.0, 0.0,
                                      -1.0, -1.0, 0.0, 0.0, 1.0,
                                      1.0, 1.0, 0.0, 1.0, 0.0,
                                      -1.0, 1.0, 0.0, 0.0, 0.0])

# Cube unité centré (36 sommets : position, normale, uv).
func cube():
    faces := [[[0.0, 0.0, 1.0], [-1.0, -1.0, 1.0], [1.0, -1.0, 1.0], [1.0, 1.0, 1.0], [-1.0, 1.0, 1.0]],
              [[0.0, 0.0, -1.0], [1.0, -1.0, -1.0], [-1.0, -1.0, -1.0], [-1.0, 1.0, -1.0], [1.0, 1.0, -1.0]],
              [[1.0, 0.0, 0.0], [1.0, -1.0, 1.0], [1.0, -1.0, -1.0], [1.0, 1.0, -1.0], [1.0, 1.0, 1.0]],
              [[-1.0, 0.0, 0.0], [-1.0, -1.0, -1.0], [-1.0, -1.0, 1.0], [-1.0, 1.0, 1.0], [-1.0, 1.0, -1.0]],
              [[0.0, 1.0, 0.0], [-1.0, 1.0, 1.0], [1.0, 1.0, 1.0], [1.0, 1.0, -1.0], [-1.0, 1.0, -1.0]],
              [[0.0, -1.0, 0.0], [-1.0, -1.0, -1.0], [1.0, -1.0, -1.0], [1.0, -1.0, 1.0], [-1.0, -1.0, 1.0]]]
    uvs := [[0.0, 1.0], [1.0, 1.0], [1.0, 0.0], [0.0, 0.0]]
    data := []
    for f in faces:
        n := f[0]
        for k in [0, 1, 2, 0, 2, 3]:
            p := f[1 + k]
            for v in p:
                append(data, v * 0.5)
            for v in n:
                append(data, v)
            for v in uvs[k]:
                append(data, v)
    return VertexBuffer(POSITION_NORMAL_UV, data)
