#!/usr/bin/env python3
"""Ajoute une SEEKTABLE (un point par seconde) à un FLAC produit par ffmpeg, qui n'en écrit pas.
Les trames sont repérées par leur synchronisation et le CRC-8 de leur en-tête (blocs de taille fixe).
Usage : add_seektable.py entree.flac sortie.flac"""
import sys, struct

def crc8(b):
    c = 0
    for x in b:
        c ^= x
        for _ in range(8):
            c = ((c << 1) ^ 7) & 255 if c & 128 else (c << 1) & 255
    return c

src, dst = sys.argv[1], sys.argv[2]
b = open(src, "rb").read()
i, blocks = 4, []
while True:
    h = b[i]; n = int.from_bytes(b[i + 1:i + 4], "big")
    blocks.append((h & 127, b[i + 4:i + 4 + n])); i += 4 + n
    if h & 128: break
first = i
si = blocks[0][1]
minb = struct.unpack(">H", si[0:2])[0]
rate = int.from_bytes(si[10:13], "big") >> 4
frames, k = [], first
while k < len(b) - 6:
    if b[k] == 0xFF and b[k + 1] == 0xF8 and b[k + 4] == len(frames):   # numéro de trame attendu (< 128)
        # en-tête sans champs optionnels (blocs et fréquence codés) : 4 octets + numéro UTF-8 (1 octet ici) + CRC
        for hl in range(5, 10):
            if k + hl < len(b) and crc8(b[k:k + hl]) == b[k + hl]:
                frames.append(k - first); break
    k += 1
points = []
for sec in range(0, 10):
    target = sec * rate
    idx = target // minb
    if idx < len(frames):
        points.append(struct.pack(">QQH", idx * minb, frames[idx], minb))
points.append(b"\xff" * 8 + b"\0" * 10)        # point de réserve
seek = b"".join(points)
out = b"fLaC"
blocks = [x for x in blocks if x[0] != 1] + [(3, seek), (1, b"\0" * 64)]
for j, (t, data) in enumerate(blocks):
    out += bytes([t | (128 if j == len(blocks) - 1 else 0)]) + len(data).to_bytes(3, "big") + data
open(dst, "wb").write(out + b[first:])
print(len(points) - 1, "points,", len(frames), "trames")
