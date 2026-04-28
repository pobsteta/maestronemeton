# Charger une zone d'interet depuis un GeoPackage

Lit le fichier GeoPackage et reprojette en Lambert-93 (EPSG:2154) si
necessaire. Affiche un resume de l'emprise et de la surface.

## Usage

``` r
load_aoi(gpkg_path, layer = NULL)
```

## Arguments

- gpkg_path:

  Chemin vers le fichier .gpkg

- layer:

  Nom de la couche (NULL = premiere couche)

## Value

sf object en Lambert-93 (EPSG:2154)

## Examples

``` r
if (FALSE) { # \dontrun{
aoi <- load_aoi("ma_zone.gpkg")
} # }
```
