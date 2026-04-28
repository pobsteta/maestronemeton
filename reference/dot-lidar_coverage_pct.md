# Mesurer la couverture LiDAR HD (DSM) d'un raster WMS

Le WMS LiDAR HD renvoie un raster valide y compris hors couverture
(pixels NA ou nuls). Cette fonction quantifie le % de pixels effectifs.

## Usage

``` r
.lidar_coverage_pct(r)
```

## Arguments

- r:

  SpatRaster a evaluer (1 bande)

## Value

Pourcentage `[0, 100]` de pixels finis et non nuls
