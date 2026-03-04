# MAESTRO Nemeton - Reconnaissance des essences forestieres

Reconnaissance automatique des essences forestieres a partir d'une zone
d'interet (`aoi.gpkg`) en utilisant le modele
[MAESTRO](https://github.com/IGNF/maestro) de l'IGNF telecharge depuis
[Hugging Face](https://huggingface.co/IGNF) via le package R
[hfhub](https://cran.r-project.org/package=hfhub).

Les donnees d'entree (orthophotos RVB, IRC et MNT 1m) sont telechargees
automatiquement depuis la [Geoplateforme IGN](https://data.geopf.fr/) via
le service WMS-R (pas de cle API necessaire).

## Pipeline

```
aoi.gpkg
   |
   v
Telechargement IGN (WMS-R Geoplateforme)
   |-- Ortho RVB (0.2m, millesime au choix)
   |-- Ortho IRC (0.2m, millesime au choix)
   |-- MNT RGE ALTI (1m, reechantillonne a 0.2m)
   |
   v
Combinaison → image 5 bandes (R, G, B, PIR, MNT)
   |
   v
Decoupage en patches 250x250 px (50m x 50m)
   |
   v
Inference MAESTRO (ViT, 13 classes PureForest)
   |
   v
Resultats
   |-- essences_forestieres.gpkg (carte vectorielle)
   |-- essences_forestieres.tif  (carte raster)
   |-- statistiques_essences.csv
```

## Essences detectees (13 classes PureForest)

| Code | Essence | Nom latin | Type |
|------|---------|-----------|------|
| 0 | Chene decidue | *Quercus spp.* | Feuillu |
| 1 | Chene vert | *Quercus ilex* | Feuillu |
| 2 | Hetre | *Fagus sylvatica* | Feuillu |
| 3 | Chataignier | *Castanea sativa* | Feuillu |
| 4 | Pin maritime | *Pinus pinaster* | Resineux |
| 5 | Pin sylvestre | *Pinus sylvestris* | Resineux |
| 6 | Pin laricio/noir | *Pinus nigra* | Resineux |
| 7 | Pin d'Alep | *Pinus halepensis* | Resineux |
| 8 | Epicea | *Picea abies* | Resineux |
| 9 | Sapin | *Abies alba* | Resineux |
| 10 | Douglas | *Pseudotsuga menziesii* | Resineux |
| 11 | Meleze | *Larix spp.* | Resineux |
| 12 | Peuplier | *Populus spp.* | Feuillu |

## Pre-requis

### R (>= 4.1)

```r
install.packages(c("hfhub", "sf", "terra", "curl", "fs",
                    "reticulate", "jsonlite", "optparse"))
```

### Python (>= 3.11)

```bash
pip install torch numpy
# Optionnel pour les poids .safetensors :
pip install safetensors
```

## Utilisation

### 1. Creer une zone d'interet

Le fichier `aoi.gpkg` est un GeoPackage contenant un ou plusieurs polygones.
Un script d'exemple est fourni :

```bash
Rscript creer_aoi_exemple.R
```

### 2. Lancer la reconnaissance des essences

```bash
# Millesime par defaut (mosaique la plus recente)
Rscript maestro_essences.R --aoi aoi.gpkg

# Millesime specifique (ortho et IRC de 2023)
Rscript maestro_essences.R --aoi aoi.gpkg \
  --millesime_ortho 2023 --millesime_irc 2023

# Avec GPU
Rscript maestro_essences.R --aoi aoi.gpkg \
  --millesime_ortho 2024 --millesime_irc 2024 --gpu
```

### Options

| Option | Description | Defaut |
|--------|-------------|--------|
| `--aoi` | Fichier GeoPackage de la zone d'interet | `aoi.gpkg` |
| `--output` | Repertoire de sortie | `resultats/` |
| `--model` | Identifiant du modele Hugging Face | `IGNF/MAESTRO_FLAIR-HUB_base` |
| `--millesime_ortho` | Annee de l'ortho RVB (NULL = plus recent) | `NULL` |
| `--millesime_irc` | Annee de l'ortho IRC (NULL = plus recent) | `NULL` |
| `--patch_size` | Taille des patches en pixels | `250` |
| `--resolution` | Resolution spatiale (m) | `0.2` |
| `--gpu` | Utiliser le GPU (CUDA) | `FALSE` |
| `--token` | Token Hugging Face | *(env var)* |

## Donnees telechargees depuis l'IGN

Les donnees sont recuperees automatiquement via le service WMS-R de la
Geoplateforme IGN (`https://data.geopf.fr/wms-r`) :

| Donnee | Couche WMS | Resolution | Bandes |
|--------|-----------|-----------|--------|
| Ortho RVB | `ORTHOIMAGERY.ORTHOPHOTOS[YYYY]` | 0.2 m | R, G, B |
| Ortho IRC | `ORTHOIMAGERY.ORTHOPHOTOS.IRC[.YYYY]` | 0.2 m | PIR, R, G |
| MNT | `ELEVATION.ELEVATIONGRIDCOVERAGE.HIGHRES` | 1 m | Altitude |

- Le **millesime** (annee) est optionnel : sans millesime, la mosaique
  nationale la plus recente est utilisee.
- Si le millesime demande n'est pas disponible pour la zone, un **fallback
  automatique** vers la mosaique la plus recente est effectue.
- Le MNT est reechantillonne de 1 m a 0.2 m pour s'aligner sur les
  orthophotos.
- Les fichiers sont mis en **cache** dans le repertoire de sortie et
  reutilises lors des executions suivantes.

## Sorties

Le script produit dans le repertoire de sortie (`resultats/`) :

| Fichier | Description |
|---------|-------------|
| `ortho_rvb.tif` | Orthophoto RVB telechargee |
| `ortho_irc.tif` | Orthophoto IRC telechargee |
| `ortho_rgbi.tif` | Image 4 bandes (R, G, B, PIR) |
| `mnt_1m.tif` | MNT RGE ALTI reechantillonne a 0.2 m |
| `image_finale.tif` | Image 5 bandes (R, G, B, PIR, MNT) |
| `essences_forestieres.gpkg` | Carte vectorielle des essences par patch |
| `essences_forestieres.tif` | Carte raster des essences (codes 0-12) |
| `statistiques_essences.csv` | Statistiques des essences detectees |

## Fonctionnement du telechargement WMS

Le telechargement respecte les contraintes du WMS IGN :
- **Tuilage automatique** : les grandes emprises sont decoupees en tuiles
  de 4096 px maximum, puis mosaiquees.
- **Retry avec backoff exponentiel** : en cas d'erreur reseau, jusqu'a 3
  tentatives avec delais croissants (2s, 4s, 8s).
- **HTTP/1.1** force pour eviter les erreurs HTTP/2 du serveur IGN.
- **Pas de cle API** necessaire : le service WMS-R est en acces libre.

Le code de telechargement est adapte du projet
[pobsteta/flair_hub_nemeton](https://github.com/pobsteta/flair_hub_nemeton).

## References

- **MAESTRO** : Labatie et al. (2025), *MAESTRO: Masked AutoEncoders for
  Multimodal, Multitemporal, and Multispectral Earth Observation Data*,
  [arXiv:2508.10894](https://arxiv.org/abs/2508.10894)
- **PureForest** : Gaydon & Roche (2024), *PureForest: A Large-Scale Aerial
  Lidar and Aerial Imagery Dataset for Tree Species Classification*,
  [arXiv:2404.12064](https://arxiv.org/abs/2404.12064)
- **IGNF sur Hugging Face** : [huggingface.co/IGNF](https://huggingface.co/IGNF)
- **hfhub** : [cran.r-project.org/package=hfhub](https://cran.r-project.org/package=hfhub)
- **Geoplateforme IGN** : [data.geopf.fr](https://data.geopf.fr/)
