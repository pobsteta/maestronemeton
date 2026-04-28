# Calculer le SAVI (Soil Adjusted Vegetation Index)

SAVI = ((PIR - Rouge) / (PIR + Rouge + L)) \* (1 + L)

## Usage

``` r
compute_savi(rgbi, nir_band = 4L, red_band = 1L, L = 0.5)
```

## Arguments

- rgbi:

  SpatRaster avec bandes R, G, B, NIR

- nir_band:

  Indice de la bande PIR (defaut: 4)

- red_band:

  Indice de la bande Rouge (defaut: 1)

- L:

  Facteur d'ajustement du sol (defaut: 0.5)

## Value

SpatRaster mono-bande avec valeurs SAVI
