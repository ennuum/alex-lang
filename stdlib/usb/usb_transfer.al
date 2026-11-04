# ALEX STANDARD LIBRARY — usb.usb_transfer
#
# Transferts USB depuis une APPLICATION (Linux, usbfs : /dev/bus/usb/BBB/DDD, sans pilote du noyau pour
# l'interface utilisée) : contrôle (requête SETUP + données), bloc (bulk), interruption ; délais ; résultat
# avec octets reçus, nombre envoyé, ou erreur (nom errno : ETIMEDOUT, EPIPE = point d'accès bloqué (STALL),
# ENODEV = débranché, EACCES = droits : voir hardware.permissions.udev_rule).
#
#   use usb.usb_transfer as ut
#   use usb.usb_descriptor as ud
#   r := ut.control(fd, ud.get_descriptor(ud.DT_DEVICE, 0, 18), null, 1000)
#   if r.ok:
#       print(r.data)                              # list[int]
#   r = ut.bulk_out(fd, 0x02, [0x55, 0x53, 0x42, 0x43], 1000)
#   r = ut.interrupt_in(fd, 0x81, 8, 100)          # ETIMEDOUT si rien n'arrive
#
# Les fonctions ne lèvent pas d'erreur : regarder r.ok / r.error. raise_for(r) la lève (UsbError).

from core use len, type
use _native_fd as _f
use _native_net as _b
use usb.usb_descriptor as ud

class TransferResult:
    func init(kind, endpoint):
        self.kind = kind              # "control", "bulk", "interrupt"
        self.endpoint = endpoint
        self.ok = false
        self.data = []                # octets reçus (entrée)
        self.length = 0               # octets transférés
        self.errno = 0
        self.error = null             # nom errno (« ETIMEDOUT »)
        self.message = null

    func timed_out():
        return self.error == "ETIMEDOUT"

    func stalled():
        return self.error == "EPIPE"

    func disconnected():
        return self.error == "ENODEV" or self.error == "ESHUTDOWN"

    func describe():
        if self.ok:
            return self.kind + " EP " + str(self.endpoint) + " : " + str(self.length) + " octets"
        return self.kind + " EP " + str(self.endpoint) + " : " + str(self.error) + " (" + str(self.message) + ")"

func _finish(r, v, input):
    if type(v) == "int":
        if v < 0:
            r.errno = -v
            r.error = _f.errno_name(-v)
            r.message = _f.strerror(-v)
            return r
        r.ok = true
        r.length = v
        return r
    r.ok = true
    if input:
        r.data = _b.to_bytes(v)
    r.length = len(r.data)
    return r

# Transfert de contrôle : setup (usb_descriptor.SetupPacket) ; data : octets à envoyer (sortie) ou null.
func control(fd, setup, data=null, timeout_ms=1000):
    r := TransferResult("control", 0)
    payload := null
    if setup.is_in():
        payload = setup.length
    elif data != null:
        payload = _b.from_bytes(data)
    else:
        payload = ""
    v := _f.usb_control(fd, setup.request_type, setup.request, setup.value, setup.index, payload, timeout_ms)
    return _finish(r, v, setup.is_in())

func _bulk(kind, fd, endpoint, data_or_length, timeout_ms):
    r := TransferResult(kind, endpoint)
    input := endpoint & 0x80 != 0
    payload := data_or_length
    if not input:
        payload = _b.from_bytes(data_or_length)
    v := _f.usb_bulk(fd, endpoint, payload, timeout_ms)
    return _finish(r, v, input)

func bulk_in(fd, endpoint, length, timeout_ms=1000):
    return _bulk("bulk", fd, endpoint | 0x80, length, timeout_ms)

func bulk_out(fd, endpoint, data, timeout_ms=1000):
    return _bulk("bulk", fd, endpoint & 0x7F, data, timeout_ms)

# Les points d'accès d'interruption passent par le même appel qu'en bloc avec usbfs.
func interrupt_in(fd, endpoint, length, timeout_ms=1000):
    return _bulk("interrupt", fd, endpoint | 0x80, length, timeout_ms)

func interrupt_out(fd, endpoint, data, timeout_ms=1000):
    return _bulk("interrupt", fd, endpoint & 0x7F, data, timeout_ms)

func raise_for(r):
    if not r.ok:
        raise("UsbError", r.describe())
    return r

# Descripteur (type, index) : list[int] ou null.
func get_descriptor(fd, kind, index, length, timeout_ms=1000):
    r := control(fd, ud.get_descriptor(kind, index, length), null, timeout_ms)
    if not r.ok:
        return null
    return r.data

# Chaîne index dans la première langue proposée : str, ou null.
func get_string(fd, index, timeout_ms=1000):
    if index == 0:
        return null
    langs := control(fd, ud.get_string(0, 0, 255), null, timeout_ms)
    if not langs.ok:
        return null
    ids := ud.parse_languages(langs.data)
    lang := 0x0409
    if len(ids) > 0:
        lang = ids[0]
    r := control(fd, ud.get_string(index, lang, 255), null, timeout_ms)
    if not r.ok:
        return null
    return ud.parse_string(r.data)
