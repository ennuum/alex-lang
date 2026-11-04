# Pair réseau des tests de pilotes : QEMU (-netdev dgram) envoie les trames Ethernet de la carte en datagrammes
# UDP à 127.0.0.1:PORT ; ce script joue la passerelle 10.0.2.2 (52:55:0a:00:02:02) : réponses ARP, échos ICMP,
# et note les datagrammes UDP reçus ; il s'arrête après DURÉE secondes et affiche ce qu'il a vu sur stderr.
import socket, struct, sys, time
port, peer_port, duration = int(sys.argv[1]), int(sys.argv[2]), float(sys.argv[3])
GW_MAC = bytes.fromhex('52550a000202')
GW_IP = bytes([10, 0, 2, 2])
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(('127.0.0.1', port))
s.settimeout(0.2)
def csum(b):
    if len(b) % 2:
        b += b'\0'
    t = sum(struct.unpack('!%dH' % (len(b) // 2), b))
    while t >> 16:
        t = (t & 0xffff) + (t >> 16)
    return (~t) & 0xffff
seen = []
end = time.time() + duration
while time.time() < end:
    try:
        f, addr = s.recvfrom(4096)
    except socket.timeout:
        continue
    dst, src, et = f[0:6], f[6:12], struct.unpack('!H', f[12:14])[0]
    if et == 0x0806 and f[20:22] == b'\x00\x01' and f[38:42] == GW_IP:
        arp = struct.pack('!HHBBH', 1, 0x800, 6, 4, 2) + GW_MAC + GW_IP + f[22:28] + f[28:32]
        s.sendto(src + GW_MAC + b'\x08\x06' + arp + bytes(18), ('127.0.0.1', peer_port))
        seen.append('arp')
    elif et == 0x0800 and f[23] == 1 and f[34] == 8 and f[30:34] == GW_IP:
        ihl = (f[14] & 15) * 4
        ip = bytearray(f[14:14 + ihl])
        total = struct.unpack('!H', ip[2:4])[0]
        icmp = bytearray(f[14 + ihl:14 + total])
        icmp[0] = 0
        icmp[2:4] = b'\0\0'
        icmp[2:4] = struct.pack('!H', csum(bytes(icmp)))
        ip[12:16], ip[16:20] = f[30:34], f[26:30]
        ip[10:12] = b'\0\0'
        ip[10:12] = struct.pack('!H', csum(bytes(ip)))
        s.sendto(src + GW_MAC + b'\x08\x00' + bytes(ip) + bytes(icmp), ('127.0.0.1', peer_port))
        seen.append('icmp')
    elif et == 0x0800 and f[23] == 17:
        ihl = (f[14] & 15) * 4
        seen.append('udp:' + f[14 + ihl + 8:14 + struct.unpack('!H', f[16:18])[0]].decode('utf-8', 'replace'))
sys.stderr.write(' '.join(seen) + '\n')
