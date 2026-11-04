#!/bin/sh
# Régénère stdlib/units/units.al = en-tête + registre (généré) + corps. Lancer depuis n'importe où.
set -e
cd "$(dirname "$0")"
python3 gen_units.py
mkdir -p ../../../stdlib/units
cat units_head.al units_registry.al units_body.al > ../../../stdlib/units/units.al
rm -f units_registry.al
echo "stdlib/units/units.al régénéré"
