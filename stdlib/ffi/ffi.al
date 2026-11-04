# ALEX STANDARD LIBRARY — ffi
#
# Appeler des fonctions C de bibliothèques partagées (.so / .dylib / .dll).
#
# Architecture
#   ffi.al        API publique ALEX (Library, Function, Buffer).
#   _native_ffi   dlopen/dlsym + appel par registres + buffers mémoire bornés
#                 (runtime/vm/vm.al, runtime/alex/native), sans dépendance externe.
#
# Types (noms acceptés)
#   void (retour seulement) · bool · i8 u8 i16 u16 i32 u32 i64 u64 ·
#   f32 f64 · ptr · cstr
#   alias : int=i32, uint=u32, long=i64, size_t=u64, float=f32, double=f64,
#           byte=u8, void*=ptr, char*=cstr
#   cstr  : argument str (ou null) -> const char* ; retour char* -> str
#           (copiée ; le C garde la propriété de son pointeur).
#   ptr   : adresse opaque (int) ou null. Obtenue d'un retour C ou de
#           Buffer.address(), à repasser telle quelle à C.
#   Entiers : bornes vérifiées avant l'appel (un u8 refuse 256). i64/u64
#           acceptent tout int ; un retour u64 > 2^63-1 lève ValueError.
#
# Limites (refusées explicitement, jamais émulées en silence)
#   - POSIX (System V) : 6 entiers/pointeurs et 8 flottants en registres, puis
#     16 arguments au plus sur la pile ; Windows x64 : 16 arguments au plus ;
#   - pas de fonctions variadiques (printf, open avec mode...) ;
#   - pas de structures par valeur, pas de callbacks ALEX -> C ;
#   - x86-64 Linux, arm64 Linux et Windows x64 (supported() == false ailleurs).
#
# Pointeurs de fonctions : function_at(adresse, nom, types, retour) lie une
# adresse rendue par du C (wglGetProcAddress, glXGetProcAddress...).
# Mémoire brute : peek / poke / peek_bytes lisent et écrivent à une adresse
# rendue par du C (NON protégés). Buffer.write_array / read_array travaillent
# en bloc (sommets, indices, échantillons ; type "pcm16" = flottants [-1, 1]
# convertis en entiers 16 bits).
#
# Sûreté
#   Les accès mémoire ALEX passent par Buffer (taille connue, bornes vérifiées,
#   initialisé à zéro). En revanche un appel C est non protégé : une signature
#   fausse ou un pointeur invalide fait planter le processus entier, comme en C.
#   Les noms commençant par `_` sont des détails d'implémentation.
#
# Erreurs
#   IoError        bibliothèque ou symbole introuvable, plateforme non supportée.
#   TypeError      argument d'un mauvais type.
#   ArgumentError  type FFI inconnu, arité fausse, valeur hors bornes, handle fermé.
#   IndexError     accès hors d'un Buffer.
#   ValueError     résultat non représentable.
#
# Exemple
#   use ffi
#   libm := ffi.Library("m")
#   cos := libm.function("cos", ["f64"], "f64")
#   print(cos.call([0.0]))                    # 1.0
#
#   libc := ffi.Library(null)                 # symboles déjà chargés dans ALEX
#   strlen := libc.function("strlen", ["cstr"], "size_t")
#   print(strlen.call(["bonjour"]))           # 7
#
#   end := ffi.Buffer(8)                      # paramètre de sortie
#   strtol := libc.function("strtol", ["cstr", "ptr", "i32"], "i64")
#   print(strtol.call(["ff", end.address(), 16]))   # 255
#   end.free()

from core use len, type
from collections use append
use string as _s
use os as _os
use _native_ffi as _f

# ---------------------------------------------------------------------
# Outils internes
# ---------------------------------------------------------------------

func _is_path(name):
    return _s.contains(name, "/") or _s.contains(name, ".so") or _s.ends_with(name, ".dylib") or _s.ends_with(name, ".dll")

