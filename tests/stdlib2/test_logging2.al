# Tests : logging.logger, log_level, log_record, log_formatter, log_handler, console_handler, file_handler,
# rotating_handler, logging_errors.
from core use len, type
from collections use append
use check as t
use os
use io
use string
use json
use filesystem as fs
use logging.logger as lg
use logging.log_level as lv
use logging.log_record as lr
use logging.log_formatter as lf
use logging.log_handler as lh
use logging.console_handler as ch
use logging.file_handler as fh
use logging.rotating_handler as rh

lr.set_clock(() => 1700000000)

# level
t.eq(lv.parse("warning"), 30, "parse")
t.eq(lv.parse("WARN"), 30, "warn")
t.eq(lv.name_of(40), "ERROR", "name_of")
t.eq(lv.name_of(33), "WARNING", "name_of intermédiaire")
lv.register("AUDIT", 35)
t.eq(lv.parse("audit"), 35, "register")
t.check(lv.is_enabled("INFO", "audit"), "is_enabled")
t.raises(() => lv.parse("bavard"), "ValueError", "inconnu")
t.check(len(lv.color("ERROR")) > 0, "color")

# record
r := lr.LogRecord("app.db", 30, "requête lente : {} ms ({table})", [812], {"table": "clients"})
t.eq(r.message(), "requête lente : 812 ms (clients)", "substitution")
t.eq(r.level_name, "WARNING", "level_name")
t.eq(r.iso_time(), "2023-11-14T22:13:20.000Z", "iso_time")
t.eq(lr.render("{1}-{0}-{x}-{}", ["a", "b"], {}), "b-a-{x}-a", "render")
t.eq(r.to_dict()["table"], "clients", "to_dict")
func fail():
    raise("IoError", "disque")
rx := null
try:
    fail()
catch e:
    rx = lr.from_exception("app", 40, "échec", e)
    t.eq(rx.exc_type, "IoError", "from_exception")
    t.check(type(rx.exc_trace) == "list", "trace")

# formatter
f := lf.Formatter("{time} [{level:8}] {name}: {message} {extra}", "utc")
t.eq(f.format(r), "2023-11-14 22:13:20 [WARNING ] app.db: requête lente : 812 ms (clients) table=clients", "Formatter")
t.eq(lf.Formatter("{level} {table}").format(r), "WARNING clients", "champ extra")
jd := json.parse(lf.JsonFormatter("epoch").format(r))
t.eq([jd["level"], jd["table"], jd["time"]], ["WARNING", "clients", "1700000000"], "JsonFormatter")
t.eq(lf.KeyValueFormatter("epoch").format(r), "time=1700000000 level=warning name=app.db msg=\"requête lente : 812 ms (clients)\" table=clients", "KeyValueFormatter")
t.check(string.contains(lf.ColorFormatter("{level}").format(r), "\u001b["), "ColorFormatter")
t.check(string.contains(lf.Formatter("{message}").format(rx), "IoError : disque"), "exception ajoutée")

# handlers + logger
lg.reset()
root := lg.root()
mem := lh.ListHandler()
root.add_handler(mem)
root.set_level("DEBUG")
log := lg.get_logger("app.db")
t.eq(log.effective_level(), 10, "niveau hérité")
log.info("connexion à {}", ["db1"])
t.eq(mem.messages(), ["connexion à db1"], "propagation")
log.set_level("WARNING")
log.info("caché")
log.warning("visible")
t.eq(len(mem.records), 2, "niveau du logger")
own := lh.ListHandler()
log.add_handler(own)
log.propagate = false
log.error("seulement ici")
t.eq(len(own.records), 1, "handler propre")
t.eq(len(mem.records), 2, "propagate=false")
log.propagate = true
try:
    fail()
catch e2:
    log.exception("échec requête", e2)
