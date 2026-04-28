# Telecharger une image Sentinel-2 pour une AOI

Telecharge les 10 bandes spectrales Sentinel-2 L2A depuis Microsoft
Planetary Computer (COG en acces libre). Utilise rstac pour la recherche
et le signing automatique des URLs.

## Usage

``` r
download_s2_for_aoi(
  aoi,
  output_dir,
  date_cible = NULL,
  annees_sentinel = NULL,
  saison = "ete",
  max_scenes_par_annee = 3L
)
```

## Arguments

- aoi:

  sf object en Lambert-93

- output_dir:

  Repertoire de sortie

- date_cible:

  Date cible (format "YYYY-MM-DD", optionnel). Ignore si
  `annees_sentinel` est fourni.

- annees_sentinel:

  Vecteur d'annees pour le composite multi-annuel (ex: `2021:2024`). Si
  NULL, utilise le comportement mono-date.

- saison:

  Saison cible pour le composite : "ete" (defaut), "printemps",
  "automne", "annee", ou vecteur de 2 mois c(debut, fin)

- max_scenes_par_annee:

  Nombre max de scenes a retenir par annee pour le composite (defaut: 3,
  les moins nuageuses)

## Value

SpatRaster avec les 10 bandes S2, ou NULL

## Details

Supporte le mode multitemporel : en fournissant `annees_sentinel`,
plusieurs scenes sont telechargees sur plusieurs annees/saisons et
combinees en un composite median pixel par pixel. Cela permet de gommer
les annees seches et de reduire l'impact des nuages.
