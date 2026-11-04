# Modules `process` et `ffi`

Deux modules de la bibliothèque standard, construits comme `os` :
primitives C++ privées (`_native_process`, `_native_ffi`) + API publique en ALEX.

```
stdlib/process/process.al      Command · Process · Result · run · spawn · which
stdlib/ffi/ffi.al              Library · Function · Buffer · cstring
runtime/native/process/        backend POSIX (posix_spawn, pipes, poll) + stub Windows
runtime/native/ffi/            dlopen/dlsym + appel par registres + buffers bornés
runtime/native/common/args.hpp validation d'arguments partagée
```

## process

Aucun shell : le programme est cherché dans le `PATH`, les arguments sont passés
tels quels (pas d'injection). Un code non nul n'est pas une erreur, sauf `check=true`.
`code < 0` : tué par le signal `-code`.

| Besoin | API |
|---|---|
| Capturer | `process.run(prog, args, input, timeout, cwd, env, check)` → `Result` |
| Fluide | `Command(prog).arg().args().cwd().env().clear_env().stdin()/stdout()/stderr().group()` puis `.run()` / `.spawn()` |
| Piloter | `Process`: `write` `write_line` `close_stdin` `read` `read_line` `read_all` `communicate` `poll` `wait` `kill` `stop` `close` |
| Utilitaires | `check_output`, `which`, `open_handles` |

Modes de flux : `"inherit"`, `"pipe"`, `"null"`, et `"stdout"` pour `stderr` (2>&1).
`env` : surcharge l'environnement hérité ; une valeur `null` supprime la variable.

Garanties : pas d'interblocage entre écriture et lecture (`communicate`, 1 Mio testé) ;
jamais de caractère UTF-8 coupé entre deux lectures ; timeout = TERM puis KILL après
`grace` secondes, sur tout le groupe ; un fils déjà attendu n'est plus jamais signalé
(pas de pid recyclé) ; un fils qui ferme son entrée donne `IoError`, pas un crash.

Cycle de vie : pas de GC des handles. `run()`/`check_output()` nettoient seuls,
y compris sur erreur ; avec `spawn()`, appeler `close()` (après `wait()`/`stop()`).

Erreurs : `IoError`, `TypeError`, `ArgumentError`, `ProcessError`, `TimeoutError`.

## ffi

Types : `void`(retour) `bool` `i8 u8 i16 u16 i32 u32 i64 u64` `f32 f64` `ptr` `cstr`
et alias (`int` `uint` `long` `size_t` `float` `double` `byte` `void*` `char*`).
Entiers : bornes vérifiées avant l'appel. `u64` retourné > 2^63-1 → `ValueError`.

`Library(null)` expose les symboles déjà chargés (libc incluse) ; `Library("m")` →
`libm.so.6` / `libm.dylib`. Les accès mémoire passent par `Buffer` (taille connue,
bornes vérifiées, zéro-initialisé, `IndexError` hors limites).

### Limites assumées
- 6 arguments entiers/pointeurs et 8 flottants maximum (refusé au `bind`, pas à l'exécution) ;
- pas de fonctions variadiques (`printf`), pas de structures par valeur, pas de callbacks ;
- x86-64 et arm64 POSIX (ABI System V / AAPCS64) ; ailleurs `ffi.supported()` est faux ;
- un appel C reste non protégé : mauvaise signature ou pointeur invalide = crash du processus.

## Plateformes
Linux (testé : x86-64, glibc 2.39). macOS/BSD : code POSIX, **non testé ici**.
Windows : `process` lève `IoError` explicite (`os.run`/`os.spawn` restent disponibles) ;
`ffi` est désactivé. Aucun comportement divergent n'est émulé.

## Tests
`make test-process` (66 vérifications), `make test-ffi` (90). Les deux passent aussi
sous ASan + UBSan avec détection de fuites.

## Pistes d'extension
Backend Windows de `process` (CreateProcessW + pipes nommés) ; callbacks et structures
via libffi optionnelle derrière `__has_include(<ffi.h>)`.
