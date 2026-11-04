# Fonctions exécutées dans des fils par tests/io/test_io.al.
use io.pipe as pipe

# Écrit n lignes dans le tube dont le bout d'écriture a le descripteur fd, puis le ferme.
func write_to_fd(fd, n):
    wr := pipe.writer_from_fd(fd)
    i := 0
    while i < n:
        wr.write_line("ligne " + str(i) + " du fil")
        i += 1
    wr.close()
    return n
