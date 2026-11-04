# ALEX STANDARD LIBRARY — multimedia.diagnostics.logging
#
# Journal des traitements multimédias : niveaux (debug, info, warning, error), catégorie (« demux », « player »...),
# champs structurés, mémoire bornée des derniers messages, sortie vers une fonction (console, fichier, interface).
# Les avertissements des MediaInfo (fichier tronqué, page corrompue...) s'y versent par log_warnings().
#
#   use multimedia.diagnostics.logging as mlog
#   j := mlog.MediaLog("info", 200)
#   j.sink = (ligne) => print(ligne)
#   j.info("player", "lecture", {"fichier": "a.flac"})
#   j.log_warnings("probe", info)
#   print(j.count("warning"), j.recent(5))

from core use len
from collections use append, keys
use time as _t
use string as _s

const LEVELS := {"debug": 10, "info": 20, "warning": 30, "error": 40}

class MediaLog:
    func init(level="info", capacity=500, clock=null):
        self.level = LEVELS[level] if level in LEVELS else 20
        self.capacity = capacity
        self.entries = []
        self.sink = null
        self.counts = {"debug": 0, "info": 0, "warning": 0, "error": 0}
        self.clock = clock if clock != null else () => _t.time()

    func log(level, category, message, fields=null):
        if not (level in LEVELS) or LEVELS[level] < self.level:
            return null
        e := {"time": self.clock(), "level": level, "category": category, "message": message, "fields": fields if fields != null else {}}
        append(self.entries, e)
        if len(self.entries) > self.capacity:
            self.entries = [self.entries[k] for k in len(self.entries) - self.capacity..len(self.entries)]
        self.counts[level] = self.counts[level] + 1
        if self.sink != null:
            self.sink(format(e))
        return e

    func debug(category, message, fields=null):
        return self.log("debug", category, message, fields)

    func info(category, message, fields=null):
        return self.log("info", category, message, fields)

    func warning(category, message, fields=null):
        return self.log("warning", category, message, fields)

    func error(category, message, fields=null):
        return self.log("error", category, message, fields)

    func log_warnings(category, media_info):
        for w in media_info.warnings:
            self.warning(category, w, {"path": media_info.path})

    func count(level):
        return self.counts[level] if level in self.counts else 0

    func recent(n=10):
        k := len(self.entries) - n
        if k < 0:
            k = 0
        return [format(self.entries[i]) for i in k..len(self.entries)]

func format(e):
    f := ""
    for k in keys(e["fields"]):
        f = f + " " + str(k) + "=" + str(e["fields"][k])
    return _s.upper(e["level"]) + " [" + e["category"] + "] " + e["message"] + f
