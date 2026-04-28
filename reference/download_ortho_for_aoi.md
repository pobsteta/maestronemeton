# Telecharger les ortho RVB et IRC pour une AOI

Telecharge les orthophotos RVB et IRC depuis la Geoplateforme IGN via
WMS-R. Gere le cache (reutilisation des fichiers existants), le
millesime (annee au choix) et le fallback automatique vers la mosaique
la plus recente si le millesime demande n'est pas disponible.

## Usage

``` r
download_ortho_for_aoi(
  aoi,
  output_dir,
  millesime_ortho = NULL,
  millesime_irc = NULL
)
```

## Arguments

- aoi:

  sf object (AOI en Lambert-93)

- output_dir:

  Repertoire de sortie

- millesime_ortho:

  `NULL` ou entier (annee de l'ortho RVB)

- millesime_irc:

  `NULL` ou entier (annee de l'ortho IRC)

## Value

Liste avec `rvb`, `irc` (SpatRaster), `rvb_path`, `irc_path`,
`millesime_ortho`, `millesime_irc`
