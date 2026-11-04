#!/bin/sh
# Disques de k_storage : trois images (IDE, SATA, NVMe) préparées par mkdisk.py dans le dossier $1.
dir=$1
python3 tests/drivers/kernel/mkdisk.py "$dir/ide.img" PATA 8
python3 tests/drivers/kernel/mkdisk.py "$dir/sata.img" SATA 16
python3 tests/drivers/kernel/mkdisk.py "$dir/nvme.img" NVME 16
