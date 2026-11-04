# ALEX STANDARD LIBRARY — memory.virtual
#
# Nom court de memory.virtual_memory (mémoire virtuelle : pages anonymes ou fichiers mappés, protections
# par page, pages de garde). Voir memory/virtual_memory.al et docs/MEMORY.md ; les deux noms restent valides.
#
#   use memory.virtual as vm
#   r := vm.map(2 * vm.page_size())
#   r.protect(vm.READ, 0, vm.page_size())
#   r.unmap()

use memory.virtual_memory as _vm

const NONE := _vm.NONE
const READ := _vm.READ
const WRITE := _vm.WRITE
const EXEC := _vm.EXEC
const RW := _vm.RW
const RX := _vm.RX

page_size := _vm.page_size
round_up := _vm.round_up
map := _vm.map
reserve := _vm.reserve
map_file := _vm.map_file
map_guarded := _vm.map_guarded
