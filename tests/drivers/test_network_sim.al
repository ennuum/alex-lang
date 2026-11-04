# Couches réseau des pilotes dans la machine simulée : MAC, CRC-32, tampons (push / pull), ARP / IPv4 /
# ICMP / UDP (construction, analyse, sommes), boucle locale et NetInterface (ARP et ping vers soi-même).
from core use len
use hw
use network_driver.ethernet as eth
use network_driver.network_buffer as nb
use network_driver.network_packet as np
use network_driver.network_device as nd
use network_driver.network_stats as nst

ok := [0]
ko := [0]
func check(cond, label):
    if cond:
        ok[0] += 1
    else:
        ko[0] += 1
        print("ÉCHEC " + label)

hw.sim_reset(32 * 1024 * 1024, 1024 * 1024)
m := eth.parse_mac("52:54:00:12:34:56")
check(m == 0x525400123456 and eth.mac_text(m) == "52:54:00:12:34:56", "MAC")
check(eth.parse_mac("zz") == -1 and eth.is_local(m) and not eth.is_multicast(m), "bits de la MAC")
check(eth.is_multicast(eth.BROADCAST) and eth.is_broadcast(eth.BROADCAST), "diffusion")
a := hw.alloc_pages(1)
hw.store_string("123456789", a)
check(eth.crc32_at(a, 9) == 0xCBF43926, "CRC-32 de référence")
check(np.ip("10.0.2.15") == 0x0A00020F and np.ip_text(0x0A00020F) == "10.0.2.15" and np.ip("1.2.3") == -1, "IPv4")

pool := nb.BufferPool(4)
b := pool.get()
check(b.headroom() == 128 and b.length == 0, "tampon vide")
b.put_string("charge")
h := b.push(4)
eth.write32be(h, 0xDEADBEEF)
check(b.length == 10 and b.u32(0) == 0xDEADBEEF and b.string(4, 6) == "charge", "push")
b.pull(4)
check(b.string(0, 6) == "charge", "pull")
erreur := ""
try:
    b.u32(4)
catch e:
    erreur = e.type
check(erreur == "MemoryError", "hors des données")
x := pool.get()
y := pool.get()
z := pool.get()
check(pool.get() == null, "limite de la réserve")
pool.put(x)
check(pool.get() != null, "rendu puis repris")

src := np.ip("10.0.2.15")
dst := np.ip("10.0.2.2")
gw := eth.parse_mac("52:55:0a:00:02:02")
np.build_arp(b, np.ARP_REQUEST, m, src, eth.BROADCAST, dst)
p := np.parse(b)
check(b.length == 60 and p.is_arp() and p.arp_op == 1 and p.target_ip == dst and p.sender_mac == m, "ARP : " + p.describe())
np.build_icmp_echo(b, m, gw, src, dst, 7, 3, "ping!")
p = np.parse(b)
check(p.is_ipv4() and p.ip_checksum_ok and p.l4_checksum_ok and p.icmp_type == 8 and p.icmp_seq == 3, "ICMP : " + p.describe())
check(p.payload_string() == "ping!", "charge ICMP")
np.build_udp(b, m, gw, src, dst, 4000, 53, "requête")
p = np.parse(b)
check(p.is_udp() and p.l4_checksum_ok and p.dst_port == 53 and p.payload_string() == "requête", "UDP : " + p.describe())
hw.poke8(b.data() + 14 + 20 + 8, 0x21)
check(not np.parse(b).l4_checksum_ok, "somme UDP fausse détectée")

pool2 := nb.BufferPool(0)
lo := nd.LoopbackDevice(pool2)
itf := nd.NetInterface(lo, np.ip("127.0.0.1"), np.ip("127.0.0.1"))
check(itf.resolve(itf.address, 10) == 0, "ARP vers soi")
check(itf.ping(itf.address, 1, 10), "ping vers soi")
check(itf.answered == 2 and itf.replies == 1, "réponses ARP et ICMP")
check(itf.send_udp(itf.address, 1, 2, "datagramme", 10), "UDP émis")
itf.poll()
check(len(itf.udp_inbox) == 1 and itf.udp_inbox[0] == "datagramme", "UDP reçu")
s := lo.stats()
check(s.tx_packets == s.rx_packets and s.tx_packets == 5, "compteurs : " + s.describe())
avant := s.snapshot()
s.count_rx(100, true, true)
check(s.diff(avant).rx_packets == 1 and s.diff(avant).rx_broadcast == 1, "différence")
print("réseau simulé : " + str(ok[0]) + " OK, " + str(ko[0]) + " échecs")
