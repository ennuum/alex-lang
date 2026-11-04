# Application UEFI (alexc build --native --uefi) : services du micrologiciel par hw.efi_call — écriture sur la
# console (ConOut->OutputString, UTF-16), pages demandées à BootServices->AllocatePages puis rendues, code de
# sortie transmis comme statut d'erreur EFI.
use hw
use string

func conout(s: str):
    st := hw.efi_system_table()
    con := hw.peek64(st + 0x40)
    fn := hw.peek64(con + 8)
    n := string.byte_len(s)
    buf := hw.alloc_pages(1)
    i := 0
    k := 0
    while i < n:
        c := string.byte_at(s, i)
        hw.poke16(buf + 2 * k, c)
        i += 1
        k += 1
    hw.poke16(buf + 2 * k, 0)
    hw.efi_call(fn, con, buf)

print("uefi : " + str(hw.uefi()))
print("image : " + str(hw.efi_image() != 0))
st := hw.efi_system_table()
print("signature : " + str(hw.peek64(st) == 0x5453595320494249))
conout("Bonjour depuis ConOut\r\n")
bs := hw.peek64(st + 0x60)
cell := hw.alloc_pages(1)
status := hw.efi_call(hw.peek64(bs + 0x28), 0, 2, 3, cell)
print("AllocatePages : " + str(status))
mem := hw.peek64(cell)
hw.poke64(mem + 8192, 42)
print("lu : " + str(hw.peek64(mem + 8192)))
print("FreePages : " + str(hw.efi_call(hw.peek64(bs + 0x30), mem, 3)))
print("service absent : " + str(hw.efi_call(hw.peek64(bs + 0x18)) == -9223372036854775805))
hw.exit(3)
