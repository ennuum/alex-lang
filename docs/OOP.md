# Orienté objet : `class`, `extends`, `super`, `interface`, `isinstance`

ALEX offre un modèle objet à **héritage simple** avec **interfaces**. `struct` reste disponible et inchangée
(type valeur-like sans héritage) ; `class` en est l'extension héritable.

```alex
interface Shape:
    func area()

class Polygon implements Shape:
    sides := 0                      # champ d'instance avec valeur par défaut
    func init(name):                # constructeur
        self.name = name
    func area():
        return 0

class Rect extends Polygon:         # héritage simple
    func init(name, w, h):
        super.init(name)            # appel à la classe de base
        self.w = w
        self.h = h
    func area():                    # redéfinition
        return self.w * self.h

r := Rect("r", 3, 4)
print(r.area())                     # 12
print(isinstance(r, Shape))         # true
```

Exemple complet : `examples/oop_demo.al`. Tests : `make test-oop`, `make test-vm-oop`.

## Syntaxe

| Forme | Sens |
|---|---|
| `class A:` | classe racine |
| `class B extends A:` | `B` hérite de `A` (une seule base) |
| `class B extends A implements I, J:` | …et s'engage à honorer les interfaces `I`, `J` |
| `nom := expr` (dans le corps) | champ d'instance avec valeur par défaut |
| `func m(...)` (dans le corps) | méthode ; `self` est implicite |
| `super.m(...)` | méthode `m` de la classe de base |
| `interface I:` + `func m(...)` sans corps | contrat |
| `isinstance(valeur, Type)` | test de type |

`implements` est un **mot contextuel** : il n'est pas réservé, `implements := 3` reste un programme valide.
La clause `extends` précède `implements`.

## Sémantique

**Construction.** `Classe(args)` crée l'instance, puis exécute dans cet ordre :
1. les champs par défaut de la **base** (récursivement), puis ceux de la classe ;
2. le constructeur `init` **effectif** : celui de la classe, sinon celui de l'ancêtre le plus proche.

Conséquence : `init` voit des champs déjà peuplés et peut les écraser. Une valeur par défaut est
**réévaluée à chaque instanciation** (une liste `items := []` n'est jamais partagée entre instances) et peut
lire `self`, y compris les champs hérités.

**Appel de méthode.** Résolue dynamiquement en partant du type **réel** de l'instance, puis en remontant
`extends`. Une méthode héritée qui appelle `self.f()` obtient donc la redéfinition de la sous-classe
(polymorphisme).

**`super`.** `super.m()` résout `m` en partant de la **base statique** de la classe qui contient l'appel, jamais
du type réel : sinon une redéfinition qui appelle `super.m()` se rappellerait elle-même pour une sous-sous-classe.
`super` n'existe que sous la forme `super.membre`, dans une méthode d'une classe qui a une base ; on ne peut
pas y affecter (`super.x = 1` est rejeté : les champs appartiennent à l'instance, écrire `self.x`).

**Interfaces.** `isinstance(x, I)` est vrai si la classe de `x`, ou un de ses ancêtres, déclare
`implements I`. Une interface n'a ni état ni corps et ne s'instancie pas.

**`isinstance(x, T)`.** Vrai pour le type exact, tout ancêtre, toute interface implémentée ; faux pour une
valeur qui n'est pas une instance (`isinstance(5, A)` vaut `false`). `T` doit être un **nom** de
struct/classe/interface, pas une expression : `Type`, ou `alias.Type` pour un type exporté par un module
importé (`use module as alias`). Dans la forme qualifiée, l'existence du membre est vérifiée à la compilation.

## Vérifications statiques (avant exécution)

| Erreur | Cas |
|---|---|
| `InheritanceError` | `extends` de soi-même, cycle, base qui est une `struct`/interface/fonction ; `super` hors méthode, sans base, nu (sans `.membre`), vers une méthode inexistante ; affectation via `super` |
| `InterfaceError` | méthode d'interface non implémentée (héritage compris) ou d'arité incompatible ; `implements` d'un non-interface ou doublon ; corps dans une interface ; interface instanciée |
| `NameError` | base ou interface inconnue |
| `ArgumentError` | arité de `Classe(...)` ou de `super.m(...)` incorrecte (constructeur hérité compris) ; `isinstance` mal formé |
| `DuplicateBindingError` | deux membres de même nom (champ/méthode) |
| `FeatureNotImplementedError` | `class`/`interface` déclarée ailleurs qu'au niveau supérieur ; instruction autre que `func`/`nom := …` dans un corps de classe |

Une base ou interface **importée** (`from m use Base`) est opaque à l'analyseur : ses vérifications
(méthodes manquantes, arité de `super`) se font à l'exécution, par la VM.

## Modules

Classes, interfaces et héritage s'exportent comme les `struct` : `from m use Animal, Speaker`, `use m as z`
puis `z.Cat(...)`. On peut **étendre une classe importée** (`class Lion extends Animal`) : constructeur,
champs par défaut et interfaces sont hérités du module. Les noms runtime sont qualifiés par module, deux
modules peuvent donc définir chacun une classe `Node` sans collision.

Le cache de signatures (`<fichier>.al.meta`) passe en **version 3** ; les caches v2 sont ignorés et régénérés.

## Architecture

- `include/alex/oop/TypeIndex.hpp`, `src/TypeIndex.cpp` : index statique des types d'un fichier
  (hiérarchie, méthodes, constructeur effectif). **Source unique** pour l'analyseur, le compilateur et
  `ModuleGraph`, qui s'accordent ainsi sur « le constructeur d'une classe ».
- Quatre opcodes, **ajoutés après `HALT`** (aucun opcode existant renuméroté : les `.albc` déjà compilés
  restent valides) : `DEF_CLASS`, `ADD_INTERFACE`, `GET_SUPER`, `INSTANCE_OF` (contrat dans `bc/Opcode.hpp`).
- La VM tient un registre de classes (`classes_`) rempli par le prologue du module, **avant** toute instruction :
  une classe est donc utilisable avant sa déclaration dans le fichier. Résolution et sous-typage sont bornés
  en profondeur (un registre corrompu ne peut pas boucler).
- Méthodes compilées sous le nom `Classe#méthode`, comme pour `struct` ; champs par défaut dans une méthode
  synthétique `Classe#__fields`.

## Limites actuelles

- Héritage **simple** uniquement ; pas d'héritage entre interfaces.
- `class`/`interface` au niveau supérieur d'un fichier seulement (pas imbriquées dans une fonction).
- Pas de visibilité (`private`/`protected`), de méthodes statiques ni de classes abstraites : une interface
  tient lieu de contrat abstrait.
- Dans une classe, les champs sont uniquement `nom := valeur` ; les champs sans valeur par défaut se créent
  par `self.x = …` dans `init`.
