# Telecharger une couche WMS IGN avec tuilage automatique

Subdivise les grandes emprises en tuiles respectant la limite WMS de
4096 px, les telecharge, puis les mosaique en un seul raster.

## Usage

``` r
download_ign_tiled(
  bbox,
  layer,
  res_m = .ign_config$RES_IGN,
  output_dir,
  prefix = "ortho",
  styles = ""
)
```

## Arguments

- bbox:

  Vecteur numerique `c(xmin, ymin, xmax, ymax)` en Lambert-93

- layer:

  Nom de couche WMS

- res_m:

  Resolution en metres

- output_dir:

  Repertoire de sortie pour les tuiles temporaires

- prefix:

  Prefixe des fichiers temporaires

- styles:

  Style WMS

## Value

SpatRaster mosaique
