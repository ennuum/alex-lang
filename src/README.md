# Sources du compilateur ALEX

Chaîne de compilation d'ALEX, écrite en ALEX (anciennement `stdlib/compiler/bc_*`, `nt_*`, `cmd_*`).
Point d'entrée : `alexc.al` (toutes les commandes `alexc` / `alex`). Les modules s'importent par leur chemin
depuis `src/` : `use lexer`, `use parser`, `use native.ir`, `use commands.pkg`...

| Dossier | Module(s) | Rôle | Ancien nom |
|---|---|---|---|
| `alexc.al` | — | point d'entrée, répartition des commandes | `tools/selfhost/alexc.al` |
| `token/` | `token` | classe `Token` et table des mots-clés | (extrait de `bc_lexer`) |
| `lexer/` | `lexer` | analyse lexicale sur octets (INDENT / DEDENT, f-strings, littéraux) | `bc_lexer` |
| `ast/` | `ast` | nœuds de l'arbre syntaxique | `bc_ast` |
| `parser/` | `parser` | analyse syntaxique et désucrages | `bc_parser` |
| `semantic/` | `semantic.analyzer`, `semantic.types` | analyse sémantique, vérification graduelle des types | `bc_analyzer`, `bc_types` |
| `bytecode/` | `bytecode.compiler`, `bytecode.format` | AST → bytecode, format `.albc` | `bc_compiler`, `bc_format` |
| `resolver/` | `resolver` | graphe de modules, résolution des `use`, préludes, liaison | `bc_modules` |
| `native/` | `native.ir`, `native.lower`, `native.inline`, `native.codegen_x64`, `native.codegen_a64`, `native.x64`, `native.a64`, `native.dyn`, `native.dyn_registry`, `native.vm`, `native.build` | compilation native x86-64 / ARM64, mode dynamique, construction de la VM | `nt_*` |
| `commands/` | `commands.common`, `commands.test`, `commands.fmt`, `commands.doc`, `commands.new`, `commands.pkg`, `commands.repl`, `commands.debug`, `commands.lsp`, `commands.lang_service`, `commands.bundle` | outils de `alexc` | `cli_common`, `cmd_*`, `lang_service`, `sdk_bundle` |

Construction : `make pure` (ou `tools/selfhost/bootstrap.sh`), puis `make alex`. Détails : `docs/SELFHOST.md`.

Les noms de dossiers évitent ceux de `stdlib/` (cherchée en premier) et ceux de la racine du dépôt.
`stdlib/compiler/` garde la bibliothèque `compiler.*` (lexer, parser, ir, codegen...) utilisée par les programmes
et par `security.sandbox` : elle fait partie de la bibliothèque standard, pas de la chaîne d'outils.
