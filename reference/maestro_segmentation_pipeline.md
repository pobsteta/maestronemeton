# Pipeline de segmentation dense MAESTRO a 0.2m

Pipeline complet : telecharge les donnees multimodales, charge le
backbone MAESTRO + decodeur de segmentation, et produit une carte
d'essences forestieres a 0.2m de resolution (classes NDP0, 10 classes).

## Usage

``` r
maestro_segmentation_pipeline(
  aoi_path = "data/aoi.gpkg",
  backbone_path,
  decoder_path,
  output_dir = "outputs",
  millesime_ortho = NULL,
  millesime_irc = NULL,
  patch_size = 250L,
  resolution = 0.2,
  overlap_m = 10,
  use_s2 = FALSE,
  use_s1 = FALSE,
  date_sentinel = NULL,
  annees_sentinel = NULL,
  saison = "ete",
  max_scenes_par_annee = 3L,
  dem_channels = c("SLOPE", "TWI"),
  gpu = FALSE,
  use_flair = FALSE,
  model_flair = "IGNF/FLAIR-INC_rgbi_15cl_resnet34-unet"
)
```

## Arguments

- aoi_path:

  Chemin vers le fichier GeoPackage de la zone d'interet

- backbone_path:

  Chemin vers le checkpoint MAESTRO pre-entraine (.ckpt)

- decoder_path:

  Chemin vers le decodeur de segmentation (.pt)

- output_dir:

  Repertoire de sortie (defaut: `"outputs"`)

- millesime_ortho:

  Millesime de l'ortho RVB (`NULL` = plus recent)

- millesime_irc:

  Millesime de l'ortho IRC (`NULL` = plus recent)

- patch_size:

  Taille des patches en pixels (defaut: 250)

- resolution:

  Resolution spatiale en metres (defaut: 0.2)

- overlap_m:

  Recouvrement entre patches en metres (defaut: 10)

- use_s2:

  Inclure Sentinel-2 (defaut: FALSE)

- use_s1:

  Inclure Sentinel-1 (defaut: FALSE)

- date_sentinel:

  Date cible pour les images Sentinel

- annees_sentinel:

  Vecteur d'annees pour un composite multi-annuel

- saison:

  Saison cible pour le composite multitemporel

- max_scenes_par_annee:

  Nombre max de scenes par annee (defaut: 3)

- dem_channels:

  Vecteur de 2 noms de canaux DEM (defaut: `c("SLOPE", "TWI")`)

- gpu:

  Utiliser le GPU CUDA (defaut: FALSE)

- use_flair:

  Logical. Appliquer la contrainte FLAIR feuillus/resineux sur la
  segmentation ? (defaut: `FALSE`). Si `TRUE`, execute l'inference FLAIR
  puis corrige les pixels incoherents.

- model_flair:

  Identifiant du modele FLAIR HuggingFace (defaut:
  `"IGNF/FLAIR-INC_rgbi_15cl_resnet34-unet"`).

## Value

SpatRaster mono-bande avec les codes NDP0 a 0.2m

## Examples

``` r
if (FALSE) { # \dontrun{
# Segmentation avec aerial + DEM (pente + TWI)
maestro_segmentation_pipeline(
  "data/aoi.gpkg",
  backbone_path = "models/MAESTRO_pretrain.ckpt",
  decoder_path = "models/segmenter_ndp0_best.pt"
)

# Avec DSM + DTM classique
maestro_segmentation_pipeline(
  "data/aoi.gpkg",
  backbone_path = "models/MAESTRO_pretrain.ckpt",
  decoder_path = "models/segmenter_ndp0_best.pt",
  dem_channels = c("DSM", "DTM")
)
} # }
```
