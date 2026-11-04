# alex: native
# ALEX STANDARD LIBRARY — storage_driver.storage_errors
#
# Erreurs du stockage et décodage des codes d'erreur des contrôleurs :
#   StorageError      erreur générale          MediaError       secteur illisible / écriture impossible
#   ReadOnlyError     support en lecture seule OutOfRangeError  bloc hors du disque
#   PartitionError    table de partitions invalide (storage_partition)
#   CacheError        incohérence du cache (storage_cache)
#   - registre d'erreur ATA (ABRT, IDNF, UNC, ICRC...) et d'état (BSY, DRDY, DF, DRQ, ERR) en texte ;
#   - mot TFD d'un port AHCI (état + erreur) ;
#   - statut NVMe (type SCT + code SC, bit DNR « ne pas réessayer ») en texte, et s'il faut réessayer ;
#   - fonctions qui lèvent l'erreur avec le disque, le bloc et le détail.
#
#   use storage_driver.storage_errors as se
#   print(se.ata_error_text(0x40))           # « UNC (donnée illisible) »
#   print(se.nvme_status_text(0x0281))       # statut complet NVMe (phase exclue)
#   if se.nvme_retryable(st): ...
#   se.media_error("sda", 1234, se.ata_error_text(err))
#
# Erreurs : celles ci-dessus. Compilable en natif (# alex: native).

const STORAGE := "StorageError"
const MEDIA := "MediaError"
const READ_ONLY := "ReadOnlyError"
const OUT_OF_RANGE := "OutOfRangeError"
const PARTITION := "PartitionError"
const CACHE := "CacheError"

func is_storage_error(t: str) -> bool:
    return t == STORAGE or t == MEDIA or t == READ_ONLY or t == OUT_OF_RANGE or t == PARTITION or t == CACHE or t == "DeviceIoError" or t == "DeviceTimeout"

func _add(t: str, part: str) -> str:
    if t == "":
        return part
    return t + ", " + part

# Registre d'erreur ATA (port 0x1F1 / octet haut de TFD).
func ata_error_text(err: int) -> str:
    t := ""
    if err & 0x80 != 0:
        t = _add(t, "ICRC (erreur CRC d'interface)")
    if err & 0x40 != 0:
        t = _add(t, "UNC (donnée illisible)")
    if err & 0x20 != 0:
        t = _add(t, "MC (support changé)")
    if err & 0x10 != 0:
        t = _add(t, "IDNF (secteur introuvable)")
    if err & 0x08 != 0:
        t = _add(t, "MCR (demande de changement de support)")
    if err & 0x04 != 0:
        t = _add(t, "ABRT (commande refusée)")
    if err & 0x02 != 0:
        t = _add(t, "TK0NF (piste 0 introuvable)")
    if err & 0x01 != 0:
        t = _add(t, "AMNF (marque d'adresse introuvable)")
    if t == "":
        return "aucune erreur"
    return t

func ata_status_text(st: int) -> str:
    t := ""
    if st & 0x80 != 0:
        t = _add(t, "BSY")
    if st & 0x40 != 0:
        t = _add(t, "DRDY")
    if st & 0x20 != 0:
        t = _add(t, "DF (défaut du périphérique)")
    if st & 0x08 != 0:
        t = _add(t, "DRQ")
    if st & 0x01 != 0:
        t = _add(t, "ERR")
    if t == "":
        return "0"
    return t

# Mot TFD d'un port AHCI : état (bits 0-7), erreur (bits 8-15).
func ahci_tfd_text(tfd: int) -> str:
    st := tfd & 0xFF
    err := (tfd >> 8) & 0xFF
    t := "état " + ata_status_text(st)
    if st & 0x01 != 0:
        t = t + " ; erreur " + ata_error_text(err)
    return t

# Erreur ATA susceptible de disparaître en réessayant (CRC d'interface, délai), pas UNC / IDNF / ABRT.
func ata_retryable(err: int) -> bool:
    if err & 0x50 != 0 or err & 0x04 != 0:
        return false
    return err & 0x80 != 0 or err == 0

# Statut NVMe (champ statut de l'entrée de complétion, bits 17-31 de DW3 décalés : SC bits 0-7, SCT bits
# 8-10, CRD 11-12, M 13, DNR 14).
func nvme_sc(status: int) -> int:
    return status & 0xFF

func nvme_sct(status: int) -> int:
    return (status >> 8) & 7

func nvme_dnr(status: int) -> bool:
    return (status >> 14) & 1 == 1

func nvme_status_text(status: int) -> str:
    sct := nvme_sct(status)
    sc := nvme_sc(status)
    t := ""
    if sct == 0:
        if sc == 0x00:
            t = "succès"
        elif sc == 0x01:
            t = "opcode invalide"
        elif sc == 0x02:
            t = "champ invalide"
        elif sc == 0x04:
            t = "erreur de transfert"
        elif sc == 0x06:
            t = "erreur interne"
        elif sc == 0x07:
            t = "commande interrompue sur demande"
        elif sc == 0x0B:
            t = "espace de noms invalide"
        elif sc == 0x80:
            t = "LBA hors limites"
        elif sc == 0x81:
            t = "capacité dépassée"
        elif sc == 0x82:
            t = "espace de noms non prêt"
        else:
            t = "statut générique " + str(sc)
    elif sct == 1:
        if sc == 0x01:
            t = "identifiant de file invalide"
        elif sc == 0x02:
            t = "taille de file invalide"
        else:
            t = "statut de commande " + str(sc)
    elif sct == 2:
        if sc == 0x80:
            t = "erreur d'écriture (support)"
        elif sc == 0x81:
            t = "erreur de lecture non corrigible"
        elif sc == 0x82:
            t = "erreur de contrôle de bout en bout (garde)"
        elif sc == 0x86:
            t = "accès refusé"
        else:
            t = "erreur de support " + str(sc)
    elif sct == 3:
        t = "erreur de chemin " + str(sc)
    else:
        t = "statut propre au fabricant " + str(sc)
    if nvme_dnr(status):
        t = t + " (ne pas réessayer)"
    return t

func nvme_ok(status: int) -> bool:
    return nvme_sct(status) == 0 and nvme_sc(status) == 0

func nvme_retryable(status: int) -> bool:
    if nvme_ok(status) or nvme_dnr(status):
        return false
    sct := nvme_sct(status)
    sc := nvme_sc(status)
    if sct == 0:
        return sc == 0x04 or sc == 0x06 or sc == 0x82
    return sct == 3

func media_error(disk: str, lba: int, detail: str):
    raise(MEDIA, disk + " : bloc " + str(lba) + " : " + detail)

func out_of_range(disk: str, lba: int, count: int, blocks: int):
    raise(OUT_OF_RANGE, disk + " : blocs " + str(lba) + "+" + str(count) + " hors du disque (" + str(blocks) + " blocs)")

func read_only(disk: str):
    raise(READ_ONLY, disk + " : support en lecture seule")
