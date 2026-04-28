# Assembler les predictions dans un GeoPackage

Joint les predictions de classes aux patches de la grille, produit un
fichier GeoPackage et un CSV de statistiques.

## Usage

``` r
assembler_resultats(
  grille,
  predictions,
  essences = NULL,
  dossier_sortie = "resultats"
)
```

## Arguments

- grille:

  sf grille de patches

- predictions:

  Liste de predictions (codes de classes)

- essences:

  Table des essences (issue de
  [`essences_pureforest()`](https://pobsteta.github.io/maestronemeton/reference/essences_pureforest.md))

- dossier_sortie:

  Repertoire de sortie

## Value

sf data.frame enrichi des colonnes `code_essence`, `classe`, etc.
