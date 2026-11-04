# ALEX STANDARD LIBRARY — io.file
#
# Fichiers, sous le nom io.file : même API que le module `file` (docs/PURE_MODULES.md), qui reste disponible.
# Lecture et écriture d'un coup (read, write, append, read_lines, write_lines, write_atomic...), fichiers
# ouverts (open, with_open : objet File avec read, read_line, write, seek...). Pour un flux interchangeable
# avec d'autres sources (tubes, processus, chaînes), voir io.stream (open_file, create_file).
#
#   use io.file as file
#   file.write("notes.txt", "bonjour\n")
#   print(file.read_lines("notes.txt"))

use file as _file

func exists(p):
    return _file.exists(p)

func size(p):
    return _file.size(p)

func read(p):
    return _file.read(p)

func read_or(p, fallback=null):
    return _file.read_or(p, fallback)

func read_lines(p, keep_ends=false):
    return _file.read_lines(p, keep_ends)

func line_count(p):
    return _file.line_count(p)

func head(p, n=10):
    return _file.head(p, n)

func tail(p, n=10):
    return _file.tail(p, n)

func read_bytes(p):
    return _file.read_bytes(p)

func write_bytes(p, data):
    return _file.write_bytes(p, data)

func append_bytes(p, data):
    return _file.append_bytes(p, data)

func create(p, text=""):
    return _file.create(p, text)

func write(p, text):
    return _file.write(p, text)

func append(p, text):
    return _file.append(p, text)

func write_lines(p, lines, newline="\n"):
    return _file.write_lines(p, lines, newline)

func append_lines(p, lines, newline="\n"):
    return _file.append_lines(p, lines, newline)

func write_atomic(p, data):
    return _file.write_atomic(p, data)

func delete(p, missing_ok=false):
    return _file.delete(p, missing_ok)

func open(p, mode="r"):
    return _file.open(p, mode)

func with_open(p, fn, mode="r"):
    return _file.with_open(p, fn, mode)
