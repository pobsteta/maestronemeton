# Contraindre la segmentation MAESTRO par la classification FLAIR

Post-traitement qui utilise la carte FLAIR (CoSIA 19 classes) pour :

1.  Forcer les pixels non-foret a la classe NDP0 = 9

2.  Contraindre les pixels "Conifere" FLAIR aux essences resineuses

3.  Contraindre les pixels "Feuillu" FLAIR aux essences feuillues

4.  Gerer les pixels "Mixte" en gardant la prediction MAESTRO

## Usage

``` r
contraindre_par_flair(
  raster_seg,
  raster_flair,
  garder_mixte = TRUE,
  garder_ligneux = TRUE
)
```

## Arguments

- raster_seg:

  SpatRaster de segmentation MAESTRO (classes NDP0 0-9)

- raster_flair:

  SpatRaster de classification FLAIR (classes CoSIA 1-19)

- garder_mixte:

  Logical. Garder la prediction MAESTRO pour les pixels "Mixte
  conifere+feuillu" (classe 17) ? Si `FALSE`, force en feuillus divers
  (defaut `TRUE`).

- garder_ligneux:

  Logical. Traiter les pixels "Ligneux" (classe 18) comme foret ?
  (defaut `TRUE`).

## Value

Liste avec :

- `raster` : SpatRaster contraint

- `stats` : data.frame avec les corrections appliquees

## Examples

``` r
if (FALSE) { # \dontrun{
# Lancer FLAIR puis contraindre
flair_result <- flair_pipeline("data/aoi.gpkg", output_dir = "outputs")
raster_flair <- terra::rast("outputs/occupation_sol.tif")

result <- contraindre_par_flair(raster_seg, raster_flair)
terra::plot(result$raster)
} # }
```
