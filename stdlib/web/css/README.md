# web.css — CSS en ALEX pur

`web.css` analyse, construit, calcule, valide et produit du **CSS**. Le paquet comprend une vraie cascade
(style calculé d'un élément `web.html` ou `web.dom`), l'évaluation des requêtes média, de conteneur et
`@supports`, des fonctions mathématiques (`calc()`, `clamp()`…) et des fonctions de temps (`cubic-bezier()`),
ainsi que des constructeurs pour les mises en page courantes. Les seules dépendances sont `string`, `math`
et `io`.

Références : CSS Syntax 3, Selectors 4, Cascade 5 (couches), Nesting, Media Queries 4/5, Containment 3
(requêtes de conteneur), Conditional 3/4, Values & Units 4, Color 4, Easing 2, Grid 2, Flexbox 1.

## Architecture

```text
stdlib/web/css/
├── css.al               point d'entrée : parse, render, minify, validate, compute, color, matches…
├── stylesheet.al        Stylesheet, CASCADE (origines, !important, @layer, spécificité, héritage, var()),
│                        feuille par défaut de l'agent utilisateur
├── css_rule.al          StyleRule (imbrication « & », aplatissement), Format de sortie
├── at_rule.al           @media @supports @container @layer @scope @font-face @page @property @import…
├── keyframes.al         @keyframes, interpolation des valeurs (nombres, dimensions, couleurs, fonctions)
├── selector.al          correspondance d'éléments (adaptateurs web.html / web.dom), select, closest
├── selector_parser.al   analyse des sélecteurs (:is :where :not :has, nth of S, &), spécificité
├── declaration.al       déclarations, blocs, raccourcis développés, contrôle des valeurs par nature
├── property.al          base de ~250 propriétés (héritée, valeur initiale, nature), raccourcis
├── value.al             jetons CSS Syntax 3, composantes (fonctions, blocs), sérialisation
├── color.al             couleurs : hex, rgb, hsl, hwb, 148 noms ; contraste WCAG, mélanges, nuances
├── units.al             dimensions, conversions, contexte (em, rem, vw, %, cq*) -> px
├── variables.al         var(), portées, résolution avec replis
├── functions.al         calc min max clamp round mod… (évaluation), dégradés, url(), attr(), env()
├── media_query.al       requêtes média (intervalles, and/or/not), Environment, analyseur de conditions partagé
├── container_query.al   @container : nom, taille, style(), conteneur le plus proche
├── supports_query.al    @supports : déclarations, selector(), font-format(), moteur simulé
├── css_parser.al        analyse tolérante d'une feuille avec récupération d'erreurs et lignes
├── css_writer.al        écriture (lisible, indentée, compacte), from_dict, fusion des @media
├── css_minifier.al      minification sûre (couleurs, zéros, doublons, fusions)
├── css_validate.al      validation : syntaxe, propriétés, valeurs, sélecteurs, @keyframes, var()
├── flexbox.al           flex(), center(), stack()… et calcul d'une ligne flexible
├── grid.al              grid(), repeat(), zones nommées, calcul des pistes (fr, minmax, auto-fill)
├── positioning.al       position, inset, centrage, visually_hidden, échelle de z-index
├── typography.al        piles de polices, échelles modulaires, tailles fluides, troncature
├── backgrounds.al       couches, couverture, motifs CSS, image-set()
├── borders.al           bordures, rayons, anneau de focus, analyse du raccourci border
├── shadows.al           Shadow, élévations, ombres en couches, analyse
├── transforms.al        Transform chaînable, matrice 2D (application, inverse, décomposition)
├── transitions.al       transitions, fonctions de temps évaluées (cubic-bezier, steps, linear())
├── animations.al        animations : analyse et simulation (itérations, direction, remplissage)
├── responsive.al        points de rupture, règles mobile d'abord, sizes / srcset
├── theme.al             jetons de conception -> variables, variantes sombre / contraste, palettes
├── css_errors.al        CssError, CssParseError, CssSelectorError, CssValueError, CssValidationError, Issue
└── README.md
```

## Exemples

```al
use web.css as css
use web.html as html

sheet := css.parse("
  :root { --accent: #2563eb; }
  .carte { padding: 1rem; border-radius: 8px;
           &:hover { box-shadow: 0 4px 12px rgb(0 0 0 / 15%); }
           @media (width >= 48em) { padding: 2rem; } }
  .carte h2 { color: var(--accent); font-size: 1.5em; }
")
print(css.render(sheet, true))

doc := html.parse("<div class=carte><h2>Titre</h2></div>")
h2 := css.select(doc, ".carte h2")[0]
st := css.compute(h2, sheet, css.environment(1024, 768))
print(st.get("color"), st.font_size_px, st.get("display"))   # #2563eb 24.0 block
```

Minifier et valider :

```al
print(css.minify("a { color: #FFFFFF; margin: 0px 0.5em; }"))   # a{color:#fff;margin:0 .5em}
r := css.validate("a { colr: red; width: 12 }")
for i in r.issues:
    print(i)       # warning [unknown-property] propriété inconnue « colr » (vouliez-vous dire « color » ?) …
```

Construire sans écrire de CSS à la main :

```al
use web.css.css_rule as cr
use web.css.flexbox as fx
use web.css.grid as grid
use web.css.typography as ty

barre := cr.StyleRule(".barre", fx.flex("row", "between", "center", true, "1rem"))
galerie := cr.StyleRule(".galerie", grid.responsive("14rem", "1.5rem"))
titre := cr.StyleRule("h1", ty.font(ty.stack("system"), ty.fluid(28, 48), 700, 1.1))
```

Calculer sans navigateur :

```al
use web.css.functions as fn
use web.css.units as units
use web.css.transitions as tr
use web.css.grid as grid

fn.evaluate("clamp(1rem, 2.5vw, 2rem)", units.Context(16, 16, 1280, 720))   # 32.0
tr.easing("cubic-bezier(0.34, 1.56, 0.64, 1)").at(0.5)                       # ≈ 1.087
grid.track_sizes("repeat(auto-fill, minmax(150px, 1fr))", 700, 10)           # [167.5, 167.5, 167.5, 167.5]
```

## La cascade

`stylesheet.compute(élément, feuilles, environnement)` suit Cascade 5 :

1. **Pertinence** : règles dont un sélecteur correspond ; `@media` évaluée sur l'`Environment`, `@supports`
   par le moteur simulé, `@container` si une fonction `containers` est fournie, `@scope (début) to (fin)`.
2. **Origine et importance** : agent utilisateur < utilisateur < auteur, puis ordre inversé pour `!important`.
3. **Style en ligne** (attribut `style` ou argument `inline`) au-dessus des règles de l'auteur.
4. **Couches** `@layer` dans l'ordre de première apparition ; les règles hors couche l'emportent
   (et perdent pour `!important`).
5. **Spécificité**, puis **ordre** d'apparition.

Viennent ensuite le développement des raccourcis, l'héritage (`inherit`, `initial`, `unset`, `revert`),
les propriétés personnalisées héritées et `var()` (une valeur invalide au calcul devient `unset`), et la
taille de police calculée en px (`em`, `rem`, `%`, mots-clés `small`… `larger`).

`ComputedStyle.get(nom)` renvoie la valeur calculée ou la valeur initiale ; un raccourci (`margin`,
`border-color`…) est recomposé depuis ses propriétés longues. `ComputedStyle.px(nom)` évalue une longueur.

Simplifications assumées : pas de mise en page (les pourcentages et `auto` restent textuels), pas de
pseudo-éléments dans le calcul, `revert` traité comme `unset`, proximité de `@scope` ignorée.

## Conventions

- Les fonctions de construction renvoient des **dicts** propriété -> valeur, directement utilisables par
  `StyleRule(sélecteur, dict)` ; les noms ALEX en `snake_case` (`font_size`) sont acceptés partout.
- Un nombre passé comme longueur devient des px (`0` reste `0`) ; un texte est gardé tel quel.
- L'analyse est **tolérante** comme celle d'un navigateur : rien n'est levé, les problèmes sont rapportés dans
  une liste d'`Issue` (niveau, code, message, ligne). `strict=true` lève `CssParseError`.
- Les propriétés personnalisées et le contenu des chaînes ne sont jamais réécrits (minifieur compris).

## Tests

```sh
make test-web        # comprend tests/web/test_web_css.al
```
