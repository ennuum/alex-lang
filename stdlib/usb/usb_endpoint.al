# ALEX STANDARD LIBRARY — usb.usb_endpoint
#
# Un point d'accès d'une interface réclamée (UsbHandle.claim) : lecture / écriture selon son type (bloc,
# interruption), avec la taille de paquet du descripteur ; lecture d'un message complet (jusqu'à un paquet
# court) ; levée du blocage (STALL).
#
#   h := dev.open()
#   h.claim(0)
#   ep := h.endpoint(0x81)                     # Endpoint
#   r := ep.read(64, 500)                      # TransferResult
#   out := h.endpoint(0x02)
#   out.write([1, 2, 3])
#
# Erreurs : ArgumentError (sens inversé). Les transferts renvoient un TransferResult (usb.usb_transfer).

from core use len
from collections use append
use _native_fd as _f
use usb.usb_descriptor as ud
use usb.usb_transfer as ut

class Endpoint:
    func init(handle, descriptor):
        self.handle = handle
        self.descriptor = descriptor          # usb_descriptor.EndpointDescriptor
        self.address = descriptor.address
        self.kind = descriptor.transfer_type()
        self.packet_size = descriptor.packet_size()
        self.transfers = 0
        self.bytes = 0

    func is_in():
        return self.descriptor.is_in()

    func kind_name():
        return ud.transfer_name(self.kind)

    func _count(r):
        self.transfers += 1
        if r.ok:
            self.bytes += r.length
        return r

    # Lit au plus length octets (par défaut un paquet).
    func read(length=null, timeout_ms=1000):
        if not self.is_in():
            raise("ArgumentError", "Endpoint.read : point d'accès de sortie " + str(self.address))
        n := length if length != null else self.packet_size
        if self.kind == ud.EP_INTERRUPT:
            return self._count(ut.interrupt_in(self.handle.fd, self.address, n, timeout_ms))
        return self._count(ut.bulk_in(self.handle.fd, self.address, n, timeout_ms))

    func write(data, timeout_ms=1000):
        if self.is_in():
            raise("ArgumentError", "Endpoint.write : point d'accès d'entrée " + str(self.address))
        if self.kind == ud.EP_INTERRUPT:
            return self._count(ut.interrupt_out(self.handle.fd, self.address, data, timeout_ms))
        return self._count(ut.bulk_out(self.handle.fd, self.address, data, timeout_ms))

    # Lit des paquets jusqu'à un paquet court (fin de message) ou max_bytes ; renvoie list[int] (null si erreur).
    func read_message(max_bytes=65536, timeout_ms=1000):
        out := []
        while len(out) < max_bytes:
            r := self.read(self.packet_size, timeout_ms)
            if not r.ok:
                return out if len(out) > 0 else null
            for b in r.data:
                append(out, b)
            if r.length < self.packet_size:
                break
        return out

    func clear_halt():
        return _f.usb_clear_halt(self.handle.fd, self.address) == 0

    func describe():
        return self.descriptor.describe() + " — " + str(self.transfers) + " transferts, " + str(self.bytes) + " octets"
