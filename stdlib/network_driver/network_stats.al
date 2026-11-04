# alex: native
# ALEX STANDARD LIBRARY — network_driver.network_stats
#
# Compteurs d'une interface réseau : paquets et octets reçus / émis, erreurs, pertes (file pleine, tampon
# manquant), trames trop courtes / longues, diffusion, multidiffusion ; instantané et différence (débits).
#
#   s := NetworkStats()
#   s.count_rx(64, false, true)
#   print(s.describe())
#   avant := s.snapshot()
#   ...
#   print(s.diff(avant).describe())
#
# Compilable en natif (# alex: native).

class NetworkStats:
    rx_packets: int := 0
    rx_bytes: int := 0
    tx_packets: int := 0
    tx_bytes: int := 0
    rx_errors: int := 0
    tx_errors: int := 0
    rx_dropped: int := 0
    tx_dropped: int := 0
    rx_broadcast: int := 0
    rx_multicast: int := 0
    rx_too_short: int := 0
    rx_too_long: int := 0
    interrupts: int := 0

    func init():
        self.reset()

    func reset():
        self.rx_packets = 0
        self.rx_bytes = 0
        self.tx_packets = 0
        self.tx_bytes = 0
        self.rx_errors = 0
        self.tx_errors = 0
        self.rx_dropped = 0
        self.tx_dropped = 0
        self.rx_broadcast = 0
        self.rx_multicast = 0
        self.rx_too_short = 0
        self.rx_too_long = 0
        self.interrupts = 0

    func count_rx(bytes: int, broadcast: bool, multicast: bool):
        self.rx_packets += 1
        self.rx_bytes += bytes
        if broadcast:
            self.rx_broadcast += 1
        elif multicast:
            self.rx_multicast += 1
        if bytes < 60:
            self.rx_too_short += 1
        if bytes > 1518:
            self.rx_too_long += 1

    func count_tx(bytes: int):
        self.tx_packets += 1
        self.tx_bytes += bytes

    func snapshot() -> NetworkStats:
        s := NetworkStats()
        s.rx_packets = self.rx_packets
        s.rx_bytes = self.rx_bytes
        s.tx_packets = self.tx_packets
        s.tx_bytes = self.tx_bytes
        s.rx_errors = self.rx_errors
        s.tx_errors = self.tx_errors
        s.rx_dropped = self.rx_dropped
        s.tx_dropped = self.tx_dropped
        s.rx_broadcast = self.rx_broadcast
        s.rx_multicast = self.rx_multicast
        s.rx_too_short = self.rx_too_short
        s.rx_too_long = self.rx_too_long
        s.interrupts = self.interrupts
        return s

    # Compteurs depuis l'instantané before.
    func diff(before: NetworkStats) -> NetworkStats:
        s := self.snapshot()
        s.rx_packets -= before.rx_packets
        s.rx_bytes -= before.rx_bytes
        s.tx_packets -= before.tx_packets
        s.tx_bytes -= before.tx_bytes
        s.rx_errors -= before.rx_errors
        s.tx_errors -= before.tx_errors
        s.rx_dropped -= before.rx_dropped
        s.tx_dropped -= before.tx_dropped
        s.rx_broadcast -= before.rx_broadcast
        s.rx_multicast -= before.rx_multicast
        s.rx_too_short -= before.rx_too_short
        s.rx_too_long -= before.rx_too_long
        s.interrupts -= before.interrupts
        return s

    func errors() -> int:
        return self.rx_errors + self.tx_errors

    func describe() -> str:
        t := "reçus " + str(self.rx_packets) + " (" + str(self.rx_bytes) + " o), émis " + str(self.tx_packets) + " (" + str(self.tx_bytes) + " o)"
        if self.errors() > 0:
            t = t + ", erreurs " + str(self.rx_errors) + "/" + str(self.tx_errors)
        if self.rx_dropped + self.tx_dropped > 0:
            t = t + ", perdus " + str(self.rx_dropped) + "/" + str(self.tx_dropped)
        return t
