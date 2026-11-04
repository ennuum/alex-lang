# alex: native
from core use len
from collections use append
use hw
use usb.usb_descriptor as ud
from usb.usb_descriptor use InterfaceDescriptor, EndpointDescriptor, SetupPacket
use usb_driver.usb_host_controller as uhc
from usb_driver.usb_host_controller use HostController, UsbDev
use usb_driver.usb_driver_errors as ude
use usb_driver.usb_hid as hid
use usb_driver.usb_mass_storage as ms
use usb_driver.usb_serial as us

class FakeHc implements HostController:
    log: list[str] := []
    report: list[int] := []
    echo: str := ""
    func init():
        self.log = []
        self.report = []
        self.echo = ""
    func name() -> str:
        return "faux"
    func setup():
        self.log = self.log
    func port_count() -> int:
        return 1
    func port_connected(port: int) -> bool:
        return true
    func reset_port(port: int) -> int:
        return 1
    func control(dev: UsbDev, setup: SetupPacket, buf: int) -> int:
        append(self.log, str(setup.request_type) + "/" + str(setup.request) + "/" + str(setup.value))
        if setup.request == ud.REQ_GET_DESCRIPTOR and (setup.value >> 8) == ud.DT_REPORT:
            d := hid.mouse_descriptor()
            i := 0
            while i < len(d):
                hw.poke8(buf + i, d[i])
                i += 1
            return len(d)
        return setup.length
    func bulk(dev: UsbDev, endpoint: int, max_packet: int, buf: int, length: int, tries: int) -> int:
        if endpoint & 0x80 != 0:
            if self.echo == "":
                return -1
            n := hw.byte_size(self.echo)
            hw.store_string(self.echo, buf)
            self.echo = ""
            return n
        self.echo = self.echo + hw.string_at(buf, length)
        return length
    func interrupt_open(dev: UsbDev, endpoint: int, max_packet: int) -> int:
        return 7
    func interrupt_read(pipe: int, buf: int) -> int:
        i := 0
        while i < len(self.report):
            hw.poke8(buf + i, self.report[i])
            i += 1
        return len(self.report)

print(ude.uhci_status_text(0x440000))
print(ude.uhci_error_type(0x400000))
print(ude.uhci_error_type(0x440000))
print(ude.recovery_hint(ude.STALL))
try:
    ude.check_td("ep1", 0x100000)
catch e:
    print(e.type)
lay := hid.parse_bytes(hid.mouse_descriptor())
for f in lay.fields:
    print(f.describe())
print(hid.device_kind(lay))
print(lay.report_bytes(hid.INPUT, 0))
rep := hw.alloc_pages(1)
hw.poke8(rep, 5)
hw.poke8(rep + 1, 0xFE)
hw.poke8(rep + 2, 3)
hw.poke8(rep + 3, 0xFF)
for v in lay.decode(rep, 4):
    print(v.describe())
kb := hid.parse_bytes(hid.keyboard_descriptor())
print(hid.device_kind(kb))
print(kb.report_bytes(hid.INPUT, 0))
print(kb.report_bytes(hid.OUTPUT, 0))
hw.zero(rep, 8)
hw.poke8(rep, 0x02)
hw.poke8(rep + 2, 4)
hw.poke8(rep + 3, 5)
for v in kb.decode(rep, 8):
    if v.value != 0:
        print(v.describe())
try:
    hid.parse_bytes([0xC0])
catch e:
    print(e.type)
hc := FakeHc()
dev := UsbDev(1, 1, 1)
itf := InterfaceDescriptor(0, 0, ud.CLASS_HID, 0, 0)
append(itf.endpoints, EndpointDescriptor(0x81, 3, 4, 10))
itf.hid_report_length = 52
h := hid.HidDevice()
print(h.matches(dev, itf))
h.attach(hc, dev, itf)
hc.report = [1, 10, 0xF6, 1]
print(h.poll())
print(h.value(hid.PAGE_BUTTON, 1))
print(h.value(hid.PAGE_GENERIC, 0x31))
print(h.pressed(hid.PAGE_BUTTON))
print(h.describe())
buf := hw.alloc_pages(1)
ms.write_cbw(buf, 9, 512, true, 0, ms.cdb_read(100, 1))
print(hw.peek32(buf) == ms.CBW_SIGNATURE)
print(hw.peek8(buf + 14))
print(hw.peek8(buf + 15))
print(len(ms.cdb_read(0x100000000, 8)))
ms.write_csw(buf, 9, 0, 1)
c := ms.parse_csw(buf, 13)
print(c.describe())
try:
    ms.parse_csw(buf, 12)
catch e:
    print(e.type)
hw.zero(buf, 64)
hw.poke8(buf, 0x70)
hw.poke8(buf + 2, 2)
hw.poke8(buf + 12, 0x3A)
s := ms.parse_sense(buf, 18)
print(s.describe())
print(ms.sense_action(s))
hw.poke8(buf + 12, 0x04)
hw.poke8(buf + 13, 0x01)
print(ms.sense_action(ms.parse_sense(buf, 18)))
hw.zero(buf, 64)
hw.poke8(buf + 1, 0x80)
hw.store_string("ALEXCORPCle USB magique 1.00", buf + 8)
print(ms.parse_inquiry(buf, 36).describe())
hw.zero(buf, 16)
hw.poke8(buf, 0xFF)
hw.poke8(buf + 1, 0xFF)
hw.poke8(buf + 2, 0xFF)
hw.poke8(buf + 3, 0xFF)
hw.poke8(buf + 6, 2)
print(ms.parse_capacity10(buf, 8))
hw.zero(buf, 16)
hw.poke8(buf + 3, 1)
hw.poke8(buf + 7, 0xFF)
hw.poke8(buf + 10, 2)
print(ms.parse_capacity16(buf, 12))
print(len(ms.reset_recovery(0, 0x81, 0x02)))
lc := us.LineCoding(115200, 8, us.PARITY_EVEN, us.STOP_2)
print(lc.describe())
print(lc.to_bytes())
lc.write(buf)
print(us.read_line_coding(buf).describe())
try:
    us.LineCoding(9600, 9, 0, 0)
catch e:
    print(e.type)
print(us.ftdi_divisor(115200, 3000000))
print(us.ftdi_divisor(9600, 3000000))
print(us.ftdi_error_permille(115200, 3000000))
print(us.ftdi_divisor(3000000, 3000000))
data := InterfaceDescriptor(1, 0, ud.CLASS_CDC_DATA, 0, 0)
append(data.endpoints, EndpointDescriptor(0x82, 2, 64, 0))
append(data.endpoints, EndpointDescriptor(0x02, 2, 64, 0))
acm := us.AcmSerial()
print(acm.matches(dev, data))
acm.attach(hc, dev, data)
print(acm.write("bonjour\r\n"))
print(acm.read())
print(acm.describe())
print(hc.log)
hw.zero(buf, 16)
hw.poke8(buf + 1, 0x20)
hw.poke16(buf + 8, 3)
print(us.serial_state_text(buf, 10))
