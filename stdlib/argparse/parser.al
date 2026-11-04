# ALEX STANDARD LIBRARY — argparse.parser
#
# Moteur d'analyse : Parser (exposé comme argparse.ArgumentParser), groupes, groupes mutuellement exclusifs,
# sous-commandes imbriquées. Voir argparse.al (façade) et docs/ARGPARSE.md.
#
# Le résultat de parse_args() est un DICT {dest: valeur}. Les erreurs d'usage lèvent
# "ArgparseError" (message = usage + « prog: erreur: … ») ; --help lève "ArgparseHelp" et
# --version "ArgparseVersion" (message = texte à afficher) quand exit_on_error vaut false ;
# avec exit_on_error=true (défaut) le parseur écrit sur stdout/stderr et quitte (0 ou 2).
# Erreurs de configuration (add_argument invalide) : "ArgparseConfigError".

from core use len, type
from collections use append, contains, contains_key, keys
use os as _os
use _native_cli as _cli
use argparse.text as _t
use argparse.help as _h
use argparse.manpage as _man
use argparse.completion as _comp

const SUPPRESS := "==SUPPRESS=="
const _UNSET := "==UNSET=="

_state := {"next_id": 1}

func _new_id():
    v := _state["next_id"]
    _state["next_id"] = v + 1
    return v

func _kind(v):
    return type(v)

func _config_error(text):
    raise("ArgparseConfigError", text)

_ARG_KEYS := ["action", "nargs", "const", "default", "type", "choices", "required", "help", "metavar", "dest", "version", "env", "hidden", "complete"]
_PARSER_KEYS := ["description", "epilog", "usage", "add_help", "version", "allow_abbrev", "exit_on_error", "width", "show_defaults", "raw_text"]
_SUB_KEYS := ["dest", "title", "description", "help", "metavar", "required"]
_ADDPARSER_KEYS := ["aliases", "help", "description", "epilog", "usage", "add_help", "hidden", "width", "show_defaults", "allow_abbrev", "exit_on_error", "raw_text"]

# Valeur de opts[key] (ou fallback) ; opts peut être null.
func _opt(opts, key, fallback):
    if opts != null and contains_key(opts, key):
        return opts[key]
    return fallback

# Refuse les clés inconnues (une faute de frappe devient une erreur claire).
func _check_opts(opts, allowed, where):
    if opts == null:
        return null
    if _kind(opts) != "dict":
        _config_error(where + " : les options doivent être un dict (obtenu '" + _kind(opts) + "')")
    for k in keys(opts):
        if not contains(allowed, k):
            _config_error(where + " : option inconnue '" + str(k) + "' (valides : " + _t.join(", ", allowed) + ")")
    return null

func _tail(items, start):
    out := []
    i := start
    while i < len(items):
        append(out, items[i])
        i = i + 1
    return out

func _copy(items):
    return _tail(items, 0)

func _is_rest(arg):
    return arg.nargs == "remainder" or arg.nargs == "parser"

func _nmin(arg):
    n := arg.nargs
    if n == null:
        return 1
    if n == "?" or n == "*" or n == "remainder":
        return 0
    if n == "+" or n == "parser":
        return 1
    return n

func _nmax(arg, avail):
    n := arg.nargs
    if n == null or n == "?":
        return 1
    if _kind(n) == "int":
        return n
    return avail

# Répartition gloutonne avec retour arrière (comme les motifs regex d'argparse) de `avail`
# jetons positionnels sur pos[idx:end]. Retourne la liste des comptes, ou null.
func _match_counts(pos, idx, end, avail):
    if idx >= end:
        return []
    a := pos[idx]
    mn := _nmin(a)
    c := _nmax(a, avail)
    if c > avail:
        c = avail
    while c >= mn:
        remaining := avail - c
        if _is_rest(a):
            remaining = 0
        rest := _match_counts(pos, idx + 1, end, remaining)
        if rest != null:
            out := [c]
            for r in rest:
                append(out, r)
            return out
        c = c - 1
    return null

# ---------------------------------------------------------------------
# Enregistrements
# ---------------------------------------------------------------------

class Argument:
    func init():
        self.id = _new_id()
        self.names = []
        self.dest = null
        self.action = "store"
        self.nargs = null
        self.constant = null
        self.default = null
        self.type = null
        self.choices = null
        self.required = false
        self.help = null
        self.metavar = null
        self.positional = false
        self.hidden = false
        self.group = null
        self.mutex = null
        self.env = null
        self.version = null
        self.complete = null
        self.sub = null

