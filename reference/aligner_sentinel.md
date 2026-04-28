# Aligner un raster Sentinel sur la grille de l'AOI

Reechantillonne un raster Sentinel (10m) pour qu'il couvre exactement la
meme emprise que le raster de reference, tout en gardant sa resolution
native (10m).

## Usage

``` r
aligner_sentinel(sentinel, reference, target_res = 10)
```

## Arguments

- sentinel:

  SpatRaster Sentinel (S1 ou S2)

- reference:

  SpatRaster de reference (ex: RGBI a 0.2m)

- target_res:

  Resolution cible en metres (defaut: 10)

## Value

SpatRaster aligne sur l'emprise de reference
