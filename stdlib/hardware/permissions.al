# ALEX STANDARD LIBRARY — hardware.permissions
#
# Qui a le droit de toucher à quel matériel ? Sous Linux, l'accès aux périphériques passe par les nœuds de /dev
# (propriétaire, groupe, bits rwx), par les groupes de l'utilisateur (video, audio, input, dialout, plugdev,
# disk, render, kvm...) et par les capacités du processus (CAP_SYS_RAWIO pour les ports, CAP_NET_ADMIN...).
# Ce module répond à « puis-je ? », explique « pourquoi pas ? » et propose le correctif (groupe à rejoindre,
# règle udev à installer).
#
#   use hardware.permissions as perm
#   print(perm.current().describe())             # uid, groupes, root, capacités
#   a := perm.check("/dev/video0")
#   if not a.allowed("rw"):
#       print(a.explain())                       # « /dev/video0 appartient au groupe video ; ... usermod -aG video ... »
#   print(perm.check_category("camera"))         # tous les nœuds d'une catégorie
#   print(perm.udev_rule(0x0483, 0x5740))        # règle pour un périphérique USB (vendeur, produit)
#
# Hors Linux (ou POSIX), check renvoie seulement l'existence et os.access.
#
# Erreurs : ArgumentError (catégorie inconnue).

from core use len, type
from collections use append, contains_key, keys, sort
use string as _s
use os as _os
use hardware._sys as _sys
use _native_fd as _f

# Capacités Linux (numéro de bit) les plus utiles pour le matériel.
const CAPABILITIES := {"chown": 0, "dac_override": 1, "dac_read_search": 2, "fowner": 3, "kill": 5, "setgid": 6, "setuid": 7,
                       "net_bind_service": 10, "net_broadcast": 11, "net_admin": 12, "net_raw": 13, "ipc_lock": 14,
                       "sys_module": 16, "sys_rawio": 17, "sys_chroot": 18, "sys_ptrace": 19, "sys_admin": 21, "sys_boot": 22,
                       "sys_nice": 23, "sys_resource": 24, "sys_time": 25, "sys_tty_config": 26, "mknod": 27,
                       "audit_write": 29, "setfcap": 31, "syslog": 34, "wake_alarm": 35, "block_suspend": 36, "bpf": 39,
                       "perfmon": 38, "checkpoint_restore": 40}

# Catégorie de matériel -> motifs de nœuds /dev et groupe habituel.
const CATEGORIES := {"camera": [["/dev/video", "/dev/media"], "video"],
                     "gpu": [["/dev/dri/card", "/dev/dri/renderD", "/dev/fb"], "video"],
                     "render": [["/dev/dri/renderD"], "render"],
                     "audio": [["/dev/snd/"], "audio"],
                     "input": [["/dev/input/event", "/dev/input/mouse", "/dev/input/js", "/dev/uinput"], "input"],
                     "serial": [["/dev/ttyS", "/dev/ttyUSB", "/dev/ttyACM"], "dialout"],
                     "usb": [["/dev/bus/usb/"], "plugdev"],
                     "storage": [["/dev/sd", "/dev/nvme", "/dev/vd", "/dev/mmcblk"], "disk"],
                     "kvm": [["/dev/kvm"], "kvm"],
                     "memory": [["/dev/mem", "/dev/port"], "kmem"],
                     "hidraw": [["/dev/hidraw"], "plugdev"]}

func _mode_text(mode):
    out := ""
    chars := "rwxrwxrwx"
    i := 0
    while i < 9:
        if mode & (1 << (8 - i)) != 0:
            out = out + str(chars[i])
        else:
            out = out + "-"
        i += 1
    return out

