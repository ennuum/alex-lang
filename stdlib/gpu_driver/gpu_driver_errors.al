# alex: native
# ALEX STANDARD LIBRARY — gpu_driver.gpu_driver_errors
#
# Erreurs des pilotes graphiques du noyau :
#   GpuDriverError   erreur générale              ModeError       mode vidéo non pris en charge / refusé
#   VramExhausted    mémoire vidéo épuisée        GpuHang         moteur bloqué (budget de commandes dépassé)
#   FirmwareError    ROM / EDID invalide          BindingError    carte déjà liée, ressources en conflit
#   - mode_error : message avec le mode demandé et les limites de la carte ;
#   - check_mode : vérifie un mode contre des GpuCapabilities (ModeError sinon) ;
#   - is_fatal : faut-il réinitialiser la carte (GpuHang) ou seulement refuser la demande.
#
#   use gpu_driver.gpu_driver_errors as gde
#   gde.check_mode(caps, 1920, 1080, 32)
#
# Compilable en natif (# alex: native).

use gpu_driver.gpu_capabilities as gcap
from gpu_driver.gpu_capabilities use GpuCapabilities

const DRIVER := "GpuDriverError"
const MODE := "ModeError"
const VRAM := "VramExhausted"
const HANG := "GpuHang"
const FIRMWARE := "FirmwareError"
const BINDING := "BindingError"

func is_gpu_driver_error(t: str) -> bool:
    return t == DRIVER or t == MODE or t == VRAM or t == HANG or t == FIRMWARE or t == BINDING

# Erreur après laquelle la carte doit être réinitialisée.
func is_fatal(t: str) -> bool:
    return t == HANG

func mode_error(card: str, width: int, height: int, bpp: int, why: str):
    raise(MODE, card + " : mode " + str(width) + "x" + str(height) + "x" + str(bpp) + " refusé (" + why + ")")

func check_mode(caps: GpuCapabilities, width: int, height: int, bpp: int):
    if width <= 0 or height <= 0:
        mode_error(caps.name, width, height, bpp, "dimensions invalides")
    if width > caps.max_width or height > caps.max_height:
        mode_error(caps.name, width, height, bpp, "maximum " + str(caps.max_width) + "x" + str(caps.max_height))
    ok := false
    for d in caps.depths:
        if d == bpp:
            ok = true
    if not ok:
        mode_error(caps.name, width, height, bpp, "profondeur non prise en charge")
    need := width * height * bpp // 8
    if need > caps.vram:
        mode_error(caps.name, width, height, bpp, str(need) + " octets > " + str(caps.vram) + " de VRAM")

func vram_exhausted(card: str, wanted: int, free: int):
    raise(VRAM, card + " : " + str(wanted) + " octets demandés, " + str(free) + " libres")

func hang(card: str, context: str, budget: int):
    raise(HANG, card + " : contexte « " + context + " » bloqué (plus de " + str(budget) + " commandes sans fin)")
