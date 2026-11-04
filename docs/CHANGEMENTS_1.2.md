# ALEX 1.2.0 — interface graphique d'Alex OS

Version issue du développement d'Alex OS 0.5.0 (interface graphique NOVA). Ajouts rétrocompatibles.

## Ajouts

* **Module `pixmap`** (`stdlib/pixmap/pixmap.al`, natif) : dessin 2D logiciel — surfaces ARGB et masques,
  remplissages, découpe, alpha, dégradés, rectangles arrondis, ombres, polygones, texte lissé (`.alfont`), images
  (`.alpx`), PNG, enveloppe de tampon de trame (docs/NATIVE.md, « Dessin 2D »).
* **Pragma `# alex: intrinsics`** (`src/NativeCodegen.cpp`) : autorise, dans un module de la bibliothèque, les
  primitives mémoire du mode sans OS dans un programme hébergé.
* **`posix`** : `set_nonblock`, `read_nb`, `eof` (lecture sans attente sur tubes et périphériques d'événements).

## Vérification

`tests/native/only/ok_pixmap.al` (surfaces, découpe, alpha, arrondis, copie, somme de contrôle, PNG), exécuté en
natif avec collecte forcée ; suite `make test` complète.
