# Assembler les resultats FLAIR en GeoPackage et statistiques

Assembler les resultats FLAIR en GeoPackage et statistiques

## Usage

``` r
assembler_resultats_flair(
  raster_classe,
  classes = NULL,
  dossier_sortie = "outputs"
)
```

## Arguments

- raster_classe:

  SpatRaster mono-bande de classification

- classes:

  Table des classes (issue de
  [`classes_cosia()`](https://pobsteta.github.io/maestronemeton/reference/classes_cosia.md)
  ou
  [`classes_lpis()`](https://pobsteta.github.io/maestronemeton/reference/classes_lpis.md))

- dossier_sortie:

  Repertoire de sortie

## Value

Liste avec `raster` et `stats`
