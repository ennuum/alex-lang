# OFFICE — `stdlib/office/`

Bibliothèque bureautique d'ALEX : lecture, création, modification et conversion des documents **Word (.docx)**,
**Excel (.xlsx)**, **PowerPoint (.pptx)**, **PDF**, **OpenDocument (.odt, .ods, .odp)**, **CSV / TSV / JSON /
HTML / Markdown / texte**, plus un moteur de **gabarits** (publipostage). Tout est écrit en ALEX ; seules les
primitives coûteuses (DEFLATE, CRC, analyse XML, jetons PDF, chiffrement RC4/AES/MD5/SHA-2, décodage PNG/LZW)
sont natives (`_native_office`, `runtime/native/office/`). Aucune dépendance externe.

```
use office.word as word
use office.excel as excel
use office.conversion as conv
use office.templates as tpl

doc := word.new()
doc.add_heading("Rapport annuel", 1)
doc.add_paragraph("Introduction en ").add_run("gras", {"bold": true})
doc.add_table([["Produit", "Qté"], ["Pommes", 3]])
doc.save("rapport.docx")

wb := excel.new("Ventes")
ws := wb.active_sheet()
ws.append(["Produit", "Qté", "Prix", "Total"], {"bold": true, "fill": "D9E2F3"})
ws.append(["Pommes", 3, 1.5, "=B2*C2"])
wb.save("ventes.xlsx")                     # formules calculées, valeurs en cache

conv.convert("rapport.docx", "rapport.pdf")
conv.convert("ventes.xlsx", "ventes.ods")
tpl.fill("modele-facture.docx", {"client": "ACME", "lignes": lignes}, "facture.docx")
```

Chaque module documente son API complète dans son en-tête (`alexc doc --html docs/api` produit la référence).

## Carte des modules

| Domaine | Modules | Rôle |
|---|---|---|
| Socle | `errors` `utils` `compression` `archive` `xml` `core` `metadata` | erreurs typées, octets / textes / unités / dates / couleurs, DEFLATE-zlib-gzip, décompression Zstandard (native), ZIP (ZIP64 en lecture), XML rapide (ordre des attributs conservé), paquets OPC, images, métadonnées de tous les formats |
| Texte et données | `csv` `tsv` `json` `html` | séparateur et encodage détectés, décimale française, tables JSON (records / rows / columns / split), HTML tolérant (texte, tableaux, liens) |
| Word | `word` (façade), `docx_reader` `docx_writer` `docx_paragraphs` `docx_tables` `docx_styles` `docx_images` | titres, paragraphes riches, listes, tableaux fusionnés, images, sommaire, en-têtes / pieds avec numéros de page, styles |
| Excel | `excel` (façade), `xlsx_reader` `xlsx_writer` `xlsx_sheets` `xlsx_cells` `xlsx_styles` `xlsx_formulas` `xlsx_charts` `xlsx_images` | cellules typées, styles, formats numériques, fusions, volets, filtres, liens, commentaires, images, graphiques, **moteur de formules** (≈ 150 fonctions, noms français acceptés) |
| PowerPoint | `powerpoint` (façade), `pptx_reader` `pptx_writer` `pptx_slides` `pptx_shapes` `pptx_text` `pptx_images` `pptx_tables` `pptx_charts` | dispositions, titres, puces à niveaux, formes, images, tableaux, graphiques (classeur incorporé), notes |
| PDF | `pdf` (façade), `pdf_reader` `pdf_writer` `pdf_extract` `pdf_tables` `pdf_pages` `pdf_merge` `pdf_split` | lecture (xref classiques / flux / réparation, chiffrement RC4 / AES-128 / AES-256), création mise en page, polices TrueType incorporées (sous-ensembles), extraction de texte / mots / images / liens / tableaux, opérations de pages, fusion, découpage |
| OpenDocument | `odf` (socle), `odt` `ods` `odp` | paquet ODF, styles automatiques, textes ↔ `document`, classeurs ↔ `excel.Workbook` (formules OpenFormula ↔ Excel, styles de données ↔ formats Excel), présentations ↔ `powerpoint.Presentation` (graphiques ODF incorporés) |
| Modèles neutres | `document` `spreadsheet` `presentation` | document (Markdown / HTML / texte / DOCX / PDF), tableur tous formats, présentation tous formats (rendu PDF et SVG des diapositives) |
| Transversal | `conversion` `templates` | conversions entre toutes les familles, gabarits Mustache/Handlebars dans tous les formats |

## Modèles et conversions

Trois modèles servent de pivot :

- **document** — `office.document.Document` : blocs `heading`, `paragraph` (segments mis en forme), `list_item`
  (niveaux, numérotées ou non), `table`, `image`, `code`, `quote`, `hr`, `page_break`. Lit et écrit Markdown, HTML,
  texte ; `to_docx()`, `to_pdf()`, `document.from_docx()` ; `odt.read` / `odt.write`.
