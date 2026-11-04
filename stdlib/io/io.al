# ALEX STANDARD LIBRARY — io
# Public API in ALEX; filesystem primitives are runtime operations.

use _native_io as _io_native

func read_file(path):
    return _io_native.read_file(path)

func write_file(path, content):
    return _io_native.write_file(path, content)

func append_file(path, content):
    return _io_native.append_file(path, content)

func file_exists(path):
    return _io_native.file_exists(path)

func delete_file(path):
    return _io_native.delete_file(path)

# ---------------------------------------------------------------------
# Accès à une POSITION (octets depuis le début du fichier), texte et binaire.
# Aucun descripteur n'est conservé entre deux appels : chaque fonction ouvre, agit, referme.
# Les « octets » sont des listes d'int 0..255 (comme dans crypto).
# ---------------------------------------------------------------------

# Crée un fichier VIDE de façon atomique : IoError s'il existe déjà (même un lien symbolique, même cassé).
# Deux processus ne peuvent pas tous deux réussir : c'est la base d'un verrou ou d'un fichier temporaire sûr.
func create_file(path):
    return _io_native.create_file(path)

# Octets [offset, offset + length) ; length = -1 : jusqu'à la fin. Au-delà de la fin : liste vide ou plus courte.
func read_bytes(path, offset=0, length=-1):
    return _io_native.read_bytes(path, offset, length)

# Remplace tout le contenu par ces octets.
func write_bytes(path, data):
    return _io_native.write_bytes(path, data)

# Écrit ces octets À LA POSITION `offset` d'un fichier existant, sans le tronquer ; au-delà de la fin, le trou est
# rempli de zéros. offset null : ajoute à la fin (le fichier est créé si besoin). Retourne le nombre d'octets écrits.
func write_bytes_at(path, data, offset=null):
    return _io_native.write_bytes_at(path, offset, data)

# Idem pour du texte (UTF-8, écrit tel quel). Retourne le nombre d'OCTETS écrits.
func write_at(path, text, offset=null):
    return _io_native.write_at(path, offset, text)

# Lit au plus `chars` caractères (points de code ; -1 : jusqu'à la fin) à partir de `offset`. Retourne
# [texte, octets_consommés]. "\r\n" et "\r" sont rendus "\n" ; une séquence UTF-8 n'est jamais coupée.
func read_text(path, offset=0, chars=-1):
    return _io_native.read_text(path, offset, chars)

# Une ligne à partir de `offset`, terminateur inclus (normalisé en "\n"). Retourne [ligne, octets_consommés] ;
# la ligne est "" en fin de fichier.
func read_line(path, offset=0):
    return _io_native.read_line(path, offset)

# Fixe la taille du fichier : raccourcit, ou prolonge avec des zéros.
func truncate(path, size):
    return _io_native.truncate(path, size)

# Vide la sortie standard : ce qu'a écrit print part tout de suite (utile quand elle est un tube ou un fichier,
# où print est tamponné ; un programme qui dure, un serveur par exemple, doit l'appeler).
func flush():
    _io_native.flush_stdout()
