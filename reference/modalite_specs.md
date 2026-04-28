# Specifications des modalites MAESTRO

Table declarative des modalites attendues par le modele
`IGNF/MAESTRO_FLAIR-HUB_base`. Chaque entree decrit la forme du patch a
fournir au DataLoader / au pipeline d'inference :

## Usage

``` r
modalite_specs()
```

## Value

Liste nommee de specifications par modalite

## Details

- `in_channels` : nombre de canaux pour le `patch_embed` de la modalite
  ;

- `image_size` : cote du patch en pixels ;

- `resolution` : taille de pixel au sol en metres ;

- `patch_size_mae` : stride du `Conv2d(stride=patch_size_mae)` du
  `patch_embed`. `image_size` doit en etre un multiple, sinon le modele
  rogne silencieusement les bords ;

- `window_m` : fenetre physique = `image_size * resolution`.

Les valeurs reproduisent la configuration FLAIR-HUB du modele de base
(cf. fiche HF `IGNF/MAESTRO_FLAIR-HUB_base`), a l'echelle 50 m de
PureForest. Les fenetres Sentinel sont elargies a 60 m pour respecter le
multiple de `patch_size_mae=2` sans padding artificiel.

## Examples

``` r
specs <- modalite_specs()
specs$aerial$image_size  # 256
#> [1] 256
specs$s2$window_m        # 60
#> [1] 60
```
