# Calculer les derives morphologiques du MNT

A partir d'un DTM (Modele Numerique de Terrain) a 1m de resolution,
calcule les derives topographiques utiles pour la segmentation
forestiere : pente, orientation (aspect), TPI (Topographic Position
Index) et TWI (Topographic Wetness Index).

## Usage

``` r
calculer_derives_terrain(dtm)
```

## Arguments

- dtm:

  SpatRaster mono-bande (DTM/MNT a 1m)

## Value

Liste nommee de SpatRasters mono-bande : `SLOPE`, `ASPECT`, `TPI`, `TWI`