# ---------------------------------------------------------------- identité du processus
class Identity:
    func init():
        ids := _f.ids()
        self.uid = ids[0]
        self.euid = ids[1]
        self.gid = ids[2]
        self.egid = ids[3]
        self.groups = ids[4]
        if not _has(self.groups, self.egid):
            append(self.groups, self.egid)
        self.user = _f.user_name(self.euid)
        self.capabilities = _caps("CapEff")
        self.bounding = _caps("CapBnd")

    func is_root():
        return self.euid == 0

    func group_names():
        out := []
        for g in self.groups:
            n := _f.group_name(g)
            append(out, n if n != null else str(g))
        return out

    func in_group(name_or_gid):
        gid := name_or_gid
        if type(name_or_gid) == "str":
            gid = _f.group_id(name_or_gid)
            if gid < 0:
                return false
        return _has(self.groups, gid)

    # Le processus a-t-il cette capacité (nom sans « cap_ », ou numéro) ?
    func has_capability(cap):
        bit := cap
        if type(cap) == "str":
            n := _s.lower(cap)
            if _s.starts_with(n, "cap_"):
                n = _s.slice(n, 4)
            if not contains_key(CAPABILITIES, n):
                raise("ArgumentError", "permissions : capacité inconnue '" + cap + "'")
            bit = CAPABILITIES[n]
        if self.capabilities == null:
            return self.is_root()
        return (self.capabilities >> bit) & 1 == 1

    func capability_names():
        out := []
        for k in _sorted(keys(CAPABILITIES)):
            if self.has_capability(k):
                append(out, k)
        return out

    func describe():
        t := "utilisateur " + str(self.user) + " (uid " + str(self.euid) + "), groupes : " + _s.join(", ", self.group_names())
        if self.is_root():
            t = t + " — root"
        elif self.capabilities != null and self.capabilities != 0:
            t = t + " — capacités : " + _s.join(", ", self.capability_names())
        return t

func _has(xs, v):
    for x in xs:
        if x == v:
            return true
    return false

func _caps(field):
    text := _sys.read("/proc/self/status")
    if text == null:
        return null
    for line in _s.split(text, "\n"):
        if _s.starts_with(line, field + ":"):
            return _sys.hex(_s.trim(_s.slice(line, len(field) + 1)))
    return null

func current():
    return Identity()

# ---------------------------------------------------------------- accès à un nœud
class Access:
    func init(path, ident):
        self.path = path
        self.identity = ident
        st := _f.stat(_sys.p(path))
        self.exists = st != null
        self.mode = null
        self.owner = null
        self.group = null
        self.owner_name = null
        self.group_name = null
        self.kind = _f.file_kind(_sys.p(path))
        self.device = null
        if st != null:
            self.mode = st[0] & 4095
            self.owner = st[1]
            self.group = st[2]
            self.owner_name = _f.user_name(st[1])
            self.group_name = _f.group_name(st[2])
            if self.kind == "char" or self.kind == "block":
                self.device = [st[3], st[4]]

    # Droits effectifs : sous-ensemble de "rwx" accordé au processus.
    func rights():
        if not self.exists:
            return ""
        out := ""
        if _os.access(_sys.p(self.path), "r"):
            out = out + "r"
        if _os.access(_sys.p(self.path), "w"):
            out = out + "w"
        if _os.access(_sys.p(self.path), "x"):
            out = out + "x"
        return out

    func allowed(want="r"):
        r := self.rights()
        for c in want:
            if not _s.contains(r, str(c)):
                return false
        return true

    # Par quelle voie le droit est-il accordé : "root", "propriétaire", "groupe", "autres", ou null.
    func granted_by(want="r"):
        if not self.exists:
            return null
        if self.identity.is_root():
            return "root"
        bits := _want_bits(want)
        if self.owner == self.identity.euid:
            return "propriétaire" if (self.mode >> 6) & bits == bits else null
        if _has(self.identity.groups, self.group):
            return "groupe" if (self.mode >> 3) & bits == bits else null
        return "autres" if self.mode & bits == bits else null

    # Groupe à rejoindre pour obtenir want, ou null (déjà permis, ou le groupe n'a pas ce droit).
    func missing_group(want="rw"):
        if not self.exists or self.allowed(want):
            return null
        bits := _want_bits(want)
        if (self.mode >> 3) & bits == bits and not _has(self.identity.groups, self.group):
            return self.group_name if self.group_name != null else str(self.group)
        return null

    func describe():
        if not self.exists:
            return self.path + " : absent"
        t := self.path + " : " + str(self.kind) + " " + _mode_text(self.mode) + " " + str(self.owner_name) + ":" + str(self.group_name)
        if self.device != null:
            t = t + " (" + str(self.device[0]) + ", " + str(self.device[1]) + ")"
        r := self.rights()
        return t + " — droits : " + (r if r != "" else "aucun")

    # Explication en français et correctif proposé.
    func explain(want="rw"):
        if not self.exists:
            return self.path + " n'existe pas (périphérique absent, pilote non chargé, ou machine virtuelle sans ce matériel)."
        if self.allowed(want):
            return self.path + " : accès " + want + " permis (" + str(self.granted_by(want)) + ")."
        g := self.missing_group(want)
        if g != null:
            return self.path + " appartient au groupe " + g + " (" + _mode_text(self.mode) + ") dont " + str(self.identity.user) + " ne fait pas partie : « sudo usermod -aG " + g + " " + str(self.identity.user) + " » puis se reconnecter."
        return self.path + " (" + _mode_text(self.mode) + " " + str(self.owner_name) + ":" + str(self.group_name) + ") : accès " + want + " réservé à root ; une règle udev (permissions.udev_rule) ou sudo est nécessaire."

