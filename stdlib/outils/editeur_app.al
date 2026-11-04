# ALEX STANDARD LIBRARY — outils.editeur_app
#
# Éditeur de code d'Alex (commande `alex edit`), écrit avec ui.view : la même application dans le terminal
# et dans une fenêtre.
#   - arbre des fichiers du dossier, plusieurs fichiers ouverts (onglets), coloration, marques d'erreur ;
#   - Fichier : nouveau (Ctrl+N), ouvrir (Ctrl+O), enregistrer (Ctrl+S), enregistrer sous (Ctrl+Maj+S),
#     fermer (Ctrl+W), quitter (Ctrl+Q, avec confirmation si des modifications ne sont pas enregistrées) ;
#   - Édition : annuler, rétablir, couper, copier, coller, tout sélectionner, rechercher, aller à la ligne,
#     commenter ;
#   - Exécuter : lancer (F5 : enregistre puis `alexc run`, sortie en direct dans le panneau du bas, arrêt par
#     Ctrl+F5 / F5 encore), vérifier (F7 : `alexc check`) ; les erreurs deviennent des marques dans le code.
#     Pendant l'exécution, la ligne « Entrée » sous la sortie envoie du texte à l'entrée standard du programme
#     (input() le reçoit) ; F8 ou « Fin » ferme l'entrée (fin de fichier).
#   - Édition : coloration des chaînes / commentaires sur plusieurs lignes, pliage des blocs (F4, Maj+F4,
#     Ctrl+F4, triangles de la marge) et complétion (F8space, ou en tapant) : voir ui.view.code_editor.
#
#   use outils.editeur_app as ed
#   studio := ed.Studio(".", ["main.al"])
#   tui.run(studio.vue, "Éditeur Alex", "dark", null, studio.tick, 0.1)

from core use len, type, to_int
from collections use append, pop, contains_key, sort
use string as _s
use os as _os
use file as _file
use process as _proc
use json as _json
use ui.view as v
use ui.view.syntax as _syn

const _IGNORE := ["build", "build-tsan", "node_modules", "__pycache__", "alex_packages"]

func _hidden(name):
    if _s.starts_with(name, "."):
        return true
    if _s.ends_with(name, ".albc") or _s.ends_with(name, ".al.meta") or _s.ends_with(name, ".o") or _s.ends_with(name, ".d"):
        return true
    for x in _IGNORE:
        if name == x:
            return true
    return false

func _join(a, b):
    if a == "." or a == "":
        return b
    if _s.ends_with(a, "/"):
        return a + b
    return a + "/" + b

func _basename(p):
    return _os.basename(p)

# Arbre des fichiers sous root (dossiers d'abord, au plus depth niveaux et limit entrées).
func file_tree(root, depth=4, limit=600):
    count := [0]
    return _tree(root, depth, limit, count)

func _tree(dir, depth, limit, count):
    out := []
    names := []
    try:
        names = _os.list_dir(dir)
    catch e:
        return out
    sort(names)
    dirs := []
    files := []
    for nm in names:
        if _hidden(nm):
            continue
        p := _join(dir, nm)
        if _os.isdir(p):
            append(dirs, [nm, p])
        else:
            append(files, [nm, p])
    for d in dirs:
        if count[0] >= limit:
            break
        count[0] += 1
        kids := _tree(d[1], depth - 1, limit, count) if depth > 1 else []
        append(out, {"label": d[0] + "/", "id": d[1], "children": kids, "dir": true})
    for f in files:
        if count[0] >= limit:
            break
        count[0] += 1
        append(out, {"label": f[0], "id": f[1], "dir": false})
    return out

# Marques d'erreur dans la sortie d'Alex pour le fichier path : list de {"line", "message", "kind"}.
#   « SyntaxError: chemin/f.al:12:5: message »  ou une trace « chemin/f.al:12, dans g » suivie de
#   « TypeError: message ».
func parse_errors(output, path):
    out := []
    base := _basename(path)
    lines := _s.split(output, "\n")
    trace_line := -1
    i := 0
    while i < len(lines):
        l := lines[i]
        k := _s.find(l, base + ":")
        if k >= 0:
            rest := _s.slice(l, k + len(base) + 1)
            num := _digits(rest)
            if num > 0:
                after := _s.slice(rest, len(str(num)))
                if _s.starts_with(after, ":"):
                    # forme fichier:ligne:colonne: message
                    msg := after
                    m2 := _s.find(_s.slice(after, 1), ": ")
                    if m2 >= 0:
                        msg = _s.slice(after, m2 + 3)
                    head := _s.slice(l, 0, k)
                    t := _s.trim(head)
                    if _s.ends_with(t, ":"):
                        msg = _s.slice(t, 0, len(t) - 1) + " : " + msg
                    append(out, {"line": num, "message": _s.trim(msg), "kind": "error"})
                elif _s.starts_with(after, ", dans"):
                    trace_line = num
        elif trace_line > 0 and _s.contains(l, "Error") and _s.contains(l, ": ") and not _s.starts_with(l, " "):
            append(out, {"line": trace_line, "message": _s.trim(l), "kind": "error"})
            trace_line = -1
        i += 1
    return out