class ArgumentGroup:
    func init(parser, title, description):
        self.parser = parser
        self.title = title
        self.description = description
        self.args = []

    func add_argument(names, opts=null):
        return self.parser._add_opts(names, opts, self, null)

    func add_mutually_exclusive_group(opts=null):
        _check_opts(opts, ["required"], "add_mutually_exclusive_group()")
        return self.parser._add_mutex(_opt(opts, "required", false), self)

class MutexGroup:
    func init(parser, required, group):
        self.id = _new_id()
        self.parser = parser
        self.required = required
        self.group = group
        self.args = []

    func add_argument(names, opts=null):
        return self.parser._add_opts(names, opts, self.group, self)

class Subparsers:
    func init(parser, dest, title, description, help, metavar, required):
        self.parser = parser
        self.dest = dest
        self.title = title
        self.description = description
        self.help = help
        self.metavar = metavar
        self.required = required
        self.commands = []
        self.arg = null

    # Cherche une sous-commande par nom ou alias ; null si absente.
    func find(name):
        for p in self.commands:
            if p.name == name or contains(p.aliases, name):
                return p
        return null

    func names():
        out := []
        for p in self.commands:
            append(out, p.name)
        return out

    # Nouvelle sous-commande (un ArgumentParser) : prog = « <parent> <nom> ».
    # opts : aliases help description epilog usage add_help hidden width show_defaults
    # allow_abbrev exit_on_error raw_text (les réglages non donnés sont hérités du parent).
    func add_parser(name, opts=null):
        _check_opts(opts, _ADDPARSER_KEYS, "add_parser()")
        aliases := _opt(opts, "aliases", null)
        help := _opt(opts, "help", null)
        hidden := _opt(opts, "hidden", false)
        if _kind(name) != "str" or name == "" or _t.starts_with(name, "-"):
            _config_error("add_parser() : nom de sous-commande invalide")
        al := []
        if aliases != null:
            al = _copy(aliases)
        candidates := [name]
        for x in al:
            append(candidates, x)
        for candidate in candidates:
            if self.find(candidate) != null:
                _config_error("add_parser() : sous-commande ou alias en double : " + candidate)
        p := self.parser
        sub_opts := {
            "description": _opt(opts, "description", null),
            "epilog": _opt(opts, "epilog", null),
            "usage": _opt(opts, "usage", null),
            "add_help": _opt(opts, "add_help", true),
            "allow_abbrev": _opt(opts, "allow_abbrev", p.allow_abbrev),
            "exit_on_error": _opt(opts, "exit_on_error", p.exit_on_error),
            "width": _opt(opts, "width", p.width),
            "show_defaults": _opt(opts, "show_defaults", p.show_defaults),
            "raw_text": _opt(opts, "raw_text", p.raw_text)
        }
        sub := Parser(p.prog + " " + name, sub_opts)
        sub.name = name
        sub.aliases = al
        sub.help_text = help
        sub.hidden = hidden
        sub.parent = p
        append(self.commands, sub)
        return sub

# ---------------------------------------------------------------------
# ArgumentParser
# ---------------------------------------------------------------------

