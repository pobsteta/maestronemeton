# Telecharger une tuile BD Foret V2 via requete WFS directe

Requete WFS GetFeature directe vers la Geoplateforme IGN (sans happign).
Plus fiable que happign pour les grandes bbox.

## Usage

``` r
.wfs_get_bdforet(bbox_vals, typename, max_features = 10000)
```

## Arguments

- bbox_vals:

  Vecteur numerique c(xmin, ymin, xmax, ymax) en WGS84

- typename:

  Nom de la couche WFS

- max_features:

  Nombre max de features par requete (defaut: 10000)

## Value

sf data.frame ou NULL
