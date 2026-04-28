# Executer le pipeline FLAIR d'occupation du sol

Pipeline de bout en bout : charge l'AOI, telecharge les donnees IGN
(ortho RVB, IRC, DEM optionnel), combine les bandes, telecharge le
modele FLAIR pre-entraine, execute la segmentation semantique
pixel-a-pixel avec blending Hann, et exporte les resultats.

## Usage

``` r
flair_pipeline(
  aoi_path = "data/aoi.gpkg",
  output_dir = "outputs",
  model_id = "IGNF/FLAIR-INC_rgbi_15cl_resnet34-unet",
  encoder = "resnet34",
  decoder = "unet",
  n_classes = 19L,
  dem_channels = NULL,
  millesime_ortho = NULL,
  millesime_irc = NULL,
  patch_size = 512L,
  overlap = 128L,
  gpu = FALSE,
  token = NULL
)
```

## Arguments

- aoi_path:

  Chemin vers le fichier GeoPackage de la zone d'interet

- output_dir:

  Repertoire de sortie (defaut: `"outputs"`)

- model_id:

  Identifiant du modele Hugging Face (defaut:
  `"IGNF/FLAIR-INC_rgbi_15cl_resnet34-unet"`)

- encoder:

  Architecture encodeur (defaut: `"resnet34"`)

- decoder:

  Architecture decodeur (defaut: `"unet"`)

- n_classes:

  Nombre de classes du modele (defaut: 19, les checkpoints FLAIR-INC ont
  19 canaux de sortie meme pour 15 classes actives)

- dem_channels:

  Canaux DEM a ajouter. `NULL` = pas de DEM (RGBI seul, 4 bandes).
  Vecteur de noms parmi
  `c("DSM", "DTM", "SLOPE", "ASPECT", "TPI", "TWI")`. Ex:
  `c("SLOPE", "TWI")` = 6 bandes (RGBI + pente + TWI). Ex: `"DTM"` = 5
  bandes (RGBI + DTM classique).

- millesime_ortho:

  Millesime de l'ortho RVB (`NULL` = plus recent)

- millesime_irc:

  Millesime de l'ortho IRC (`NULL` = plus recent)

- patch_size:

  Taille des patches en pixels (defaut: 512)

- overlap:

  Recouvrement entre patches (defaut: 128)

- gpu:

  Utiliser le GPU CUDA (defaut: FALSE)

- token:

  Token Hugging Face (optionnel)

## Value

Liste invisible avec `raster` (SpatRaster) et `stats` (data.frame)

## Details

Les modeles FLAIR produisent des cartes de classification par pixel,
contrairement a MAESTRO qui classifie par patch.

## Examples

``` r
if (FALSE) { # \dontrun{
# Classification basique RGBI (4 bandes)
flair_pipeline("data/aoi.gpkg")

# Avec pente + TWI (6 bandes, optimal foret)
flair_pipeline("data/aoi.gpkg",
                dem_channels = c("SLOPE", "TWI"),
                model_id = "IGNF/FLAIR-INC_rgbie_15cl_resnet34-unet")

# Avec DTM classique (5 bandes)
flair_pipeline("data/aoi.gpkg",
                dem_channels = "DTM",
                model_id = "IGNF/FLAIR-INC_rgbie_15cl_resnet34-unet")
} # }
```