class Parser:
    # opts : description epilog usage add_help version allow_abbrev exit_on_error width
    # show_defaults raw_text.   Pour des arguments nommés : argparse.parser(prog=..., ...).
    func init(prog=null, opts=null):
        _check_opts(opts, _PARSER_KEYS, "ArgumentParser()")
        add_help := _opt(opts, "add_help", true)
        version := _opt(opts, "version", null)
        self.prog = prog
        if prog == null:
            self.prog = _default_prog()
        self.description = _opt(opts, "description", null)
        self.epilog = _opt(opts, "epilog", null)
        self.usage_text = _opt(opts, "usage", null)
        self.add_help = add_help
        self.version = version
        self.allow_abbrev = _opt(opts, "allow_abbrev", true)
        self.exit_on_error = _opt(opts, "exit_on_error", true)
        self.width = _opt(opts, "width", null)
        self.show_defaults = _opt(opts, "show_defaults", false)
        self.raw_text = _opt(opts, "raw_text", false)
        self.args = []
        self.groups = []
        self.mutexes = []
        self.sub = null
        self.defaults = {}
        self.opt_names = []
        self.opt_map = {}
        self.neg_opts = false
        self.last_error = null
        # nœud d'arbre (rempli par Subparsers.add_parser)
        self.name = null
        self.aliases = []
        self.help_text = null
        self.hidden = false
        self.parent = null
        self.pos_group = ArgumentGroup(self, _t.msg("positional"), null)
        self.opt_group = ArgumentGroup(self, _t.msg("options"), null)
        append(self.groups, self.pos_group)
        append(self.groups, self.opt_group)
        if add_help:
            self._add(["-h", "--help"], "help", null, null, "==UNSET==", null, null, null, _t.msg("help_desc"), null, null, null, null, false, null, null, null)
        if version != null:
            self._add(["--version"], "version", null, null, "==UNSET==", null, null, null, _t.msg("version_desc"), null, null, version, null, false, null, null, null)

    # --- construction ---------------------------------------------------------

    # opts : action nargs const default type choices required help metavar dest version env
    # hidden complete  (voir docs/ARGPARSE.md).
    func add_argument(names, opts=null):
        return self._add_opts(names, opts, null, null)

    func _add_opts(names, opts, group, mutex):
        _check_opts(opts, _ARG_KEYS, "add_argument()")
        return self._add(names, _opt(opts, "action", "store"), _opt(opts, "nargs", null), _opt(opts, "const", null), _opt(opts, "default", _UNSET), _opt(opts, "type", null), _opt(opts, "choices", null), _opt(opts, "required", null), _opt(opts, "help", null), _opt(opts, "metavar", null), _opt(opts, "dest", null), _opt(opts, "version", null), _opt(opts, "env", null), _opt(opts, "hidden", false), _opt(opts, "complete", null), group, mutex)

    func add_argument_group(title, description=null):
        g := ArgumentGroup(self, title, description)
        append(self.groups, g)
        return g

    func add_mutually_exclusive_group(opts=null):
        _check_opts(opts, ["required"], "add_mutually_exclusive_group()")
        return self._add_mutex(_opt(opts, "required", false), null)

    func _add_mutex(required, group):
        g := MutexGroup(self, required, group)
        append(self.mutexes, g)
        return g

    # Une seule déclaration de sous-commandes par parseur.
    # opts : dest title description help metavar required
    func add_subparsers(opts=null):
        _check_opts(opts, _SUB_KEYS, "add_subparsers()")
        dest := _opt(opts, "dest", null)
        title := _opt(opts, "title", null)
        description := _opt(opts, "description", null)
        help := _opt(opts, "help", null)
        metavar := _opt(opts, "metavar", null)
        required := _opt(opts, "required", false)
        if self.sub != null:
            _config_error("add_subparsers() : ce parseur a déjà des sous-commandes")
        sp := Subparsers(self, dest, title, description, help, metavar, required)
        a := Argument()
        a.action = "parser"
        a.nargs = "parser"
        a.positional = true
        a.dest = dest
        if dest == null:
            a.dest = "command"
        a.metavar = metavar
        a.help = help
        a.required = required
        a.sub = sp
        sp.arg = a
        a.names = []
        group := self.pos_group
        if title != null:
            group = ArgumentGroup(self, title, description)
            append(self.groups, group)
        a.group = group
        append(group.args, a)
        append(self.args, a)
        self.sub = sp
        return sp

    func set_defaults(values):
        for k in keys(values):
            self.defaults[k] = values[k]
            for a in self.args:
                if a.dest == k and a.action != "parser":
                    a.default = values[k]
        return null

    func get_default(dest):
        for a in self.args:
            if a.dest == dest:
                return a.default
        if contains_key(self.defaults, dest):
            return self.defaults[dest]
        return null

    func _add(names, action, nargs, constant, default, type, choices, required, help, metavar, dest, version, env, hidden, complete, group, mutex):
        nl := []
        if _kind(names) == "str":
            nl = [names]
        elif _kind(names) == "list":
            nl = _copy(names)
        else:
            _config_error("add_argument() : names doit être une str ou une list de str")
        if len(nl) == 0:
            _config_error("add_argument() : au moins un nom est requis")
        for n in nl:
            if _kind(n) != "str" or n == "" or n == "-" or n == "--":
                _config_error("add_argument() : nom invalide")
        positional := not _t.starts_with(nl[0], "-")
        for n in nl:
            if (not _t.starts_with(n, "-")) != positional:
                _config_error("add_argument() : mélange d'options et de positionnel dans " + _t.join(", ", nl))
        if positional and len(nl) > 1:
            _config_error("add_argument() : un positionnel n'a qu'un seul nom")
        valid := ["store", "store_const", "store_true", "store_false", "append", "append_const", "extend", "count", "help", "version", "boolean_optional"]
        if not contains(valid, action):
            _config_error("add_argument() : action inconnue '" + str(action) + "'")
        flag := action != "store" and action != "append" and action != "extend"
        if flag and nargs != null:
            _config_error("add_argument() : nargs interdit avec l'action " + action)
        if flag and positional:
            _config_error("add_argument() : l'action " + action + " ne s'applique qu'à une option")
        if nargs != null:
            ok := false
            if _kind(nargs) == "int" and nargs >= 1:
                ok = true
            if nargs == "?" or nargs == "*" or nargs == "+" or nargs == "remainder":
                ok = true
            if not ok:
                _config_error("add_argument() : nargs invalide (entier >= 1, \"?\", \"*\", \"+\" ou \"remainder\")")
        if action == "extend" and nargs == null:
            nargs = "+"
        if (action == "store_const" or action == "append_const") and constant == null:
            _config_error("add_argument() : constant est requis avec " + action)
        if choices != null and (_kind(choices) != "list" or len(choices) == 0):
            _config_error("add_argument() : choices doit être une list non vide")
        if metavar != null and _kind(metavar) != "str" and _kind(metavar) != "list":
            _config_error("add_argument() : metavar doit être une str ou une list")
        if mutex != null and positional:
            _config_error("add_argument() : un groupe exclusif ne contient que des options")
        if action == "boolean_optional":
            if len(nl) != 1 or not _t.starts_with(nl[0], "--"):
                _config_error("add_argument() : boolean_optional attend une unique option longue (--nom)")
            append(nl, "--no-" + _t.from_index(nl[0], 2))
        a := Argument()
        a.names = nl
        a.action = action
        a.nargs = nargs
        a.constant = constant
        a.type = type
        a.choices = choices
        a.help = help
        a.metavar = metavar
        a.positional = positional
        a.hidden = hidden or help == SUPPRESS
        if help == SUPPRESS:
            a.help = null
        a.env = env
        a.version = version
        a.complete = complete
        if positional:
            a.dest = nl[0]
            if dest != null:
                _config_error("add_argument() : dest n'a pas de sens pour un positionnel")
            a.required = _nmin(a) >= 1
        else:
            if dest != null:
                a.dest = dest
            else:
                a.dest = _derive_dest(nl)
            a.required = required == true
            if mutex != null and a.required:
                _config_error("add_argument() : un argument d'un groupe exclusif ne peut pas être required")
        # défaut
        if default == _UNSET:
            if action == "store_true":
                a.default = false
            elif action == "store_false":
                a.default = true
            elif action == "count":
                a.default = 0
            elif positional and nargs == "*":
                a.default = []
            else:
                a.default = null
        else:
            a.default = default
        # noms d'options uniques
        for n in nl:
            if contains_key(self.opt_map, n):
                _config_error("add_argument() : option déjà définie : " + n)
        if not positional:
            for n in nl:
                self.opt_map[n] = a
                append(self.opt_names, n)
                if _t.looks_like_negative_number(n):
                    self.neg_opts = true
        # groupes
        g := group
        if g == null:
            if positional:
                g = self.pos_group
            else:
                g = self.opt_group
        a.group = g
        append(g.args, a)
        if mutex != null:
            a.mutex = mutex
            append(mutex.args, a)
        append(self.args, a)
        return a

    # --- aide -------------------------------------------------------------------

    func format_usage():
        return _h.format_usage(self) + "\n"

    func format_help():
        return _h.format_help(self)

    func print_help():
        _cli.write_out(self.format_help())
        return null

    func print_usage():
        _cli.write_out(self.format_usage())
        return null

    # Lève ArgparseError (usage + « prog: erreur: message »).
    func error(message):
        self.last_error = message
        raise("ArgparseError", _h.format_usage(self) + "\n" + self.prog + ": " + _t.msg("error") + ": " + message)

    # Page de manuel roff de ce parseur (voir argparse.manpage).
    func format_man(section=1, date=null, source=null, manual=null, author=null):
        return _man.format_man(self, section, date, source, manual, author)

    # {nom de fichier: contenu roff} pour ce parseur et chaque sous-commande (prog-sous.1).
    func man_pages(section=1, date=null, source=null, manual=null, author=null):
        return _man.man_pages(self, section, date, source, manual, author)

    # Script de complétion : shell = "bash" | "zsh" | "powershell".
    func completion(shell, prog=null):
        return _comp.generate(self, shell, prog)

    # --- analyse ----------------------------------------------------------------------

    # dict {dest: valeur}. argv : list de str (défaut : os.args()).
    func parse_args(argv=null):
        ctx := self._entry(argv, false)
        return ctx["ns"]

    # [dict, arguments non reconnus].
    func parse_known_args(argv=null):
        ctx := self._entry(argv, true)
        return [ctx["ns"], ctx["extras"]]

    # {"args": dict, "path": [noms de sous-commandes], "parser": parseur final,
    #  "extras": [...]}  (utile pour dispatcher une sous-commande).
    func parse_args_ex(argv=null, known=false):
        ctx := self._entry(argv, known)
        parsers := ctx["parsers"]
        return {"args": ctx["ns"], "path": ctx["path"], "parser": parsers[len(parsers) - 1], "extras": ctx["extras"]}

    func _entry(argv, known):
        args := argv
        if args == null:
            args = _os.args()
        if _kind(args) != "list" and _kind(args) != "tuple":
            raise("TypeError", "argparse : argv doit être une list de str (obtenu '" + _kind(args) + "')")
        for a in args:
            if _kind(a) != "str":
                raise("TypeError", "argparse : argv ne doit contenir que des str")
        ctx := {"ns": {}, "extras": [], "path": [], "parsers": [self], "seen": {}, "mutex_seen": {}, "explicit": {}}
        failure := null
        try:
            self._parse(_copy(args), ctx)
            if not known and len(ctx["extras"]) > 0:
                self.error(_t.fmt("unrecognized", [_t.join(" ", ctx["extras"])]))
        catch e:
            failure = e
        if failure != null:
            if self.exit_on_error and failure.type == "ArgparseError":
                _cli.write_err(failure.message + "\n")
                _cli.exit(2)
            if self.exit_on_error and (failure.type == "ArgparseHelp" or failure.type == "ArgparseVersion"):
                _cli.write_out(failure.message)
                _cli.exit(0)
            raise(failure.type, failure.message)
        return ctx

    # --- noms d'arguments pour les messages ------------------------------------------------

    func _argname(arg):
        if arg.positional:
            return _h.metavar_of(arg)
        return _t.join("/", arg.names)

    func _fail(arg, text):
        self.error(_t.fmt("arg_prefix", [self._argname(arg), text]))

    # --- conversion de types ------------------------------------------------------------------

    func _convert_one(arg, text):
        spec := arg.type
        if spec == null or spec == "str" or spec == "path" or spec == "file" or spec == "dir":
            return text
        if spec == "int":
            if not _t.is_int_text(text):
                self._fail(arg, _t.fmt("invalid_type", ["int", _t.quote(text)]))
            return _t.parse_int(text)
        if spec == "float":
            if not _t.is_float_text(text):
                self._fail(arg, _t.fmt("invalid_type", ["float", _t.quote(text)]))
            return _t.parse_float(text)
        if spec == "bool":
            low := _t.lower(text)
            if contains(["true", "yes", "on", "1", "y", "t"], low):
                return true
            if contains(["false", "no", "off", "0", "n", "f"], low):
                return false
            self._fail(arg, _t.fmt("invalid_type", ["bool", _t.quote(text)]))
        if _kind(spec) == "str":
            _config_error("type inconnu : " + spec + " (str, int, float, bool, path, file, dir ou une fonction)")
        result := null
        failure := null
        try:
            result = spec(text)
        catch e:
            failure = e
        if failure != null:
            if failure.type == "ArgumentTypeError":
                self._fail(arg, failure.message)
            self._fail(arg, _t.fmt("invalid_value", [_t.quote(text)]))
        return result

    func _check_choice(arg, value):
        if arg.choices != null and not contains(arg.choices, value):
            shown := []
            for c in arg.choices:
                if _kind(c) == "str":
                    append(shown, _t.quote(c))
                else:
                    append(shown, str(c))
            self._fail(arg, _t.fmt("invalid_choice", [_t.quote(str(value)) if _kind(value) == "str" else str(value), _t.join(", ", shown)]))
        return value

    func _convert(arg, text):
        return self._check_choice(arg, self._convert_one(arg, text))

    # --- défauts --------------------------------------------------------------------------------

    func _apply_defaults(ctx):
        ns := ctx["ns"]
        for a in self.args:
            if a.action == "help" or a.action == "version":
                continue
            if a.action == "parser" and a.sub.dest == null:
                continue
            key := a.dest
            if contains_key(ns, key) and contains_key(ctx["explicit"], key):
                continue
            value := a.default
            if a.env != null:
                raw := _os.getenv(a.env, null)
                if raw != null:
                    ctx["seen"][a.id] = true
                    ctx["explicit"][key] = true
                    if a.action == "store_true":
                        value = contains(["true", "yes", "on", "1", "y", "t"], _t.lower(raw))
                    elif a.action == "store_false":
                        value = not contains(["true", "yes", "on", "1", "y", "t"], _t.lower(raw))
                    elif a.action == "store":
                        value = self._convert(a, raw)
                    ns[key] = value
                    continue
            if _kind(value) == "str" and a.action == "store" and a.type != null and a.type != "str":
                value = self._convert_one(a, value)
            ns[key] = value
        for k in keys(self.defaults):
            if not contains_key(ns, k) or not contains_key(ctx["explicit"], k):
                ns[k] = self.defaults[k]
        return null

    # --- classification des jetons ---------------------------------------------------------------

    # null = positionnel ; liste d'entrées [arg, option, valeur_explicite] ; {"ambiguous": [...]}.
    func _parse_optional(tok):
        if tok == "" or not _t.starts_with(tok, "-"):
            return null
        if contains_key(self.opt_map, tok):
            return [[self.opt_map[tok], tok, null]]
        if len(tok) == 1:
            return null
        sp := _t.split_once(tok, "=")
        if sp != null and contains_key(self.opt_map, sp[0]):
            return [[self.opt_map[sp[0]], sp[0], sp[1]]]
        found := self._option_matches(tok)
        if len(found) > 1:
            names := []
            for f in found:
                append(names, f[1])
            return {"ambiguous": names}
        if len(found) == 1:
            return found
        if _t.looks_like_negative_number(tok) and not self.neg_opts:
            return null
        if _t.contains_text(tok, " "):
            return null
        return [[null, tok, null]]

    # Abbreviations d'options longues et options courtes à valeur collée (-n5, -abc).
    func _option_matches(tok):
        out := []
        if _t.starts_with(tok, "--"):
            if not self.allow_abbrev:
                return out
            prefix := tok
            explicit := null
            sp := _t.split_once(tok, "=")
            if sp != null:
                prefix = sp[0]
                explicit = sp[1]
            for o in self.opt_names:
                if _t.starts_with(o, prefix):
                    append(out, [self.opt_map[o], o, explicit])
            return out
        short := _t.head(tok, 2)
        rest := _t.from_index(tok, 2)
        for o in self.opt_names:
            if o == short:
                append(out, [self.opt_map[o], o, rest])
            elif self.allow_abbrev and _t.starts_with(o, tok) and not _t.starts_with(o, "--"):
                append(out, [self.opt_map[o], o, null])
        return out

    # --- cœur de l'analyse ------------------------------------------------------------------------

    func _parse(argv, ctx):
        self._apply_defaults(ctx)
        n := len(argv)
        kinds := []
        opts := []
        after_dd := false
        i := 0
        while i < n:
            tok := argv[i]
            if after_dd:
                append(kinds, "A")
                append(opts, null)
            elif tok == "--":
                append(kinds, "-")
                append(opts, null)
                after_dd = true
            else:
                m := self._parse_optional(tok)
                if m == null:
                    append(kinds, "A")
                else:
                    append(kinds, "O")
                append(opts, m)
            i = i + 1
        pos := []
        for a in self.args:
            if a.positional:
                append(pos, a)
        st := {"argv": argv, "kinds": kinds, "opts": opts, "n": n, "pos": pos}
        max_opt := -1
        i = 0
        while i < n:
            if kinds[i] == "O":
                max_opt = i
            i = i + 1
        start := 0
        while start <= max_opt:
            nxt := start
            while nxt <= max_opt and kinds[nxt] != "O":
                nxt = nxt + 1
            if start != nxt:
                end := self._consume_positionals(st, ctx, start, false)
                if end > start:
                    start = end
                    continue
                start = end
            if start >= n:
                break
            if kinds[start] != "O":
                j := start
                while j < nxt:
                    if kinds[j] != "-":
                        append(ctx["extras"], argv[j])
                    j = j + 1
                start = nxt
            if start >= n:
                break
            start = self._consume_optional(st, ctx, start)
        stop := self._consume_positionals(st, ctx, start, true)
        j2 := stop
        while j2 < n:
            if kinds[j2] != "-":
                append(ctx["extras"], argv[j2])
            j2 = j2 + 1
        self._check_required(ctx, st)
        return null

    func _consume_positionals(st, ctx, start, final):
        pos := st["pos"]
        if len(pos) == 0:
            return start
        kinds := st["kinds"]
        argv := st["argv"]
        n := st["n"]
        avail := 0
        j := start
        while j < n and (kinds[j] == "A" or kinds[j] == "-"):
            if kinds[j] == "A":
                avail = avail + 1
            j = j + 1
        counts := null
        k := len(pos)
        while k >= 1 and counts == null:
            counts = _match_counts(pos, 0, k, avail)
            k = k - 1
        if counts == null:
            return start
        m := len(counts)
        if not final:
            while m > 0 and counts[m - 1] == 0 and not _is_rest(pos[m - 1]):
                m = m - 1
        if m == 0:
            return start
        p := start
        idx := 0
        taken_args := []
        while idx < m:
            a := pos[idx]
            c := counts[idx]
            toks := []
            if _is_rest(a):
                while p < n and kinds[p] == "-":
                    p = p + 1
                q := p
                while q < n:
                    append(toks, argv[q])
                    q = q + 1
                p = n
            else:
                got := 0
                while got < c:
                    if kinds[p] == "A":
                        append(toks, argv[p])
                        got = got + 1
                    p = p + 1
            append(taken_args, [a, toks])
            idx = idx + 1
        st["pos"] = _tail(pos, m)
        for pair in taken_args:
            self._take(pair[0], pair[1], null, ctx)
        return p

    func _explicit_count(arg, option):
        a := arg.action
        if a != "store" and a != "append" and a != "extend":
            return 0
        n := arg.nargs
        if _kind(n) == "int" and n > 1:
            self._fail(arg, _t.fmt("expected_n", [n]))
        return 1

    func _consume_optional(st, ctx, start):
        argv := st["argv"]
        kinds := st["kinds"]
        n := st["n"]
        tok := argv[start]
        m := st["opts"][start]
        if _kind(m) == "dict":
            self.error(_t.fmt("ambiguous", [tok, _t.join(", ", m["ambiguous"])]))
        entry := m[0]
        action := entry[0]
        ostr := entry[1]
        explicit := entry[2]
        if action == null:
            append(ctx["extras"], tok)
            return start + 1
        while true:
            if explicit != null:
                cnt := self._explicit_count(action, ostr)
                if cnt == 0:
                    single := not _t.starts_with(ostr, "--")
                    if single and len(explicit) > 0:
                        nxt_opt := "-" + _t.char_at(explicit, 0)
                        if contains_key(self.opt_map, nxt_opt):
                            self._take(action, [], ostr, ctx)
                            action = self.opt_map[nxt_opt]
                            ostr = nxt_opt
                            rest := _t.from_index(explicit, 1)
                            if rest == "":
                                explicit = null
                            else:
                                explicit = rest
                            continue
                    self._fail(action, _t.fmt("ignored_explicit", [_t.quote(explicit)]))
                self._take(action, [explicit], ostr, ctx)
                return start + 1
            # valeurs qui suivent
            nargs := action.nargs
            if action.action != "store" and action.action != "append" and action.action != "extend":
                self._take(action, [], ostr, ctx)
                return start + 1
            if nargs == "remainder":
                toks := []
                q := start + 1
                while q < n:
                    append(toks, argv[q])
                    q = q + 1
                self._take(action, toks, ostr, ctx)
                return n
            j := start + 1
            run := 0
            while j < n and kinds[j] == "A":
                run = run + 1
                j = j + 1
            want := 0
            if nargs == null:
                if run < 1:
                    self._fail(action, _t.msg("expected_one"))
                want = 1
            elif nargs == "?":
                want = run
                if want > 1:
                    want = 1
            elif nargs == "*":
                want = run
            elif nargs == "+":
                if run < 1:
                    self._fail(action, _t.msg("expected_one_or_more"))
                want = run
            else:
                if run < nargs:
                    self._fail(action, _t.fmt("expected_n", [nargs]))
                want = nargs
            toks2 := []
            q2 := 0
            while q2 < want:
                append(toks2, argv[start + 1 + q2])
                q2 = q2 + 1
            self._take(action, toks2, ostr, ctx)
            return start + 1 + want
        return start + 1

    # --- application d'une action ------------------------------------------------------------------

    func _values_of(arg, toks):
        nargs := arg.nargs
        if nargs == "remainder":
            return _copy(toks)
        if nargs == null:
            return self._convert(arg, toks[0])
        if nargs == "?":
            if len(toks) == 0:
                if arg.positional:
                    return arg.default
                return arg.constant
            return self._convert(arg, toks[0])
        if nargs == "*" and len(toks) == 0:
            if arg.positional:
                if arg.default != null:
                    return arg.default
                return []
            if arg.constant != null:
                return arg.constant
            return []
        out := []
        for t in toks:
            append(out, self._convert(arg, t))
        return out

    func _take(arg, toks, ostr, ctx):
        ns := ctx["ns"]
        a := arg.action
        if arg.mutex != null:
            g := arg.mutex
            prev := null
            if contains_key(ctx["mutex_seen"], g.id):
                prev = ctx["mutex_seen"][g.id]
            if prev != null and prev.id != arg.id:
                self._fail(arg, _t.fmt("not_allowed", [self._argname(prev)]))
            ctx["mutex_seen"][g.id] = arg
        ctx["seen"][arg.id] = true
        if a == "help":
            raise("ArgparseHelp", self.format_help())
        if a == "version":
            text := arg.version
            if text == null:
                text = ""
            raise("ArgparseVersion", _t.replace_all(text, "%(prog)s", self.prog) + "\n")
        if a == "parser":
            name := toks[0]
            target := arg.sub.find(name)
            if target == null:
                shown := []
                for c in arg.sub.commands:
                    if not c.hidden:
                        append(shown, _t.quote(c.name))
                self._fail(arg, _t.fmt("invalid_choice", [_t.quote(name), _t.join(", ", shown)]))
            if arg.sub.dest != null:
                ns[arg.sub.dest] = target.name
            append(ctx["path"], target.name)
            append(ctx["parsers"], target)
            target._parse(_tail(toks, 1), ctx)
            return null
        key := arg.dest
        ctx["explicit"][key] = true
        if a == "store":
            ns[key] = self._values_of(arg, toks)
        elif a == "store_const":
            ns[key] = arg.constant
        elif a == "store_true":
            ns[key] = true
        elif a == "store_false":
            ns[key] = false
        elif a == "boolean_optional":
            ns[key] = not _t.starts_with(ostr, "--no-")
        elif a == "count":
            cur := 0
            if contains_key(ns, key) and _kind(ns[key]) == "int":
                cur = ns[key]
            ns[key] = cur + 1
        elif a == "append" or a == "append_const" or a == "extend":
            cur_list := []
            if contains_key(ns, key) and _kind(ns[key]) == "list":
                cur_list = _copy(ns[key])
            if a == "append":
                append(cur_list, self._values_of(arg, toks))
            elif a == "append_const":
                append(cur_list, arg.constant)
            else:
                for v in self._values_of(arg, toks):
                    append(cur_list, v)
            ns[key] = cur_list
        return null

    # --- contrôles finaux ---------------------------------------------------------------------------------

    func _check_required(ctx, st):
        seen := ctx["seen"]
        missing := []
        for a in self.args:
            if a.action == "help" or a.action == "version":
                continue
            if not a.required:
                continue
            if contains_key(seen, a.id):
                continue
            append(missing, self._argname(a))
        if len(missing) > 0:
            self.error(_t.fmt("required", [_t.join(", ", missing)]))
        for g in self.mutexes:
            if not g.required:
                continue
            hit := false
            for a in g.args:
                if contains_key(seen, a.id):
                    hit = true
            if not hit:
                names := []
                for a in g.args:
                    if not a.hidden:
                        append(names, self._argname(a))
                self.error(_t.fmt("mutex_required", [_t.join(" ", names)]))
        return null

func _derive_dest(names):
    chosen := names[0]
    for n in names:
        if _t.starts_with(n, "--"):
            chosen = n
            break
    i := 0
    while i < len(chosen) and _t.char_at(chosen, i) == "-":
        i = i + 1
    return _t.replace_all(_t.from_index(chosen, i), "-", "_")

# Nom de programme par défaut : nom de fichier du script, sans « .al ».
func _default_prog():
    full := _os.argv()
    if len(full) == 0:
        return "prog"
    path := full[0]
    base := path
    i := len(path) - 1
    while i >= 0:
        c := _t.char_at(path, i)
        if c == "/" or c == "\\":
            base = _t.from_index(path, i + 1)
            i = -1
        else:
            i = i - 1
    if len(base) > 3 and _t.from_index(base, len(base) - 3) == ".al":
        base = _t.head(base, len(base) - 3)
    if base == "":
        return "prog"
    return base
