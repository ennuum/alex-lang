# alex: native
#
# ALEX STANDARD LIBRARY — pci.pci_ids
#
# Noms des identifiants PCI : fabricants (vendor), périphériques connus (machines virtuelles QEMU / KVM /
# VirtualBox / VMware, puces Intel, virtio...), et la table COMPLÈTE des classes, sous-classes et interfaces de
# programmation (PCI Code and ID Assignment Specification). Aussi quelques fabricants USB.
#
#   use pci.pci_ids as ids
#   print(ids.vendor_name(0x8086))                 # Intel
#   print(ids.device_name(0x8086, 0x100E))         # 82540EM Gigabit Ethernet (e1000)
#   print(ids.class_name(0x01, 0x06, 0x01))        # SATA (AHCI 1.0)
#
# Module du sous-ensemble natif : utilisable dans un noyau (--freestanding) comme dans la VM.

from collections use contains_key

_vendors: dict[int, str] := {0x8086: "Intel", 0x1022: "AMD", 0x1002: "AMD (ATI)", 0x10DE: "NVIDIA", 0x1AF4: "Red Hat (virtio)",
    0x1B36: "Red Hat (QEMU)", 0x1234: "QEMU (Bochs)", 0x15AD: "VMware", 0x80EE: "VirtualBox (Oracle)", 0x1414: "Microsoft",
    0x106B: "Apple", 0x14E4: "Broadcom", 0x10EC: "Realtek", 0x168C: "Qualcomm Atheros", 0x17CB: "Qualcomm", 0x1B4B: "Marvell",
    0x1000: "Broadcom / LSI", 0x9005: "Microchip (Adaptec)", 0x1077: "QLogic", 0x15B3: "Mellanox (NVIDIA)", 0x19A2: "Emulex",
    0x144D: "Samsung", 0x1C5C: "SK hynix", 0x126F: "Silicon Motion", 0x1987: "Phison", 0x15B7: "Sandisk (WD)",
    0x1179: "Toshiba (Kioxia)", 0x1E0F: "Kioxia", 0x8087: "Intel (USB)", 0x1912: "Renesas", 0x1033: "NEC", 0x1106: "VIA",
    0x1039: "SiS", 0x10B9: "ULi (ALi)", 0x1095: "Silicon Image", 0x197B: "JMicron", 0x1B21: "ASMedia", 0x1217: "O2 Micro",
    0x1180: "Ricoh", 0x104C: "Texas Instruments", 0x11AB: "Marvell (ancien)", 0x13F6: "C-Media", 0x1102: "Creative",
    0x1274: "Ensoniq", 0x125D: "ESS", 0x1AE0: "Google", 0x1D0F: "Amazon", 0x1DB7: "Phytium", 0x19E5: "Huawei",
    0x1172: "Altera (Intel)", 0x10EE: "Xilinx (AMD)", 0x1D17: "Zhaoxin", 0x18D1: "Google (ancien)", 0x1C58: "HGST",
    0x1344: "Micron", 0x1CC1: "ADATA", 0x2646: "Kingston", 0x1D79: "Transcend", 0x1E4B: "Maxio", 0x5853: "XenSource",
    0x1AB8: "Parallels", 0x102B: "Matrox", 0x1A03: "ASPEED", 0x18CA: "XGI", 0x5333: "S3", 0x121A: "3dfx", 0x1013: "Cirrus Logic"}

