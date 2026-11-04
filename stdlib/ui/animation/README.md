# ALEX UI V0.6 — Animations

Animation engine pure ALEX, séparé des contrôles.

## API

- `ui.animation(...)` crée une animation de propriété.
- `ui.animate(animation)` exécute l'animation.
- `ui.move(...)` anime la position.
- `ui.resize_animation(...)` anime la taille.
- `ui.pulse(...)` crée une attention visuelle répétée.
- `ui.animation_state(...)` retourne `idle`, `running` ou `finished`.

## Easing

`linear`, `ease_in`, `ease_out`, `ease_in_out`, `smoothstep`, `smootherstep`, `cubic_*`, `quart_*`, `quint_*`, `sine_*`, `expo_*`, `back_*`, `bounce_*`.

## Architecture

```text
ui.al
  -> animation.al
      -> animation/animation.al
      -> animation/easing.al
          -> os.monotonic_time/sleep
          -> ui.widget
```

Aucune dépendance graphique externe n'est ajoutée.
