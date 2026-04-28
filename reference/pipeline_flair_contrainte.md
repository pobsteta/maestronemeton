# Lancer FLAIR puis contraindre la segmentation MAESTRO

Pipeline complet qui :

1.  Execute l'inference FLAIR pour obtenir une carte feuillus/resineux

2.  Applique la contrainte sur la segmentation MAESTRO existante

## Usage

``` r
pipeline_flair_contrainte(
  raster_seg,
  rgbi,
  dem = NULL,
  output_dir = "outputs",
  model_flair = "IGNF/FLAIR-INC_rgbi_15cl_resnet34-unet",
  gpu = FALSE
)
```

## Arguments

- raster_seg:

  SpatRaster de segmentation MAESTRO (classes NDP0)

- rgbi:

  SpatRaster RGBI 4 bandes pour l'inference FLAIR

- dem:

  SpatRaster DEM (optionnel, pour le modele RGBI-DEM 5 bandes)

- output_dir:

  Repertoire de sortie

- model_flair:

  Identifiant du modele FLAIR HuggingFace (defaut
  `"IGNF/FLAIR-INC_rgbi_15cl_resnet34-unet"`).

- gpu:

  Logical. Utiliser le GPU ? (defaut `FALSE`).

## Value

Liste avec `raster` contraint et `stats` des corrections

## Examples

``` r
if (FALSE) { # \dontrun{
result <- pipeline_flair_contrainte(
  raster_seg = terra::rast("outputs/segmentation_ndp0.tif"),
  rgbi       = terra::rast("outputs/ortho_rgbi.tif"),
  output_dir = "outputs"
)
} # }
```