func _want_bits(want):
    b := 0
    for c in want:
        if c == 'r':
            b = b | 4
        elif c == 'w':
            b = b | 2
        elif c == 'x':
            b = b | 1
    return b

func check(path):
    return Access(path, Identity())

func can_read(path):
    return check(path).allowed("r")

func can_write(path):
    return check(path).allowed("w")

# Nœuds /dev d'une catégorie (camera, gpu, render, audio, input, serial, usb, storage, kvm, memory, hidraw).
func nodes(category):
    if not contains_key(CATEGORIES, category):
        raise("ArgumentError", "permissions : catégorie inconnue '" + category + "' (connues : " + _s.join(", ", _sorted(keys(CATEGORIES))) + ")")
    out := []
    for prefix in CATEGORIES[category][0]:
        d := _os.dirname(prefix)
        start := _os.basename(prefix)
        if _s.ends_with(prefix, "/"):
            d = _s.slice(prefix, 0, len(prefix) - 1)
            start = ""
        for n in (_sys.list(d)):
            if _s.starts_with(n, start):
                path := d + "/" + n
                k := _f.file_kind(_sys.p(path))
                if k == "char" or k == "block":
                    append(out, path)
                elif k == "dir" and category == "usb":
                    for m in (_sys.list(path)):
                        append(out, path + "/" + m)
    return out

class CategoryReport:
    func init(category, accesses, group):
        self.category = category
        self.accesses = accesses
        self.group = group               # groupe habituel de la catégorie

    func present():
        return len(self.accesses) > 0

    func usable(want="rw"):
        if len(self.accesses) == 0:
            return false
        for a in self.accesses:
            if not a.allowed(want):
                return false
        return true

    func describe():
        if len(self.accesses) == 0:
            return self.category + " : aucun nœud dans /dev"
        lines := [self.category + " : " + ("utilisable" if self.usable() else "accès incomplet")]
        for a in self.accesses:
            append(lines, "  " + a.describe())
        return _s.join("\n", lines)

func check_category(category):
    ident := Identity()
    return CategoryReport(category, [Access(p, ident) for p in nodes(category)], CATEGORIES[category][1])

# Rapport pour toutes les catégories présentes sur la machine.
func report():
    lines := [current().describe()]
    for c in _sorted(keys(CATEGORIES)):
        r := check_category(c)
        if r.present():
            append(lines, r.describe())
    return _s.join("\n", lines)

# Accès aux ports d'entrée-sortie (ioperm / /dev/port) : CAP_SYS_RAWIO.
func can_access_ports():
    return current().has_capability("sys_rawio")

# Règle udev donnant l'accès à un périphérique USB (vendeur, produit) au groupe choisi ; à écrire dans
# /etc/udev/rules.d/70-<nom>.rules puis « sudo udevadm control --reload && sudo udevadm trigger ».
func udev_rule(vendor_id, product_id=null, group="plugdev", mode="0660", subsystem="usb"):
    t := "SUBSYSTEM==\"" + subsystem + "\", ATTRS{idVendor}==\"" + _sys.hex4(vendor_id) + "\""
    if product_id != null:
        t = t + ", ATTRS{idProduct}==\"" + _sys.hex4(product_id) + "\""
    return t + ", MODE=\"" + mode + "\", GROUP=\"" + group + "\", TAG+=\"uaccess\""

func _sorted(xs):
    out := [x for x in xs]
    sort(out)
    return out
