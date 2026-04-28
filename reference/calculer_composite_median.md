# Calculer un composite median a partir de plusieurs rasters

Calcule la mediane pixel par pixel pour chaque bande a partir d'une
liste de rasters multi-bandes. La mediane est robuste aux valeurs
aberrantes (nuages residuels, secheresse ponctuelle).

## Usage

``` r
calculer_composite_median(rasters)
```

## Arguments

- rasters:

  Liste de SpatRaster (meme nombre de bandes et emprise)

## Value

SpatRaster composite median
