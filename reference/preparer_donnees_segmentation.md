# Pipeline de preparation des donnees d'entrainement pour la segmentation

Telecharge les donnees multimodales et la BD Foret V2 pour l'AOI,
rasterise les labels NDP0, et decoupe le tout en patches d'entrainement.

## Usage

``` r
preparer_donnees_segmentation(
  aoi_path = "data/aoi.gpkg",
  output_dir = "data/segmentation",
  millesime_ortho = NULL,
  millesime_irc = NULL,
  patch_size = 250L,
  resolution = 0.2,
  val_ratio = 0.15,
  min_forest_pct = 10,
  use_s2 = FALSE,
  use_s1 = FALSE,
  date_sentinel = NULL,
  annees_sentinel = NULL,
  saison = "ete",
  max_scenes_par_annee = 3L,
  dem_channels = c("SLOPE", "TWI")
)
```

## Arguments

- aoi_path:

  Chemin vers le fichier GeoPackage de la zone d'interet

- output_dir:

  Repertoire de sortie pour les patches

- millesime_ortho:

  Millesime de l'ortho RVB

- millesime_irc:

  Millesime de l'ortho IRC

- patch_size:

  Taille des patches en pixels (defaut: 250)

- resolution:

  Resolution en metres (defaut: 0.2)

- val_ratio:

  Proportion de validation (defaut: 0.15)

- min_forest_pct:

  Pourcentage minimum de foret par patch (defaut: 10)

- use_s2:

  Inclure Sentinel-2 (defaut: FALSE)

- use_s1:

  Inclure Sentinel-1 (defaut: FALSE)

- date_sentinel:

  Date cible pour Sentinel

- annees_sentinel:

  Vecteur d'annees pour composite

- saison:

  Saison cible

- max_scenes_par_annee:

  Nombre max de scenes par annee

- dem_channels:

  Vecteur de noms de canaux DEM parmi
  `c("DSM", "DTM", "SLOPE", "ASPECT", "TPI", "TWI")`. Defaut :
  `c("SLOPE", "TWI")`.

## Value

Liste avec n_train, n_val, n_skipped
