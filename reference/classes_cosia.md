# Classes d'occupation du sol CoSIA (15 classes actives + non classifie)

Table des classes d'occupation du sol CoSIA apres remapping depuis les
codes FLAIR-1. Les classes desactivees (coupe, mixte, ligneux, autre)
sont remappees a 0 (non classifie).

## Usage

``` r
classes_cosia()
```

## Value

Un data.frame avec les colonnes code, classe, couleur

## Details

Compatible avec la sortie des modeles 19 classes apres remapping.

## Examples

``` r
cls <- classes_cosia()
cls[cls$code <= 5, ]
#>   code                  classe couleur
#> 1    0           Non classifie #808080
#> 2    1                Batiment #db0e9a
#> 3    2 Serre / bache plastique #3de6eb
#> 4    3                 Piscine #ffffff
#> 5    4        Zone impermeable #f80c00
#> 6    5          Zone permeable #938e7b
```
