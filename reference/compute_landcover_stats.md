# Calculer les statistiques d'occupation du sol

Produit un tableau de statistiques par classe a partir d'un raster de
classification.

## Usage

``` r
compute_landcover_stats(raster_classe, classes = NULL)
```

## Arguments

- raster_classe:

  SpatRaster mono-bande de classification

- classes:

  Table des classes (issue de
  [`classes_cosia()`](https://pobsteta.github.io/maestronemeton/reference/classes_cosia.md)
  ou
  [`classes_lpis()`](https://pobsteta.github.io/maestronemeton/reference/classes_lpis.md))

## Value

data.frame avec colonnes code, classe, n_pixels, proportion, surface_ha
