# Assembler un DEM multi-bandes a partir des canaux choisis

Selectionne 1 a 6 canaux parmi les sources disponibles (DSM, DTM, SLOPE,
ASPECT, TPI, TWI) et les empile en un SpatRaster. MAESTRO attend 2
bandes, FLAIR peut utiliser 1 a 2 bandes supplementaires.

## Usage

``` r
assembler_dem_channels(dsm, dtm, derives, dem_channels)
```

## Arguments

- dsm:

  SpatRaster mono-bande (DSM)

- dtm:

  SpatRaster mono-bande (DTM)

- derives:

  Liste de derives terrain (issue de
  [`calculer_derives_terrain()`](https://pobsteta.github.io/maestronemeton/reference/calculer_derives_terrain.md))

- dem_channels:

  Vecteur de 1 a 6 noms de canaux parmi
  `c("DSM", "DTM", "SLOPE", "ASPECT", "TPI", "TWI")`

## Value

SpatRaster avec les canaux selectionnes
