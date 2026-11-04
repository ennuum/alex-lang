# Système : `system.signal`, `system.environment`, `system.system_info`, `system.process`, `system.filesystem`, `system.time`

```
use system.signal as signal
use system.environment as env
use system.system_info as info

arret := [false]
signal.on("TERM", (nom) => arret[0] = true)       # arrêt propre sur demande
signal.interrupt_on("INT")                         # Ctrl+C lève InterruptError

port := env.get_int("PORT", 8080)
print(env.expand("${HOME}/données"))
print(info.cpu_model(), info.format_bytes(info.memory()["available"]))
```

| Module | Rôle |
|---|---|
| `system.signal` | `on(signal, gestionnaire)` → gestionnaire précédent, `interrupt_on("INT")`, `with_handler(signal, gestionnaire, fn)`, `watch(signal)` puis `received`, `pending`, `wait(signaux, délai)` ; `ignore`, `reset` ; `send(pid, signal)`, `raise_signal(signal)` ; `names()`, `number(nom)`, `name_of(signal)`, `supported()` |
| `system.environment` | variables : `get`, `set`, `unset`, `has`, `all`, `names`, lecture typée `get_int`, `get_bool`, `get_list`, `expand("$A ${B:-défaut}")`, `with_vars(dict, fn)` ; `path_dirs`, `path_list_separator`, `find_program` ; `args`, `argv`, `program`, `home`, `username`, `cwd`, `tmp_dir`, `pid` |
| `system.system_info` | `platform`, `name`, `kernel_version`, `arch`, `hostname`, `username`, `os_release`, `distribution`, `cpu_count`, `cpu_model`, `load_average`, `total_memory`, `memory()`, `disk_usage(chemin)`, `mounts()`, `uptime`, `boot_time`, `format_bytes`, `summary()` |
| `system.process` | le module `process` (docs/PROCESS_FFI.md) : `run`, `spawn`, `check_output`, `which`, `Command`... |
| `system.filesystem` | le module `filesystem` (docs/PURE_MODULES.md) avec `mkdir`, `mkdir_all`, `rmdir`, `cwd`, `chdir`, `size`, `realpath`, `absolute`, `permissions`, `chmod`, `mtime` de `os`, et `disk_usage(chemin)` |
| `system.time` | le module `time` (docs/TIME_DATETIME.md) : horloges, `sleep`, calendrier, `strftime` / `strptime`, durées, `Stopwatch`, `Deadline`... |
| `memory.virtual` | nom court de `memory.virtual_memory` (docs/MEMORY.md) |

Les modules d'origine (`process`, `filesystem`, `time`, `os`, `memory.virtual_memory`) restent disponibles ; les
façades `system.*` ne font que les regrouper sous un même espace de noms.

## Signaux

- **Gestionnaire (`on`)** : la fonction reçoit le nom court du signal (`"USR1"`). Elle s'exécute dans le
  programme principal entre deux instructions, dès que le signal arrive. La VM insère son appel au point sûr
  de sa boucle, là où le ramasse-miettes peut aussi passer. Le calcul en cours n'est pas dérangé : la pile
  d'opérandes est rendue intacte.
- **Exception levée par un gestionnaire** : elle part de l'instruction où en était le programme. Les `try` /
  `catch` / `finally` s'appliquent normalement. `interrupt_on("INT")` s'en sert pour transformer Ctrl+C en
  `InterruptError`, ce qui permet de libérer les ressources avant de quitter.
- **Gestionnaires et signaux simultanés** : un gestionnaire n'en interrompt jamais un autre. Les signaux
  arrivés entre-temps sont comptés et traités ensuite, un appel par arrivée.
- **Surveillance (`watch`)** : rien ne s'exécute tout seul ; le programme interroge `received(signal)`
  (consomme), `pending(signal)` (compte) ou attend `wait(signaux, délai)`, qui renvoie le nom du signal ou
  `null` après le délai. Les gestionnaires de `on` continuent de s'exécuter pendant `wait`.
- **Comportement d'origine** : `reset` rétablit le comportement d'avant la première interception (souvent :
  arrêter le programme). `ignore` rend le signal sans effet.
