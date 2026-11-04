# Programme piloté par tests/io/console_pty.py dans un pseudo-terminal.
use io.console as console

console.write_line("PRET " + str(console.is_terminal("stdin")))
console.flush()
k := 0
while k < 5:
    console.write_line("TOUCHE " + str(console.read_key(5.0)))
    console.flush()
    k += 1
mdp := console.read_password("MDP: ")
console.write_line("SECRET [" + mdp + "]")
console.write_line("DELAI " + str(console.read_key(0.2)))
console.flush()
