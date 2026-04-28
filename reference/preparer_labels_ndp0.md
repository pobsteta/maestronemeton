# Telecharger et rasteriser la BD Foret V2 pour une AOI

Fonction combinee : telecharge les polygones via happign puis rasterise
a la resolution du raster de reference (0.2m).

## Usage

``` r
preparer_labels_ndp0(aoi, reference, output_dir = "outputs")
```

## Arguments

- aoi:

  sf object (AOI en Lambert-93)

- reference:

  SpatRaster de reference (ex: ortho RGBI a 0.2m)

- output_dir:

  Repertoire de sortie

## Value

SpatRaster mono-bande avec les codes NDP0
