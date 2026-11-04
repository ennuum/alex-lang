# a64run : exécute un programme Linux AArch64 (ELF statique) sur une machine Linux x86-64 (émulateur écrit en
# ALEX : stdlib/outils/a64emu.al). Construit par tests/native/run_aarch64_tests.sh :
#   alexc build --native --static --image-base 0x10000000 tests/native/aarch64/a64run.al -o a64run
# Usage : a64run programme [arguments...]     A64RUN_TRACE=1 : trace des instructions (pc, mot)
use outils.a64emu as emu
emu.main()
