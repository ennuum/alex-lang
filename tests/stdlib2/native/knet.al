# alex: native
from core use len
from collections use append
use hw
use network_driver.ethernet as eth
use network_driver.network_packet as np
use network_driver.network_buffer as nb
from network_driver.network_buffer use PacketBuffer, BufferPool
use network_driver.network_device as nd
from network_driver.network_device use LoopbackDevice
use network_driver.network_driver_errors as nde
use network_driver.network_ring as nr
use network_driver.network_offload as no
use network_driver.network_interface as ni

pool := BufferPool(64)
b := pool.get()
if b != null:
    np.build_udp(b, eth.parse_mac("52:54:00:12:34:56"), eth.BROADCAST, np.ip("10.0.2.15"), np.ip("10.0.2.2"), 1234, 53, "bonjour")
    print(b.length)
    print(nde.frame_problem(b.data(), b.length, false) == "")
    print(nde.frame_problem(b.data(), 20, false))
    fcs := eth.crc32_at(b.data(), b.length)
    hw.poke32(b.data() + b.length, fcs)
    print(nde.frame_problem(b.data(), b.length + 4, true) == "")
    hw.poke8(b.data() + 30, 1)
    print(nde.frame_problem(b.data(), b.length + 4, true))
    v := no.verify_checksums(b)
    print(v)
    no.fill_checksums(b)
    print(no.verify_checksums(b))
    no.insert_vlan(b, 42, 3)
    print(eth.vlan_of(b.data()))
    print(np.parse(b).describe())
    print(no.strip_vlan(b))
    print(no.verify_checksums(b))
    print(np.parse(b).is_udp())
f := no.negotiate(no.Features(no.TSO | no.TX_CSUM | no.RX_CSUM), no.ALL)
print(f.describe())
big := pool.get()
if big != null:
    payload := ""
    k := 0
    while k < 100:
        payload = payload + "0123456789"
        k += 1
    no.build_tcp(big, 1, 2, np.ip("10.0.0.1"), np.ip("10.0.0.2"), 4000, 80, 1000, 1, 0x19, payload)
    print(no.verify_checksums(big))
    segs := no.segment_tcp(big, 300, pool)
    print(len(segs))
    tot := 0
    for s in segs:
        p := np.parse(s)
        tot += p.payload_length
        vv := no.verify_checksums(s)
        print(str(s.u32(14 + 20 + 4)) + " " + str(p.payload_length) + " " + str(s.u8(14 + 20 + 13)) + " " + str(vv[0] and vv[1]))
    print(tot)
    print(no.e1000_context(big))
tx := nr.TxRing(4, nr.legacy_tx(), pool)
tails: list[int] := []
k2 := 0
while k2 < 4:
    pb := pool.get()
    if pb != null:
        pb.put_string("x")
        print(tx.send(pb))
    k2 += 1
print(tx.in_flight())
tx.device_complete(0)
tx.device_complete(1)
print(tx.reclaim())
print(tx.describe())
rx := nr.RxRing(4, nr.legacy_rx(), pool)
print(rx.fill())
src := hw.alloc_pages(1)
hw.store_string("trame-reçue", src)
print(rx.device_receive(src, 12, true, 0))
print(rx.device_receive(src, 5, false, 0))
print(rx.device_receive(src, 7, true, 0x01))
got := rx.harvest(8)
print(len(got))
print(got[0].string(0, 5))
print(rx.describe())
print(pool.available())
t := ni.InterfaceTable()
lo := t.add(LoopbackDevice(pool), "lo")
e0 := t.add(LoopbackDevice(pool), "eth")
e1 := t.add(LoopbackDevice(pool), "eth")
print(e1.name)
t.assign("lo", np.ip("127.0.0.1"), 8)
t.assign("eth0", np.ip("10.0.2.15"), 24)
t.assign("eth1", np.ip("192.168.1.10"), 24)
t.add_route(0, 0, np.ip("10.0.2.2"), "eth0", 100)
t.add_route(0, 0, np.ip("192.168.1.1"), "eth1", 50)
lo.set_up(true)
e0.set_up(true)
r := t.lookup(np.ip("8.8.8.8"))
print(r.describe())
e1.set_up(true)
print(t.lookup(np.ip("8.8.8.8")).describe())
print(t.lookup(np.ip("10.0.2.77")).describe())
print(np.ip_text(t.lookup(np.ip("10.0.2.77")).next_hop(np.ip("10.0.2.77"))))
try:
    e0.set_mtu(70000)
catch e:
    print(e.type)
e0.set_up(false)
e1.set_up(false)
try:
    t.lookup(np.ip("8.8.8.8"))
catch e:
    print(e.type)
print(t.describe())
