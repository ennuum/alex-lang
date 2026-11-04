use hw
use pilote
use modele
use testing

func test_mesure():
    hw.sim_reset(16 * 1024 * 1024)
    m := modele.CapteurSimule(768, -35)
    hw.sim_map_ports(768, 4, m)
    c := pilote.Capteur(768)
    testing.assert_eq(c.lire_dixiemes(), -35)
    testing.assert_eq(c.mesures, 1)
    testing.assert_eq(m.commandes, 1)
