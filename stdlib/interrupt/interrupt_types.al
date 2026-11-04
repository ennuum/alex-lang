# alex: native
# ALEX STANDARD LIBRARY — interrupt.interrupt_types
#
# Vocabulaire des interruptions x86-64 : vecteurs des exceptions du processeur (0..31) et leurs noms, lignes
# d'interruption (IRQ) héritées du PC, vecteurs choisis par la bibliothèque (PIC remappé à 32, APIC, MSI,
# inter-processeurs, parasite), modes de déclenchement.
#
#   use interrupt.interrupt_types as it
#   print(it.exception_name(14))                  # « défaut de page (#PF) »
#   v := it.irq_vector(it.IRQ_KEYBOARD)           # 33
#   print(it.kind_of(v))                          # « irq »
#
# Module compilable en natif (# alex: native) : utilisable dans un noyau (--freestanding) comme dans la VM.

# ---- exceptions du processeur ----
const DIVIDE_ERROR := 0
const DEBUG := 1
const NMI := 2
const BREAKPOINT := 3
const OVERFLOW := 4
const BOUND_RANGE := 5
const INVALID_OPCODE := 6
const DEVICE_NOT_AVAILABLE := 7
const DOUBLE_FAULT := 8
const INVALID_TSS := 10
const SEGMENT_NOT_PRESENT := 11
const STACK_FAULT := 12
const GENERAL_PROTECTION := 13
const PAGE_FAULT := 14
const X87_FLOATING_POINT := 16
const ALIGNMENT_CHECK := 17
const MACHINE_CHECK := 18
const SIMD_FLOATING_POINT := 19
const VIRTUALIZATION := 20
const CONTROL_PROTECTION := 21

# ---- lignes héritées du PC (ISA) ----
const IRQ_TIMER := 0
const IRQ_KEYBOARD := 1
const IRQ_CASCADE := 2
const IRQ_COM2 := 3
const IRQ_COM1 := 4
const IRQ_LPT2 := 5
const IRQ_FLOPPY := 6
const IRQ_LPT1 := 7
const IRQ_RTC := 8
const IRQ_ACPI := 9
const IRQ_FREE10 := 10
const IRQ_FREE11 := 11
const IRQ_MOUSE := 12
const IRQ_FPU := 13
const IRQ_ATA_PRIMARY := 14
const IRQ_ATA_SECONDARY := 15
const LEGACY_IRQS := 16

# ---- vecteurs ----
const IRQ_BASE := 32           # PIC remappé : IRQ 0..15 -> 32..47 (et IO-APIC : GSI n -> 32 + n)
const IRQ_LAST := 47
const GSI_LAST := 79           # IO-APIC : jusqu'à 48 entrées de redirection (vecteurs 32..79)
const MSI_BASE := 80           # vecteurs attribués aux MSI / MSI-X : 80..223
const MSI_LAST := 223
const IPI_BASE := 224          # inter-processeurs : 224..239
const IPI_LAST := 239
const APIC_TIMER := 240        # minuterie de l'APIC local
const APIC_ERROR := 254
const SPURIOUS := 255          # vecteur parasite de l'APIC local
const SYSCALL := 128           # int 0x80 (convention)

# ---- déclenchement (IO-APIC, MSI) ----
const EDGE := 0
const LEVEL := 1
const ACTIVE_HIGH := 0
const ACTIVE_LOW := 1

func is_exception(vector: int) -> bool:
    return vector >= 0 and vector < 32

# Les exceptions qui empilent un code d'erreur.
func has_error_code(vector: int) -> bool:
    return vector == 8 or (vector >= 10 and vector <= 14) or vector == 17 or vector == 21 or vector == 29 or vector == 30

func exception_name(vector: int) -> str:
    if vector == 0:
        return "division par zéro (#DE)"
    if vector == 1:
        return "débogage (#DB)"
    if vector == 2:
        return "interruption non masquable (NMI)"
    if vector == 3:
        return "point d'arrêt (#BP)"
    if vector == 4:
        return "dépassement (#OF)"
    if vector == 5:
        return "hors limites (#BR)"
    if vector == 6:
        return "instruction invalide (#UD)"
    if vector == 7:
        return "coprocesseur indisponible (#NM)"
    if vector == 8:
        return "double faute (#DF)"
    if vector == 9:
        return "dépassement de segment du coprocesseur"
    if vector == 10:
        return "TSS invalide (#TS)"
    if vector == 11:
        return "segment absent (#NP)"
    if vector == 12:
        return "faute de pile (#SS)"
    if vector == 13:
        return "protection générale (#GP)"
    if vector == 14:
        return "défaut de page (#PF)"
    if vector == 16:
        return "erreur flottante x87 (#MF)"
    if vector == 17:
        return "alignement (#AC)"
    if vector == 18:
        return "erreur matérielle (#MC)"
    if vector == 19:
        return "erreur flottante SIMD (#XM)"
    if vector == 20:
        return "virtualisation (#VE)"
    if vector == 21:
        return "protection du flot de contrôle (#CP)"
    if vector == 29:
        return "communication VMM (#VC)"
    if vector == 30:
        return "sécurité (#SX)"
    if vector < 32:
        return "exception réservée " + str(vector)
    return "vecteur " + str(vector)

func irq_name(irq: int) -> str:
    if irq == 0:
        return "minuterie (PIT)"
    if irq == 1:
        return "clavier PS/2"
    if irq == 2:
        return "cascade (PIC esclave)"
    if irq == 3:
        return "COM2"
    if irq == 4:
        return "COM1"
    if irq == 5:
        return "LPT2 / son"
    if irq == 6:
        return "lecteur de disquettes"
    if irq == 7:
        return "LPT1 / parasite"
    if irq == 8:
        return "horloge temps réel (RTC)"
    if irq == 9:
        return "ACPI"
    if irq == 12:
        return "souris PS/2"
    if irq == 13:
        return "coprocesseur"
    if irq == 14:
        return "ATA primaire"
    if irq == 15:
        return "ATA secondaire / parasite"
    return "IRQ " + str(irq)

func irq_vector(irq: int) -> int:
    return IRQ_BASE + irq

func vector_irq(vector: int) -> int:
    if vector >= IRQ_BASE and vector <= GSI_LAST:
        return vector - IRQ_BASE
    return -1

# « exception », « irq », « msi », « ipi », « apic », « parasite », « appel système » ou « logiciel ».
func kind_of(vector: int) -> str:
    if vector < 32:
        return "exception"
    if vector <= GSI_LAST:
        return "irq"
    if vector == SYSCALL:
        return "appel système"
    if vector >= MSI_BASE and vector <= MSI_LAST:
        return "msi"
    if vector >= IPI_BASE and vector <= IPI_LAST:
        return "ipi"
    if vector == SPURIOUS:
        return "parasite"
    if vector >= 240:
        return "apic"
    return "logiciel"

func describe(vector: int) -> str:
    if vector < 32:
        return exception_name(vector)
    irq := vector_irq(vector)
    if irq >= 0:
        return "IRQ " + str(irq) + " (" + irq_name(irq) + ")"
    return kind_of(vector) + " " + str(vector)

# Adresse et données d'un message MSI vers l'APIC local apic_id (x86) : [adresse, données].
func msi_message(vector: int, apic_id: int, level: bool) -> list[int]:
    addr := 0xFEE00000 | ((apic_id & 255) << 12)
    data := vector & 255
    if level:
        data = data | 0xC000
    return [addr, data]
