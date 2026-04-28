# Aligner le DEM 2 bandes (DSM+DTM) sur la grille RGBI

Reechantillonne le DEM (2 bandes : DSM, DTM) sur la grille de l'image
RGBI aerienne. Utilisee pour preparer les entrees multi-modales MAESTRO.

## Usage

``` r
aligner_dem_sur_rgbi(dem, rgbi)
```

## Arguments

- dem:

  SpatRaster 2 bandes (DSM, DTM)

- rgbi:

  SpatRaster de reference (meme emprise/resolution)

## Value

SpatRaster 2 bandes (DSM, DTM) alignees sur la grille RGBI
