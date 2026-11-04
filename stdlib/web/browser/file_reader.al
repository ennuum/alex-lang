# ALEX STANDARD LIBRARY — web.browser.file_reader
#
# FileReader : lecture ASYNCHRONE d'un Blob / File en texte, URL data:, octets ou chaîne binaire, avec les
# événements loadstart, progress, load, loadend (ou abort / error) distribués par la boucle d'événements,
# comme dans un navigateur.
#
#   use web.browser.file_reader as fr
#   r := fr.FileReader(loop)
#   r.add_event_listener("load", (e) => print(r.result))
#   r.read_as_text(fichier)
#   loop.run_until_idle()              # affiche le texte
#   r.ready_state == fr.DONE           # true
#   fr.read_text(loop, fichier).wait() # forme promesse
#
# Erreurs : InvalidStateError (lecture déjà en cours), TypeError (objet qui n'est pas un Blob).

from core use len, type
from collections use append
use string as _s
use web.browser.browser_errors as _err
use web.browser.blob as _blob
use web.browser.timers as _tm
use web.dom.event as _ev
use web.dom.event_target as _et
from web.dom.event_target use EventTarget
from web.dom.event use Event

const EMPTY := 0
const LOADING := 1
const DONE := 2

class ProgressEvent extends Event:
    func init(event_type, loaded=0, total=0):
        super.init(event_type)
        self.length_computable = total > 0
        self.loaded = loaded
        self.total = total

class FileReader extends EventTarget:
    func init(loop=null):
        super.init()
        self.loop = loop if loop != null else _tm.default_loop()
        self.ready_state = EMPTY
        self.result = null
        self.error = null
        self.aborted = false
        self.job = 0

    func _start(blob, kind, encoding):
        if self.ready_state == LOADING:
            _err.invalid_state("FileReader", "lecture déjà en cours")
        if not isinstance(blob, _blob.Blob):
            _err.type_error("FileReader", "Blob ou File attendu")
        self.ready_state = LOADING
        self.result = null
        self.error = null
        self.aborted = false
        self.job += 1
        job := self.job
        r := self
        self.loop.queue_task(() => r._run(job, blob, kind, encoding))

    func _fire(event_type, loaded, total):
        _et.dispatch(self, ProgressEvent(event_type, loaded, total), true)

    func _run(job, blob, kind, encoding):
        if job != self.job or self.aborted:
            return
        total := blob.size
        self._fire("loadstart", 0, total)
        if kind == "text":
            self.result = blob.text_now()
        elif kind == "data_url":
            self.result = blob.to_data_url()
        elif kind == "array_buffer":
            self.result = blob.bytes()
        else:
            parts := []
            for b in blob.bytes():
                append(parts, str(_s.chr(b)))
            self.result = _s.join("", parts)
        self.ready_state = DONE
        self._fire("progress", total, total)
        self._fire("load", total, total)
        self._fire("loadend", total, total)

    func read_as_text(blob, encoding="utf-8"):
        self._start(blob, "text", encoding)

    func read_as_data_url(blob):
        self._start(blob, "data_url", null)

    func read_as_array_buffer(blob):
        self._start(blob, "array_buffer", null)

    func read_as_binary_string(blob):
        self._start(blob, "binary", null)

    func abort():
        if self.ready_state != LOADING:
            return
        self.aborted = true
        self.ready_state = DONE
        self.result = null
        self.error = _err.ErrorValue(_err.ABORT, "lecture annulée")
        self._fire("abort", 0, 0)
        self._fire("loadend", 0, 0)

func _read(loop, blob, kind):
    lp := loop if loop != null else _tm.default_loop()
    p := _tm.Promise(lp)
    r := FileReader(lp)
    r.add_event_listener("load", (e) => p.resolve(r.result))
    r.add_event_listener("abort", (e) => p.reject(r.error))
    if kind == "text":
        r.read_as_text(blob)
    elif kind == "data_url":
        r.read_as_data_url(blob)
    else:
        r.read_as_array_buffer(blob)
    return p

func read_text(loop, blob):
    return _read(loop, blob, "text")

func read_data_url(loop, blob):
    return _read(loop, blob, "data_url")

func read_bytes(loop, blob):
    return _read(loop, blob, "array_buffer")
