# Getting started with maestro

`maestro` enchaine telechargement IGN, extraction de patches
multi-modaux, et inference des modeles MAESTRO (classification par
patch, 13 essences PureForest) et FLAIR (segmentation pixel, 15 classes
CoSIA), publies sur Hugging Face par l’IGN.

## Installation

``` r
# install.packages("remotes")
remotes::install_github("pobsteta/maestronemeton")
```

Cote Python (reticulate gere l’environnement) :

``` r
maestronemeton::configurer_python()
```

[`configurer_python()`](https://pobsteta.github.io/maestronemeton/reference/configurer_python.md)
cree un environnement conda dedie (`maestro-py`) si necessaire et
installe les dependances : `torch`, `transformers`,
`segmentation_models_pytorch`, `rasterio`, etc.

## Pipeline minimal — classification d’essences forestieres

L’AOI est un GeoPackage en Lambert-93 (`EPSG:2154`). Tout polygone
fonctionne ; voir `inst/extdata/` du package pour un exemple jouet.

``` r
library(maestronemeton)

resultat <- maestro_pipeline(
  aoi_path  = "data/aoi.gpkg",
  output_dir = "outputs"
)

# resultat$grille  : sf des patches avec colonne `essence`
# resultat$raster  : SpatRaster mono-bande avec les codes PureForest
```

Par defaut le pipeline utilise la modalite `aerial` (RGBI 0,2 m) et le
modele de base `IGNF/MAESTRO_FLAIR-HUB_base` (13 classes PureForest).

## Ajouter le DEM (modalite `dem`)

Le DEM (DSM + DTM 2 bandes) ameliore la discrimination des resineux. La
modalite `dem` impose la modalite `aerial` car elle est extraite sur la
meme grille.

``` r
maestro_pipeline(
  aoi_path  = "data/aoi.gpkg",
  modalites = c("aerial", "dem")
)
```

Le DSM provient du LiDAR HD IGN (couverture partielle, completion d’ici
2026). Sous le seuil de couverture,
[`prepare_dem()`](https://pobsteta.github.io/maestronemeton/reference/prepare_dem.md)
rebascule sur DSM = DTM avec un warning ; passez
`allow_dtm_only_fallback = FALSE` pour retirer la modalite a la place.

## Multimodal complet — aerial + DEM + Sentinel

``` r
maestro_pipeline(
  aoi_path        = "data/aoi.gpkg",
  modalites       = c("aerial", "dem", "s2", "s1_asc", "s1_des"),
  annees_sentinel = 2022:2024,
  saison          = "ete"
)
```

Le composite Sentinel multi-annuel est mediane pixel par pixel sur la
saison choisie (`"ete"`, `"printemps"`, `"automne"`, `"annee"` ou
vecteur `c(mois_debut, mois_fin)`).

## Fine-tune PureForest

Charger un checkpoint local plutot que le modele de base :

``` r
maestro_pipeline(
  aoi_path   = "data/aoi.gpkg",
  checkpoint = "outputs/training/maestro_pureforest_best.pt"
)
```

Les modalites et `n_classes` sont lus du checkpoint et imposes au
pipeline. Pour entrainer le checkpoint, voir
`inst/scripts/cloud_train_pureforest.sh` et la vignette [Pipeline
Python](https://pobsteta.github.io/maestronemeton/articles/python-pipeline.md).

## Segmentation pixel-a-pixel (FLAIR)

``` r
flair_pipeline(
  aoi_path     = "data/aoi.gpkg",
  model_id     = "IGNF/FLAIR-INC_rgbi_15cl_resnet34-unet",
  dem_channels = c("SLOPE", "TWI")  # 6 bandes : RGBI + pente + TWI
)
```

Les modeles FLAIR-INC produisent une carte d’occupation du sol par pixel
a 0,2 m. Voir
[`flair_models()`](https://pobsteta.github.io/maestronemeton/reference/flair_models.md)
pour la liste des modeles supportes.

## Et apres

- Le tour d’horizon de la stack Python (entrainement, fine-tuning) :
  vignette [Pipeline
  Python](https://pobsteta.github.io/maestronemeton/articles/python-pipeline.md).
- Toutes les fonctions par theme :
  [Reference](https://pobsteta.github.io/maestronemeton/reference/index.md).
