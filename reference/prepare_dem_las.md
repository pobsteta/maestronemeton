# Pipeline LiDAR `lasR` pour deriver DSM + DTM d'une AOI

Execute un pipeline `lasR` sur les nuages LAZ fournis : triangulation
TIN sur les points classes sol (ASPRS 2) pour le DTM, sur les premiers
retours (return_number == 1) pour le DSM, rasterisation a 1 m avec un
buffer de 20 m sur le `LAScatalog` pour gerer les effets de bord. Les
rasters par tuile sont ensuite mosaiques, croppes sur l'AOI puis
ree-chantillonnes sur la grille de la modalite `aerial` (resolution 0,2
m typiquement).

## Usage

``` r
prepare_dem_las(
  aoi,
  las_files,
  output_dir,
  rgbi = NULL,
  buffer_m = 20,
  ncores = 2L,
  keep_tiles = FALSE
)
```

## Arguments

- aoi:

  sf object en Lambert-93.

- las_files:

  Vecteur character de chemins vers des fichiers LAZ/LAS.

- output_dir:

  Repertoire de sortie (ecrit `dem_2bands.tif` et les tuiles
  intermediaires `lasr_dtm_*.tif`, `lasr_dsm_*.tif`).

- rgbi:

  SpatRaster aerial de reference pour le reechantillonnage a 0,2 m (NULL
  = garde la resolution native 1 m).

- buffer_m:

  Buffer (m) applique au LAScatalog pour les effets de bord (defaut :
  20, valeur recommandee dans DEV_PLAN.md S3.3).

- ncores:

  Nombre de coeurs paralleles (defaut : 2).

- keep_tiles:

  Si TRUE, conserve les rasters par tuile dans `output_dir`. Sinon
  (defaut), les supprime apres mosaiquage.

## Value

Liste avec

- `dem` : SpatRaster 2 bandes nommees `DSM`, `DTM`

- `dem_path` : chemin du GeoTIFF ecrit

- `dsm_source` : `"lasR"`

- `lidar_hd_coverage_pct` : NA (la mesure de couverture WMS n'a pas de
  sens en mode LAS ou les points sont par construction LiDAR)

## Details

Cette fonction est la voie `source = "las"` de
[`prepare_dem()`](https://pobsteta.github.io/maestronemeton/reference/prepare_dem.md)
(cf. ticket P2-02 du `DEV_PLAN.md`). Le pattern lasR est repris du
tutoriel `pobsteta/nemeton` `inst/tutorials/07-lidar-advanced` (cf.
DEV_PLAN.md S3.3).

Le telechargement automatique des tuiles LAZ depuis l'IGN (catalogue
cartes.gouv.fr / S3) est hors scope de cette fonction : les chemins sont
a fournir explicitement via `las_files`.
