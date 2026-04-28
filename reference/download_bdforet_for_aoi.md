# Telecharger la BD Foret V2 pour une AOI

Telecharge les polygones de la BD Foret V2 depuis le service WFS de la
Geoplateforme IGN via requete directe. Les polygones sont reprojectes en
Lambert-93 et les codes TFV sont convertis en classes NDP0.

## Usage

``` r
download_bdforet_for_aoi(
  aoi,
  output_dir,
  layer_name = "LANDCOVER.FORESTINVENTORY.V2:formation_vegetale"
)
```

## Arguments

- aoi:

  sf object (AOI en Lambert-93 ou WGS84)

- output_dir:

  Repertoire de sortie

- layer_name:

  Nom de la couche WFS BD Foret

## Value

sf data.frame avec les polygones BD Foret et la colonne `code_ndp0`

## Details

Pour les grandes AOI (\> 0.5 degre), la bbox est decoupee en tuiles.