# Noms candidats pour `use ffi` : "m" -> libm.so.6 sous Linux, libm.dylib sous macOS.
func _candidates(name):
    if name == null:
        return [null]
    if type(name) != "str":
        raise("TypeError", "ffi.Library() : nom attendu str ou null (obtenu '" + type(name) + "')")
    if _is_path(name):
        return [name]
    plat := _os.platform()
    if plat == "macos":
        if name == "c":
            return ["libSystem.B.dylib"]
        return ["lib" + name + ".dylib", name]
    if name == "c":
        return ["libc.so.6", "libc.so"]
    if plat == "windows":
        if name == "c":
            return ["msvcrt.dll", "ucrtbase.dll"]
        if name == "m":
            return ["msvcrt.dll", "ucrtbase.dll"]
        return [name + ".dll", "lib" + name + ".dll", name]
    if name == "m":
        return ["libm.so.6", "libm.so"]
    return ["lib" + name + ".so", name]

func _need_list(fn, value, label):
    t := type(value)
    if t != "list" and t != "tuple":
        raise("TypeError", "ffi." + fn + "() : " + label + " doit être une list (obtenu '" + t + "')")
    return value

# ---------------------------------------------------------------------
# Fonction liée
# ---------------------------------------------------------------------

class Function:
    func init(handle, name, arg_types, ret_type):
        self._h = handle
        self.name = name
        self.arg_types = arg_types
        self.ret_type = ret_type

    # Appelle la fonction C. `args` : list de valeurs, une par type déclaré.
    func call(args=null):
        values := args
        if values == null:
            values = []
        return _f.call(self._h, _need_list("Function.call", values, "args"))

    func call0():
        return _f.call(self._h, [])

    func call1(a):
        return _f.call(self._h, [a])

    func call2(a, b):
        return _f.call(self._h, [a, b])

    func call3(a, b, c):
        return _f.call(self._h, [a, b, c])

# ---------------------------------------------------------------------
# Bibliothèque
# ---------------------------------------------------------------------

class Library:
    # name : "m", "libz.so.1", "/chemin/lib.so", ou null (symboles du processus
    # ALEX, libc comprise). Plusieurs noms candidats sont essayés.
    func init(name=null):
        _check_supported()
        self.name = name
        self._h = null
        first_error := null
        for candidate in _candidates(name):
            if self._h == null:
                try:
                    self._h = _f.load(candidate)
                catch e:
                    if first_error == null:
                        first_error = e.message
        if self._h == null:
            raise("IoError", "ffi.Library('" + _label(name) + "') : " + first_error)

    func _live():
        if self._h == null:
            raise("ArgumentError", "ffi : Library déjà fermée (close())")
        return self._h

    # Le symbole existe-t-il ?
    func has(symbol):
        return _f.has_symbol(self._live(), symbol)

    # Adresse brute du symbole (int, 0 s'il est absent) : pointeur à passer à du C.
    func address(symbol):
        return _f.symbol_address(self._live(), symbol)

    # Lie le symbole C à une signature. Retourne une Function.
    func function(symbol, arg_types, ret_type):
        types := _need_list("Library.function", arg_types, "arg_types")
        handle := _f.bind(self._live(), symbol, types, ret_type)
        return Function(handle, symbol, types, ret_type)

    # Raccourci : lie puis appelle une fois (liaison refaite à chaque appel :
    # pour une boucle, garder la Function).
    func call(symbol, arg_types, ret_type, args=null):
        return self.function(symbol, arg_types, ret_type).call(args)

    # Décharge la bibliothèque : ses Function deviennent invalides. Idempotent.
    func close():
        if self._h != null:
            _f.unload(self._h)
            self._h = null
        return null

func _label(name):
    if name == null:
        return "<processus>"
    return name

func _check_supported():
    if not _f.supported():
        raise("IoError", "ffi : non supporté sur cette plateforme (x86-64 / arm64 Linux ou Windows x64 requis)")

# ---------------------------------------------------------------------
# Buffer mémoire géré
# ---------------------------------------------------------------------

