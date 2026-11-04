# ALEX UI — plateformes et backends

| Plateforme | Backend | Rendu | Widgets |
|---|---|---|---|
| Windows | Win32 + Direct2D | matériel | contrôles natifs Win32 |
| Linux (X11 / XWayland) | `x11` | logiciel (`raster.cpp`) | émulés (rendu + interactions) |
| Tout (CI, serveur sans écran) | `headless` | logiciel, hors écran | émulés, événements injectables |

Choix du backend (non-Windows) : variable `ALEX_UI_BACKEND=auto|x11|headless`
(`auto` = X11 ; sans `DISPLAY`, `ui.window()` lève une `IoError` explicite).
`ui.backend()` renvoie le backend actif.

## Compilation Linux
`make alex` active X11 si `X11/Xlib.h` est présent (`libx11-dev` / `libX11-devel`). libX11 est chargée
à l'exécution (`dlopen`) : l'exécutable n'a pas de dépendance de lien vers X11 et reste utilisable
sans (headless). Sans les en-têtes, seul `headless` est disponible.

## Ce que fait le backend portable
- Fenêtres, titre, taille, non-redimensionnable, fermeture (`WM_DELETE_WINDOW`), `resize`.
- Widgets : button, label, input (UTF-8, curseur, Home/End/Suppr, Ctrl+V/C), checkbox, radio (exclusifs),
  combo, progress, scroll ; Tab / Maj+Tab, Entrée/Espace, états hover/pressed/focus/disabled.
- Événements : `button`, `check`, `radio`, `change`, `key_down` (champs `key`, `mods`, `text`),
  `pointer_move|down|up` (champs `x`, `y`, `button`), `wheel`, `resize`, `shortcut`, `command`, `close`.
- Canvas complet : formes anti-crénelées, chemins, dégradés, ombres floues, images (PNG/BMP/PPM),
  clip, transformation, opacité, texte (DejaVu Sans embarquée, UTF-8).
- Système : presse-papiers (`wl-copy`/`xclip`/`xsel`), notifications (`notify-send`),
  sélecteur de fichiers (`zenity`/`kdialog`), DPI (`Xft.dpi`), écran, menu (barre simple), raccourcis.

## Automatisation / tests (additif)
`ui.inject_mouse(win, "move|down|up|click", x, y)`, `ui.inject_key(win, vk, mods)`,
`ui.inject_text(win, texte)`, `ui.screenshot(win, "x.png")`, `canvas.save_png(c, "x.png")`.

## Limites connues (Linux)
Pas de glisser-déposer de fichiers (XDND) ; pas de Wayland natif (XWayland requis) ; pas d'IME riche ;
texte : pas de rotation ; la barre de menu est plate (pas de sous-menus).

## Tests
`make test-ui-portable` (headless) · `make test-ui-x11` (Xvfb, vrais événements X).
