# ALEX UI V0.3 — Layouts

Le moteur de layout est écrit en ALEX pur. Les layouts calculent les géométries puis utilisent `ui.widget.set_position()` et `ui.widget.set_size()`.

## API

- `ui.vbox(children, width, height, gap, padding, alignment)`
- `ui.hbox(children, width, height, gap, padding, alignment)`
- `ui.grid(children, width, height, columns, gap, padding)`
- `ui.stack(children, width, height, padding)`
- `ui.anchor(children, width, height, padding)`
- `ui.responsive(children, width, height, breakpoint, gap, padding, alignment)`

Un enfant standard est créé avec :

```al
item := ui.layout_item(widget, 180, 36, 0, 8)
```

`flex > 0` permet au `VBox` ou `HBox` de distribuer l'espace restant.

Pour l'ancrage :

```al
item := ui.anchor_item(widget, 200, 40, 10, 10, null, null)
```

Les constantes d'alignement sont exposées par :

- `ui.alignment_start()`
- `ui.alignment_center()`
- `ui.alignment_end()`
