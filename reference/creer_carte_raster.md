# Creer le raster de classification des essences

Rasterise les predictions vectorielles en un GeoTIFF avec les codes
d'essences (0 a 12).

## Usage

``` r
creer_carte_raster(grille, resolution = 0.2, dossier_sortie = "resultats")
```

## Arguments

- grille:

  sf data.frame avec colonne `code_essence`

- resolution:

  Resolution en metres (defaut: 0.2)

- dossier_sortie:

  Repertoire de sortie

## Value

SpatRaster de classification
