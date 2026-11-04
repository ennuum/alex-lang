# ALEX STANDARD LIBRARY — ipc.ipc_message
#
# Message interprocessus STRUCTURÉ et auto-descriptif : enveloppe (identifiant, sujet, expéditeur, date,
# corrélation pour les réponses, en-têtes) + charge utile JSON, avec version de format, empreinte
# d'intégrité (Adler-32) et taille maximale. Transportable par n'importe quel canal qui envoie des chaînes :
# file de messages, socket local, tube, mémoire partagée.
#
#   use ipc.ipc_message as msg
#   m := msg.IpcMessage("travail.nouveau", {"id": 42, "fichier": "a.csv"})
#   m.set_header("priorite", "haute")
#   data := m.encode()                         # str (JSON compact + empreinte)
#   r := msg.decode(data)                      # MessageError si altéré
#   print(r.topic, r.payload["id"], r.sender)
#   rep := r.reply({"ok": true})               # correlation_id = r.id, sujet « travail.nouveau.reponse »
#   print(rep.is_reply_to(r))                  # true
#   q := ipc.message_queue("travaux")
#   msg.send(q, m)                             # q.send(m.encode())
#   x := msg.receive(q, 1.0)
#
# Erreurs : MessageError (format, version, empreinte, taille), TypeError.

from core use len, type, to_int
from collections use append
use string as _s
use json as _json
use os as _os
use ipc.ipc_errors as _e

const FORMAT := "alex-ipc"
const VERSION := 1
const MAX_SIZE := 16777216     # 16 Mio

_counter := [0]

func _new_id():
    _counter[0] += 1
    return str(_os.pid()) + "-" + str(to_int(_os.time() * 1000)) + "-" + str(_counter[0])

# Adler-32 des octets de text.
func checksum(text):
    a := 1
    b := 0
    for byte in _s.byte_unpack(text):
        a = (a + byte) % 65521
        b = (b + a) % 65521
    return (b << 16) | a

class IpcMessage:
    func init(topic, payload=null, headers=null):
        if type(topic) != "str" or topic == "":
            raise("TypeError", "IpcMessage : sujet (str non vide) attendu")
        self.id = _new_id()
        self.topic = topic
        self.payload = payload
        self.headers = {}
        if headers != null:
            for k in headers:
                self.headers[k] = headers[k]
        self.sender = _os.pid()
        self.timestamp = _os.time()
        self.correlation_id = null
        self.reply_to = null

    func set_header(name, value):
        self.headers[name] = value
        return self

    func header(name, default=null):
        if name in self.headers:
            return self.headers[name]
        return default

    # Message de réponse corrélé à celui-ci.
    func reply(payload=null, topic=null):
        t := topic
        if t == null:
            t = self.topic + ".reponse"
        r := IpcMessage(t, payload)
        r.correlation_id = self.id
        return r

    func is_reply_to(other):
        return self.correlation_id != null and self.correlation_id == other.id

    func age():
        return _os.time() - self.timestamp

    func to_dict():
        return {"format": FORMAT, "version": VERSION, "id": self.id, "topic": self.topic, "sender": self.sender,
                "timestamp": self.timestamp, "correlation_id": self.correlation_id, "reply_to": self.reply_to,
                "headers": self.headers, "payload": self.payload}

    func encode(max_size=MAX_SIZE):
        body := _json.stringify(self.to_dict())
        out := str(checksum(body)) + ":" + body
        if _s.byte_len(out) > max_size:
            _e.message_error("IpcMessage.encode", "message de " + str(_s.byte_len(out)) + " octets > " + str(max_size))
        return out

    func size():
        return _s.byte_len(self.encode())

    func __str__():
        return "IpcMessage(" + self.topic + ", #" + self.id + ")"

func from_dict(d):
    if not ("format" in d) or d["format"] != FORMAT:
        _e.message_error("ipc_message.decode", "format inconnu")
    if d["version"] > VERSION:
        _e.message_error("ipc_message.decode", "version " + str(d["version"]) + " non prise en charge (max " + str(VERSION) + ")")
    m := IpcMessage(d["topic"], d["payload"], d["headers"])
    m.id = d["id"]
    m.sender = d["sender"]
    m.timestamp = d["timestamp"]
    m.correlation_id = d["correlation_id"]
    m.reply_to = d["reply_to"]
    return m

func decode(data, max_size=MAX_SIZE):
    if type(data) != "str":
        raise("TypeError", "ipc_message.decode : str attendue (obtenu '" + type(data) + "')")
    if _s.byte_len(data) > max_size:
        _e.message_error("ipc_message.decode", "message trop grand")
    i := _s.find(data, ":")
    if i <= 0:
        _e.message_error("ipc_message.decode", "empreinte absente")
    sum_text := _s.substring(data, 0, i)
    body := _s.substring(data, i + 1, len(data))
    expected := 0
    try:
        expected = to_int(sum_text)
    catch e:
        _e.message_error("ipc_message.decode", "empreinte illisible")
    if checksum(body) != expected:
        _e.message_error("ipc_message.decode", "empreinte invalide : message altéré ou tronqué")
    d := null
    try:
        d = _json.parse(body)
    catch e2:
        _e.message_error("ipc_message.decode", "JSON invalide : " + e2.message)
    if type(d) != "dict":
        _e.message_error("ipc_message.decode", "objet JSON attendu")
    return from_dict(d)

func is_valid(data):
    try:
        decode(data)
        return true
    catch e:
        return false

# Envoie m par un canal doté de send(str) (file, socket, tube...).
func send(channel, m):
    channel.send(m.encode())

# Reçoit un IpcMessage d'un canal doté de receive(timeout) ; null si rien (délai).
func receive(channel, timeout=null):
    data := null
    try:
        data = channel.receive(timeout)
    catch TimeoutError:
        return null
    if data == null or data == "":
        return null
    return decode(data)

# Filtre : messages dont le sujet commence par prefix (« travail. »).
func matches(m, pattern):
    if _s.ends_with(pattern, "*"):
        return _s.starts_with(m.topic, _s.substring(pattern, 0, len(pattern) - 1))
    return m.topic == pattern
