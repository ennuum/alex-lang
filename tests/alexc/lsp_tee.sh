#!/bin/sh
# Serveur de langage intercalé (tests/alexc/golden.sh) : lance « $REAL lsp ... » et copie sa sortie dans $LOG.
"$REAL" "$@" | tee "$LOG"
