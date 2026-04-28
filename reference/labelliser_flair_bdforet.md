# Labelliser les patches FLAIR-HUB avec la BD Foret V2

Pour chaque patch aerial FLAIR-HUB, telecharge les polygones BD Foret V2
couvrant l'emprise du patch via WFS, et rasterise les codes NDP0 a la
resolution du patch (0.2m, 250x250 px). Les labels sont sauvegardes dans
un dossier `labels_ndp0/` parallele a `aerial/`.

## Usage

``` r
labelliser_flair_bdforet(
  flair_dir = "data/flair_hub",
  domaines = NULL,
  overwrite = FALSE
)
```

## Arguments

- flair_dir:

  Repertoire racine des donnees FLAIR-HUB (ex: `"data/flair_hub"`)

- domaines:

  Vecteur de domaines a traiter (`NULL` = tous les domaines trouves).
  Ex: `c("D001_2019", "D013_2020")`

- overwrite:

  Recalculer les labels existants (defaut: FALSE)

## Value

data.frame avec les statistiques par domaine (n_patches, n_forest,
pct_forest)

## Details

Les requetes WFS sont groupees par domaine (D001_2019, etc.) pour
limiter le nombre d'appels au service.
