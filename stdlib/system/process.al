# ALEX STANDARD LIBRARY — system.process
#
# Le module `process` (docs/PROCESS_FFI.md) sous le nom system.process : lancer des programmes sans shell
# (run, spawn, check_output, which), Command(programme) pour tout régler (arguments, répertoire, environnement,
# flux "pipe" / "null" / descripteur, délai), Process (read, write, wait, kill...). `process` reste disponible.
#
#   use system.process as process
#   r := process.run("git", ["status", "--short"], timeout=10)
#   print(r.code, r.stdout)

use process as _p


const INHERIT := _p.INHERIT
const PIPE := _p.PIPE
const DEVNULL := _p.DEVNULL
const STDOUT := _p.STDOUT

run := _p.run
spawn := _p.spawn
check_output := _p.check_output
which := _p.which
open_handles := _p.open_handles
supported := _p.supported

func Command(program, args=null):
    return _p.Command(program, args)