t.eq(own.records[1].exc_type, "IoError", "exception()")
t.eq(own.records[1].level_name, "ERROR", "exception niveau")
b := log.bind({"req": 42})
b.warning("avec contexte")
t.eq(own.records[2].extra["req"], 42, "bind")
t.eq(b.bind({"u": 1}).logger.name, "app.db", "bind imbriqué")
t.check(lg.get_logger("app.db") == log, "même objet")
t.eq(log.child("pool").name, "app.db.pool", "child")
t.eq(lg.get_logger("app.db.pool").parent.name, "app.db", "parent")
flt := lh.ListHandler()
flt.add_filter(lh.Filter("app.web"))
root.add_handler(flt)
lg.get_logger("app.web.api").warning("w")
lg.get_logger("app.db").warning("d")
t.eq(flt.messages(), ["w"], "Filter nom")
lvlf := lh.ListHandler()
lvlf.add_filter(lh.Filter(null, "WARNING", "WARNING"))
root.add_handler(lvlf)
log.error("e")
log.warning("w2")
t.eq(lvlf.messages(), ["w2"], "Filter niveaux")
calls := []
root.add_handler(lh.FunctionHandler((txt, rec) => append(calls, rec.level), "CRITICAL"))
log.critical("c")
t.eq(calls, [50], "FunctionHandler + niveau")
bad := lh.FunctionHandler((txt, rec) => fail())
root.add_handler(bad)
log.warning("ne casse rien")
t.eq(bad.errors, 1, "erreur d'émission comptée")
root.remove_handler(bad)
target := lh.ListHandler()
memh := lh.MemoryHandler(target, 10, "ERROR")
mlog := lg.get_logger("mem")
mlog.propagate = false
mlog.add_handler(memh)
mlog.info("a")
mlog.info("b")
t.eq(len(target.records), 0, "MemoryHandler tamponne")
mlog.error("boom")
t.eq(target.messages(), ["a", "b", "boom"], "MemoryHandler vide au niveau ERROR")
t.raises(() => log.add_handler(5), "LoggingError", "handler invalide")
with lg.timed(log, "étape", "WARNING"):
    os.sleep(0.01)
t.check(string.contains(own.records[len(own.records) - 1].message(), "étape"), "timed")
t.check(own.records[len(own.records) - 1].extra["duration_ms"] >= 5, "durée")

# fichiers
tmp := fs.make_temp_dir()
fp := os.join(os.join(tmp, "sous"), "app.log")
fh1 := fh.FileHandler(fp, "a", 0, lf.Formatter("{level} {message}"))
flog := lg.get_logger("fichier")
flog.propagate = false
flog.add_handler(fh1)
flog.warning("un")
flog.error("deux")
t.eq(io.read_file(fp), "WARNING un\nERROR deux\n", "FileHandler")
t.eq(fh1.lines_written, 2, "lines_written")
rp := os.join(tmp, "rot.log")
rot := rh.RotatingFileHandler(rp, 30, 2, 0, lf.Formatter("{message}"))
rlog := lg.get_logger("rot")
rlog.propagate = false
rlog.add_handler(rot)
i := 0
while i < 10:
    rlog.warning("message numéro " + str(i))
    i += 1
t.eq(len(rot.backups()), 2, "rotation : 2 sauvegardes")
t.check(rot.rotations >= 4, "rotations")
t.check(os.size(rp) <= 30, "taille bornée")
t.eq(io.read_file(rp), "message numéro 9\n", "fichier courant")
now := [1700000000]
lr.set_clock(() => now[0])
tp := os.join(tmp, "jour.log")
tr := rh.TimedRotatingFileHandler(tp, "hourly", 3, 0, lf.Formatter("{message}"))
tlog := lg.get_logger("temps")
tlog.propagate = false
tlog.add_handler(tr)
tlog.warning("h1")
now[0] = now[0] + 3600
tlog.warning("h2")
t.eq(tr.rotations, 1, "rotation horaire")
t.eq(io.read_file(tp + ".1"), "h1\n", "ancienne heure")
t.raises(() => rh.TimedRotatingFileHandler(tp, "parfois"), "LoggingError", "période inconnue")

# console
c := ch.ConsoleHandler("INFO", "stdout", false)
t.check(not c.color, "pas de couleur hors terminal")
t.raises(() => ch.ConsoleHandler(0, "imprimante"), "ArgumentError", "flux inconnu")
lg.reset()
lg.basic_config("INFO", "{level}: {message}")
t.eq(lg.root().effective_level(), 20, "basic_config")
lg.get_logger("demo").info("message console de démonstration")

fs.remove_tree(tmp)
t.summary("logging2")
