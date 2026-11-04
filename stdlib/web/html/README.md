# web.html — HTML5 en ALEX pur

`web.html` construit, analyse, transforme, valide et produit du HTML5. Tout est écrit en ALEX, sans
dépendance native. Principe de sécurité : **le texte est toujours échappé** ; seul `RawHtml` insère du balisage
tel quel, et il ne doit jamais recevoir une donnée d'utilisateur.

## Architecture

```text
stdlib/web/html/
├── html.al               point d'entrée : h, document, parse, render, sanitize, validate
├── document.al           Document : <!DOCTYPE html>, <html>, <head>, <body>, titre, langue, encodage
├── document_type.al      DocumentType, modes standards / quirks
├── element.al            Element : arbre, édition, navigation, sélecteurs CSS
├── element_factory.al    h(), make(), from_spec(), tag_builder(), éléments connus / obsolètes
├── attributes.al         Attributes : ordre, class, style, data-*, aria-*
├── attribute_value.al    conversion des valeurs, attributs booléens, noms valides, URL sûres
├── text_node.al          TextNode (texte échappé au rendu)
├── comment_node.al       CommentNode (contenu neutralisé)
├── raw_html.al           RawHtml (balisage de confiance)
├── html_writer.al        HtmlWriter : écriture en flux, sans arbre
├── html_parser.al        analyse tolérante façon navigateur, fragments, sanitize, to_text
├── html_serializer.al    sérialisation compacte ou indentée (algorithme WHATWG)
├── html_escape.al        échappement, 2 231 références nommées, script / style / commentaire
├── html_validate.al      conformité, accessibilité, sécurité (Issue)
├── semantic_elements.al  sections, titres, texte, figures, détails, fil d'Ariane…
├── metadata.al           meta, Open Graph, Twitter / X, JSON-LD, CSP, canonique, icônes
├── head.al               construire et modifier <head> sans doublons
├── body.al               <body>, région principale, page complète accessible
├── links.al              <a> (externe, mailto, tel…), navigation, pagination, réécriture d'URL
├── images.al             <img>, srcset, <picture>, figures, data:, cartes d'images
├── tables.al             tableaux depuis lignes / enregistrements, et lecture inverse
├── lists.al              ul, ol, dl, listes imbriquées, et lecture inverse
├── forms.al              champs accessibles, CSRF, form_data / fill / set_error
├── scripts.al            <script> (defer, module, SRI, nonce), JSON embarqué sûr, importmap
├── stylesheets.al        <link rel=stylesheet>, <style>, générateur de CSS
├── iframe.al             iframe (sandbox strict par défaut), srcdoc, vidéos, cartes, embed / object
├── html_errors.al        erreurs, Issue
└── README.md
```

## Construire une page

```al
use web.html.body as bd
use web.html.semantic_elements as se
use web.html.tables as tb

menu := [("Accueil", "/"), ("Rapports", "/rapports")]
contenu := [se.h1("Ventes"), tb.from_rows([["Mois", "Total"], ["Janvier", 1200]], "Ventes 2026")]
doc := bd.page("Rapports", contenu, "fr", ["/static/site.css"], null, "Tableau de bord", menu, "/rapports")
print(doc.pretty())
```

La page produite contient `<!DOCTYPE html>`, `lang`, `<meta charset="utf-8">`, la fenêtre d'affichage, un lien
d'évitement, `<header>` / `<nav aria-current>` / `<main id="contenu">`, et passe `html_validate` sans erreur.

## Analyser et extraire

```al
use web.html as html
doc := html.parse(texte_telecharge)
for a in doc.find_all("article h2 > a[href^=\"https\"]"):
    print(a.text_content(), a.get("href"))
for i in doc.issues:
    print(str(i))                 # écarts relevés par l'analyseur, avec la ligne
```

Sélecteurs : type, `*`, `#id`, `.classe`, `[attr]`, `[attr=v]`, `~=`, `^=`, `$=`, `*=`, `|=`, `i`,
`:first-child`, `:last-child`, `:only-child`, `:nth-child()`, `:nth-last-child()`, `:nth-of-type()`,
`:first-of-type`, `:last-of-type`, `:not()`, `:empty`, `:checked`, `:disabled`, `:enabled`, `:required`,
`:optional`, `:root`, combinateurs `␠`, `>`, `+`, `~`, listes `a, b`.

## Contenu non fiable

```al
html.sanitize(commentaire)        # balises et attributs sûrs seulement, URL javascript: retirées
html.escape(nom)                  # pour l'insérer dans du HTML écrit à la main
```

## Valider

```al
use web.html.html_validate as hv
print(hv.report(hv.validate(doc)))
```

Codes stables (`img-alt`, `duplicate-id`, `control-label`, `heading-order`, `unsafe-url`…) : voir
`html_validate.al`.

## Erreurs

`HtmlError`, `HtmlParseError`, `HtmlAttributeError`, `HtmlTagError`, `HtmlValidationError` — voir
`html_errors.al`.
