# Generer un rapport de segmentation MAESTRO (HTML ou PDF)

Compile le template Rmd de segmentation pour produire un rapport complet
: donnees d'entree (RGBI, DEM avec SLOPE/TWI/TPI/ASPECT, Sentinel),
indices spectraux (NDVI), carte de segmentation NDP0 a 0.2m,
distribution des essences, et analyses topographiques croisees.

## Usage

``` r
generer_rapport_segmentation(
  aoi_path,
  backbone_path,
  decoder_path = "segmenter_ndp0_best.pt",
  output_dir = "outputs",
  format = c("html", "pdf"),
  output_file = NULL,
  millesime_ortho = NULL,
  millesime_irc = NULL,
  dem_channels = c("SLOPE", "TWI"),
  use_s2 = FALSE,
  use_s1 = FALSE,
  date_sentinel = NULL,
  gpu = FALSE,
  run_segmentation = TRUE,
  use_flair = FALSE,
  model_flair = "IGNF/FLAIR-INC_rgbi_15cl_resnet34-unet",
  open = interactive()
)
```

## Arguments

- aoi_path:

  Chemin vers le fichier GeoPackage de l'AOI.

- backbone_path:

  Chemin vers le checkpoint MAESTRO (.ckpt).

- decoder_path:

  Chemin vers le decodeur de segmentation (.pt).

- output_dir:

  Repertoire de sortie (defaut `"outputs"`).

- format:

  Format de sortie : `"html"` (par defaut) ou `"pdf"`.

- output_file:

  Nom du fichier de sortie (optionnel).

- millesime_ortho:

  Millesime de l'ortho RVB (`NULL` = plus recent).

- millesime_irc:

  Millesime de l'ortho IRC (`NULL` = plus recent).

- dem_channels:

  Vecteur de 2 canaux DEM parmi `"DSM"`, `"DTM"`, `"SLOPE"`, `"ASPECT"`,
  `"TPI"`, `"TWI"` (defaut `c("SLOPE", "TWI")`).

- use_s2:

  Logical. Inclure Sentinel-2 ? (defaut `FALSE`).

- use_s1:

  Logical. Inclure Sentinel-1 ? (defaut `FALSE`).

- date_sentinel:

  Date cible pour Sentinel (`NULL`).

- gpu:

  Logical. Utiliser le GPU ? (defaut `FALSE`).

- run_segmentation:

  Logical. Executer la segmentation ? Si `FALSE`, charge un resultat
  existant depuis `output_dir` (defaut `TRUE`).

- use_flair:

  Logical. Appliquer la contrainte FLAIR feuillus/resineux apres la
  segmentation ? (defaut `FALSE`).

- model_flair:

  Identifiant du modele FLAIR HuggingFace (defaut
  `"IGNF/FLAIR-INC_rgbi_15cl_resnet34-unet"`).

- open:

  Logical. Ouvrir le rapport apres generation ? (defaut `TRUE` en
  session interactive).

## Value

Le chemin du fichier rapport genere (invisiblement).

## Examples

``` r
if (FALSE) { # \dontrun{
# Rapport HTML de segmentation
generer_rapport_segmentation(
  aoi_path      = "data/aoi.gpkg",
  backbone_path = modele$weights,
  decoder_path  = "segmenter_ndp0_best.pt"
)

# Rapport PDF avec DEM DSM+DTM et Sentinel-2
generer_rapport_segmentation(
  aoi_path      = "data/aoi.gpkg",
  backbone_path = modele$weights,
  decoder_path  = "segmenter_ndp0_best.pt",
  format        = "pdf",
  dem_channels  = c("DSM", "DTM"),
  use_s2        = TRUE
)

# Rapport depuis resultats existants (sans re-executer)
generer_rapport_segmentation(
  aoi_path         = "data/aoi.gpkg",
  backbone_path    = NULL,
  decoder_path     = "segmenter_ndp0_best.pt",
  run_segmentation = FALSE
)
} # }
```
