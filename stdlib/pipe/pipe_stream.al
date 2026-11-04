# ALEX STANDARD LIBRARY — pipe.pipe_stream
#
# Flux structurés au-dessus d'un tube (ou de tout couple io.stream Reader / Writer) : lignes, MESSAGES délimités
# (préfixe de longueur : un message n'est jamais coupé ni collé au suivant), valeurs JSON ; attente sur
# plusieurs tubes à la fois (poll), copie, duplication (tee).
#
#   use pipe.pipe_stream as ps
#   use pipe.anonymous_pipe as ap
#   t := ap.AnonymousPipe()
#   s := ps.PipeStream(t.reader, t.writer)
#   s.send_message("un\nmessage\nsur plusieurs lignes")
#   s.send_json({"cmd": "start", "n": 3})
#   print(s.receive_message(1.0))              # le texte exact
#   print(s.receive_json(1.0)["cmd"])          # « start »
#   prets := ps.poll([t1.reader, t2.reader], 0.5)   # lecteurs qui ont des données
#
# Format d'un message : « <longueur en octets>\n<octets> ». Il convient au texte comme au binaire et se lit
# facilement depuis un autre langage.
#
# Erreurs : ProtocolError (message mal formé ou trop grand), IoError, TimeoutError, TypeError.

from core use len, type, to_int
from collections use append
use json as _json
use _native_fd as _f
use _native_net as _b

const MAX_MESSAGE := 67108864   # 64 Mio

class PipeStream:
    # reader / writer : flux io.stream (null : sens absent).
    func init(reader, writer=null, max_message=MAX_MESSAGE):
        self.reader = reader
        self.writer = writer
        self.max_message = max_message

    func _need_writer():
        if self.writer == null:
            raise("IoError", "PipeStream : pas de sens écriture")
        return self.writer

    func _need_reader():
        if self.reader == null:
            raise("IoError", "PipeStream : pas de sens lecture")
        return self.reader

    func send(text):
        return self._need_writer().write(text)

    func send_line(text):
        return self._need_writer().write_line(text)

    func receive(max=65536, timeout=null):
        return self._need_reader().read(max, timeout)

    func receive_line(timeout=null):
        return self._need_reader().read_line(timeout)

    # Un message (str, texte ou octets) avec sa longueur : l'autre bout le reçoit en entier.
    func send_message(data):
        if type(data) != "str":
            raise("TypeError", "PipeStream.send_message : str attendue (obtenu '" + type(data) + "')")
        n := _b.blen(data)
        if n > self.max_message:
            raise("ProtocolError", "PipeStream.send_message : message de " + str(n) + " octets (maximum " + str(self.max_message) + ")")
        return self._need_writer().write(str(n) + "\n" + data)

    # Le message suivant ; null : fin du flux entre deux messages.
    func receive_message(timeout=null):
        r := self._need_reader()
        head := r.read_until("\n", timeout, 32)
        if head == null:
            return null
        n := null
        try:
            n = to_int(head)
        catch e:
            raise("ProtocolError", "PipeStream.receive_message : en-tête invalide '" + head + "'")
        if n < 0 or n > self.max_message:
            raise("ProtocolError", "PipeStream.receive_message : longueur " + str(n) + " hors limites")
        if n == 0:
            return ""
        try:
            return r.read_exact(n, timeout)
        catch IoError as e:
            raise("ProtocolError", "PipeStream.receive_message : flux fermé au milieu d'un message")

    # Valeur JSON (dict, list, str, nombre, bool, null) en un message.
    func send_json(value):
        return self.send_message(_json.stringify(value))

    func receive_json(timeout=null):
        m := self.receive_message(timeout)
        if m == null:
            raise("IoError", "PipeStream.receive_json : fin du flux")
        return _json.parse(m)

    # Envoie une requête JSON et attend la réponse (protocole question / réponse).
    func request(value, timeout=null):
        self.send_json(value)
        return self.receive_json(timeout)

    func close():
        if self.reader != null:
            self.reader.close()
        if self.writer != null:
            self.writer.close()

# Descripteur système d'un flux (FdReader, bout de tube, extrémité duplex), ou null.
func _fd_of(stream):
    fd := null
    try:
        fd = stream.fd
    catch e:
        fd = null
    if type(fd) == "function":
        fd = stream.fd()
    if type(fd) == "int":
        return fd
    try:
        return _fd_of(stream.reader)
    catch e:
        return null

func _buffered(stream):
    r := stream
    try:
        r = stream.reader
    catch e:
        r = stream
    try:
        return _b.blen(r._buffer) > 0
    catch e:
        return false

# Parmi les flux (lecteurs de tubes, extrémités duplex...), ceux qui ont des données à lire (ou la fin du flux),
# sans attendre plus de timeout secondes (null : jusqu'au premier prêt). Liste dans l'ordre d'origine.
func poll(streams, timeout=null):
    ready := [s for s in streams if _buffered(s)]
    if len(ready) > 0:
        return ready
    items := []
    for s in streams:
        fd := _fd_of(s)
        if fd == null:
            raise("TypeError", "pipe_stream.poll : flux sans descripteur système")
        append(items, [fd, "r"])
    r := _f.poll(items, timeout)
    if type(r) == "int":
        raise("IoError", "pipe_stream.poll : " + _f.strerror(r))
    out := []
    for s in streams:
        fd := _fd_of(s)
        for pair in r:
            if pair[0] == fd:
                append(out, s)
                break
    return out

# Copie tout reader dans writer ; renvoie le nombre d'octets.
func copy(reader, writer, chunk=65536):
    total := 0
    while true:
        data := reader.read(chunk)
        if data == "":
            return total
        writer.write(data)
        total += _b.blen(data)

# Copie reader dans chacun des writers (comme `tee`) ; renvoie le nombre d'octets.
func tee(reader, writers, chunk=65536):
    total := 0
    while true:
        data := reader.read(chunk)
        if data == "":
            return total
        for w in writers:
            w.write(data)
        total += _b.blen(data)
