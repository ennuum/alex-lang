# ALEX STANDARD LIBRARY — usb.usb_interface
#
# Interfaces USB vues comme des FONCTIONS du périphérique : regroupement des réglages alternatifs d'un même
# numéro d'interface, recherche de points d'accès (sens, type), BANDE PASSANTE des points d'accès périodiques
# (interruption, isochrone) selon la vitesse, et lecture des descripteurs de CLASSE rangés avec l'interface :
# HID (pays, longueur du descripteur de rapport), CDC (en-tête, union maître / esclaves, gestion d'appel, ACM),
# audio (sous-type des descripteurs de contrôle / flux).
#
#   use usb.usb_interface as ui
#   cfg := device.configuration()                       # usb.usb_descriptor.ConfigurationDescriptor
#   for f in ui.functions(cfg):                         # UsbInterface (toutes les alternatives d'un numéro)
#       print(f.number, f.class_name(), len(f.alternates))
#   f := ui.find(cfg, 0x02)                             # première interface CDC
#   print(f.cdc_union())                                # [maître, [esclaves]] (ex. [0, [1]])
#   ep := f.endpoint(usb_descriptor.EP_BULK, true)      # point d'accès bloc entrant
#   alt := f.best_alternate(usb_descriptor.EP_ISOCHRONOUS, 1000000, "high")  # réglage assurant 1 Mo/s
#   print(ui.bandwidth(ep, "high"))                     # octets / seconde réservés
#
# Erreurs : ArgumentError (vitesse inconnue, interface absente).

from core use len, type
from collections use append
use usb.usb_descriptor as ud

const CDC_HEADER := 0x00
const CDC_CALL_MANAGEMENT := 0x01
const CDC_ACM := 0x02
const CDC_UNION := 0x06
const CDC_ETHERNET := 0x0F
const CS_INTERFACE := 0x24
const CS_ENDPOINT := 0x25

func _frames_per_second(speed):
    if speed == "low" or speed == "full":
        return 1000
    if speed == "high" or speed == "super":
        return 8000
    raise("ArgumentError", "vitesse USB inconnue : " + str(speed) + " (low, full, high, super)")

# Octets par seconde réservés par un point d'accès périodique (0 pour bloc et contrôle).
func bandwidth(ep, speed="full"):
    t := ep.transfer_type()
    if t != ud.EP_INTERRUPT and t != ud.EP_ISOCHRONOUS:
        return 0
    per_frame := ep.packet_size()
    if speed == "high" or speed == "super":
        per_frame = per_frame * (((ep.max_packet >> 11) & 3) + 1)
    fps := _frames_per_second(speed)
    interval := ep.interval
    if interval < 1:
        interval = 1
    if speed == "high" or speed == "super" or t == ud.EP_ISOCHRONOUS:
        # intervalle exprimé en 2^(bInterval-1) (micro-)trames
        n := 1
        k := 1
        while k < interval and k < 16:
            n = n * 2
            k += 1
        return per_frame * fps // n
    return per_frame * fps // interval

class UsbInterface:
    func init(number, alternates):
        self.number = number
        self.alternates = alternates          # InterfaceDescriptor, réglage 0 en tête
        self.current = 0

    func descriptor():
        for a in self.alternates:
            if a.alternate == self.current:
                return a
        return self.alternates[0]

    func iclass():
        return self.descriptor().iclass

    func class_name():
        return ud.class_name(self.iclass())

    func endpoints():
        return self.descriptor().endpoints

    func endpoint(kind, input):
        return self.descriptor().endpoint(kind, input)

    func alternate(n):
        for a in self.alternates:
            if a.alternate == n:
                return a
        return null

    # Bande passante totale d'un réglage.
    func bandwidth(alt=null, speed="full"):
        d := self.descriptor()
        if alt != null:
            d = self.alternate(alt)
        total := 0
        for e in d.endpoints:
            total += bandwidth(e, speed)
        return total

    # Plus petit réglage dont un point d'accès du type demandé atteint min_bytes_per_s (null sinon).
    func best_alternate(kind, min_bytes_per_s, speed="full"):
        best := null
        best_bw := 0
        for a in self.alternates:
            for e in a.endpoints:
                if e.transfer_type() == kind:
                    bw := bandwidth(e, speed)
                    if bw >= min_bytes_per_s and (best == null or bw < best_bw):
                        best = a.alternate
                        best_bw = bw
        return best

    func class_descriptors(kind=CS_INTERFACE):
        out := []
        for a in self.alternates:
            for x in a.extra:
                if len(x) >= 3 and x[1] == kind:
                    append(out, x)
        return out

    # CDC : [maître, [esclaves]] du descripteur d'union, ou null.
    func cdc_union():
        for x in self.class_descriptors():
            if x[2] == CDC_UNION and len(x) >= 5:
                return [x[3], [x[k] for k in 4..len(x)]]
        return null

    # CDC ACM : capacités (bits : 1 commandes de ligne, 2 rupture, 4 notification réseau...).
    func cdc_acm_capabilities():
        for x in self.class_descriptors():
            if x[2] == CDC_ACM and len(x) >= 4:
                return x[3]
        return null

    func cdc_call_management():
        for x in self.class_descriptors():
            if x[2] == CDC_CALL_MANAGEMENT and len(x) >= 5:
                return {"capabilities": x[3], "data_interface": x[4]}
        return null

    func cdc_version():
        for x in self.class_descriptors():
            if x[2] == CDC_HEADER and len(x) >= 5:
                return ud.bcd_text(x[3] | (x[4] << 8))
        return null

    # HID : longueur du descripteur de rapport, et code pays.
    func hid_info():
        d := self.descriptor()
        if d.iclass != ud.CLASS_HID:
            return null
        return {"report_length": d.hid_report_length, "boot_keyboard": d.is_boot_keyboard(), "boot_mouse": d.is_boot_mouse()}

    # Audio : sous-types des descripteurs de classe (1 en-tête, 2 terminal d'entrée, 3 de sortie...).
    func audio_subtypes():
        if self.iclass() != ud.CLASS_AUDIO:
            return []
        return [x[2] for x in self.class_descriptors()]

    func describe():
        t := "interface " + str(self.number) + " : " + self.class_name() + ", " + str(len(self.alternates)) + " réglage(s)"
        for e in self.endpoints():
            t += "\n  " + e.describe()
        return t

# Interfaces (regroupées par numéro) d'une configuration.
func functions(cfg):
    out := []
    index := {}
    for i in cfg.interfaces:
        if i.number in index:
            append(out[index[i.number]].alternates, i)
        else:
            index[i.number] = len(out)
            append(out, UsbInterface(i.number, [i]))
    return out

func find(cfg, iclass):
    for f in functions(cfg):
        if f.iclass() == iclass:
            return f
    return null

func get(cfg, number):
    for f in functions(cfg):
        if f.number == number:
            return f
    raise("ArgumentError", "interface " + str(number) + " absente de la configuration " + str(cfg.value))
