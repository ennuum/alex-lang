# Pilote de clavier PS/2 par interruption (ligne 1 du PIC, vecteur 33), jeu de codes 1, disposition QWERTY.
use hw
from collections use append
from core use len

const NORMAL := "\0\0" + "1234567890-=" + "\0\t" + "qwertyuiop[]" + "\n\0" + "asdfghjkl;'`" + "\0\\" + "zxcvbnm,./" + "\0*\0 "
const SHIFTED := "\0\0" + "!@#$%^&*()_+" + "\0\t" + "QWERTYUIOP{}" + "\n\0" + "ASDFGHJKL:\"~" + "\0|" + "ZXCVBNM<>?" + "\0*\0 "
const BACKSPACE := '\0'

_keys: list[char] := []
_head := 0
_shift := false
_backspace := 0

func _interrupt(code: int):
    sc := hw.inb(96) # 0x60 : code de touche
    if sc == 42 or sc == 54:
        _shift = true
    elif sc == 170 or sc == 182:
        _shift = false
    elif sc == 14:
        _backspace += 1
        append(_keys, BACKSPACE)
    elif sc < len(NORMAL):
        c := NORMAL[sc]
        if _shift:
            c = SHIFTED[sc]
        if c != '\0':
            append(_keys, c)
    hw.eoi(1)

func init():
    hw.on_interrupt(33, _interrupt)
    while (hw.inb(100) & 1) != 0: # 0x64 : vide le tampon du contrôleur
        hw.inb(96)
    hw.irq_enable(1)

func available() -> bool:
    return _head < len(_keys)

# Prochain caractère (BACKSPACE pour le retour arrière) ; attend une frappe.
func read_char() -> char:
    while true:
        hw.disable()
        if _head < len(_keys):
            c := _keys[_head]
            _head += 1
            hw.enable()
            return c
        hw.wait()
    return '\0'
