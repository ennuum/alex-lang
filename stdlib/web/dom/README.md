# web.dom — le DOM en ALEX

`web.dom` implémente le **Document Object Model** du standard WHATWG en ALEX pur : arbre de nœuds, éléments
et attributs, sélecteurs CSS, événements avec capture et bouillonnement, observateurs (mutations,
intersection, taille) et fenêtre (requêtes média, styles calculés). L'API suit les noms du navigateur en
`snake_case` : `append_child`, `query_selector_all`, `add_event_listener`, `class_list.toggle`…

Il sert à **manipuler du HTML comme le ferait le JavaScript d'une page**, à **tester des pages et des
composants sans navigateur** (clics, saisies, envois de formulaires simulés), et de base à `web.browser`.
L'analyse HTML vient de `web.html`, les sélecteurs, la cascade et les requêtes média de `web.css`.

## Architecture

```text
stdlib/web/dom/
├── dom.al                    point d'entrée : parse, document, window, query, on, click, flush…
├── document.al               Document, DOMImplementation, focus, collections, analyse et sérialisation
├── window.al                 Window : dimensions, défilement, match_media, get_computed_style, dialogues
├── node.al                   Node (insertion, retrait, hiérarchie, clonage, position), DocumentFragment
├── node_list.al              NodeList (statique ou vivante), HTMLCollection
├── element.al                Element : attributs, dataset, style, HTML, formulaires, click(), géométrie
├── text.al                   CharacterData, Text, Comment, CDATASection, ProcessingInstruction, DocumentType
├── attributes.al             Attr, NamedNodeMap
├── class_list.al             DOMTokenList (class_list, rel_list)
├── selectors.al              sélecteurs CSS sur le DOM (moteur web.css.selector, cache)
├── query_selector.al         query_selector(_all), get_element_by_id, get_elements_by_*
├── tree_operations.al        TreeWalker, NodeIterator, NodeFilter, wrap / unwrap, chemins
├── events.al                 on / delegate / fire, simulations : click, hover, type_text, press_key…
├── event_target.al           EventTarget et algorithme de distribution
├── event.al                  Event, UIEvent, FocusEvent
├── keyboard_event.al         KeyboardEvent, raccourcis « Ctrl+Shift+K »
├── mouse_event.al            MouseEvent, WheelEvent
├── pointer_event.al          PointerEvent
├── input_event.al            InputEvent, CompositionEvent, application d'une saisie
├── custom_event.al           CustomEvent
├── mutation_observer.al      MutationObserver, MutationRecord
├── intersection_observer.al  IntersectionObserver (géométrie simulée)
├── resize_observer.al        ResizeObserver (géométrie simulée)
├── dom_errors.al             DOMException nommées et codes
└── README.md
```

## Exemple

```al
use web.dom as dom
use web.dom.events as evs

doc := dom.parse("<!DOCTYPE html><form id=f><input name=q required><button>Chercher</button></form><ul id=r></ul>")
win := dom.window(doc, 390, 844)

f := doc.get_element_by_id("f")
f.add_event_listener("submit", (e) => liste_resultats(doc, doc.query_selector("input").value()))

evs.type_text(doc.query_selector("input"), "chat")    # keydown, beforeinput, input, keyup par caractère
evs.press_key(doc.query_selector("input"), "Enter")    # envoi implicite (validation required comprise)
print(doc.get_element_by_id("r").inner_html())
```

Observer les changements :

```al
use web.dom.mutation_observer as mo
obs := mo.MutationObserver((records, o) => print(len(records), "changement(s)"))
obs.observe(doc.body(), {"child_list": true, "subtree": true})
doc.body().append_child(doc.create_element("p"))
mo.flush(doc)          # les enregistrements sont livrés de façon asynchrone, comme dans un navigateur
```

## Points d'attention

- **Livraison asynchrone** : `MutationObserver`, `IntersectionObserver` et `ResizeObserver` livrent leurs
  entrées en micro-tâche quand `web.browser` fournit un ordonnanceur, sinon à `flush()` ; `take_records()`
  reste immédiat.
- **Pas de mise en page** : la géométrie est simulée (`element.set_layout(x, y, l, h)`), la fenêtre a une
  taille et un défilement ; les observateurs d'intersection et de taille s'en servent.
- **Styles** : `window.get_computed_style(el)` applique la cascade de `web.css` (feuille par défaut,
  éléments `<style>` selon leur attribut `media`, `document.style_sheets`) ; `display`, couleurs, tailles de
  police calculées… mais pas de dimensions issues d'une mise en page.
- **Formulaires** : `value()`, `checked()`, `selected()` gardent l'état « sale » distinct des attributs ;
  `click()` applique les comportements par défaut (cases, radios, envoi, réinitialisation, étiquettes,
  liens via `document.on_navigate`, `<summary>`). Un envoi accepté appelle `document.on_submit` ou est
  consigné dans `document.submissions`.
- **Exceptions** : les erreurs portent le nom standard (`HierarchyRequestError`, `NotFoundError`…) ; une
  exception levée par un écouteur n'interrompt pas la distribution (voir `event_target.reported_errors()`).

## Tests

```sh
make test-web        # comprend tests/web/test_web_dom.al
```
