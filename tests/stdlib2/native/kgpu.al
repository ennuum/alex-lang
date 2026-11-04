# alex: native
from core use len
from collections use append
use hw
use driver.driver_info as di
from driver.driver_info use HwDevice
use gpu_driver.gpu_capabilities as gcap
from gpu_driver.gpu_capabilities use GpuCapabilities
use gpu_driver.gpu_command as gc
from gpu_driver.gpu_command use Surface2D, CommandBuffer
use gpu_driver.gpu_driver_errors as gde
use gpu_driver.gpu_scheduler as gs
use gpu_driver.gpu_firmware as gf
use gpu_driver.gpu_device_binding as gb

caps := GpuCapabilities("bochs", 16 * 1024 * 1024, 2560, 1600)
caps.depths = [8, 16, 24, 32]
gde.check_mode(caps, 1024, 768, 32)
try:
    gde.check_mode(caps, 4096, 768, 32)
catch e:
    print(e.type + " " + e.message)
try:
    gde.check_mode(caps, 1024, 768, 12)
catch e:
    print(e.message)
print(gde.is_fatal(gde.HANG))
mem := hw.alloc_pages(64)
a := Surface2D(mem, 64, 64, 256)
b := Surface2D(mem + 64 * 256, 64, 64, 256)
sch := gs.GpuScheduler(4)
desk := sch.context("bureau", gs.PRIO_HIGH, a)
app := sch.context("appli", gs.PRIO_NORMAL, b)
bg := sch.context("fond", gs.PRIO_NORMAL, b)
cb := CommandBuffer()
k := 0
while k < 10:
    cb.fill_rect(k, k, 4, 4, 0xFF0000)
    k += 1
v1 := sch.submit(app, cb)
v2 := sch.submit(bg, cb)
cb2 := CommandBuffer()
cb2.clear(0x000020)
cb2.fence(7)
v3 := sch.submit(desk, cb2)
print(sch.run(1))
print(sch.fence(desk) == v3)
print(sch.run(2))
print(app.preemptions)
print(sch.wait(app, v1))
print(sch.fence(bg))
print(sch.run(100))
print(sch.pending())
sch.hang_slices = 2
long := CommandBuffer()
k = 0
while k < 40:
    long.pixel(1, 1, 5)
    k += 1
sch.submit(app, long)
sch.submit(desk, cb2)
sch.run(100)
print(app.hangs)
print(sch.fence(desk))
print(sch.report())
rom := hw.alloc_pages(8)
n1 := gf.build_rom_image(rom, 0x1234, 0x1111, 0x030000, 0, 4, false)
n2 := gf.build_rom_image(rom + n1, 0x1234, 0x1111, 0x030000, 3, 2, true)
for img in gf.parse_option_rom(rom, n1 + n2):
    print(img.describe())
hw.poke8(rom + 100, 7)
print(gf.parse_option_rom(rom, n1 + n2)[0].checksum_ok)
try:
    gf.parse_option_rom(rom + 1, 100)
catch e:
    print(e.type)
ed := hw.alloc_pages(1)
gf.build_edid(ed, "RHT", 0x1234, 1024, 768, "QEMU Monitor")
e := gf.parse_edid(ed)
print(e.describe())
print(e.pixel_clock_khz)
hw.poke8(ed + 3, 0)
try:
    gf.parse_edid(ed)
catch er:
    print(er.type)
st := gf.FirmwareStore()
blob := hw.alloc_pages(1)
hw.store_string("microcode v2", blob)
st.add("gpu/ucode.bin", "2", blob, 12)
print(st.request("gpu/ucode.bin", 8).describe())
hw.poke8(blob, 0x6E)
try:
    st.request("gpu/ucode.bin", 8)
catch er:
    print(er.message)
try:
    st.request("absent", 1)
catch er:
    print(er.type)
vga := di.platform("00:02.0", 0, 0, -1)
vga.bus = "pci"
vga.cls = 3
vga.subclass = 0
vga.add_resource("mem", 0xFD000000, 0x1000000)
g3 := di.platform("01:00.0", 0, 0, -1)
g3.cls = 3
g3.subclass = 2
g3.add_resource("mem", 0xE0000000, 0x10000000)
nic := di.platform("00:03.0", 0, 0, -1)
nic.cls = 2
devs: list[HwDevice] := [g3, nic, vga]
t := gb.GpuBindingTable()
print(t.scan(devs))
p := t.primary()
if p != null:
    print(p.location)
t.set_boot_framebuffer(0xE0100000, 1024 * 768 * 4)
p2 := t.primary()
if p2 != null:
    print(p2.location)
bd := t.bind(g3, "pilote-3d", 0xE0000000, 256 * 1048576)
print(bd.describe())
t.bind(vga, "bochs-vga", 0xFD000000, 16 * 1048576)
try:
    t.bind(vga, "x", 0, 0)
catch er:
    print(er.type)
print(len(t.conflicts()))
g3.add_resource("mem", 0xFD800000, 0x1000)
print(t.conflicts())
print(t.report())
print(t.log)
