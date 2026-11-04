# ALEX STANDARD LIBRARY — gpu
#
# Cartes graphiques et calcul parallèle pour les applications :
#
# | Module            | Contenu                                                                         |
# |-------------------|---------------------------------------------------------------------------------|
# | gpu.gpu_info      | modèle, pilote, VRAM, charge, température, fréquences (sysfs, nvidia-smi)       |
# | gpu.gpu_device    | GpuDevice : carte + calcul + mémoire (logiciel si pas de dorsal matériel)       |
# | gpu.gpu_memory    | GpuMemory / GpuBuffer : tampons typés, upload / download, capacité              |
# | gpu.gpu_compute   | ComputeDevice : noyaux sur une grille, saxpy, matmul, convolution, histogramme  |
#
#   use gpu
#   for g in gpu.list():
#       print(g.describe())
#   dev := gpu.device()
#   print(dev.compute.dot([1.0, 2.0], [3.0, 4.0]))       # 11.0
#   dev.close()
#
# Le rendu graphique (contextes, tampons, textures, shaders, pipeline) est dans le paquet graphics ; les
# pilotes de carte d'un noyau Alex dans gpu_driver.

use gpu.gpu_info as gi
use gpu.gpu_device as gd
use gpu.gpu_compute as gc

func list():
    return gi.gpus()

func primary():
    return gi.primary()

func available():
    return len_of(gi.gpus()) > 0

func len_of(xs):
    n := 0
    for x in xs:
        n += 1
    return n

func device(backend="threads", workers=null):
    return gd.default(backend, workers)

func compute(backend="threads", workers=null):
    return gc.ComputeDevice(backend, workers)
