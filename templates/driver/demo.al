# Démonstration dans la VM : alexc run demo.al
use hw
use pilote
use modele

hw.sim_reset(16 * 1024 * 1024)
hw.sim_map_ports(768, 4, modele.CapteurSimule(768, 215)) # 0x300
c := pilote.Capteur(768)
t := c.lire_dixiemes()
print("température : " + str(t / 10.0) + " °C")
