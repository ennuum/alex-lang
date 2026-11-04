# ALEX STANDARD LIBRARY — modules.plugin
#
# Système de greffons (plugins) : des composants qui s'enregistrent auprès d'une application, déclarent
# leurs dépendances entre eux, sont activés dans le bon ordre, et étendent l'application par des POINTS
# D'EXTENSION (hooks).
#
#   use modules.plugin as plg

#   pm := plg.PluginManager({"app": "demo"})
#   pm.register(plg.SimplePlugin("journal", "1.0.0", [], (ctx) => ctx.on("requete", (r) => noter(r))))
#   pm.register(plg.SimplePlugin("auth", "2.1.0", ["journal"], activer_auth))
#   pm.activate_all()                       # journal puis auth (ordre des dépendances)
#   resultats := pm.emit("requete", req)    # appelle tous les gestionnaires du point « requete »
#   pm.deactivate_all()                     # ordre inverse
#
# Un greffon implémente l'interface Plugin : name(), version(), requires(), activate(ctx), deactivate(ctx).
# BasePlugin en fournit une base à étendre (from modules.plugin use BasePlugin).
# Erreurs : PluginError (doublon, dépendance absente ou de version incompatible, activation en échec),
#           DependencyCycleError.

from core use len, type
from collections use append
use string as _s
use modules.version as _v
use modules.dependency as _dep

const ERROR := "PluginError"

interface Plugin:
    func name()
    func version()
    func requires()
    func activate(ctx)
    func deactivate(ctx)

class BasePlugin implements Plugin:
    func init(name, version="0.1.0", requires=null):
        self._name = name
        self._version = version
        self._requires = requires
        if self._requires == null:
            self._requires = []

    func name():
        return self._name

    func version():
        return self._version

    # Liste de noms, ou de « nom@contrainte » (ex. "journal@^1.0").
    func requires():
        return self._requires

    func activate(ctx):
        return null

    func deactivate(ctx):
        return null

# Greffon construit à partir de fonctions (sans écrire de classe).
class SimplePlugin extends BasePlugin:
    func init(name, version="0.1.0", requires=null, on_activate=null, on_deactivate=null):
        super.init(name, version, requires)
        self._on = on_activate
        self._off = on_deactivate

    func activate(ctx):
        if self._on != null:
            return self._on(ctx)
        return null

    func deactivate(ctx):
        if self._off != null:
            return self._off(ctx)
        return null

# Contexte passé aux greffons : configuration partagée, services, points d'extension.
class PluginContext:
    func init(manager, plugin_name):
        self._m = manager
        self.plugin = plugin_name
        self.config = manager.config

    # Abonne handler au point d'extension hook.
    func on(hook, handler, priority=0):
        self._m.add_hook(hook, handler, self.plugin, priority)

    # Publie un service (objet) pour les autres greffons.
    func provide(service_name, service):
        self._m.provide(service_name, service, self.plugin)

    func service(service_name):
        return self._m.service(service_name)

    func emit(hook, *args):
        return self._m.emit(hook, *args)

class PluginManager:
    func init(config=null):
        self.config = config
        if self.config == null:
            self.config = {}
        self._plugins = {}
        self._order = []
        self._active = []
        self._hooks = {}
        self._services = {}
        self.errors = []

    func register(plugin):
        if not isinstance(plugin, Plugin):
            raise("TypeError", "PluginManager.register : Plugin attendu")
        n := plugin.name()
        if n in self._plugins:
            raise(ERROR, "greffon '" + n + "' déjà enregistré")
        if not _v.is_valid(plugin.version()):
            raise(ERROR, "greffon '" + n + "' : version invalide '" + plugin.version() + "'")
        self._plugins[n] = plugin
        append(self._order, n)
        return plugin

    func get(name):
        if not (name in self._plugins):
            raise(ERROR, "greffon '" + name + "' inconnu")
        return self._plugins[name]

    func names():
        return self._order[:]

    func is_active(name):
        for a in self._active:
            if a == name:
                return true
        return false

    func _requirements(p):
        out := []
        for r in p.requires():
            append(out, _dep.parse_spec(r))
        return out

    # Ordre d'activation (dépendances d'abord) ; vérifie présence et versions.
    func activation_order():
        g := _dep.DependencyGraph()
        for n in self._order:
            g.add_node(n)
            for d in self._requirements(self._plugins[n]):
                if not (d.name in self._plugins):
                    raise(ERROR, "greffon '" + n + "' : dépendance '" + d.name + "' absente")
                dv := self._plugins[d.name].version()
                if not d.accepts(dv):
                    raise(ERROR, "greffon '" + n + "' : exige " + d.name + " " + str(d.constraint) + ", présent " + dv)
                g.add_edge(n, d.name)
        return g.topological_order()

    func activate(name):
        if self.is_active(name):
            return
        p := self.get(name)
        for d in self._requirements(p):
            self.activate(d.name)
        try:
            p.activate(PluginContext(self, name))
        catch e:
            self._remove_owned(name)
            raise(ERROR, "activation de '" + name + "' : " + e.type + " : " + e.message)
        append(self._active, name)

    func activate_all():
        for n in self.activation_order():
            self.activate(n)
        return self._active[:]

    func deactivate(name):
        if not self.is_active(name):
            return
        # Les greffons qui en dépendent d'abord.
        for other in self._active[::-1]:
            for d in self._requirements(self._plugins[other]):
                if d.name == name:
                    self.deactivate(other)
        p := self._plugins[name]
        try:
            p.deactivate(PluginContext(self, name))
        catch e:
            append(self.errors, name + " : " + e.type + " : " + e.message)
        self._remove_owned(name)
        self._active = [a for a in self._active if a != name]

    func deactivate_all():
        for n in self._active[::-1]:
            self.deactivate(n)

    func active():
        return self._active[:]

    # ------------------------------------------------------------ points d'extension

    func add_hook(hook, handler, owner=null, priority=0):
        if type(handler) != "function":
            raise("TypeError", "add_hook : gestionnaire (fonction) attendu")
        if not (hook in self._hooks):
            self._hooks[hook] = []
        lst := self._hooks[hook]
        entry := [priority, owner, handler]
        i := 0
        while i < len(lst) and lst[i][0] >= priority:
            i += 1
        self._hooks[hook] = lst[:i] + [entry] + lst[i:]

    func hooks():
        return [h for h in self._hooks]

    func handler_count(hook):
        if not (hook in self._hooks):
            return 0
        return len(self._hooks[hook])

    # Appelle chaque gestionnaire (priorité décroissante) ; renvoie la liste de leurs résultats.
    func emit(hook, *args):
        if not (hook in self._hooks):
            return []
        return [e[2](*args) for e in self._hooks[hook]]

    # Passe value à travers les gestionnaires : value = h(value) (filtre / transformation en chaîne).
    func pipe(hook, value):
        if not (hook in self._hooks):
            return value
        v := value
        for e in self._hooks[hook]:
            v = e[2](v)
        return v

    func provide(service_name, service, owner=null):
        self._services[service_name] = [owner, service]

    func service(service_name):
        if not (service_name in self._services):
            raise(ERROR, "service '" + service_name + "' non fourni")
        return self._services[service_name][1]

    func has_service(service_name):
        return service_name in self._services

    func _remove_owned(name):
        for h in self._hooks:
            self._hooks[h] = [e for e in self._hooks[h] if e[1] != name]
        for s in [k for k in self._services]:
            if self._services[s][0] == name:
                del self._services[s]
