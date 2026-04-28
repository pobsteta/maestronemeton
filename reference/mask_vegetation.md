# Creer un masque de vegetation par seuillage NDVI

Creer un masque de vegetation par seuillage NDVI

## Usage

``` r
mask_vegetation(rgbi, seuil = 0.3, nir_band = 4L, red_band = 1L)
```

## Arguments

- rgbi:

  SpatRaster avec bandes R, G, B, NIR

- seuil:

  Seuil NDVI pour la vegetation (defaut: 0.3)

- nir_band:

  Indice de la bande PIR (defaut: 4)

- red_band:

  Indice de la bande Rouge (defaut: 1)

## Value

SpatRaster binaire (1 = vegetation, 0 = non-vegetation)
