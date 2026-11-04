# Image de disque de test : table MBR (2 partitions), signature au secteur 1, motif au secteur 100.
import struct, sys
path, label, size_mib = sys.argv[1], sys.argv[2], int(sys.argv[3])
img = bytearray(size_mib * 1024 * 1024)
mbr = bytearray(512)
struct.pack_into('<I', mbr, 440, 0xA1EC0DE5)
def entry(i, boot, t, start, count):
    o = 446 + 16 * i
    mbr[o] = 0x80 if boot else 0
    mbr[o + 4] = t
    struct.pack_into('<II', mbr, o + 8, start, count)
entry(0, True, 0x0C, 2048, 4096)
entry(1, False, 0x83, 6144, 2048)
mbr[510:512] = b'\x55\xaa'
img[0:512] = mbr
sig = ('DISQUE-' + label).encode()
img[512:512 + len(sig)] = sig
for i in range(512):
    img[100 * 512 + i] = i & 255
open(path, 'wb').write(img)