- **Attentes bloquantes** : `time.sleep` s'interrompt pour laisser passer le gestionnaire ; la pause n'est
  pas reprise ensuite. Un appel bloquant **sans délai** (lecture d'un tube, `accept`, `receive`...) se
  termine avant que le gestionnaire ne s'exécute ; dans une boucle de service, utiliser des délais. Pendant
  un `await` du programme principal, le gestionnaire s'exécute à sa reprise.
- **Fils** : seul le programme principal intercepte les signaux. `on`, `watch`, `ignore` et `reset` depuis un
  fil de `concurrency.thread` lèvent `ThreadError`.
- **Signaux non interceptables** : `KILL` et `STOP` (le système l'interdit) ; `SEGV`, `BUS`, `FPE` et `ILL`
  (des fautes : reprendre après elles reproduirait la faute).
- **Erreurs** : `ArgumentError` (nom inconnu, signal non interceptable), `TypeError`, `ThreadError`,
  `ProcessError` (`send` vers un processus absent), `SignalError` (autre erreur du système).
- **Plateformes** : POSIX (Linux, macOS). Sous Windows, `supported()` vaut `false`.

Implémentation : le module natif `_native_signal` (runtime/native/signal) installe un gestionnaire C minimal
(sigaction, `SA_RESTART`). Ce gestionnaire incrémente un compteur atomique par signal, pose le drapeau
`alex::vm::signalPending` et écrit un octet dans un tube qui réveille `wait`. La VM du programme principal
teste ce drapeau en tête de boucle et appelle alors le répartiteur Alex (`_dispatch` dans system/signal.al)
dans un frame marqué : son résultat est ignoré et la pile est rendue à sa hauteur d'avant.

## Environnement

- `get_int` et `get_bool` renvoient la valeur par défaut si la variable est absente ou vide. Ils lèvent
  `ArgumentError` si la valeur est illisible. `get_bool` accepte `1/true/yes/on/oui/vrai` et
  `0/false/no/off/non/faux`, sans tenir compte de la casse.
- `set` convertit les nombres et les booléens (`true` → `"1"`).
- `expand` gère `$NOM`, `${NOM}`, `${NOM:-défaut}` (défaut si absente ou vide) et `$$` → `$`. Un `$` sans nom
  reste tel quel. Le dict `vars` facultatif a priorité sur l'environnement.
- `with_vars({"LANG": "C", "DEBUG": null}, fn)` : `null` supprime la variable le temps de `fn()`.
  L'environnement est rétabli même si `fn` lève une exception.

## Informations sur la machine

Les valeurs viennent du système (`sysconf`, `statvfs`, `getloadavg`) et, sous Linux, de `/proc` (`meminfo`,
`cpuinfo`, `uptime`, `mounts`) et `/etc/os-release`. Une information indisponible vaut `null` : ces fonctions
ne lèvent jamais d'erreur. `memory()` renvoie `total`, `available`, `free`, `used` (= total − available),
`percent_used`, `swap_total` et `swap_free`. `disk_usage` renvoie `total`, `used`, `free` et `available`
(la place encore utilisable par un utilisateur ordinaire).

Ajouts au module natif `_native_os` : `disk_usage(chemin)` et `load_average()`. Correction du module `io` :
`read_bytes` (donc `file.open(..., "rb")` et `io.stream.open_file`) lit désormais jusqu'à la fin du fichier sans
se fier à la taille annoncée, qui vaut 0 pour les fichiers de `/proc`.

## Tests

`make test-system` : `tests/system/test_system.al` (66 vérifications). Elles couvrent :

- des signaux envoyés par un autre processus pendant un calcul récursif, dont le résultat reste juste ;
- `InterruptError` avec `finally` et l'interruption de `sleep` ;
- `with_handler`, `watch`, `wait` et un gestionnaire exécuté pendant `wait` ;
- `send` vers un fils, et `ThreadError` depuis un fil ;
- l'environnement, la machine, les façades et `memory.virtual`.

Le test passe aussi sous `ALEX_GC_STRESS=50`.
