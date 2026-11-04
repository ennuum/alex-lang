# Entrées-sorties : `io.stream`, `io.pipe`, `io.console`, `io.file`

```
use io.stream as stream
use io.pipe as pipe
use io.console as console

r := pipe.pipeline([["printf", "b\na\nc\n"], ["sort"], ["head", "-n", "2"]])
print(r.stdout, r.codes)                      # "a\nb\n" [0, 0, 0]

for ligne in stream.open_file("notes.txt").lines():
    console.write_line(console.style(ligne, "green", bold=true))

if console.confirm("Continuer ?", true):
    k := console.read_key()                   # "up", "enter", "a", "ctrl+c"...
```

| Module | Rôle |
|---|---|
| `io` (existant) | `print`, `input`, `read_file`, `write_file`... et `flush()` |
| `io.file` | le module `file` sous le nom `io.file` : `read`, `write`, `append`, `read_lines`, `write_lines`, `write_atomic`, `read_bytes`, `head`, `tail`, `delete`, `open`, `with_open`... (`file` reste disponible) |
| `io.stream` | flux interchangeables : `Reader` (`read`, `read_line`, `read_until`, `read_exact`, `read_all`, `read_bytes`, `lines`, `at_end`, `close`) et `Writer` (`write`, `write_line`, `write_bytes`, `flush`, `close`). Sources : `from_string` / `StringReader`, `StringWriter` (`value()`), `open_file` / `create_file(chemin, ajout)`, `FdReader` / `FdWriter` (descripteur), `stdin()`, `stdout()`, `stderr()`, `ProcessReader` / `ProcessWriter` (processus fils). `copy(reader, writer)` |
| `io.pipe` | `Pipe()` (`reader`, `writer`, `close`), `reader_from_fd`, `writer_from_fd` ; tubes nommés `create_fifo(chemin, droits)`, `open_fifo_reader`, `open_fifo_writer(chemin, délai)` ; `pipeline(commandes, entrée, délai, check)` → `PipelineResult` (`stdout`, `codes`, `timed_out`, `ok()`) |
| `io.console` | écriture (`write`, `write_line`, `error`, `error_line`, `flush`), terminal (`is_terminal`, `size`, `colors_enabled`), styles ANSI (`style`, `rgb`, `strip_styles`, `visible_length`, `progress_bar`), curseur (`clear`, `clear_line`, `move_to`, `move_up`, `move_down`, `hide_cursor`, `show_cursor`, `bell`), saisie (`read_line`, `read_password`, `read_key`, `key_name`, `confirm`, `choose`) |

## Principes

- **Octets et texte** : les flux lisent des octets (tailles en octets) ; une `str` peut porter du binaire.
  `read(max)` ne coupe jamais un caractère UTF-8 : si `max` est plus petit que le premier caractère, ce
  caractère est rendu entier. `read_bytes` / `write_bytes` utilisent des `list[int]`.
- **Délais** : les lectures qui peuvent attendre (descripteur, processus) acceptent `timeout` en secondes
  (`null` : sans limite) et lèvent `TimeoutError`. Une chaîne ou un fichier n'attend jamais.
- **Erreurs** : `IoError` (système, avec le nom de l'erreur, `[ENOENT]`), `TimeoutError`, `TypeError` /
  `ArgumentError` (usage), `ProcessError` (`pipeline(..., check=true)` avec un code non nul).
- **Tubes et processus** : un bout de tube se donne à un processus fils (`process.Command(...).stdin(tube.reader)`
  accepte un objet ayant `.fd`, ou un entier). Le parent doit ensuite fermer sa copie pour que la fin de flux se
  propage. Les descripteurs appartiennent au processus : un bout passe d'un fil (`concurrency.thread`) à l'autre
  par son numéro (`bout.fd`, puis `pipe.reader_from_fd(fd)` dans le fil qui l'adopte).
- **`pipeline` sans shell** : chaque commande est une liste `[programme, arguments...]` ; rien n'est interprété
  (`$`, `;`, `|`, espaces), donc aucune injection n'est possible. L'entrée est envoyée et la sortie lue en
  alternance (pas de blocage mutuel, même sur de gros volumes) ; au-delà du délai total, les processus sont tués
  et `timed_out` vaut `true`. La sortie d'erreur des commandes s'affiche normalement.
- **Tubes nommés** : `open_fifo_writer` attend qu'un lecteur ait ouvert le tube (au plus `timeout` secondes) ;
  `open_fifo_reader` ouvre tout de suite.
- **Couleurs** : `style` et `rgb` n'ajoutent les codes ANSI que si la sortie est un terminal qui les accepte
  (pas de variable `NO_COLOR`, `TERM` différent de `dumb`) ; `force=true` les ajoute toujours.
- **Saisie** : `read_key` passe le terminal en mode brut le temps d'une touche (Ctrl+C est alors une touche,
  `"ctrl+c"`) ; `read_password` coupe l'écho le temps d'une ligne (Ctrl+C interrompt toujours). Le terminal
  retrouve ses réglages ensuite, y compris si le programme s'arrête net. Hors terminal (entrée redirigée),
  `read_password` lit une ligne ordinaire et `read_key` un caractère. Noms de touches : `up`, `down`, `left`,
  `right`, `home`, `end`, `insert`, `delete`, `page_up`, `page_down`, `f1`..`f4`, `enter`, `tab`,
  `backspace`, `escape`, `space`, `ctrl+a`..`ctrl+z`, sinon le caractère lui-même ; `"eof"` en fin d'entrée,
  `null` après `timeout`.

## Module natif `_native_fd`

Descripteurs POSIX (Linux, macOS ; `supported()` faux ailleurs) : `pipe` (`O_CLOEXEC`), `mkfifo`, `open_fifo`,
`read(fd, max, délai)` (→ `str`, `null` après le délai, ou `-errno`), `write`, `close` (seulement les
descripteurs ouverts par ce module), `isatty`, `set_nonblocking`, `set_mode(fd, brut, écho)` / `restore`,
`strerror`, `errno_name`.

## Tests

`make test-io` : `tests/io/test_io.al` (52 vérifications : flux, fichiers, processus, tubes entre fils et vers
un fils, tube nommé, pipeline de 1 Mio, couleurs, barre de progression) et `tests/io/console_pty.py`
(8 vérifications : flèche, caractère UTF-8, Ctrl+C, Échap, mot de passe sans écho avec correction, délai)
dans un pseudo-terminal.
