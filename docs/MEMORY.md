# Module `memory` — gestion mémoire hybride

Deux niveaux, un seul registre natif, une frontière explicite :

```
Safe Alex                                 unsafe Alex
─────────                                 ───────────
gestion automatique                       pointeurs / mémoire brute
memory.buffer       Buffer · Arena        memory.alloc          raw · calloc · realloc
memory.memory_view  MemoryView            memory.free           address · FreeList
memory.reference    Ref · Rc · RefCell    memory.pointer        Pointer typé
                                          memory.virtual_memory pages · mprotect · mmap
                  frontière : memory.unsafe  (block · require · audit)
```

```
stdlib/memory/
├── memory.al          façade : raccourcis, diagnostics (use memory)
├── unsafe.al          le garde-fou : unsafe.block(), require(), audit
├── alloc.al           block() sûr · raw() calloc() aligned() realloc() unsafe
├── free.al            libération, double free, FreeList, scope(), leaks()
├── buffer.al          Buffer propriétaire · Arena · scoped()
├── pointer.al         Pointer typé + arithmétique (déréférencer = unsafe)
├── reference.al       Ref · Rc/Weak · RefCell · HandleTable
├── memory_view.al     MemoryView : tranches bornées, lecture seule, invalidation
└── virtual_memory.al  pages, protections R/W/X, fichiers mappés, pages de garde
runtime/native/memory/ _native_memory : registre des régions, accès bornés, mmap
```

## La règle du modèle

**Créer, copier, comparer, décaler un `Pointer` est sûr** (ce n'est qu'un entier).
**Le déréférencer, allouer/libérer à l'adresse, ou rendre une page exécutable exige
`unsafe.block(...)`** — sinon `UnsafeError`. ALEX n'a pas de bloc anonyme : on passe une
fonction nommée (ou une lambda `() => expr`).

```alex
use memory
use memory.pointer as pointer

func brut():
    p := pointer.malloc(4, "i32")
    p.write_array([10, 20, 30, 40])
    print(p.offset(2).read())            # 30
    p.free()

memory.unsafe_block(brut, "error")       # "error" : toute fuite du bloc => LeakError
```

Un `Pointer` sorti du bloc ne peut plus être déréférencé. `leaks` : `"ignore"` (défaut),
`"free"` (libère à la sortie), `"error"` (libère puis `LeakError`).

## Garanties

