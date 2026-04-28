# Preparer la modalite `dem` MAESTRO pour une AOI (DSM + DTM)

Construit le raster 2 bandes attendu par la modalite `dem` du modele
MAESTRO : `(DSM, DTM)` dans cet ordre. Deux sources sont supportees :

## Usage

``` r
prepare_dem(
  aoi,
  output_dir,
  rgbi = NULL,
  source = c("wms", "las"),
  coverage_threshold = 10,
  allow_dtm_only_fallback = TRUE,
  las_files = NULL,
  ncores = 2L
)
```

## Arguments

- aoi:

  sf object en Lambert-93.

- output_dir:

  Repertoire de sortie (ecrit `dem_2bands.tif`).

- rgbi:

  SpatRaster aerial de reference pour le reechantillonnage a 0,2 m (NULL
  = garde la resolution native 1 m).

- source:

  `"wms"` (defaut) pour Geoplateforme IGN. `"las"` pour derivation
  locale via lasR a partir de `las_files`.

- coverage_threshold:

  Pourcentage minimum de pixels LiDAR HD valides pour considerer la
  couverture suffisante en mode WMS (defaut : 10).

- allow_dtm_only_fallback:

  Mode WMS uniquement. Si TRUE et couverture insuffisante, utilise DSM =
  DTM (warning) ; sinon retourne NULL.

- las_files:

  Mode `"las"` uniquement : vecteur de chemins vers les tuiles LAZ/LAS a
  traiter (1 km x 1 km IGN typiquement).

- ncores:

  Mode `"las"` uniquement : nombre de coeurs paralleles pour le pipeline
  lasR (defaut : 2).

## Value

Liste avec

- `dem` : SpatRaster 2 bandes nommees `DSM`, `DTM`

- `dem_path` : chemin du GeoTIFF ecrit

- `dsm_source` : `"lidar_hd"` \| `"rge_alti_fallback"` \| `"lasR"` \|
  `"cache"`

- `lidar_hd_coverage_pct` : couverture LiDAR HD mesuree (mode WMS) ou NA
  (mode LAS) Renvoie NULL si le DTM RGE ALTI ne peut pas etre telecharge
  (mode WMS), ou si le LiDAR HD est insuffisant et
  `allow_dtm_only_fallback = FALSE`.

## Details

**`source = "wms"`** (defaut) : DTM depuis le RGE ALTI 1 m (couverture
nationale, couche WMS `ELEVATION.ELEVATIONGRIDCOVERAGE.HIGHRES`), DSM
depuis le LiDAR HD IGN (couverture partielle en cours de completion
d'ici 2026, couche `IGNF_LIDAR-HD_MNS_ELEVATION...`). Quand le LiDAR HD
ne couvre pas l'AOI (couverture \< `coverage_threshold`), deux
strategies selon `allow_dtm_only_fallback` :

- `TRUE` (defaut) : duplique le DTM comme DSM avec un warning explicite.
  Le CHM (DSM - DTM) sera plat, ce qui degrade le signal pour MAESTRO. A
  reserver aux mode degrade ou tests d'integration.

- `FALSE` : retourne `NULL` pour que l'appelant retire la modalite `dem`
  du pipeline et evite d'injecter des donnees corrompues dans le modele.

**`source = "las"`** : derivation directe via lasR a partir des nuages
LAZ fournis dans `las_files`. Pipeline TIN sol + premiers retours,
buffer 20 m sur le `LAScatalog`, mosaiquage et crop sur l'AOI, resample
sur la grille aerial. Le telechargement automatique des tuiles LAZ
depuis l'IGN n'est pas (encore) couvert : les chemins sont a fournir
explicitement (cf. catalogue cartes.gouv.fr).
