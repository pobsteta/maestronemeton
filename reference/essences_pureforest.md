# Classes d'essences forestieres PureForest

Table des 13 classes d'essences forestieres du jeu de donnees PureForest
(IGN), utilise pour l'entrainement du modele MAESTRO. Source officielle
: fiche dataset Hugging Face `IGNF/PureForest`.

## Usage

``` r
essences_pureforest()
```

## Value

Un data.frame avec les colonnes code, classe, nom_latin et type

## Examples

``` r
ess <- essences_pureforest()
ess[ess$type == "feuillu", ]
#>   code       classe                               nom_latin    type
#> 1    0 Chene decidu Quercus robur, Q. petraea, Q. pubescens feuillu
#> 2    1   Chene vert                            Quercus ilex feuillu
#> 3    2        Hetre                         Fagus sylvatica feuillu
#> 4    3  Chataignier                         Castanea sativa feuillu
#> 5    4     Robinier                    Robinia pseudoacacia feuillu
```
