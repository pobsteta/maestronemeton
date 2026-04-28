# Generer un rapport HTML ou PDF du pipeline MAESTRO

Compile le template Rmd fourni avec le package pour produire un rapport
complet du pipeline : telechargement des donnees, combinaison, creation
des patches, indices spectraux et optionnellement inference.

## Usage

``` r
generer_rapport(
  aoi_path,
  output_dir = "outputs",
  format = c("html", "pdf"),
  output_file = NULL,
  millesime = NULL,
  inference = FALSE,
  gpu = FALSE,
  model_id = "IGNF/MAESTRO_FLAIR-HUB_base",
  use_s2 = FALSE,
  use_s1 = FALSE,
  date_sentinel = NULL,
  open = interactive()
)
```

## Arguments

- aoi_path:

  Chemin vers le fichier GeoPackage de l'AOI.

- output_dir:

  Repertoire de sortie pour les resultats et le rapport (par defaut
  `"outputs"`).

- format:

  Format de sortie : `"html"` (par defaut) ou `"pdf"`. Le format PDF
  necessite une installation LaTeX (voir
  [`tinytex::install_tinytex()`](https://rdrr.io/pkg/tinytex/man/install_tinytex.html)).

- output_file:

  Nom du fichier de sortie (optionnel). Par defaut
  `"rapport_pipeline_aoi.html"` ou `"rapport_pipeline_aoi.pdf"`.

- millesime:

  Millesime des orthophotos IGN (`NULL` = le plus recent).

- inference:

  Logical. Lancer l'inference MAESTRO ? (defaut `FALSE`).

- gpu:

  Logical. Utiliser le GPU pour l'inference ? (defaut `FALSE`).

- model_id:

  Identifiant du modele sur Hugging Face (defaut
  `"IGNF/MAESTRO_FLAIR-HUB_base"`).

- use_s2:

  Logical. Telecharger et integrer les donnees Sentinel-2 ? (defaut
  `FALSE`).

- use_s1:

  Logical. Telecharger et integrer les donnees Sentinel-1 ? (defaut
  `FALSE`).

- date_sentinel:

  Date cible pour les donnees Sentinel (format `"YYYY-MM-DD"` ou
  `NULL`).

- open:

  Logical. Ouvrir le rapport dans le navigateur apres generation ?
  (defaut `TRUE` en session interactive).

## Value

Le chemin du fichier rapport genere (invisiblement).

## Examples

``` r
if (FALSE) { # \dontrun{
# Rapport HTML simple
generer_rapport("data/aoi.gpkg")

# Rapport PDF avec inference
generer_rapport("data/aoi.gpkg", format = "pdf", inference = TRUE)

# Rapport complet avec Sentinel-2 et inference GPU
generer_rapport(
  aoi_path   = "data/aoi.gpkg",
  format     = "html",
  inference  = TRUE,
  gpu        = TRUE,
  use_s2     = TRUE,
  date_sentinel = "2024-06-15"
)
} # }
```
