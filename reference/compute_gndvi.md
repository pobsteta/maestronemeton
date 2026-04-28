# Calculer le GNDVI (Green Normalized Difference Vegetation Index)

GNDVI = (PIR - Vert) / (PIR + Vert)

## Usage

``` r
compute_gndvi(rgbi, nir_band = 4L, green_band = 2L)
```

## Arguments

- rgbi:

  SpatRaster avec bandes R, G, B, NIR

- nir_band:

  Indice de la bande PIR (defaut: 4)

- green_band:

  Indice de la bande Verte (defaut: 2)

## Value

SpatRaster mono-bande avec valeurs GNDVI entre -1 et 1