- **classeur** — `office.excel.Workbook` : utilisé tel quel par `ods`, `spreadsheet` (CSV, TSV, JSON, HTML,
  Markdown, texte aligné, PDF).
- **présentation** — `office.powerpoint.Presentation` : utilisé par `odp` et `presentation` (PDF vectoriel, HTML avec
  un SVG par diapositive, Markdown façon Marp, texte ; `from_markdown`, `from_document`, `to_document`).

`conversion.convert(src, dst)` choisit le chemin d'après les extensions :

| Depuis | Vers |
|---|---|
| docx, odt, html, md, txt, pdf | docx, odt, html, md, txt, pdf, pptx, odp (un titre = une diapositive), xlsx, ods, csv (tableaux) |
| xlsx, ods, csv, tsv, json | xlsx, ods, csv, tsv, json, html, md, txt, pdf, docx, odt, pptx, odp |
| pptx, odp | pptx, odp, pdf, html, md, txt, docx, odt, xlsx, ods, csv |

Le PDF en entrée est restructuré (`conversion.pdf_to_document`) : titres d'après la taille des caractères, listes,
paragraphes, tableaux à filets, en-têtes / pieds répétés et numéros de page retirés ; vers un tableur
(`pdf_to_workbook`), chaque tableau détecté devient une feuille.

## Gabarits

```
tpl.render("Bonjour {{client.nom | upper}} — {{total | money}} au {{date | date('d mmmm yyyy')}}", data)
tpl.render("{{#each lignes}}{{@index1}}. {{produit}}{{#unless @last}}, {{/unless}}{{/each}}", data)
```

Syntaxe : `{{chemin}}`, filtres (`upper lower title trim default date number money percent round join length
replace truncate pad yesno sum sort json…`, extensibles avec `register_filter`), `{{#if}}`/`{{else}}`,
`{{#unless}}`, `{{#each}}` (`@index @index1 @first @last @key`), `{{#with}}`, `{{! commentaire }}`, `{{{brut}}}`
(mode HTML). Nombres et dates à la française par défaut (`{"locale": "en"}` sinon).

`tpl.fill(modèle, données, sortie)` remplit un DOCX, XLSX, PPTX, ODT, ODS, ODP, HTML, Markdown ou texte en gardant
la mise en forme : une balise répartie sur plusieurs segments de texte est recollée ; un paragraphe ne contenant que
`{{#each x}}` … `{{/each}}` répète les paragraphes entre les deux ; une ligne de tableau commençant par
`{{#each x}}` et finissant par `{{/each}}` est répétée ; dans un classeur, la ligne modèle est répétée vers le bas
(formules recopiées, plages `SUM(B2:B2)` étendues) et une cellule `{{valeur}}` seule garde son type (nombre, date).
`fill_many` produit un fichier par enregistrement.

## Erreurs

Familles (`e.type`) : `OfficeError`, `FormatError`, `ArchiveError`, `CompressionError`, `XMLError`, `PDFError`,
`DOCXError`, `XLSXError`, `PPTXError`, `ODFError`, `FormulaError`, `TemplateError`, `ConversionError`,
`UnsupportedError` ; les erreurs de programmation gardent `TypeError`, `ValueError`, `IndexError`, `IoError`.
Les erreurs de calcul des formules sont des valeurs (`#DIV/0!`, `#N/A`…), pas des exceptions.

## Performances

Analyse XML, parcours (`children`, `first`, `find_all`, `attr`, `text`) et texte ODF sont natifs ; les chaînes
mettent en cache leur index de points de code (indexation O(1)). Ordre de grandeur : classeur 10 000 lignes × 5
colonnes ≈ 4 s en lecture comme en écriture (XLSX ou ODS), document de quelques pages en quelques dizaines de ms.

## Limites connues

- Pas de rendu fidèle de toutes les fonctionnalités : mises en forme conditionnelles, validations, tableaux
  croisés, macros (jamais exécutées), SmartArt, animations et transitions sont ignorés (conservés quand un fichier
  est seulement modifié via le paquet bas niveau).
- Les graphiques d'un classeur ne sont pas exportés en ODS (ils le sont en XLSX) ; ceux des présentations le sont
  en ODP (objets graphiques ODF).
- Rendu PDF / SVG des diapositives : formes tournées dessinées sans rotation ; polices remplacées par Helvetica /
  Times / Courier pour les métriques (police TrueType du système pour les caractères hors Windows-1252).
- PDF : pas de signature numérique, de formulaire interactif ni d'OCR.

Tests : `make test-office` (5 suites : socle, OOXML, PDF, OpenDocument, conversions et gabarits).