# Périphériques connus : clé (vendor << 16) | device.
_devices: dict[int, str] := {
    0x80861237: "440FX - 82441FX PMC [Natoma]", 0x80867000: "82371SB PIIX3 ISA [Natoma/Triton II]",
    0x80867010: "82371SB PIIX3 IDE [Natoma/Triton II]", 0x80867020: "82371SB PIIX3 USB [Natoma/Triton II] (UHCI)",
    0x80867113: "82371AB/EB/MB PIIX4 ACPI", 0x80867111: "82371AB/EB/MB PIIX4 IDE", 0x80867112: "82371AB/EB/MB PIIX4 USB (UHCI)",
    0x808629C0: "82G33/G31/P35/P31 Express DRAM Controller (Q35)", 0x80862918: "82801IB (ICH9) LPC Interface Controller",
    0x80862922: "82801IR/IO/IH (ICH9R/DO/DH) 6 port SATA Controller [AHCI mode]", 0x80862930: "82801I (ICH9 Family) SMBus Controller",
    0x80862934: "82801I (ICH9 Family) USB UHCI Controller #1", 0x8086293A: "82801I (ICH9 Family) USB2 EHCI Controller #1",
    0x808624CD: "82801DB/DBM (ICH4/ICH4-M) USB2 EHCI Controller", 0x80862415: "82801AA AC'97 Audio Controller",
    0x80862668: "82801FB/FBM/FR/FW/FRW (ICH6 Family) High Definition Audio Controller",
    0x8086293E: "82801I (ICH9 Family) HD Audio Controller", 0x8086100E: "82540EM Gigabit Ethernet Controller (e1000)",
    0x8086100F: "82545EM Gigabit Ethernet Controller (Copper)", 0x808610D3: "82574L Gigabit Network Connection (e1000e)",
    0x808610C9: "82576 Gigabit Network Connection (igb)", 0x808615F3: "Ethernet Controller I225-V", 0x80861533: "I210 Gigabit Network Connection",
    0x80865845: "QEMU NVM Express Controller", 0x808625AB: "6300ESB Watchdog Timer",
    0x80863A3A: "82801JI (ICH10 Family) USB UHCI", 0x80861E31: "7 Series/C210 Series Chipset Family USB xHCI Host Controller",
    0x12341111: "Bochs / QEMU standard VGA", 0x1B360001: "QEMU PCI-PCI bridge", 0x1B360002: "QEMU PCI 16550A Adapter",
    0x1B360005: "QEMU PCI test device", 0x1B360008: "QEMU PCIe Host bridge", 0x1B36000C: "QEMU PCIe Root port",
    0x1B36000D: "QEMU XHCI Host Controller", 0x1B360010: "QEMU NVM Express Controller", 0x1B360011: "QEMU PVPanic device",
    0x1B360100: "QXL paravirtual graphic card", 0x1AF41000: "Virtio network device (legacy)", 0x1AF41001: "Virtio block device (legacy)",
    0x1AF41002: "Virtio memory balloon (legacy)", 0x1AF41003: "Virtio console (legacy)", 0x1AF41004: "Virtio SCSI (legacy)",
    0x1AF41005: "Virtio RNG (legacy)", 0x1AF41009: "Virtio filesystem (legacy)", 0x1AF41041: "Virtio 1.0 network device",
    0x1AF41042: "Virtio 1.0 block device", 0x1AF41043: "Virtio 1.0 console", 0x1AF41044: "Virtio 1.0 RNG",
    0x1AF41045: "Virtio 1.0 balloon", 0x1AF41048: "Virtio 1.0 SCSI", 0x1AF41049: "Virtio 1.0 filesystem",
    0x1AF41050: "Virtio 1.0 GPU", 0x1AF41052: "Virtio 1.0 input", 0x1AF41053: "Virtio 1.0 socket", 0x15AD0405: "SVGA II Adapter",
    0x15AD07B0: "VMXNET3 Ethernet Controller", 0x15AD07C0: "PVSCSI SCSI Controller", 0x80EEBEEF: "VirtualBox Graphics Adapter",
    0x80EECAFE: "VirtualBox Guest Service", 0x10EC8139: "RTL-8100/8101L/8139 PCI Fast Ethernet Adapter",
    0x10EC8168: "RTL8111/8168/8411 PCI Express Gigabit Ethernet Controller", 0x10222000: "79c970 [PCnet32 LANCE]",
    0x10DE1EB8: "TU104GL [Tesla T4]", 0x102B0522: "MGA G200e", 0x1A032000: "ASPEED Graphics Family", 0x10131111: "GD 5446"}

_classes: dict[int, str] := {0x00: "Non classé", 0x01: "Contrôleur de stockage", 0x02: "Contrôleur réseau",
    0x03: "Contrôleur d'affichage", 0x04: "Contrôleur multimédia", 0x05: "Contrôleur mémoire", 0x06: "Pont",
    0x07: "Contrôleur de communication", 0x08: "Périphérique système", 0x09: "Contrôleur d'entrée", 0x0A: "Station d'accueil",
    0x0B: "Processeur", 0x0C: "Contrôleur de bus série", 0x0D: "Contrôleur sans fil", 0x0E: "Contrôleur d'E/S intelligent",
    0x0F: "Contrôleur de communication par satellite", 0x10: "Contrôleur de chiffrement", 0x11: "Contrôleur d'acquisition",
    0x12: "Accélérateur de calcul", 0x13: "Instrumentation non essentielle", 0x40: "Coprocesseur", 0xFF: "Non attribué"}

