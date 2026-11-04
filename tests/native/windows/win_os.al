# Exécutable Windows : module os (plateforme, environnement insensible à la casse) et io (chemins UTF-8 -> UTF-16).
use io
use os
print(os.name(), os.platform(), os.arch())
print(os.getenv("ALEX_WIN_VAR"), os.getenv("alex_win_var"), os.getenv("Alex_Win_Var", "d"), os.hasenv("ALEX_WIN_ABSENT"))
print(os.version() != "", os.hostname() != "", os.pid() > 0, os.parent_pid() > 0)
d := os.getenv("ALEX_WIN_DIR")
if d != null:
    p := d + "/été ☀.txt"
    io.write_file(p, "contenu\n")
    io.append_file(p, "suite")
    print(io.read_file(p))
    print(io.file_exists(p), os.isfile(p), os.isdir(d))
    io.delete_file(p)
    print(io.file_exists(p))
    os.chdir(d)
    print(os.cwd() == d)
