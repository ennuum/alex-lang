# Sans OS (QEMU, réseau « user ») : pilote e1000 — adresse MAC, lien, ARP vers la passerelle 10.0.2.2,
# ping (écho ICMP), UDP, compteurs ; paquets construits et analysés par network_driver.network_packet.
use hw
use network_driver
use network_driver.ethernet as eth
use network_driver.network_packet as np
use network_driver.network_device as nd
from network_driver.network_device use NetInterface
from core use len

carte := network_driver.find_e1000()
if carte == null:
    print("pas de carte e1000")
else:
    print("carte : " + carte.name() + " " + eth.mac_text(carte.mac()) + " lien " + str(carte.link_up()))
    itf := NetInterface(carte, np.ip("10.0.2.15"), np.ip("10.0.2.2"))
    m := itf.resolve(itf.gateway, 5000000)
    print("ARP 10.0.2.2 -> " + eth.mac_text(m))
    print("ping 10.0.2.2 : " + str(itf.ping(itf.gateway, 1, 5000000)))
    print("ping 10.0.2.2 : " + str(itf.ping(itf.gateway, 2, 5000000)))
    print("journal : " + itf.log[0])
    print("UDP vers 10.0.2.2:9 : " + str(itf.send_udp(itf.gateway, 4000, 9, "bonjour", 1000)))
    print("émission terminée : " + str(carte.flush_tx(1000000)))
    s := carte.stats()
    print("compteurs : émis " + str(s.tx_packets) + ", reçus " + str(s.rx_packets) + ", erreurs " + str(s.errors()))
