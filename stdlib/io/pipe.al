# ALEX STANDARD LIBRARY — io.pipe
#
# Tubes du système : anonymes (Pipe : un bout en lecture, un bout en écriture), nommés (FIFO : un chemin du
# système de fichiers que des processus sans lien de parenté ouvrent pour se parler), et chaînes de
# processus `a | b | c` SANS shell (pipeline : pas d'interprétation des arguments, pas d'injection possible).
#
# Les bouts de tube sont des flux io.stream (read_line, read_all, write_line...) ; ils se branchent sur un
# processus fils (process.Command(...).stdin(tube.reader)) et, étant des descripteurs du processus, passent
# d'un fil à l'autre (concurrency.thread) par leur numéro : bout.fd, puis pipe.reader_from_fd(fd).
#
# Exemple
#   use io.pipe as pipe
#   r := pipe.pipeline([["printf", "b\na\nc\n"], ["sort"], ["head", "-n", "2"]])
#   print(r.stdout)        # "a\nb\n"
#   print(r.codes)         # [0, 0, 0]
#
# Erreurs : IoError (système), TimeoutError, ProcessError (pipeline avec check=true et un code non nul).

from core use len, type
from collections use append
use _native_fd as _f
use _native_net as _b
use io.stream as _stream
from io.stream use FdReader, FdWriter
use process as _proc
use os as _os

func supported():
    return _f.supported()

func _fail(op, code):
    name := _f.errno_name(code)
    if name == "ETIMEDOUT":
        raise("TimeoutError", op + " : délai dépassé")
    raise("IoError", op + " : " + _f.strerror(code) + " [" + name + "]")

class PipeReader extends FdReader:
    func init(fd):
        super.init(fd, true)

class PipeWriter extends FdWriter:
    func init(fd, timeout=null):
        super.init(fd, true, timeout)

class Pipe:
    func init():
        if not _f.supported():
            raise("IoError", "io.pipe : non pris en charge sur cette plateforme")
        fds := _f.pipe()
        self.reader = PipeReader(fds[0])
        self.writer = PipeWriter(fds[1])

    func close():
        self.reader.close()
        self.writer.close()

# Bout de tube désigné par son descripteur (reçu d'un autre fil) ; il appartient alors à celui qui l'adopte.
func reader_from_fd(fd):
    return PipeReader(fd)

func writer_from_fd(fd):
    return PipeWriter(fd)

# ---------------------------------------------------------------- tubes nommés (FIFO)
# Crée le tube nommé path (mode : droits, 0o600 par défaut).
func create_fifo(path, mode=384):
    r := _f.mkfifo(path, mode)
    if r < 0:
        _fail("create_fifo('" + path + "')", r)

# Ouvre un tube nommé en lecture (tout de suite) ou en écriture (attend qu'un lecteur l'ait ouvert, au plus
# timeout secondes).
func open_fifo_reader(path):
    r := _f.open_fifo(path, false, null)
    if r < 0:
        _fail("open_fifo_reader('" + path + "')", r)
    return PipeReader(r)

func open_fifo_writer(path, timeout=null):
    r := _f.open_fifo(path, true, timeout)
    if r < 0:
        _fail("open_fifo_writer('" + path + "')", r)
    return PipeWriter(r)

# ---------------------------------------------------------------- chaînes de processus
class PipelineResult:
    func init(stdout, codes, timed_out):
        self.stdout = stdout
        self.codes = codes          # code de sortie de chaque commande (négatif : tuée par un signal)
        self.timed_out = timed_out

    # Vrai si toutes les commandes ont réussi (code 0).
    func ok():
        if self.timed_out:
            return false
        for c in self.codes:
            if c != 0:
                return false
        return true

func _need_commands(commands):
    if type(commands) != "list" or len(commands) == 0:
        raise("ArgumentError", "pipeline : list non vide de commandes attendue")
    for c in commands:
        if type(c) != "list" or len(c) == 0:
            raise("ArgumentError", "pipeline : chaque commande est une list [programme, arguments...]")
        for part in c:
            if type(part) != "str":
                raise("TypeError", "pipeline : programme et arguments doivent être des str")

# Exécute commands[0] | commands[1] | ... : la sortie de chacune est l'entrée de la suivante, sans shell.
# input : texte envoyé à la première (null : rien). Renvoie la sortie de la dernière et les codes de toutes.
# Les erreurs (stderr) s'affichent normalement. timeout : délai total (les processus sont alors tués).
func pipeline(commands, input=null, timeout=null, check=false):
    _need_commands(commands)
    n := len(commands)
    first_in := Pipe()
    last_out := Pipe()
    links := []
    i := 0
    while i < n - 1:
        append(links, Pipe())
        i += 1
    procs := []
    try:
        i = 0
        while i < n:
            cmd := commands[i]
            c := _proc.Command(cmd[0])
            c.args([cmd[k] for k in 1..len(cmd)])
            if i == 0:
                c.stdin(first_in.reader)
            else:
                c.stdin(links[i - 1].reader)
            if i == n - 1:
                c.stdout(last_out.writer)
            else:
                c.stdout(links[i].writer)
            append(procs, c.spawn())
            i += 1
    finally:
        # Le parent rend ses copies des bouts donnés aux fils : la fin de flux se propage le long de la chaîne.
        first_in.reader.close()
        last_out.writer.close()
        for l in links:
            l.close()
    # Envoi de l'entrée et lecture de la sortie entrelacés (jamais de blocage mutuel), délai total ; seuls les
    # bouts du parent sont non bloquants (les fils gardent des flux ordinaires).
    _f.set_nonblocking(first_in.writer.fd, true)
    _f.set_nonblocking(last_out.reader.fd, true)
    pending := ""
    if input != null:
        pending = str(input)
    out := _stream.StringWriter()
    timed_out := false
    started := _os.monotonic_time()
    input_open := true
    while true:
        if input_open:
            if pending == "":
                first_in.writer.close()
                input_open = false
            else:
                k := _f.write(first_in.writer.fd, pending, 0.02)
                if k > 0:
                    pending = _b.bslice(pending, k, _b.blen(pending))
                elif k < 0 and _f.errno_name(k) == "EPIPE":
                    first_in.writer.close()
                    input_open = false
        chunk := _f.read(last_out.reader.fd, 65536, 0.02)
        if type(chunk) == "str":
            if chunk == "":
                break
            out.write(chunk)
        elif type(chunk) == "int":
            break
        if timeout != null and _os.monotonic_time() - started > timeout:
            timed_out = true
            break
    if input_open:
        first_in.writer.close()
    last_out.reader.close()
    codes := []
    for p in procs:
        if timed_out:
            p.kill("KILL")
        append(codes, p.wait())
        p.close()
    r := PipelineResult(out.value(), codes, timed_out)
    if check and not r.ok():
        if timed_out:
            raise("TimeoutError", "pipeline : délai dépassé")
        raise("ProcessError", "pipeline : codes de sortie " + str(codes))
    return r
