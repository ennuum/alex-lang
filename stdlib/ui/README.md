# ALEX STANDARD LIBRARY — UI V0.3

> Pour décrire une interface une fois et l'afficher dans une fenêtre (`gui`) ou dans le terminal (`tui`),
> voir `ui.view` et docs/UI_VIEW.md. Ce module-ci reste le socle : fenêtres, contrôles natifs, canvas.

API desktop native ALEX, organisée en modules `.al` spécialisés.

## Architecture

```text
stdlib/ui/
├── ui.al
├── window.al
├── widget.al
├── button.al
├── label.al
├── text_input.al
├── checkbox.al
├── radio_button.al
├── combo_box.al
├── progress_bar.al
├── scroll_view.al
├── event.al
└── layout/
    ├── layout.al
    ├── vbox.al
    ├── hbox.al
    ├── grid.al
    ├── stack.al
    ├── anchor.al
    ├── padding.al
    ├── margin.al
    ├── alignment.al
    ├── responsive.al
    └── README.md
```

## Layouts V0.3

Le calcul de géométrie est réalisé en ALEX pur. Le runtime natif ne fait que l'application de la position et de la taille aux widgets.

- VBox : flux vertical + flex
- HBox : flux horizontal + flex
- Grid : grille uniforme
- Stack : superposition
- Anchor : ancrage aux bords
- Padding : helpers d'espacement
- Margin : helper d'espacement
- Alignment : start / center / end
- Responsive : bascule VBox/HBox selon la largeur

## Exemple

```al
use ui

window := ui.window("ALEX UI V0.3", 800, 500)
label := ui.label(window, "Nom")
button := ui.button(window, "Valider")
field := ui.input_field(window)

children := [
    ui.layout_item(label, 220, 30),
    ui.layout_item(field, 300, 32, 1),
    ui.layout_item(button, 180, 36)
]

ui.vbox(children, 760, 460, 10, 20, ui.alignment_center())
ui.show(window)
ui.run(window)
```


## UI V0.5 — Applications modernes

Nouveaux modules : `application.al`, `notification.al`, `clipboard.al`, `shortcut.al`, `dragdrop.al`, `menu.al`, `file_dialog.al`, `screen.al`, `dpi.al`.

Les événements natifs supplémentaires sont `shortcut`, `drop` et `command`; les événements exposent également `data`.

Sous Windows, le backend utilise Win32, Common Controls, Shell32 et Common Dialogs. Les fonctions non disponibles sur une plateforme renvoient une erreur explicite au lieu d'une implémentation simulée.
