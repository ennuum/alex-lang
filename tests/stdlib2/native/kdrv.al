# alex: native
from core use len
from collections use append
from driver.driver use Driver
use driver.driver_info as di
from driver.driver_info use DriverInfo, HwDevice
use driver.driver_manager as dmg
use driver.driver_version as dv
use driver.driver_permissions as dp
use driver.driver_lifecycle as dl
from driver.driver_lifecycle use PowerHooks
use driver.driver_loader as dld

class Serial implements Driver:
    i: DriverInfo
    fails: int := 0
    func init():
        self.i = DriverInfo("serie", "1.2.0", "port série", "platform")
        self.i.add_id(di.named("com1"))
        self.fails = 0
    func info() -> DriverInfo:
        return self.i
    func probe(dev: HwDevice) -> bool:
        return true
    func attach(dev: HwDevice):
        if self.fails > 0:
            self.fails -= 1
            raise("DeviceTimeout", "pas de réponse")
    func detach(dev: HwDevice):
        self.fails = self.fails
    func status(dev: HwDevice) -> str:
        return "ok"

class Tty implements Driver:
    i: DriverInfo
    func init():
        self.i = DriverInfo("tty", "0.3", "terminal", "platform")
        self.i.add_id(di.named("tty0"))
    func info() -> DriverInfo:
        return self.i
    func probe(dev: HwDevice) -> bool:
        return true
    func attach(dev: HwDevice):
        self.i = self.i
    func detach(dev: HwDevice):
        self.i = self.i
    func status(dev: HwDevice) -> str:
        return "ok"

class Hooks implements PowerHooks:
    n: int := 0
    func init():
        self.n = 0
    func suspend(dev: HwDevice):
        self.n += 1
    func resume(dev: HwDevice):
        self.n += 10

func make_serial() -> Driver:
    return Serial()

func make_tty() -> Driver:
    return Tty()

print(dv.parse("v1.4.2-rc1").format())
print(dv.compare("1.10", "1.9"))
print(dv.compare("2.0.0-rc1", "2.0"))
print(dv.satisfies("1.4.2", "^1.2"))
print(dv.satisfies("1.4.2", ">=1.2, <1.4"))
print(dv.satisfies("1.2.9", "~1.2.3"))
print(dv.satisfies("0.3.1", "^0.2"))
print(dv.latest(["1.0", "1.10.1", "1.9"]))
try:
    dv.parse("1.x")
catch e:
    print(e.type)
com := di.platform("com1", 0x3F8, 8, 4)
pol := dp.PermissionPolicy(true)
p := pol.for_device("serie", com)
print(p.check_io(0x3FD, 1))
print(p.check_irq(4))
try:
    p.check_io(0x60, 1)
catch e:
    print(e.type)
p.grant("dma", 0, 0xFFFFFFFF)
print(p.check_dma(0x1000))
try:
    p.check_dma(0x100000000)
catch e:
    print(e.type)
print(pol.denied_count())
print(p.describe())
m := dmg.DriverManager()
ld := dld.DriverLoader(m)
ld.add(dld.DriverFactory("serie", make_serial, [], "^1.0"))
deps: list[str] := ["serie"]
ld.add(dld.DriverFactory("tty", make_tty, deps, "*"))
ld.add(dld.DriverFactory("futur", make_tty, [], ">=2.0"))
print(ld.order("tty"))
print(ld.configure("# conf\noption serie baud=115200 bits=8\nblacklist vieux"))
print(ld.option("serie", "baud", "9600"))
try:
    ld.load("futur")
catch e:
    print(e.type)
m.add_device(com)
m.add_device(di.platform("tty0", 0, 0, -1))
print(ld.autoload())
print(ld.report())
try:
    ld.unload("serie")
catch e:
    print(e.message)
lc := dl.Lifecycle(m)
hk := Hooks()
lc.set_power_hooks("serie", hk)
print(lc.start(com))
lc.suspend(com)
lc.resume(com)
print(hk.n)
try:
    lc.resume(com)
catch e:
    print(e.type)
lc.fail(com, "file bloquée")
print(lc.state_name(com))
print(lc.restart(com))
lc.remove(com)
print(lc.state_name(com))
print(lc.history_text())
ld.unload("tty")
ld.unload("serie")
print(ld.report())
