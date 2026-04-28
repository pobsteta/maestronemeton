# Rasteriser la BD Foret V2 en masque de classes NDP0

Convertit les polygones BD Foret V2 en raster a 0.2m de resolution avec
les codes de classes NDP0. Les pixels hors polygones recoivent la classe
9 (Non-foret).

## Usage

``` r
rasteriser_bdforet(bdforet, reference, output_dir = "outputs")
```

## Arguments

- bdforet:

  sf data.frame avec colonne `code_ndp0` (issue de
  [`download_bdforet_for_aoi()`](https://pobsteta.github.io/maestronemeton/reference/download_bdforet_for_aoi.md))

- reference:

  SpatRaster de reference pour l'emprise et la resolution (ex: ortho
  RGBI a 0.2m)

- output_dir:

  Repertoire de sortie

## Value

SpatRaster mono-bande (uint8) avec les codes NDP0
