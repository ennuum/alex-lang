# ALEX STANDARD LIBRARY — pipe
#
# Tubes : anonymes (pipe.anonymous_pipe), nommés (pipe.named_pipe), duplex, flux structurés et attente sur
# plusieurs tubes (pipe.pipe_stream), chaînes de processus sans shell (pipeline).
#
#   use pipe
#   t := pipe.create()                          # tube anonyme : t.reader, t.writer
#   t.send_line("bonjour")
#   print(t.receive_line(1))
#   d := pipe.duplex()                           # deux sens : d[0], d[1]
#   f := pipe.named("/tmp/canal")                # FIFO (créé si besoin)
#   s := pipe.stream(t)                          # messages délimités, JSON
#   r := pipe.pipeline([["ls"], ["sort", "-r"], ["head", "-n", "3"]])
#   print(r.stdout, r.codes, r.ok())
#   prets := pipe.poll([t1.reader, t2.reader], 0.5)
#
# Les modules détaillés restent accessibles : pipe.anonymous_pipe, pipe.named_pipe, pipe.pipe_stream, et la
# couche io.pipe sur laquelle ils reposent (docs/PIPE.md).

use io.pipe as _iop
use pipe.anonymous_pipe as _anon
use pipe.named_pipe as _named
use pipe.pipe_stream as _ps

func supported():
    return _anon.supported()

# Tube anonyme (AnonymousPipe : reader, writer, send, receive, receive_line, close...).
func create():
    return _anon.AnonymousPipe()

# Tube à deux sens : (a, b), deux DuplexEnd reliés.
func duplex():
    return _anon.duplex()

# Tube nommé au chemin path, créé s'il n'existe pas.
func named(path, mode=384):
    return _named.NamedPipe(path).create(mode, true)

func temporary_named():
    return _named.temporary()

# Flux structuré sur un tube anonyme, une extrémité duplex, ou un couple (reader, writer).
func stream(source, writer=null):
    if writer != null:
        return _ps.PipeStream(source, writer)
    return _ps.PipeStream(source.reader, source.writer)

# Chaîne de processus a | b | c sans shell (io.pipe.pipeline).
func pipeline(commands, input=null, timeout=null, check=false):
    return _iop.pipeline(commands, input, timeout, check)

# Lecteurs prêts parmi streams (pipe_stream.poll).
func poll(streams, timeout=null):
    return _ps.poll(streams, timeout)

func copy(reader, writer):
    return _ps.copy(reader, writer)

func reader_from_fd(fd):
    return _iop.reader_from_fd(fd)

func writer_from_fd(fd):
    return _iop.writer_from_fd(fd)
