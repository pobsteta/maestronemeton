# Correler l'occupation du sol avec le DEM

Calcule les statistiques d'altitude par classe d'occupation du sol.

## Usage

``` r
cross_landcover_dem(raster_classe, dem, classes = NULL)
```

## Arguments

- raster_classe:

  SpatRaster de classification

- dem:

  SpatRaster du Modele Numerique de Terrain

- classes:

  Table des classes

## Value

data.frame avec altitude moyenne, min, max par classe
