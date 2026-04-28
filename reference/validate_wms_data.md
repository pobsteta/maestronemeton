# Verifier qu'un raster WMS contient des donnees reelles

Certaines couches millésimees ne couvrent pas toutes les zones. Le WMS
retourne alors un raster valide mais vide (pixels a 0 ou NA).

## Usage

``` r
validate_wms_data(r, min_pct = 5)
```

## Arguments

- r:

  SpatRaster a valider

- min_pct:

  Pourcentage minimum de pixels non-vides requis (defaut: 5)

## Value

TRUE si le raster contient suffisamment de donnees
