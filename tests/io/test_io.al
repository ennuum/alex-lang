# Test des modules io.stream, io.pipe, io.console (parties non interactives) et io.file.
# La saisie au clavier (read_key, read_password) est testée dans un pseudo-terminal : tests/io/console_pty.py.

from core use len, type
from collections use append
use string as s
use os
use process as proc
use io.stream as stream
use io.pipe as pipe
use io.console as console
use io.file as iofile
use concurrency.thread as thread
use tests.io.io_workers as w

stats := [0, 0]
notes := []

func check_eq(actual, expected, label):
    if actual == expected:
        stats[0] = stats[0] + 1
    else:
        stats[1] = stats[1] + 1
        append(notes, f"{label} : obtenu {actual}, attendu {expected}")

func check(cond, label):
    check_eq(cond, true, label)

func error_of(f):
    try:
        f()
    catch e:
        return e.type
    return "aucune erreur"

func main():
    tmp := os.tmp_dir() + "/alex_test_io_" + str(os.pid())
    os.mkdir(tmp)

    # ------------------------------------------------------------ stream
    r := stream.from_string("un\r\ndeux\ntrois;quatre;cinq")
    check_eq(r.read_line(), "un", "read_line (\\r\\n)")
    check_eq(r.read_line(), "deux", "read_line")
    check_eq(r.read_until(";"), "trois", "read_until")
    check_eq(r.read_exact(6), "quatre", "read_exact")
    check_eq(r.read(1), ";", "read(1)")
    check_eq(r.read_all(), "cinq", "read_all")
    check(r.at_end(), "at_end")
    check_eq(r.read_line(), null, "read_line à la fin")
    check_eq(error_of(() => stream.from_string("ab").read_exact(3)), "IoError", "read_exact au-delà de la fin")
    check_eq(stream.from_string("a\nb\n\nc").lines(), ["a", "b", "", "c"], "lines")
    check_eq(stream.from_string("été").read(1), "é", "read ne coupe pas un caractère")
    check_eq(stream.from_string("AB").read_bytes(), [65, 66], "read_bytes")
    sw := stream.StringWriter()
    sw.write("a")
    sw.write_line("b")
    sw.write_bytes([195, 169])
    check_eq(sw.value(), "ab\né", "StringWriter")
    check_eq(error_of(() => sw.write(3)), "TypeError", "write d'un int")

    # Fichiers en flux : texte UTF-8 et octets quelconques.
    path := tmp + "/flux.txt"
    fw := stream.create_file(path)
    fw.write_line("première ligne é")
    fw.write_bytes([0, 255, 10])
    fw.write("fin")
    fw.close()
    fr := stream.open_file(path)
    check_eq(fr.read_line(), "première ligne é", "FileReader : ligne UTF-8")
    check_eq(stream.from_string(fr.read_exact(3)).read_bytes(), [0, 255, 10], "FileReader : octets bruts")
    check_eq(fr.read_all(), "fin", "FileReader : reste")
    fr.close()
    copy := stream.StringWriter()
    check_eq(stream.copy(stream.open_file(path), copy), iofile.size(path), "copy : octets")
    fa := stream.create_file(path, true)
    fa.write("+ajout")
    fa.close()
    check(s.ends_with(iofile.read(path), "fin+ajout"), "FileWriter en ajout")

    # Processus en flux.
    p := proc.Command("printf").args(["x\ny\n"]).stdout("pipe").spawn()
    check_eq(stream.ProcessReader(p).lines(5.0), ["x", "y"], "ProcessReader")
    p.wait()
    p.close()

    # ------------------------------------------------------------ pipe
    pp := pipe.Pipe()
    pp.writer.write_line("dans le tube")
    pp.writer.close()
    check_eq(pp.reader.read_line(2.0), "dans le tube", "tube anonyme")
    check_eq(pp.reader.read_line(2.0), null, "fin du tube après fermeture de l'écriture")
    pp.reader.close()
    p2 := pipe.Pipe()
    check_eq(error_of(() => p2.reader.read(10, 0.05)), "TimeoutError", "lecture d'un tube vide : délai")
    p2.close()

    # Un fil écrit dans un tube du programme principal (le descripteur passe d'un fil à l'autre).
    p3 := pipe.Pipe()
    t := thread.spawn(w.write_to_fd, [p3.writer.fd, 3])
    lines := p3.reader.lines(10.0)
    check_eq(lines, ["ligne 0 du fil", "ligne 1 du fil", "ligne 2 du fil"], "tube entre deux fils")
    t.join()
    p3.reader.close()

    # Tube branché sur l'entrée d'un processus fils.
    p4 := pipe.Pipe()
    child := proc.Command("tr").args(["a-z", "A-Z"]).stdin(p4.reader).stdout("pipe").spawn()
    p4.reader.close()
    p4.writer.write("majuscules\n")
    p4.writer.close()
    check_eq(child.read_all(), "MAJUSCULES\n", "tube vers l'entrée d'un fils")
    child.wait()
    child.close()

    # Tube nommé.
    fifo := tmp + "/fifo"
    pipe.create_fifo(fifo)
    check_eq(error_of(() => pipe.create_fifo(fifo)), "IoError", "create_fifo : existe déjà")
    check_eq(error_of(() => pipe.open_fifo_writer(fifo, 0.1)), "TimeoutError", "open_fifo_writer sans lecteur : délai")
    fr2 := pipe.open_fifo_reader(fifo)
    fw2 := pipe.open_fifo_writer(fifo, 2.0)
    fw2.write_line("par le tube nommé")
    fw2.close()
    check_eq(fr2.read_line(2.0), "par le tube nommé", "tube nommé")
    fr2.close()
    check_eq(error_of(() => pipe.open_fifo_reader(tmp + "/absent")), "IoError", "tube nommé absent")

    # Chaînes de processus sans shell.
    pl := pipe.pipeline([["printf", "b\na\nc\n"], ["sort"], ["head", "-n", "2"]])
    check_eq([pl.stdout, pl.codes, pl.ok()], ["a\nb\n", [0, 0, 0], true], "pipeline à trois commandes")
    check_eq(pipe.pipeline([["tr", "a-z", "A-Z"]], "abc").stdout, "ABC", "pipeline avec entrée")
    big := s.repeat("0123456789abcdef\n", 65536)
    out := pipe.pipeline([["cat"], ["cat"]], big)
    check_eq(len(out.stdout), len(big), "pipeline : 1 Mio sans blocage mutuel")
    check_eq(pipe.pipeline([["printf", "x"], ["false"]]).codes, [0, 1], "pipeline : code de chaque commande")
    check_eq(error_of(() => pipe.pipeline([["false"]], null, null, true)), "ProcessError", "pipeline check")
    slow := pipe.pipeline([["sleep", "5"]], null, 0.3)
    check(slow.timed_out and not slow.ok(), "pipeline : délai total")
    check_eq(error_of(() => pipe.pipeline([])), "ArgumentError", "pipeline vide")
    check_eq(error_of(() => pipe.pipeline([["echo", 3]])), "TypeError", "argument non str")
    check_eq(pipe.pipeline([["echo", "a b;c|d $HOME"]]).stdout, "a b;c|d $HOME\n", "pas d'interprétation par un shell")

    # ------------------------------------------------------------ console (non interactive)
    esc := str(s.chr(27))
    check_eq(console.style("ok", "green", null, true, false, false, false, true), esc + "[1;32mok" + esc + "[0m", "style forcé")
    check_eq(console.style("ok", "red", "white", false, false, false, true, true), esc + "[4;31;47mok" + esc + "[0m", "style souligné, fond")
    check_eq(console.rgb("x", 1, 2, 3, true), esc + "[38;2;1;2;3mx" + esc + "[0m", "rgb forcé")
    check_eq(console.strip_styles(esc + "[1;32mvert" + esc + "[0m et " + esc + "[2Knormal"), "vert et normal", "strip_styles")
    check_eq(console.visible_length(console.style("abc", "blue", null, false, false, false, false, true)), 3, "visible_length")
    check_eq(error_of(() => console.style("x", "violet", null, false, false, false, false, true)), "ArgumentError", "couleur inconnue")
    check_eq(console.progress_bar(0.5, 10), "[#####.....]  50 %", "progress_bar")
    check_eq(console.progress_bar(2, 4), "[####] 100 %", "progress_bar bornée")
    check_eq([console.key_name(esc + "[A"), console.key_name("\r"), console.key_name(str(s.chr(3))), console.key_name(esc), console.key_name("é")], ["up", "enter", "ctrl+c", "escape", "é"], "key_name")
    sz := console.size()
    check(type(sz[0]) == "int" and sz[0] > 0 and sz[1] > 0, "size")
    check_eq(error_of(() => console.is_terminal("autre")), "ArgumentError", "is_terminal : flux inconnu")

    # ------------------------------------------------------------ io.file
    fp := tmp + "/fichier.txt"
    iofile.write(fp, "a\nb\n")
    iofile.append(fp, "c\n")
    check_eq(iofile.read_lines(fp), ["a", "b", "c"], "io.file : write, append, read_lines")
    check_eq(iofile.with_open(fp, (f) => f.read_line()), "a\n", "io.file : with_open")
    iofile.delete(fp)
    check(not iofile.exists(fp), "io.file : delete")

    os.rmdir(tmp, true)
    print(f"io : {stats[0]} vérifications OK, {stats[1]} échec(s)")
    for n in notes:
        print("  ÉCHEC " + n)
    if stats[1] > 0:
        raise("TestError", "test_io : échecs")

if thread.is_main():
    main()
