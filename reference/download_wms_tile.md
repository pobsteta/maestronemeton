# Telecharger une tuile WMS IGN

Envoie une requete WMS 1.3.0 a la Geoplateforme IGN et retourne un
SpatRaster. Gere le retry avec backoff exponentiel.

## Usage

``` r
download_wms_tile(
  bbox,
  layer,
  res_m = .ign_config$RES_IGN,
  dest_file,
  styles = "",
  max_retries = 3
)
```

## Arguments

- bbox:

  Vecteur numerique `c(xmin, ymin, xmax, ymax)` en Lambert-93

- layer:

  Nom de couche WMS

- res_m:

  Resolution en metres (defaut: 0.2)

- dest_file:

  Chemin du fichier GeoTIFF de sortie

- styles:

  Style WMS (`""` pour ortho, `"normal"` pour elevation)

- max_retries:

  Nombre maximal de tentatives (defaut: 3)

## Value

SpatRaster ou NULL si echec
