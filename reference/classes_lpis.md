# Classes de cultures LPIS/RPG (23 classes)

Table des 23 classes de cultures du jeu de donnees FLAIR-HUB, issues du
Registre Parcellaire Graphique (RPG / LPIS).

## Usage

``` r
classes_lpis()
```

## Value

Un data.frame avec les colonnes code, classe, couleur

## Examples

``` r
cls <- classes_lpis()
head(cls)
#>   code                classe couleur
#> 1    1            Ble tendre #ffff00
#> 2    2 Mais grain / ensilage #ff6600
#> 3    3                  Orge #d8b56b
#> 4    4       Autres cereales #aa7841
#> 5    5                 Colza #00ff00
#> 6    6             Tournesol #ffaa00
```