| Niveau | Garantie | Erreur |
|---|---|---|
| Sûr | accès hors bornes (Buffer, vue, sous-vue) | `IndexError` |
| Sûr | utilisation après `free()`, double free de bloc géré | `MemoryError` |
| Sûr | écriture sur tampon gelé / vue en lecture seule | `MemoryError` |
| Sûr | vue d'une arène après `reset()`/`free()` | `StaleViewError` |
| Sûr | débordement d'un bloc (canaris avant/après, vérifiés à `free`/`check`) | `MemoryError` |
| Sûr | mémoire toujours initialisée (zéro, ou 0xCD si `zero=false`) | — |
| Sûr | emprunts `RefCell` incompatibles ; handle périmé | `BorrowError` / `StaleHandleError` |
| Unsafe | déréférencement hors bloc unsafe | `UnsafeError` |
| Unsafe | adresse hors de toute région suivie, page non lisible/inscriptible, pointeur nul | `MemoryError` |
| Unsafe | double free, pointeur intérieur, pointeur inconnu, genre incompatible (`free` d'une page) | `MemoryError` / `ArgumentError` |
| Virtuelle | accès à une page `PROT_NONE` / lecture seule ; `W+X` refusé | `MemoryError` / `ArgumentError` |

Les accès par adresse sont **validés** contre le registre (`alloc`, `raw`, `vm_map`, `track`) :
un pointeur fou donne une exception, pas un segfault. `unsafe.set_checks(false)` (dans un bloc
unsafe) retire ce contrôle : accès nu comme en C, qui **peut planter le processus**. La mémoire
étrangère (retournée par du C via `ffi`) se déclare avec `pointer.track(adresse, taille)`.

## Gestion automatique : ce qui est vrai

Le ramasse-miettes de la VM est actif (docs/RUNTIME.md §4, module `gc`). La libération automatique repose, dans
l'ordre, sur :

1. **portées déterministes** — `buffer.scoped`, `buffer.scoped_arena`, `free.scope`, `FreeList` : libération
   garantie, y compris sur exception (ALEX n'a pas de `finally`) ;
2. `free()` explicite, idempotent sur `Buffer` ;
3. **ramasse-miettes** — chaque `Buffer` porte un « garde » natif (un `ObjNative` dont la destruction libère le
   bloc) : quand le GC détruit un `Buffer` devenu inaccessible, son bloc natif est libéré. Vérifié : 500 `Buffer`
   abandonnés → 0 bloc restant après `gc.collect()`.

Garanties de durée de vie : une `MemoryView` (et ses sous-vues) **garde son `Buffer` vivant** ; un `Pointer`,
`Buffer.address()` ou `pointer.from_buffer` **ne le garde pas** (conserver le `Buffer`, sinon `MemoryError`
contrôles actifs, ou plantage contrôles coupés). Le GC est déclenché par le **nombre d'objets ALEX**, pas par les
octets natifs : un gros `Buffer` abandonné peut rester longtemps, d'où l'intérêt de 1 et 2 pour borner la mémoire,
ou d'un `gc.collect()`. Les régions `raw` et `mapped` ne sont jamais libérées par le GC (`leaks()` les liste).

Quota : `memory.set_limit(octets)` borne le total vivant (blocs + adresses brutes) ;
`memory.stats()` / `memory.leak_report()` / `memory.check_all()` pour le diagnostic.

## Mémoire virtuelle

`vm.map(taille, prot)` · `vm.reserve` · `vm.map_file(chemin, writable, shared, offset, length)` ·
`vm.map_guarded(taille, at_end)` ; sur `Region` : `protect`, `prot_at`, `read/write/…`, `view`,
`lock/unlock`, `advise`, `resident`, `sync`, `unmap`. Protections : `NONE=0 READ=1 WRITE=2 EXEC=4`.
`map_guarded` borde les données de pages `PROT_NONE` : un dépassement d'un octet est détecté.
Toute protection contenant `EXEC` exige un bloc unsafe ; `WRITE+EXEC` est refusé (W^X).

## Limites assumées

- Testé : Linux x86-64 (glibc), 505 vérifications, propres sous ASan + UBSan + LSan
  (natif instrumenté). Le code Windows (`VirtualAlloc`/`VirtualProtect`/`VirtualQuery`) **compile**
  (mingw) mais **n'a pas été exécuté** ; `map_file`, `advise`, `resident` y lèvent `IoError`.
  macOS/BSD : code POSIX, non testé. Big-endian / non-64 bits : `supported()` est faux.
- Le compteur de profondeur `unsafe` est global : ne pas `await` dans un bloc unsafe.
- Un entier ALEX est signé 64 bits : lire un `u64` > 2^63-1 lève `ValueError` (lire en `i64`).
- Les canaris détectent les débordements **contigus** constatés à `free`/`check`, pas toute
  écriture folle ; les pages de garde (`map_guarded`) détectent immédiatement.
- Les mémoires `raw`/`mapped` sont hors du GC : à libérer à la main (`leaks()` les liste).

## Erreurs

Natives : `MemoryError` (nouveau code runtime), `IndexError`, `ArgumentError`, `TypeError`,
`ValueError`, `IoError`. Levées par la couche ALEX : `UnsafeError`, `LeakError`,
`StaleViewError`, `BorrowError`, `StaleHandleError`, `OwnershipError`.

## Tests

`make test-memory` (`tests/memory/test_memory.al`, 505 vérifications) ; exemple :
`examples/memory_demo.al`.
