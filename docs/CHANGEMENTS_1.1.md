# ALEX 1.1.0 — corrections et ajouts (travaux d'Alex OS)

Version issue de l'audit et du développement d'Alex OS (0.2.2 à 0.4.5), qui compile son noyau et ses programmes
avec ce compilateur. Toutes les modifications sont rétrocompatibles : aucun programme existant ne change de
comportement.

## Corrections

* **Compilateur bytecode** (`src/Compiler.cpp`) : l'opérateur de décomposition (`...e`, `**e`) rencontré hors d'un
  contexte autorisé tombait hors du `switch` des opérateurs unaires sans diagnostic (avertissement du compilateur
  C++ et chemin non défini) ; il lève désormais une erreur de compilation explicite.
* **Test de la VM périmé** (`tests/test_vm_coll.cpp`) : `liste_index_negatif` exigeait une `IndexError` pour
  `xs[-1]`, alors que les indices négatifs comptés depuis la fin font partie du langage (docs/PYTHONIC.md) et
  sont implémentés. Ce test échouait et, la cible `make test` s'arrêtant au premier échec, empêchait l'exécution
  de toutes les suites suivantes. Il vérifie maintenant `xs[-1]` (dernier élément) et l'`IndexError` d'un indice
  négatif au-delà du début.

* **Test des pilotes du noyau** (`tests/drivers/run_kernel_drivers.sh`) : la sortie attendue contenait la
  révision du micrologiciel NVMe rapportée par QEMU (« 8.2.2 », « 9.2.0 »...), qui dépend de la version de QEMU ;
  le test échouait sur toute autre version. La révision est neutralisée des deux côtés avant comparaison.
* **Commentaire** de `posix.chmod` précisé (mode octal).

## Vérification

`make test` complet au vert (y compris `tests/native/ok_bytes.al`, en mode hébergé et sans OS). Une exécution
de `test-ui-portable` a une fois été interrompue par SIGPIPE (code 141) dans `tests/ui/test_interact.al`, puis
3 exécutions sur 3 ont réussi : défaut intermittent du test, préexistant (non lié à ces changements), à suivre.
Alex OS 0.4.5 reconstruit avec ce compilateur : scénarios et tests réseau, dont TLS, au vert.

## Ajouts — module `string` (VM et natif)

Fonctions d'octets pour les données binaires (réseau, fichiers, cryptographie) ; les autres fonctions du module
comptent en points de code UTF-8, ce qui ne convient pas à des octets quelconques :
`byte_len`, `byte_at`, `byte_slice`, `byte_find`, `byte_char`, `byte_pack`, `byte_unpack`, `byte_join`
(docs/STRING.md). Implémentées dans la VM (`runtime/native/string/string_native.cpp`, `stdlib/string/string.al`)
et dans la bibliothèque native (`src/NativeStdlib.cpp`), avec les mêmes résultats et messages d'erreur
(`tests/native/ok_bytes.al` compare les deux).

## Ajouts — module `posix` (natif)

Fonctions utilisées par les programmes d'Alex OS, portables (appels système x86-64 standard) :

* fichiers et utilisateurs : `lseek`, `chmod`, `getuid`, `setpgid`, `getpgid`, `getpgrp`, `sync`, `link`,
  `symlink`, `readlink` ;
* réseau IPv4 : `socket`, `connect`, `bind`, `listen`, `accept`, `peer`, `send`, `sendto`, `recv`, `recvfrom`
  (adresses en texte, erreurs `OSError` avec messages en français : connexion refusée, délai dépassé...) ;
* aléa : `random_bytes(n)` (appel `getrandom`).

Documentation : docs/NATIVE.md (« Processus : module posix »).