# Clé (classe << 8) | sous-classe.
_subclasses: dict[int, str] := {
    0x0000: "Non-VGA", 0x0001: "Compatible VGA",
    0x0100: "SCSI", 0x0101: "IDE", 0x0102: "Disquette", 0x0103: "IPI", 0x0104: "RAID", 0x0105: "ATA", 0x0106: "SATA",
    0x0107: "SAS", 0x0108: "Mémoire non volatile (NVMe)", 0x0109: "UFS", 0x0180: "Stockage (autre)",
    0x0200: "Ethernet", 0x0201: "Token Ring", 0x0202: "FDDI", 0x0203: "ATM", 0x0204: "ISDN", 0x0205: "WorldFip",
    0x0206: "PICMG", 0x0207: "InfiniBand", 0x0208: "Fabric", 0x0280: "Réseau (autre)",
    0x0300: "Compatible VGA", 0x0301: "XGA", 0x0302: "3D (non VGA)", 0x0380: "Affichage (autre)",
    0x0400: "Vidéo", 0x0401: "Audio", 0x0402: "Téléphonie", 0x0403: "Audio haute définition (HDA)", 0x0480: "Multimédia (autre)",
    0x0500: "RAM", 0x0501: "Flash", 0x0502: "CXL", 0x0580: "Mémoire (autre)",
    0x0600: "Pont hôte", 0x0601: "Pont ISA", 0x0602: "Pont EISA", 0x0603: "Pont MCA", 0x0604: "Pont PCI-PCI", 0x0605: "Pont PCMCIA",
    0x0606: "Pont NuBus", 0x0607: "Pont CardBus", 0x0608: "Pont RACEway", 0x0609: "Pont PCI-PCI semi-transparent",
    0x060A: "Pont InfiniBand-PCI", 0x0680: "Pont (autre)",
    0x0700: "Série", 0x0701: "Parallèle", 0x0702: "Multiport série", 0x0703: "Modem", 0x0704: "GPIB", 0x0705: "Carte à puce",
    0x0780: "Communication (autre)",
    0x0800: "PIC", 0x0801: "DMA", 0x0802: "Minuterie", 0x0803: "Horloge temps réel", 0x0804: "Hot-plug PCI", 0x0805: "SD",
    0x0806: "IOMMU", 0x0880: "Système (autre)",
    0x0900: "Clavier", 0x0901: "Numériseur (stylet)", 0x0902: "Souris", 0x0903: "Scanner", 0x0904: "Port de jeu", 0x0980: "Entrée (autre)",
    0x0B00: "386", 0x0B01: "486", 0x0B02: "Pentium", 0x0B10: "Alpha", 0x0B20: "PowerPC", 0x0B30: "MIPS", 0x0B40: "Coprocesseur",
    0x0C00: "FireWire (IEEE 1394)", 0x0C01: "ACCESS.bus", 0x0C02: "SSA", 0x0C03: "USB", 0x0C04: "Fibre Channel", 0x0C05: "SMBus",
    0x0C06: "InfiniBand", 0x0C07: "IPMI", 0x0C08: "SERCOS", 0x0C09: "CANbus", 0x0C80: "Bus série (autre)",
    0x0D00: "IRDA", 0x0D01: "Infrarouge grand public", 0x0D10: "RF", 0x0D11: "Bluetooth", 0x0D12: "Large bande",
    0x0D20: "Ethernet 802.1a", 0x0D21: "Ethernet 802.1b", 0x0D80: "Sans fil (autre)",
    0x1000: "Chiffrement réseau et informatique", 0x1010: "Chiffrement de divertissement", 0x1080: "Chiffrement (autre)",
    0x1100: "DPIO", 0x1101: "Compteur de performance", 0x1110: "Synchronisation de communication", 0x1120: "Gestion", 0x1180: "Acquisition (autre)",
    0x1200: "Accélérateur de traitement"}