class Buffer:
    # `size` octets, initialisés à zéro.
    func init(size):
        _check_supported()
        self._h = _f.buf_alloc(size)

    func _live():
        if self._h == null:
            raise("ArgumentError", "ffi : Buffer déjà libéré (free())")
        return self._h

    func size():
        return _f.buf_size(self._live())

    # Adresse brute (int) à passer à une fonction C de type "ptr".
    # Valable tant que le Buffer n'est pas libéré.
    func address():
        return _f.buf_address(self._live())

    # Valeur typée à `offset` (octets). type : voir l'en-tête du module ;
    # "cstr" lit jusqu'au NUL de fin.
    func read(type_name, offset=0):
        return _f.buf_read(self._live(), offset, type_name)

    func write(type_name, value, offset=0):
        return _f.buf_write(self._live(), offset, type_name, value)

    # Tableau de `count` valeurs consécutives de ce type (lecture en bloc).
    func read_array(type_name, count, offset=0):
        return _f.buf_read_array(self._live(), offset, type_name, count)

    # Écrit une list de valeurs en bloc ; rend le nombre d'octets écrits.
    # type_name "pcm16" : flottants [-1, 1] bornés et convertis en i16.
    func write_array(type_name, values, offset=0):
        return _f.buf_write_array(self._live(), offset, type_name, _need_list("Buffer.write_array", values, "values"))

    # Copie `length` octets de `source` (Buffer) vers ce buffer.
    func copy_from(source, length, offset=0, source_offset=0):
        _f.buf_copy(self._live(), offset, source._live(), source_offset, length)
        return null

    # Chaîne C (UTF-8 + NUL) : retourne le nombre d'octets écrits (NUL compris).
    func write_str(text, offset=0):
        return _f.buf_write(self._live(), offset, "cstr", text)

    func read_str(offset=0):
        return _f.buf_read(self._live(), offset, "cstr")

    # Octets bruts <-> str (aucun NUL implicite). Pour des données non UTF-8,
    # le résultat peut être une str invalide : à manipuler avec précaution.
    func read_bytes(offset, length):
        return _f.buf_read_bytes(self._live(), offset, length)

    func write_bytes(data, offset=0):
        return _f.buf_write_bytes(self._live(), offset, data)

    func fill(byte_value=0, offset=0, length=null):
        n := length
        if n == null:
            n = _f.buf_size(self._live()) - offset
        _f.buf_fill(self._live(), offset, n, byte_value)
        return null

    # Libère la mémoire. Idempotent. Une adresse déjà passée à C devient invalide.
    func free():
        if self._h != null:
            _f.buf_free(self._h)
            self._h = null
        return null

# ---------------------------------------------------------------------
# Raccourcis
# ---------------------------------------------------------------------

func load(name=null):
    return Library(name)

func buffer(size):
    return Buffer(size)

# Buffer contenant `text` suivi d'un NUL (chaîne C à durée de vie contrôlée).
func cstring(text):
    b := Buffer(len(text) * 4 + 1) # majorant UTF-8 : 4 octets par caractère
    b.write_str(text)
    return b

# Fonction C à une adresse connue (pointeur de fonction rendu par du C).
func function_at(address, name, arg_types, ret_type):
    _check_supported()
    types := _need_list("function_at", arg_types, "arg_types")
    return Function(_f.bind_addr(address, name, types, ret_type), name, types, ret_type)

# Lecture / écriture NON PROTÉGÉES à une adresse brute (champ d'une structure rendue par du C).
# "cstr" lit le pointeur char* rangé à l'adresse puis la chaîne pointée.
func peek(address, type_name):
    return _f.ptr_read(address, type_name)

func poke(address, type_name, value):
    _f.ptr_write(address, type_name, value)
    return null

func peek_bytes(address, length):
    return _f.ptr_read_bytes(address, length)

# Taille en octets d'un type ("i32" -> 4, "ptr" -> 8).
func sizeof(type_name):
    return _f.type_size(type_name)

func supported():
    return _f.supported()

# Ressources FFI vivantes : {"libraries": n, "functions": n, "buffers": n}.
func live_counts():
    return _f.live_counts()
