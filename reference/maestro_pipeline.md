# Executer le pipeline MAESTRO de reconnaissance d'essences forestieres

Pipeline de bout en bout : charge l'AOI, telecharge les modalites
demandees (aerien IGN, DEM, Sentinel-2, Sentinel-1), construit une
grille de patches alignee sur la modalite aerienne, extrait les fenetres
centrees par modalite (cf.
[`modalite_specs()`](https://pobsteta.github.io/maestronemeton/reference/modalite_specs.md))
et execute l'inference multi-modale MAESTRO.

## Usage

``` r
maestro_pipeline(
  aoi_path = "data/aoi.gpkg",
  output_dir = "outputs",
  model_id = "IGNF/MAESTRO_FLAIR-HUB_base",
  checkpoint = NULL,
  modalites = c("aerial"),
  millesime_ortho = NULL,
  millesime_irc = NULL,
  n_classes = 13L,
  date_sentinel = NULL,
  annees_sentinel = NULL,
  saison = "ete",
  max_scenes_par_annee = 3L,
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

  Identifiant Hugging Face du modele de base (defaut:
  `"IGNF/MAESTRO_FLAIR-HUB_base"`). Ignore si `checkpoint` est fourni.

- checkpoint:

  Chemin vers un checkpoint fine-tune (`*.pt`). Lorsque fourni, les
  modalites et le nombre de classes sont lus du checkpoint et imposes au
  pipeline. Ex. `"outputs/training/maestro_pureforest_best.pt"`.

- modalites:

  Vecteur de modalites a utiliser parmi
  `c("aerial", "dem", "s2", "s1_asc", "s1_des")` (defaut: `"aerial"`,
  MVP phase 1).

- millesime_ortho:

  Millesime de l'ortho RVB (`NULL` = plus recent)

- millesime_irc:

  Millesime de l'ortho IRC (`NULL` = plus recent)

- n_classes:

  Nombre de classes en sortie. Defaut 13 (PureForest). Ecrase par
  `checkpoint$n_classes` si un checkpoint fine-tune est fourni.

- date_sentinel:

  Date cible pour Sentinel (`"YYYY-MM-DD"`, NULL = ete de l'annee
  courante). Ignore si `annees_sentinel` est fourni.

- annees_sentinel:

  Vecteur d'annees pour un composite multi-annuel (ex. `2021:2024`).
  Active le mode multitemporel.

- saison:

  Saison du composite : `"ete"`, `"printemps"`, `"automne"`, `"annee"`,
  ou vecteur `c(mois_debut, mois_fin)`.

- max_scenes_par_annee:

  Nombre max de scenes par annee pour le composite (defaut : 3, les
  moins nuageuses).

- gpu:

  Utiliser le GPU CUDA (defaut: FALSE).

- token:

  Token Hugging Face (optionnel).

## Value

Liste invisible avec `grille` (sf), `raster` (SpatRaster) et `modalites`
(character) effectivement utilisees.

## Details

Modalites supportees (cf. fiche modele HF `IGNF/MAESTRO_FLAIR-HUB_base`)
:

- `aerial` : RGBI 4 bandes a 0,2 m, fenetre 51,2 m (256 x 256 px,
  `patch_size.mae=16`)

- `dem` : DSM+DTM 2 bandes a 0,2 m, meme fenetre 51,2 m
  (`patch_size.mae=32`)

- `s2` : Sentinel-2 L2A 10 bandes a 10 m, fenetre 60 m (6 x 6 px,
  `patch_size.mae=2`)

- `s1_asc` / `s1_des` : Sentinel-1 RTC VV+VH a 10 m, fenetre 60 m

Les modalites Sentinel utilisent une fenetre legerement elargie (60 m au
lieu de 51,2 m) pour respecter le multiple de `patch_size.mae=2`.

## Examples

``` r
if (FALSE) { # \dontrun{
# MVP : aerial seul, modele de base PureForest 13 classes
maestro_pipeline("data/aoi.gpkg")

# Aerial + DEM (Phase 2)
maestro_pipeline("data/aoi.gpkg", modalites = c("aerial", "dem"))

# Toutes les modalites avec composite Sentinel multi-annuel (Phase 3)
maestro_pipeline("data/aoi.gpkg",
                  modalites = c("aerial", "dem", "s2", "s1_asc", "s1_des"),
                  annees_sentinel = 2022:2024, saison = "ete")

# Avec checkpoint fine-tune PureForest
maestro_pipeline("data/aoi.gpkg",
                  checkpoint = "outputs/training/maestro_pureforest_best.pt")
} # }
```