func _digits(t):
    v := 0
    k := 0
    for c in t:
        if c < '0' or c > '9':
            break
        v = v * 10 + to_int(str(c))
        k += 1
    return v if k > 0 else 0

_uid := [0]

class Buffer:
    func init(path, text):
        _uid[0] += 1
        self.uid = "editeur-" + str(_uid[0])
        self.path = path
        self.text = text
        self.saved = text
        self.markers = []
        self.cursor = [1, 1]
        self.language = _syn.language_of(path) if path != null else "alex"

    func name():
        if self.path == null:
            return "sans titre.al"
        return _basename(self.path)

    func modified():
        return self.text != self.saved

class Studio:
    func init(root=".", paths=null):
        self.root = root
        self.buffers = []
        self.current = 0
        self.tree = file_tree(root)
        self.output = ""
        self.show_output = false
        self.status = "Prêt. F5 : exécuter, Ctrl+S : enregistrer, F10 : menus."
        self.dialog = null
        self.dialog_text = ""
        self.save_dirs = []          # « Enregistrer sous » : [libellé, chemin] des dossiers proposés
        self.save_dir = 0
        self.save_name = ""
        self.save_newdir = ""
        self.save_error = ""
        self.save_confirm = null     # chemin existant dont le remplacement attend une confirmation
        self.tree_dir = null         # dossier sélectionné dans l'arbre des fichiers
        self.proc = null
        self.debug_mode = false
        self.debug_buffer = ""
        self.debug_line = 0
        self.debug_file = null
        self.debug_frames = []
        self.breakpoints = []
        self.run_path = null
        self.run_started = 0.0
        self.input_text = ""
        self.stdin_open = false
        self.counter = 0
        self.first = true
        if paths != null:
            for p in paths:
                self.open(p)
        if len(self.buffers) == 0:
            self.new()
        self.current = 0
        # Méthodes liées : à passer directement comme gestionnaires.
        self.vue = self._vue
        self.tick = self._tick

    # ------------------------------------------------------------ fichiers
    func _focus_editor():
        b := self.buffer()
        if b != null:
            v.focus(b.uid)

    func buffer():
        if len(self.buffers) == 0:
            return null
        return self.buffers[self.current]

    func new():
        append(self.buffers, Buffer(null, ""))
        self.current = len(self.buffers) - 1
        self._focus_editor()

    func open(path):
        k := 0
        for b in self.buffers:
            if b.path == path:
                self.current = k
                self._focus_editor()
                return true
            k += 1
        text := ""
        if _os.exists(path):
            if _os.isdir(path):
                self.status = path + " est un dossier"
                return false
            try:
                text = _file.read(path)
            catch e:
                self.status = "Ouverture impossible : " + e.message
                return false
        b := Buffer(path, _s.replace(text, "\r\n", "\n"))
        # remplacer un « sans titre » vide qui n'a pas servi
        cur := self.buffer()
        if cur != null and cur.path == null and cur.text == "" and len(self.buffers) == 1:
            self.buffers = [b]
            self.current = 0
        else:
            append(self.buffers, b)
            self.current = len(self.buffers) - 1
        self.status = "Ouvert : " + path if _os.exists(path) else "Nouveau fichier : " + path
        self._focus_editor()
        return true

    func save():
        b := self.buffer()
        if b == null:
            return false
        if b.path == null:
            self.ask("save_as", "")
            return false
        try:
            _file.write(b.path, b.text)
        catch e:
            self.status = "Enregistrement impossible : " + e.message
            return false
        b.saved = b.text
        self.status = "Enregistré : " + b.path
        self.tree = file_tree(self.root)
        return true

    func save_as(path):
        b := self.buffer()
        if b == null or _s.trim(path) == "":
            return false
        old_path := b.path
        old_language := b.language
        b.path = _s.trim(path)
        b.language = _syn.language_of(b.path)
        if self.save():
            return true
        b.path = old_path          # échec : le fichier garde son ancien nom
        b.language = old_language
        return false

    func close(force=false):
        b := self.buffer()
        if b == null:
            return null
        if b.modified() and not force:
            self.ask("close", "")
            return null
        pop(self.buffers, self.current)
        if len(self.buffers) == 0:
            self.new()
        self.current = _min(self.current, len(self.buffers) - 1)

    func unsaved():
        n := 0
        for b in self.buffers:
            if b.modified():
                n += 1
        return n

    func quit(force=false):
        if not force and self.unsaved() > 0:
            self.ask("quit", "")
            return null
        self.stop_run()
        v.quit()

    # ------------------------------------------------------------ exécution
    func _exe():
        e := _os.executable()
        if e == null:
            return "alex"
        return e

    func run(check_only=false):
        if self.proc != null:
            self.stop_run()
            return null
        b := self.buffer()
        if b == null:
            return null
        if b.path == null or b.modified():
            if not self.save():
                return null
        if b.language != "alex":
            self.status = "Seuls les fichiers .al s'exécutent"
            return null
        cmd := "check" if check_only else "run"
        self.output = "$ alex " + cmd + " " + b.path + "\n"
        self.show_output = true
        b.markers = []
        try:
            self.proc = _proc.Command(self._exe()).args([cmd, b.path]).cwd(self.root).stdin("pipe").stdout("pipe").stderr("stdout").spawn()
        catch e:
            self.output += "Lancement impossible : " + e.message + "\n"
            self.proc = null
            return null
        self.run_path = b.path
        self.run_started = _os.monotonic_time()
        self.input_text = ""
        self.stdin_open = true
        if check_only:
            self._close_input(false)
            self.status = "Vérification…"
        else:
            self.status = "Exécution… (F5 : arrêter, ligne « Entrée » : saisie du programme)"
            v.focus("entree")

    # ------------------------------------------------------------ débogueur JSON Lines
    func debug_start():
        if self.proc != null:
            self.status = "Un processus est déjà actif"
            return null
        b := self.buffer()
        if b == null:
            return null
        if b.path == null or b.modified():
            if not self.save():
                return null
        if b.language != "alex":
            self.status = "Seuls les fichiers .al peuvent être débogués"
            return null
        self.output = "$ alexc debug " + b.path + "\n"
        self.show_output = true
        self.debug_mode = true
        self.debug_buffer = ""
        self.debug_line = 0
        self.debug_file = b.path
        self.debug_frames = []
        try:
            self.proc = _proc.Command(self._exe()).args(["debug", b.path]).cwd(self.root).stdin("pipe").stdout("pipe").stderr("inherit").spawn()
        catch e:
            self.output += "Lancement du débogueur impossible : " + e.message + "\n"
            self.proc = null
            self.debug_mode = false
            return null
        self.run_path = b.path
        self.run_started = _os.monotonic_time()
        self.stdin_open = true
        # Les commandes sont mises en file sur stdin ; le protocole CLI les
        # traite dès la pause initiale, avant la première reprise.
        for bp in self.breakpoints:
            self._debug_send({"command": "breakpoint.add", "file": bp["file"], "line": bp["line"]})
        self.status = "Débogueur démarré — attente de la première pause"
        self._refresh_markers()

    func _debug_send(command):
        if self.proc == null or not self.debug_mode:
            return null
        try:
            self.proc.write_line(_json.stringify(command))
        catch e:
            self.status = "Envoi au débogueur impossible : " + e.message

    func debug_continue():
        self._debug_send({"command": "continue"})
        self.status = "Exécution jusqu'au prochain point d'arrêt…"

    func debug_step(mode="into"):
        self._debug_send({"command": "step", "mode": mode})
        self.status = "Pas à pas : " + mode

    func debug_stop():
        if self.proc != null and self.debug_mode:
            self._debug_send({"command": "stop"})
            self.status = "Arrêt du débogueur…"
        else:
            self.stop_run()

    func debug_toggle_breakpoint():
        b := self.buffer()
        if b == null or b.path == null:
            self.status = "Enregistrez le fichier avant de poser un point d'arrêt"
            return null
        line := b.cursor[0]
        found := -1
        i := 0
        for bp in self.breakpoints:
            if bp["file"] == b.path and bp["line"] == line:
                found = i
                break
            i += 1
        if found >= 0:
            pop(self.breakpoints, found)
            if self.debug_mode:
                self._debug_send({"command": "breakpoint.remove", "file": b.path, "line": line})
            self.status = "Point d'arrêt supprimé ligne " + str(line)
        else:
            append(self.breakpoints, {"file": b.path, "line": line})
            if self.debug_mode:
                self._debug_send({"command": "breakpoint.add", "file": b.path, "line": line})
            self.status = "Point d'arrêt ajouté ligne " + str(line)
        self._refresh_markers()

    func _refresh_markers():
        for b in self.buffers:
            marks := []
            for bp in self.breakpoints:
                if bp["file"] == b.path:
                    append(marks, {"line": bp["line"], "message": "Point d'arrêt", "kind": "warning"})
            if self.debug_mode and self.debug_file == b.path and self.debug_line > 0:
                append(marks, {"line": self.debug_line, "message": "Instruction courante", "kind": "warning"})
            b.markers = marks

    # À chaque pause, sélectionne l'onglet source correspondant et place le curseur
    # au début de la ligne arrêtée. Les coordonnées de Buffer sont 1-based.
    func _debug_navigate_to_pause():
        if self.debug_file == null or self.debug_line <= 0:
            return null
        i := 0
        for b in self.buffers:
            if b.path == self.debug_file:
                self.current = i
                b.cursor = [self.debug_line, 1]
                self._focus_editor()
                return null
            i += 1
        # Certains compilateurs rapportent un chemin canonique différent du chemin
        # utilisé pour ouvrir l'onglet. N'utilise le basename que s'il est unique.
        match_index := -1
        i = 0
        for b in self.buffers:
            if b.path != null and _basename(b.path) == _basename(self.debug_file):
                if match_index >= 0:
                    return null
                match_index = i
            i += 1
        if match_index >= 0:
            self.current = match_index
            self.buffers[match_index].cursor = [self.debug_line, 1]
            self._focus_editor()
        return null

    func _debug_event(line):
        event := null
        try:
            event = _json.parse(line)
        catch e:
            self.output += "[événement de débogage invalide] " + line + "\n"
            return null
        kind := event["event"] if contains_key(event, "event") else "unknown"
        if kind == "paused":
            self.debug_line = event["line"] if contains_key(event, "line") else 0
            self.debug_file = event["file"] if contains_key(event, "file") and event["file"] != "" else self.run_path
            self.debug_frames = event["frames"] if contains_key(event, "frames") else []
            self._debug_navigate_to_pause()
            self.output += "\n⏸ Pause — " + str(self.debug_file) + ":" + str(self.debug_line) + "\n"
            if contains_key(event, "message"):
                self.output += str(event["message"]) + "\n"
            self.status = "En pause — F6 continuer, F9 pas à pas, Ctrl+F5 arrêter"
            self._refresh_markers()
        elif kind == "terminated":
            self.output += "\n✓ Programme terminé\n"
            self.status = "Débogage terminé"
        elif kind == "stopped":
            self.output += "\n[Débogage arrêté]\n"
            self.status = "Débogage arrêté"
        elif kind == "exception" or kind == "error":
            self.output += "\n✗ " + str(event["message"] if contains_key(event, "message") else kind) + "\n"
            self.status = "Erreur pendant le débogage"
        elif kind == "breakpoint":
            self.output += "[Point d'arrêt " + str(event["message"] if contains_key(event, "message") else "mis à jour") + "]\n"
        # Afficher les variables du frame courant dans le panneau de sortie.
        if kind == "paused" and len(self.debug_frames) > 0:
            frame := self.debug_frames[0]
            self.output += "Fonction : " + str(frame["function"] if contains_key(frame, "function") else "?") + "\n"
            locals := frame["locals"] if contains_key(frame, "locals") else []
            if len(locals) == 0:
                self.output += "  (aucune variable locale)\n"
            for variable in locals:
                self.output += "  " + str(variable["name"]) + " : " + str(variable["type"]) + " = " + str(variable["value"]) + "\n"
        if len(self.output) > 200000:
            self.output = "[…]\n" + _s.slice(self.output, len(self.output) - 150000)

    func _debug_tick():
        if self.proc == null:
            return false
        reads := 0
        while reads < 20:
            chunk := null
            try:
                chunk = self.proc.read("stdout", 65536, 0)
            catch e:
                chunk = ""
            if chunk == null or chunk == "":
                break
            self.debug_buffer += chunk
            reads += 1
        while true:
            n := _s.find(self.debug_buffer, "\n")
            if n < 0:
                break
            line := _s.substring(self.debug_buffer, 0, n)
            self.debug_buffer = _s.substring(self.debug_buffer, n + 1, len(self.debug_buffer))
            if _s.trim(line) != "":
                self._debug_event(line)
        code := self.proc.poll()
        if code != null:
            if _s.trim(self.debug_buffer) != "":
                self._debug_event(self.debug_buffer)
            self.proc.close()
            self.proc = null
            self.stdin_open = false
            self.debug_mode = false
            self.debug_buffer = ""
            self._refresh_markers()
            self.output += "[processus de débogage terminé : " + str(code) + "]\n"
            self._focus_editor()
        return true

    func stop_run():
        if self.proc != null:
            try:
                self.proc.kill("KILL")
                self.proc.wait(2.0)
                self.proc.close()
            catch e:
                self.proc = null
            self.proc = null
            self.stdin_open = false
            self.debug_mode = false
            self.debug_buffer = ""
            self._refresh_markers()
            self.output += "\n[arrêté]\n"
            self.status = "Exécution arrêtée"
            self._focus_editor()

    # ------------------------------------------------------------ entrée standard du programme
    func _set_input(t):
        self.input_text = t

    # Envoie une ligne à l'entrée standard du programme (et la répète dans la sortie : aucun terminal ne le fait).
    func _send_input(t=null):
        if t != null:
            self.input_text = t
        if self.proc == null or not self.stdin_open:
            return null
        line := self.input_text
        self.input_text = ""
        self.output += line + "\n"
        try:
            self.proc.write(line + "\n")
        catch e:
            self.stdin_open = false
            self.status = "Entrée impossible : " + e.message

    # Ferme l'entrée standard : input() reçoit une fin de fichier.
    func _close_input(echo=true):
        if self.proc == null or not self.stdin_open:
            return null
        self.stdin_open = false
        try:
            self.proc.close_stdin()
        catch e:
            self.status = "Fermeture de l'entrée impossible : " + e.message
        if echo:
            self.output += "[fin de l'entrée]\n"

    # Appelé régulièrement (tick) : lit la sortie du programme en cours.
    func _tick(now=null):
        if self.proc == null:
            return false
        if self.debug_mode:
            return self._debug_tick()
        reads := 0
        while reads < 20:
            chunk := null
            try:
                chunk = self.proc.read("stdout", 65536, 0)
            catch e:
                chunk = ""
            if chunk == null or chunk == "":
                break
            self.output += _strip_footer(chunk)
            reads += 1
        if len(self.output) > 200000:
            self.output = "[…]\n" + _s.slice(self.output, len(self.output) - 150000)
        code := self.proc.poll()
        if code != null:
            rest := ""
            try:
                rest = self.proc.read_all("stdout")
            catch e:
                rest = ""
            self.output += _strip_footer(rest)
            self.proc.close()
            self.proc = null
            self.stdin_open = false
            elapsed := _os.monotonic_time() - self.run_started
            self.output += "\n[code de sortie " + str(code) + ", " + str(to_int(elapsed * 1000)) + " ms]\n"
            for b in self.buffers:
                if b.path == self.run_path:
                    b.markers = parse_errors(self.output, b.path)
                    if len(b.markers) > 0:
                        self.status = str(len(b.markers)) + " erreur(s) — ligne " + str(b.markers[0]["line"])
                    else:
                        self.status = "Terminé (code " + str(code) + ")" if code != 0 else "Terminé sans erreur"
            self._focus_editor()

    # ------------------------------------------------------------ dialogues
    func ask(kind, text):
        self.dialog = kind
        self.dialog_text = text
        if kind == "save_as":
            self._save_dialog_init(text)
            v.focus("nom_fichier")
        elif kind == "open":
            v.focus("chemin")

    func _close_dialog():
        self.dialog = null
        self._focus_editor()

    func _dialog_ok():
        kind := self.dialog
        text := self.dialog_text
        self.dialog = null
        if kind == "open":
            if _s.trim(text) != "":
                self.open(_s.trim(text))
        elif kind == "quit":
            self.quit(true)
        elif kind == "close":
            self.close(true)
            self._focus_editor()
        else:
            self._focus_editor()

    # ------------------------------------------------------------ « Enregistrer sous »
    # Le dossier se choisit dans une liste (ceux de l'arbre des fichiers) : seul le nom du fichier se tape.
    func _norm(p):
        q := _s.replace(_s.trim(p), "\\", "/")
        while _s.starts_with(q, "./"):
            q = _s.slice(q, 2)
        if q == "":
            return "."
        return q

    func _relative(path):
        r := self._norm(self.root)
        if r != "." and _s.starts_with(path, r + "/"):
            return _s.slice(path, len(r) + 1)
        return path

    func _collect_folders(nodes, out):
        for n in nodes:
            if n["dir"] == true:
                append(out, [self._relative(n["id"]) + "/", n["id"]])
                if contains_key(n, "children"):
                    self._collect_folders(n["children"], out)

    func _save_dialog_init(current):
        want := null
        name := "sans_titre.al"
        if current != null and current != "":
            want = self._norm(_os.dirname(current))
            name = _basename(current)
        elif self.tree_dir != null:
            want = self._norm(self.tree_dir)
        top := "(dossier du projet)" if self._norm(self.root) == "." else "(dossier du projet) " + self.root
        dirs := [[top, self.root]]
        self._collect_folders(self.tree, dirs)
        idx := -1
        i := 0
        for d in dirs:
            if want != null and self._norm(d[1]) == want:
                idx = i
                break
            i += 1
        if idx < 0 and want != null:
            # dossier hors de l'arbre (profondeur limitée, chemin extérieur) : proposé en tête de liste
            dirs2 := [[want + "/", want]]
            for d in dirs:
                append(dirs2, d)
            dirs = dirs2
            idx = 0
        if idx < 0:
            idx = 0
        self.save_dirs = dirs
        self.save_dir = idx
        self.save_name = name
        self.save_newdir = ""
        self.save_error = ""
        self.save_confirm = null

    # Chemin complet visé, ou null si le nom est vide. Sans extension, « .al » est ajouté.
    func _save_target():
        name := _s.trim(self.save_name)
        if name == "" or len(self.save_dirs) == 0:
            return null
        dir := self.save_dirs[self.save_dir][1]
        sub := self._norm(self.save_newdir)
        if sub != ".":
            dir = _join(dir, sub)
        if _os.extension(_basename(name)) == "":
            name += ".al"
        return _join(dir, _s.replace(name, "\\", "/"))

    func _set_save_dir(i):
        self.save_dir = i
        self.save_error = ""
        self.save_confirm = null

    func _set_save_name(t):
        self.save_name = t
        self.save_error = ""
        self.save_confirm = null

    func _set_save_newdir(t):
        self.save_newdir = t
        self.save_error = ""
        self.save_confirm = null

    func _save_to_name(x=null):
        v.focus("nom_fichier")

    func _save_submit(t=null):
        self._save_ok()

    func _save_ok():
        target := self._save_target()
        if target == null:
            self.save_error = "Donnez un nom au fichier."
            v.focus("nom_fichier")
            return null
        if _os.isdir(target):
            self.save_error = "« " + target + " » est un dossier : choisissez un autre nom."
            return null
        b := self.buffer()
        if _os.exists(target) and (b == null or b.path != target) and self.save_confirm != target:
            self.save_confirm = target       # une seconde validation remplace le fichier
            return null
        folder := _os.dirname(target)
        if folder != "" and not _os.exists(folder):
            try:
                _os.mkdir_all(folder)
            catch e:
                self.save_error = "Création du dossier impossible : " + e.message
                return null
        self.dialog = null
        self.save_as(target)
        self._focus_editor()

    func _save_dialog():
        labels := [d[0] for d in self.save_dirs]
        target := self._save_target()
        confirm := target != null and self.save_confirm == target
        info := "Donnez un nom au fichier." if target == null else "Sera enregistré : " + target
        warn := null
        if self.save_error != "":
            warn = v.text(self.save_error, style="error", wrap=true)
        elif confirm:
            warn = v.text("Ce fichier existe déjà. Cliquez sur « Remplacer » pour l'écraser.", style="warning", wrap=true)
        return v.dialog("Enregistrer sous", [
            v.text("Dossier :", style="muted"),
            v.list_view(labels, self.save_dir, self._set_save_dir, self._save_to_name, height=7, id="dossiers"),
            v.text("Nouveau sous-dossier (facultatif) :", style="muted"),
            v.field(self.save_newdir, self._set_save_newdir, self._save_to_name, placeholder="ex. projets/tests", id="nouveau_dossier"),
            v.text("Nom du fichier :", style="muted"),
            v.field(self.save_name, self._set_save_name, self._save_submit, placeholder="nom.al", id="nom_fichier"),
            v.text(info, style="muted", wrap=true),
            warn,
        ], [["Remplacer" if confirm else "Enregistrer", self._save_ok], ["Annuler", self._close_dialog]], self._close_dialog, 64)

    func _tree_select(node):
        if node["dir"] == true:
            self.tree_dir = node["id"]
        else:
            self.tree_dir = _os.dirname(node["id"])

    func _set_dialog_text(t):
        self.dialog_text = t

    # ------------------------------------------------------------ vue
    func _set_text(t):
        b := self.buffer()
        if b != null:
            b.text = t

    func _set_cursor(l, c):
        b := self.buffer()
        if b != null:
            b.cursor = [l, c]

    func _set_tab(i):
        self.current = i
        self._focus_editor()

    func _tree_activate(node):
        if node["dir"] != true:
            self.open(node["id"])

    func _toggle_output():
        self.show_output = not self.show_output

    func _on_key(k):
        if k == "f6" and self.debug_mode:
            self.debug_continue()
            return true
        if k == "f9" and self.debug_mode:
            self.debug_step("into")
            return true
        if k == "shift+f9" and self.debug_mode:
            self.debug_step("over")
            return true
        if k == "ctrl+f9" and self.debug_mode:
            self.debug_step("out")
            return true
        if k == "f2":
            self.debug_toggle_breakpoint()
            return true
        if k == "escape" and self.proc != null:
            self._focus_editor()
            return true
        if k == "f8" and self.proc != null:
            self._close_input()
            return true
        if k == "escape" and self.show_output and self.proc == null:
            self.show_output = false
            return true
        return false

    func _menus():
        st := self

        func open_dialog():
            st.ask("open", "")

        func save_as_dialog():
            b := st.buffer()
            st.ask("save_as", b.path if b != null and b.path != null else "")

        func about():
            st.ask("about", "")

        return v.menu_bar([
            v.menu("Fichier", [
                v.item("Nouveau", self.new, "ctrl+n"),
                v.item("Ouvrir…", open_dialog, "ctrl+o"),
                v.item("Enregistrer", self.save, "ctrl+s"),
                v.item("Enregistrer sous…", save_as_dialog, "ctrl+shift+s"),
                v.item("Fermer", self.close, "ctrl+w"),
                v.menu_separator(),
                v.item("Quitter", self.quit, "ctrl+q"),
            ]),
            v.menu("Édition", [
                v.item("Annuler", () => v.press("ctrl+z"), "ctrl+z"),
                v.item("Rétablir", () => v.press("ctrl+y"), "ctrl+y"),
                v.menu_separator(),
                v.item("Couper", () => v.press("ctrl+x")),
                v.item("Copier", () => v.press("ctrl+c")),
                v.item("Coller", () => v.press("ctrl+v")),
                v.item("Tout sélectionner", () => v.press("ctrl+a")),
                v.menu_separator(),
                v.item("Rechercher…", () => v.press("ctrl+f")),
                v.item("Aller à la ligne…", () => v.press("ctrl+g")),
                v.item("Commenter / décommenter", () => v.press("ctrl+/")),
                v.menu_separator(),
                v.item("Complétion", () => v.press("ctrl+space"), "ctrl+space"),
                v.item("Plier / déplier le bloc", () => v.press("f4"), "f4"),
                v.item("Tout plier", () => v.press("shift+f4"), "shift+f4"),
                v.item("Tout déplier", () => v.press("ctrl+f4"), "ctrl+f4"),
            ]),
            v.menu("Exécuter", [
                v.item("Lancer", self.run, "f5"),
                v.item("Démarrer le débogage", self.debug_start, "f6"),
                v.item("Continuer", self.debug_continue, "f6", enabled=self.debug_mode),
                v.item("Pas à pas — entrer", () => self.debug_step("into"), "f9", enabled=self.debug_mode),
                v.item("Pas à pas — suivant", () => self.debug_step("over"), "shift+f9", enabled=self.debug_mode),
                v.item("Pas à pas — sortir", () => self.debug_step("out"), "ctrl+f9", enabled=self.debug_mode),
                v.item("Point d'arrêt sur la ligne courante", self.debug_toggle_breakpoint, "f2"),
                v.item("Vérifier", () => st.run(true), "f7"),
                v.item("Arrêter", self.debug_stop, "ctrl+f5", enabled=self.proc != null),
                v.item("Fin de l'entrée du programme", self._close_input, "f8", enabled=self.proc != null and self.stdin_open),
                v.menu_separator(),
                v.item("Panneau de sortie", self._toggle_output, "f12", checked=self.show_output),
            ]),
            v.menu("Aide", [v.item("À propos", about)]),
        ])

    func _dialog():
        k := self.dialog
        if k == null:
            return null
        if k == "save_as":
            return self._save_dialog()
        if k == "open":
            return v.dialog("Ouvrir un fichier", [
                v.text("Chemin (relatif au dossier " + self.root + ") :", style="muted"),
                v.field(self.dialog_text, self._set_dialog_text, self._submit_dialog, placeholder="dossier/fichier.al", id="chemin"),
            ], [["OK", self._dialog_ok], ["Annuler", self._close_dialog]], self._close_dialog, 56)
        if k == "quit":
            return v.dialog("Quitter", v.text(str(self.unsaved()) + " fichier(s) modifié(s) non enregistré(s). Quitter quand même ?", wrap=true), [["Quitter", self._dialog_ok], ["Annuler", self._close_dialog]], self._close_dialog, 48)
        if k == "close":
            return v.dialog("Fermer", v.text(self.buffer().name() + " a des modifications non enregistrées. Fermer quand même ?", wrap=true), [["Fermer", self._dialog_ok], ["Annuler", self._close_dialog]], self._close_dialog, 48)
        return v.alert("Éditeur Alex", "Éditeur de code d'Alex, écrit en Alex avec ui.view : le même programme dans une fenêtre (alex edit --gui) ou dans le terminal (alex edit).", self._close_dialog)

    func _submit_dialog(t):
        self.dialog_text = t
        self._dialog_ok()

    func _vue():
        b := self.buffer()
        if self.first:
            self.first = false
            self._focus_editor()
        pages := []
        for x in self.buffers:
            title := x.name() + (" •" if x.modified() else "")
            ed := v.code_editor(x.text, self._set_text, x.language, self._set_cursor, x.markers, id=x.uid)
            append(pages, [title, ed])
        center := v.tabs(pages, self.current, self._set_tab, id="onglets")
        if self.show_output:
            sortie := v.panel(v.code_editor(self.output, null, "text", null, null, true, false, id="sortie", completion=false), title="Sortie", padding=0, flex=1)
            if self.proc != null:
                saisie := v.row([
                    v.text("Entrée ▸", style="muted"),
                    v.field(self.input_text, self._set_input, self._send_input, placeholder="texte envoyé au programme (Entrée) ; F8 : fin", enabled=self.stdin_open, id="entree", flex=1),
                    v.button("Fin", self._close_input, enabled=self.stdin_open),
                ], gap=1)
                sortie = v.column([sortie, saisie], gap=0)
            if self.debug_mode and len(self.debug_frames) > 0:
                frame := self.debug_frames[0]
                vars_text := "Pile d'appels\n"
                for fr in self.debug_frames:
                    vars_text += "  " + str(fr["function"] if contains_key(fr, "function") else "?") + " — " + str(fr["file"] if contains_key(fr, "file") else "") + ":" + str(fr["line"] if contains_key(fr, "line") else 0) + "\n"
                vars_text += "\nVariables locales\n"
                locals := frame["locals"] if contains_key(frame, "locals") else []
                for variable in locals:
                    vars_text += str(variable["name"]) + " : " + str(variable["type"]) + " = " + str(variable["value"]) + "\n"
                inspecteur := v.panel(v.text(vars_text, wrap=true), title="Débogueur", padding=1, height=10)
                sortie = v.column([inspecteur, sortie], gap=0)
            center = v.split(center, sortie, vertical=true, ratio=0.68, id="centre")
        fichiers := v.panel(v.tree(self.tree, self._tree_select, self._tree_activate, id="arbre"), title="Fichiers", padding=0)
        corps := v.split(fichiers, center, ratio=0.22, id="corps")
        where := ""
        if b != null:
            where = b.name() + "   Ln " + str(b.cursor[0]) + ", Col " + str(b.cursor[1]) + "   " + b.language
            if b.modified():
                where += "   modifié"
        statut := v.row([v.text(self.status, style="muted", flex=1), v.text(where, style="muted")], padding=[1, 0])
        return v.column([self._menus(), corps, statut, self._dialog()], gap=0)

# Retire la ligne « -- terminé, valeur de retour: ... » qu'alexc run ajoute à la fin.
func _strip_footer(text):
    k := _s.find(text, "-- terminé, valeur de retour:")
    if k < 0:
        return text
    e := _s.find(_s.slice(text, k), "\n")
    if e < 0:
        return _s.slice(text, 0, k)
    return _s.slice(text, 0, k) + _s.slice(text, k + e + 1)

func _min(a, b):
    if a < b:
        return a
    return b
