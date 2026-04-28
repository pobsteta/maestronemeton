# Telecharger les donnees Sentinel-1 pour une AOI

Telecharge les polarisations VV et VH depuis Planetary Computer
(collection sentinel-1-rtc, deja corrige du terrain). Les valeurs
lineaires (gamma0) sont converties en dB : 10 \* log10(val).

## Usage

``` r
download_s1_for_aoi(
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

  Date cible (optionnel). Ignore si `annees_sentinel` est fourni.

- annees_sentinel:

  Vecteur d'annees pour le composite multi-annuel (ex: `2021:2024`). Si
  NULL, utilise le comportement mono-date.

- saison:

  Saison cible pour le composite : "ete" (defaut), "printemps",
  "automne", "annee", ou vecteur de 2 mois

- max_scenes_par_annee:

  Nombre max de scenes par annee/orbite pour le composite (defaut: 3)

## Value

Liste avec `s1_asc` et `s1_des` (SpatRaster 2 bandes VV+VH chacun), ou
NULL si non disponible

## Details

Supporte le mode multitemporel : en fournissant `annees_sentinel`,
plusieurs scenes sont telechargees et combinees en composite median.
