# ALEX STANDARD LIBRARY — process._base (interne)
#
# Donne à process.Command un second nom, BaseCommand, pour que process.command puisse définir sa propre classe
# Command qui l'étend (une classe ne peut pas étendre un nom qualifié « module.Classe », et `from m use X` n'a pas
# d'alias).

from process use Command

class BaseCommand extends Command:
    func init(program, args=null):
        super.init(program, args)
