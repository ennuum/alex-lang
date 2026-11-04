# ALEX STANDARD LIBRARY — gpu.gpu_memory
#
# Mémoire d'un périphérique de calcul : tampons typés (float32, int32, uint8...) avec forme (dimensions),
# copie vers le périphérique (upload) et retour (download), réserve qui compte les octets alloués et refuse
# au-delà de la capacité (comme une vraie VRAM), statistiques.
#
#   use gpu.gpu_memory as gm
#   mem := gm.GpuMemory(256 * 1048576)
#   a := mem.upload([1.0, 2.0, 3.0, 4.0], "float32", [2, 2])
#   b := mem.zeros("float32", [2, 2])
#   print(a.get(1, 0), a.size_bytes())       # 3.0 16
#   x := a.download()                        # list (copie)
#   mem.free(a)

from core use len, to_int, to_float
from collections use append, keys

const DTYPES := {"float32": 4, "float64": 8, "int32": 4, "int64": 8, "uint8": 1, "int8": 1, "int16": 2}

func dtype_size(dtype):
    for k in ["float32", "float64", "int32", "int64", "uint8", "int8", "int16"]:
        if k == dtype:
            return DTYPES[k]
    raise("ArgumentError", "gpu : type d'élément inconnu '" + str(dtype) + "'")

func _product(shape):
    n := 1
    for d in shape:
        n = n * d
    return n

func _cast(v, dtype):
    if dtype == "float32" or dtype == "float64":
        return to_float(v)
    n := to_int(v)
    if dtype == "uint8":
        return n & 255
    if dtype == "int8":
        n = n & 255
        return n - 256 if n >= 128 else n
    if dtype == "int16":
        n = n & 0xFFFF
        return n - 65536 if n >= 32768 else n
    if dtype == "int32":
        n = n & 0xFFFFFFFF
        return n - 4294967296 if n >= 2147483648 else n
    return n

class GpuBuffer:
    func init(memory, dtype, shape, data, id):
        self.memory = memory
        self.dtype = dtype
        self.shape = shape
        self.data = data
        self.id = id
        self.freed = false

    func count():
        return _product(self.shape)

    func size_bytes():
        return self.count() * dtype_size(self.dtype)

    func _index(i, j):
        if len(self.shape) == 1:
            return i
        return i * self.shape[1] + j

    func get(i, j=0):
        self._check()
        return self.data[self._index(i, j)]

    func set(i, j, v):
        self._check()
        self.data[self._index(i, j)] = _cast(v, self.dtype)

    func _check():
        if self.freed:
            raise("MemoryError", "GpuBuffer : tampon " + str(self.id) + " libéré")

    # Copie du contenu vers la mémoire de l'application.
    func download():
        self._check()
        self.memory.downloads += 1
        return [x for x in self.data]

    # Remplace le contenu (même nombre d'éléments).
    func write(values):
        self._check()
        if len(values) != self.count():
            raise("ArgumentError", "GpuBuffer.write : " + str(self.count()) + " éléments attendus")
        self.data = [_cast(v, self.dtype) for v in values]
        self.memory.uploads += 1

    func reshape(shape):
        if _product(shape) != self.count():
            raise("ArgumentError", "GpuBuffer.reshape : nombre d'éléments différent")
        self.shape = shape
        return self

    func describe():
        return "tampon " + str(self.id) + " " + self.dtype + " " + str(self.shape) + " (" + str(self.size_bytes()) + " octets)"

class GpuMemory:
    func init(capacity):
        self.capacity = capacity
        self.used = 0
        self.peak = 0
        self.buffers = {}
        self.next_id = 1
        self.uploads = 0
        self.downloads = 0

    func _reserve(n):
        if self.used + n > self.capacity:
            raise("MemoryError", "gpu : mémoire du périphérique épuisée (" + str(self.used + n) + " > " + str(self.capacity) + " octets)")
        self.used += n
        if self.used > self.peak:
            self.peak = self.used

    func allocate(dtype, shape, fill=0):
        n := _product(shape)
        self._reserve(n * dtype_size(dtype))
        b := GpuBuffer(self, dtype, shape, [_cast(fill, dtype) for i in 0..n], self.next_id)
        self.buffers[self.next_id] = b
        self.next_id += 1
        return b

    func zeros(dtype, shape):
        return self.allocate(dtype, shape, 0)

    # Copie values (list) dans un nouveau tampon ; shape par défaut [len(values)].
    func upload(values, dtype="float32", shape=null):
        s := shape if shape != null else [len(values)]
        if _product(s) != len(values):
            raise("ArgumentError", "gpu.upload : forme incompatible avec " + str(len(values)) + " éléments")
        self._reserve(len(values) * dtype_size(dtype))
        b := GpuBuffer(self, dtype, s, [_cast(v, dtype) for v in values], self.next_id)
        self.buffers[self.next_id] = b
        self.next_id += 1
        self.uploads += 1
        return b

    func free(b):
        if not b.freed:
            b.freed = true
            self.used -= b.size_bytes()
            self.buffers[b.id] = null

    func available():
        return self.capacity - self.used

    func live():
        n := 0
        for k in keys(self.buffers):
            if self.buffers[k] != null:
                n += 1
        return n

    func describe():
        return "mémoire : " + str(self.used) + " / " + str(self.capacity) + " octets (pointe " + str(self.peak) + "), " + str(self.live()) + " tampons"
