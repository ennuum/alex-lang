# Décrit des fichiers multimédias : conteneur, pistes, durée, étiquettes, ce qui est décodable ici.
#   alex run examples/multimedia/media_info.al -- fichier1 [fichier2...]
#   (sans argument : le corpus de tests/multimedia/fixtures)
from core use len
use os
use multimedia
use multimedia.container.probe as probe

args := os.args()
fichiers := [a for a in args]
if len(fichiers) == 0:
    D := "tests/multimedia/fixtures/"
    fichiers = [D + "media/tags.wav", D + "media/tone.flac", D + "media/tone_v24.mp3", D + "media/tone.m4a", D + "images/rgba8.png"]

for r in probe.probe_many(fichiers):
    info := r[0]
    if info == null:
        print("✗ " + r[1])
        continue
    print("● " + info.path)
    print("    " + info.describe() + (" — " + info.mime if info.mime != null else ""))
    for s in info.streams:
        print("    piste " + s.describe())
    if len(info.tags) > 0:
        print("    étiquettes : " + str(info.tags))
    for w in info.warnings:
        print("    ! " + w)
print("")
print(multimedia.capabilities())
