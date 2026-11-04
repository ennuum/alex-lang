#!/bin/sh
# Clé USB de k_usb : image préparée par mkdisk.py dans le dossier $1.
python3 tests/drivers/kernel/mkdisk.py "$1/usb.img" USBK 4
