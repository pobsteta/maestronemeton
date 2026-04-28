# Calculer le NDVI (Normalized Difference Vegetation Index)

Calcule le NDVI a partir d'un raster RGBI ou de bandes PIR et Rouge
separees. NDVI = (PIR - Rouge) / (PIR + Rouge)

## Usage

``` r
compute_ndvi(rgbi, nir_band = 4L, red_band = 1L)
```

## Arguments

- rgbi:

  SpatRaster avec bandes R, G, B, NIR (ou 2 bandes PIR, Rouge)

- nir_band:

  Indice de la bande PIR (defaut: 4 pour RGBI)

- red_band:

  Indice de la bande Rouge (defaut: 1 pour RGBI)

## Value

SpatRaster mono-bande avec valeurs NDVI entre -1 et 1

## Examples

``` r
if (FALSE) { # \dontrun{
rgbi <- terra::rast("ortho_rgbi.tif")
ndvi <- compute_ndvi(rgbi)
terra::plot(ndvi)
} # }
```