# Clé (classe << 16) | (sous-classe << 8) | interface.
_prog_ifs: dict[int, str] := {
    0x010100: "IDE ISA (compatibilité)", 0x010105: "IDE PCI natif", 0x01018A: "IDE ISA + bus master", 0x01018F: "IDE PCI natif + bus master",
    0x010180: "IDE ISA + bus master (PIIX)", 0x010520: "ATA ADMA (une étape)", 0x010530: "ATA ADMA (enchaîné)",
    0x010600: "SATA (spécifique au fabricant)", 0x010601: "SATA (AHCI 1.0)", 0x010602: "SATA (bus série de stockage)",
    0x010801: "NVMHCI", 0x010802: "NVM Express (NVMe)",
    0x030000: "VGA", 0x030001: "8514",
    0x060400: "Pont PCI-PCI (décodage normal)", 0x060401: "Pont PCI-PCI (décodage soustractif)",
    0x070000: "8250 (XT)", 0x070002: "16550", 0x070003: "16650", 0x070004: "16750", 0x070005: "16850", 0x070006: "16950",
    0x080000: "8259", 0x080001: "ISA PIC", 0x080002: "EISA PIC", 0x080010: "I/O APIC", 0x080020: "I/O(x) APIC",
    0x0C0300: "UHCI (USB 1.1)", 0x0C0310: "OHCI (USB 1.1)", 0x0C0320: "EHCI (USB 2.0)", 0x0C0330: "xHCI (USB 3)",
    0x0C0380: "USB (non spécifié)", 0x0C03FE: "Périphérique USB (non hôte)", 0x0C0700: "IPMI SMIC", 0x0C0701: "IPMI clavier", 0x0C0702: "IPMI bloc"}

# Fabricants USB courants.
_usb_vendors: dict[int, str] := {0x046D: "Logitech", 0x045E: "Microsoft", 0x05AC: "Apple", 0x0781: "SanDisk", 0x0951: "Kingston",
    0x8087: "Intel", 0x8086: "Intel", 0x1D6B: "Linux Foundation", 0x0627: "QEMU", 0x0BDA: "Realtek", 0x0B05: "ASUSTek",
    0x04F2: "Chicony", 0x04CA: "Lite-On", 0x1532: "Razer", 0x1B1C: "Corsair", 0x413C: "Dell", 0x03F0: "HP", 0x17EF: "Lenovo",
    0x04E8: "Samsung", 0x054C: "Sony", 0x057E: "Nintendo", 0x0BC2: "Seagate", 0x1058: "Western Digital", 0x2109: "VIA Labs",
    0x05E3: "Genesys Logic", 0x0424: "Microchip (SMSC)", 0x0403: "FTDI", 0x10C4: "Silicon Labs", 0x067B: "Prolific",
    0x1A86: "QinHeng (CH340)", 0x2341: "Arduino", 0x2E8A: "Raspberry Pi", 0x18D1: "Google", 0x22B8: "Motorola", 0x12D1: "Huawei",
    0x0A5C: "Broadcom", 0x0CF3: "Qualcomm Atheros", 0x046A: "Cherry", 0x0D8C: "C-Media", 0x1050: "Yubico", 0x0BB4: "HTC",
    0x2717: "Xiaomi", 0x0E8D: "MediaTek", 0x058F: "Alcor Micro", 0x0C45: "Microdia", 0x174F: "Syntek", 0x5986: "Acer (Bison)",
    0x13D3: "IMC Networks (AzureWave)", 0x8564: "Transcend", 0x090C: "Silicon Motion"}

func vendor_name(vendor: int) -> str:
    if contains_key(_vendors, vendor):
        return _vendors[vendor]
    return "fabricant " + hex16(vendor)

func device_name(vendor: int, device: int) -> str:
    k := (vendor << 16) | device
    if contains_key(_devices, k):
        return _devices[k]
    return "périphérique " + hex16(vendor) + ":" + hex16(device)

func known_device(vendor: int, device: int) -> bool:
    return contains_key(_devices, (vendor << 16) | device)

func base_class_name(cls: int) -> str:
    if contains_key(_classes, cls):
        return _classes[cls]
    return "classe " + hex8(cls)

# Nom le plus précis : interface, sinon sous-classe, sinon classe.
func class_name(cls: int, subclass: int, prog_if: int) -> str:
    k := (cls << 16) | (subclass << 8) | prog_if
    if contains_key(_prog_ifs, k):
        return _prog_ifs[k]
    s := (cls << 8) | subclass
    if contains_key(_subclasses, s):
        return _subclasses[s]
    return base_class_name(cls)

func usb_vendor_name(vendor: int) -> str:
    if contains_key(_usb_vendors, vendor):
        return _usb_vendors[vendor]
    return "fabricant " + hex16(vendor)

func hex8(v: int) -> str:
    digits := "0123456789abcdef"
    return str(digits[(v >> 4) & 15]) + str(digits[v & 15])

func hex16(v: int) -> str:
    return hex8((v >> 8) & 255) + hex8(v & 255)

func hex32(v: int) -> str:
    return hex16((v >> 16) & 65535) + hex16(v & 65535)
