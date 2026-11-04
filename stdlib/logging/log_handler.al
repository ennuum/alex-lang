# ALEX STANDARD LIBRARY — logging.log_handler
#
# Gestionnaires (handlers) : OÙ vont les enregistrements. Un Handler a un niveau minimal, un formateur et des
# filtres ; les sous-classes redéfinissent emit(texte, enregistrement).
#   Handler          base (à étendre : emit)
#   FunctionHandler  appelle fn(texte, enregistrement)
#   ListHandler      garde les enregistrements en mémoire (tests, affichage dans une interface)
#   MemoryHandler    tamponne puis transmet à une cible : quand le tampon est plein, ou dès qu'un enregistrement
#                    atteint flush_level (le contexte qui précède une erreur est ainsi conservé)
#   NullHandler      ne fait rien
#   Filter           filtres : par préfixe de nom, plage de niveaux, prédicat
#
#   use logging.log_handler as lh
#   mem := lh.ListHandler()
#   journal.add_handler(mem)
#   print(mem.messages())
#   h := lh.FunctionHandler((txt, r) => envoyer(txt), "ERROR")
#   h.add_filter(lh.Filter("app.db"))          # seulement app.db et ses descendants
#
# Erreurs : une exception dans emit est comptée (errors) et signalée une fois sur la sortie d'erreur ; elle
# n'interrompt jamais le programme.

from core use len, type
from collections use append
use string as _s
use io.stream as _st
use logging.log_level as _lv
use logging.log_formatter as _lf

class Filter:
    # name : préfixe de logger (« app » accepte app et app.*) ; min_level / max_level ; predicate(record).
    func init(name=null, min_level=null, max_level=null, predicate=null):
        self.name = name
        self.min_level = min_level
        self.max_level = max_level
        self.predicate = predicate

    func accepts(r):
        if self.name != null and self.name != "":
            if not (r.name == self.name or _s.starts_with(r.name, self.name + ".")):
                return false
        if self.min_level != null and r.level < _lv.parse(self.min_level):
            return false
        if self.max_level != null and r.level > _lv.parse(self.max_level):
            return false
        if self.predicate != null and not self.predicate(r):
            return false
        return true

class Handler:
    func init(level=0, formatter=null):
        self.level = _lv.parse(level)
        self.formatter = formatter
        if self.formatter == null:
            self.formatter = _lf.Formatter()
        self.filters = []
        self.errors = 0
        self.handled = 0
        self._warned = false
        self.closed = false

    func set_level(level):
        self.level = _lv.parse(level)
        return self

    func set_formatter(f):
        self.formatter = f
        return self

    func add_filter(f):
        append(self.filters, f)
        return self

    func accepts(r):
        if r.level < self.level:
            return false
        for f in self.filters:
            if not f.accepts(r):
                return false
        return true

    func format(r):
        return self.formatter.format(r)

    # À redéfinir.
    func emit(text, r):
        return null

    func handle(r):
        if self.closed or not self.accepts(r):
            return false
        try:
            self.emit(self.format(r), r)
            self.handled += 1
        catch e:
            self.errors += 1
            if not self._warned:
                self._warned = true
                try:
                    _st.stderr().write_line("logging : échec d'émission (" + e.type + " : " + e.message + ")")
                catch e2:
                    pass
        return true

    func flush():
        return null

    func close():
        self.flush()
        self.closed = true

class FunctionHandler extends Handler:
    func init(fn, level=0, formatter=null):
        super.init(level, formatter)
        self.fn = fn

    func emit(text, r):
        self.fn(text, r)

class NullHandler extends Handler:
    func init():
        super.init(0)

    func handle(r):
        return false

class ListHandler extends Handler:
    func init(level=0, formatter=null, capacity=null):
        super.init(level, formatter)
        self.records = []
        self.lines = []
        self.capacity = capacity

    func emit(text, r):
        append(self.records, r)
        append(self.lines, text)
        if self.capacity != null and len(self.records) > self.capacity:
            self.records = self.records[1:]
            self.lines = self.lines[1:]

    func messages():
        return [r.message() for r in self.records]

    func levels():
        return [r.level_name for r in self.records]

    func clear():
        self.records = []
        self.lines = []

    func contains(text):
        for m in self.messages():
            if _s.contains(m, text):
                return true
        return false

class MemoryHandler extends Handler:
    func init(target, capacity=100, flush_level="ERROR", level=0):
        super.init(level)
        self.target = target
        self.capacity = capacity
        self.flush_level = _lv.parse(flush_level)
        self.buffer = []

    func handle(r):
        if self.closed or not self.accepts(r):
            return false
        append(self.buffer, r)
        if len(self.buffer) >= self.capacity or r.level >= self.flush_level:
            self.flush()
        return true

    func flush():
        b := self.buffer
        self.buffer = []
        for r in b:
            self.target.handle(r)
        self.target.flush()

    func close():
        self.flush()
        self.closed = true
