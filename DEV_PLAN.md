# Plan de développement — `maestronemeton`

Reprise du dépôt R `maestronemeton` (`github.com/pobsteta/maestronemeton`,
souvent cloné en local sous le nom historique `maestro_nemeton/`) pour
exploiter réellement le modèle MAESTRO
de l'IGN sur les essences forestières françaises, avec ses six modalités
natives (aérien 0,2 m, DEM/CHM, Sentinel-1 ascendant, Sentinel-1 descendant,
Sentinel-2, et SPOT). Le plan ci-dessous part du code existant
(version `0.2.0`, branche `cleanup/code-review`) et propose une refonte
incrémentale en quatre phases, en gardant à chaque étape un système qui
tourne de bout en bout sur une AOI réelle.

Le livrable final est l'inférence de 13 classes PureForest sur une AOI
arbitraire en France, à partir d'un fine-tuning de
`IGNF/MAESTRO_FLAIR-HUB_base` augmenté de modalités Sentinel et d'un CHM
LiDAR HD. Tout choix technique est justifié par les fiches officielles IGN /
Hugging Face / MAESTRO et indiqué dans la section concernée.

## Sommaire

1. Diagnostic du dépôt actuel
2. Architecture cible
3. Stratégie LiDAR HD
4. Augmentation de PureForest avec Sentinel
5. DataLoader PureForest pour MAESTRO
6. Plan de fine-tuning
7. Pipeline d'inférence
8. Phasage
9. Risques et points ouverts
10. Backlog priorisé

---

## 1. Diagnostic du dépôt actuel

Statut par module : `KEEP` = à conserver tel quel, `REFACTOR` = retoucher
sans changer le périmètre, `REWRITE` = repartir d'une feuille blanche en
gardant l'idée, `DELETE` = supprimer.

### 1.1 Code R (`R/`)

| Fichier | Statut | Justification | Dépendances |
|--------|--------|---------------|-------------|
| `aoi.R` | KEEP | `load_aoi()` est correct : lecture GPKG, reprojection L93, log d'emprise et de surface. Pas de bug observé. | `sf` |
| `download_ign.R` | REFACTOR | Le tuilage WMS, le retry et le fallback de millésime sont solides. Trois changements à faire : (a) la couche LiDAR HD MNS exposée par `LAYER_MNS` (`IGNF_LIDAR-HD_MNS_ELEVATION.ELEVATIONGRIDCOVERAGE.LAMB93`) renvoie un MNS sol+sur-sol mais aucun MNH ; il faut ajouter une couche dédiée au CHM (`IGNF_LIDAR-HD_MNH...`) ou la dériver localement (cf. §3) ; (b) la routine `download_dem_for_aoi()` empile DSM puis DTM avec un *fallback* DSM = copie du DTM, ce qui produit un CHM plat de zéro — comportement délétère pour MAESTRO ; (c) `download_mnt_for_aoi()` (MNT seul, 1 m, ré-échantillonné à 0,2 m) doit être supprimé : la modalité `dem` de MAESTRO attend deux canaux. | `curl`, `terra`, `sf`, `fs`, `.ign_config` |
| `download_sentinel.R` | KEEP/REFACTOR | Bon socle : recherche STAC `planetarycomputer.microsoft.com`, signing automatique via `rstac::sign_planetary_computer`, composite médian par bande, conversion S1 dB. À retoucher : (a) tolérance plus fine au cloud (`s2cloudless`), (b) sortie en **série temporelle** plutôt qu'en composite médian quand la modalité MAESTRO `s2` natif attend des séries, (c) gestion des sous-bbox quand l'AOI dépasse une tuile MGRS. | `rstac`, `terra`, `sf` |
| `combine.R` | REWRITE | `combine_rvb_irc()` reste utile (RGBI à 4 canaux). En revanche `combine_rgbi_mnt()` qui empile RGBI + MNT en un cube **5 canaux unique** est incompatible avec MAESTRO : le modèle attend des modalités séparées (aerial 4 canaux, dem 2 canaux, patches embedded indépendamment). Cette fonction doit être supprimée et remplacée par un dictionnaire de modalités passé au DataLoader. `aligner_dem_sur_rgbi()` est conservé (resample `terra::resample`). | `terra` |
| `essences.R` | REWRITE | **Bug majeur**. La table `essences_pureforest()` est décalée à partir du code 4 : code 4 doit être *Robinier* (Black locust, *Robinia pseudoacacia*) et non *Pin maritime*. La classe Robinier manque, la classe « Peuplier » qui n'existe pas dans PureForest est ajoutée à tort à la fin (code 12 = *Douglas*, pas *Populus*). La table officielle (fiche dataset Hugging Face `IGNF/PureForest`, voir §1.4) liste 13 classes : `Deciduous oak, Evergreen oak, Beech, Chestnut, Black locust, Maritime pine, Scotch pine, Black pine, Aleppo pine, Fir, Spruce, Larch, Douglas`. La proportion `train` reportée est respectivement 22,9/16,8/10,1/4,8/2,4/6,6/16,4/6,3/5,8/0,14/3,7/3,7/0,2 %. La fonction `essences_treesatai()` (7 classes) doit également disparaître au profit du mapping officiel TreeSatAI 20 → groupes que l'utilisateur souhaite. | aucune |
| `patches.R` | REWRITE | Trois bugs structurels. (a) `creer_grille_patches()` ouvre une grille de pas 50 m alors que MAESTRO attend des fenêtres compatibles avec ses `patch_size.mae` ; le pas doit dériver de la configuration du modèle (51,2 m si on retient 256×256 px @ 0,2 m, voir §2). (b) `extraire_patches_raster()` force un échantillonnage à 250 px par patch ; **250 n'est pas multiple de 16** (`patch_size.mae` du module `aerial`), ce qui crashe la couche `Conv2d(stride=16)` ou produit un padding silencieux. (c) `taille_patch_modalite()` câble 5 px pour les modalités Sentinel : `5` n'est pas multiple de `patch_size.mae=2`. Tout ce module doit être réécrit autour d'une matrice de spécifications par modalité, alignée sur la config Hydra de MAESTRO. | `sf`, `terra` |
| `pipeline.R` | REWRITE | `maestro_pipeline()` orchestre une chaîne dont chaque maillon est cassé : il appelle `combine_rgbi_mnt()` (modalité fausse), une grille à 250 px (taille fausse), `executer_inference_multimodal()` avec un dictionnaire de patches dont la forme ne correspond pas à `inputs` du modèle Python. La mention `n_classes = 7L` par défaut est incohérente avec la promesse « 13 classes PureForest » du README. À refaire en suivant le contrat MAESTRO : `dict[str, Tensor (B,C,H,W)]` par modalité avec dimensions cohérentes. | tous les autres modules |
| `inference.R` | REFACTOR | `executer_inference()` (legacy, mono-raster) n'est plus utile : la garder serait redondant avec la version multimodale. `executer_inference_multimodal()` est sur la bonne voie mais souffre de transpositions nombreuses (`aperm` 4D ré-itéré). Remplacer par un encodage direct des modalités en tenseurs (C, H, W) côté Python. `configurer_python()` est correct (auto-détection conda, fallback `RETICULATE_PYTHON`). | `reticulate`, modules Python |
| `model.R` | KEEP | `telecharger_modele()`, `find_checkpoint_name()`, `reparer_symlink_hf()` sont propres et utiles ; les conserver tels quels. La résolution de blob HF Windows (`reparer_symlink_hf`) sert pour le cas Windows sans privilèges développeur. | `hfhub`, `curl`, `jsonlite` |
| `export.R` | KEEP | `assembler_resultats()` (jointure prédictions ↔ grille, écriture GPKG + CSV) et `creer_carte_raster()` (rasterisation `terra::rasterize`) restent valables une fois le mapping des classes corrigé (cf. `essences.R`). | `sf`, `terra` |
| `finetune.R` | DELETE | Toute la logique TreeSatAI (download Zenodo, extraction zip, organisation `train/test/<species>`, mapping 20 → 7) sera obsolète dès qu'on cible PureForest comme dataset principal. Le code `download_treesatai()` peut être archivé sous `inst/legacy/` mais n'a plus sa place dans le NAMESPACE. | `hfhub`, `curl`, `utils` |
| `flair_pipeline.R`, `flair_inference.R`, `flair_classes.R`, `flair_download.R`, `flair_analysis.R` | KEEP | Pipeline FLAIR (segmentation occupation du sol) sans rapport direct avec MAESTRO. Le garder isolé. Pertinent comme étape de pré-filtrage (cf. §7) pour masquer les zones non forestières avant l'inférence MAESTRO. | `terra`, `sf`, modules Python FLAIR |
| `spectral_indices.R` | KEEP | NDVI/GNDVI/SAVI utilitaires, optionnels. | `terra` |
| `zzz.R` | REFACTOR | La config `.ign_config` doit refléter la nouvelle stratégie LiDAR (couches MNS et MNH, ou téléchargement direct LAZ + dérivation locale). | base |

### 1.2 Code Python (`inst/python/`)

| Fichier | Statut | Justification |
|--------|--------|---------------|
| `maestro_inference.py` | REFACTOR | Architecture `MAESTROModel` reconstruite à la main (PatchifyBands + Attention + FF + TransformerEncoder), `embed_dim=768, encoder_depth=9, inter_depth=3, num_heads=12`, modalités complètes. Charge correctement le checkpoint `pretrain-epoch=99.ckpt`. À simplifier : (a) `predire_batch_from_values()` essaie de deviner la forme à partir du nombre de canaux (`<=4`, `5`, `>=6`), ce qui casse dès qu'on a plusieurs modalités ; à remplacer par un dict explicite côté R ; (b) la normalisation `_normaliser_mnt()` min-max **par batch** est dangereuse — il faut une normalisation globale par dataset comme dans le repo MAESTRO officiel (cf. `Modality.std_norm` dans la config Hydra). |
| `maestro_finetune.py` | REWRITE | Dépendance `Dataset = TreeSatAIDataset` ; mapping 20→7 classes ; head 256→7. Le tout est à remplacer par un `PureForestDataset` qui retourne `dict[str, Tensor]` multimodal et un classifieur 13 classes. La logique d'entraînement (early stopping, class weights, cosine LR) est saine, à conserver dans le nouveau script. |
| `train_treesatai.py` | DELETE | Doublon de `maestro_finetune.py` avec un mapping 15→8 classes différent et incohérent. L'archiver. |
| `flair_inference.py` | KEEP | Module FLAIR autonome. |

### 1.3 Scripts (`inst/scripts/`)

| Script | Statut | Justification |
|--------|--------|---------------|
| `maestro_cli.R` | REFACTOR | Bon point d'entrée CLI ; à mettre à jour quand le pipeline R sera réécrit (modalités explicites, taille de patch alignée, plus de `combine_rgbi_mnt`). |
| `finetune_cli.R` | REWRITE | Cible TreeSatAI ; à remplacer par `pureforest_finetune_cli.R`. |
| `predict_from_checkpoint.R` | REFACTOR | Récupère un checkpoint TreeSatAI fine-tuné et appelle `maestro_pipeline()` avec `n_classes` lu du checkpoint. À conserver une fois la chaîne corrigée : la logique `is_finetune` qui filtre les modalités présentes dans le checkpoint reste utile. |
| `predict_treesatai.R` | DELETE | Wrapper minimal ; sera obsolète. |
| `entrainer_treesatai.R` | DELETE | Idem. |
| `cloud_train.sh`, `deploy_scaleway.sh`, `recover_model.sh`, `mount_data.sh` | REFACTOR | Tooling Scaleway encore valide (création GPU, montage volume, tmux, notifications). Le contenu de `cloud_train.sh` est cependant câblé sur `train_treesatai.py` ; il faut le rebrancher sur `pureforest_finetune.py`. Cohérence à corriger : `deploy_scaleway.sh` parle de « TreeSatAI 8 classes » alors que l'inférence locale prétend produire 13 classes PureForest (incohérence diagnostiquée par l'utilisateur). |
| `test_train_remote.sh` | DELETE | Workaround temporaire (1 epoch de test). |
| `test_pipeline.R`, `rapport_pipeline_aoi.R`, `creer_aoi_exemple.R`, `maestro_rapport.R` | KEEP | Outils de test et de rapport, sans dépendance forte sur les bugs ci-dessus. |

### 1.4 Données et artefacts (`data/`, racine)

- `data/treesatai/` (untracked) : dataset TreeSatAI extrait localement. À déplacer vers `data/external/` ou `~/.cache` et hors dépôt.
- `maestro_treesatai_best.pt` (344 Mo, racine) : checkpoint binaire au cœur du repo, à déplacer en LFS ou stockage externe. Sera **déprécié** quand le checkpoint PureForest sera produit.
- `outputs/` : produits temporaires, hors dépôt ; déjà ignoré par `.gitignore`.
- `maestro_nemeton.Rproj` (ou `maestronemeton.Rproj` selon le nom du
  répertoire local choisi par l'utilisateur après clone) : fichier RStudio,
  non tracké, à conserver.

---

## 2. Architecture cible

### 2.1 Schéma global

```
        AOI (.gpkg, Lambert-93)
                 │
                 ▼
    ┌────────────────────────────┐
    │  Préparation des modalités │
    └─┬──────┬──────┬──────┬─────┘
      │      │      │      │
      ▼      ▼      ▼      ▼
   aerial  dem   s2     s1_asc / s1_des
   (4ch,  (2ch,  (10ch, T)  (2ch, T)
   0,2 m) 0,2 m) 10 m       10 m

        IGN WMS-R          STAC Planetary
   data.geopf.fr/wms-r       Computer
   (RVB+IRC, ortho 0,2 m)   (S2 L2A, S1 RTC)

   IGN LiDAR HD              IGN Geoplateforme
   tuiles LAZ 1 km × 1 km    Couche WMS / WCS
   classifiées + dérivés     ELEVATIONGRIDCOVERAGE
   MNS + MNT IGN             HIGHRES (RGE ALTI)
   (cf. §3)
                 │
                 ▼
    ┌────────────────────────────┐
    │ Découpage en patches       │
    │ Fenêtre = 51,2 m × 51,2 m  │
    │ 256 × 256 px @ 0,2 m       │
    │ Centré sur grille AOI      │
    └─┬──────────────────────────┘
      │
      │  dict[str, Tensor (B, C, H_mod, W_mod)]
      │     aerial : (B, 4, 256, 256)
      │     dem    : (B, 2, 256, 256)
      │     s2     : (B, 10, 6, 6)        sur fenêtre 60 m × 60 m
      │     s1_asc : (B, 2, 6, 6)
      │     s1_des : (B, 2, 6, 6)
      ▼
    ┌────────────────────────────┐
    │  MAESTRO MAEbase           │
    │  embed=768, enc=9, inter=3 │
    │  patch_size.mae :          │
    │    aerial 16 (256/16=16)   │
    │    dem    32 (256/32=8)    │
    │    s2/s1   2 (6/2=3)       │
    │  + classifieur 13 classes  │
    └─┬──────────────────────────┘
      │
      ▼
    Logits (B, 13)
      │
      ▼
   GeoPackage + raster + CSV stats
```

### 2.2 Cahier des charges des modalités

Source : fiche modèle `IGNF/MAESTRO_FLAIR-HUB_base` (`config_resolved.yaml`),
fiche dataset `IGNF/PureForest`, doc IGN Géoplateforme.

| Modalité | Source | Canaux | Résolution finale | Format intermédiaire | Fenêtre patch | `patch_size.mae` | Justification taille |
|----------|--------|-------:|--------------------|----------------------|---------------|-----------------:|----------------------|
| `aerial` | IGN WMS-R `ORTHOIMAGERY.ORTHOPHOTOS[YYYY]` + `ORTHOIMAGERY.ORTHOPHOTOS.IRC.[YYYY]` | 4 (NIR, R, G, B) | 0,2 m | GeoTIFF L93, LZW | 256 × 256 px (51,2 m) | 16 | 256/16 = 16 (entier). 250 px du code actuel n'est pas multiple de 16. |
| `dem` | LiDAR HD (DSM) + RGE ALTI 1 m (DTM) ou tuiles LAZ + dérivation locale | 2 (DSM/CHM, DTM) | 0,2 m (resample bilinéaire) | GeoTIFF L93, LZW | 256 × 256 px (51,2 m) | 32 | 256/32 = 8 (entier). MAESTRO attend `patch_size.mae=32` pour `dem`. |
| `s2` | STAC Planetary Computer collection `sentinel-2-l2a` | 10 (B02, B03, B04, B05, B06, B07, B08, B8A, B11, B12) | 10 m (re-projeté L93) | GeoTIFF L93 par scène + manifeste JSON | 6 × 6 px (60 m) | 2 | 6/2 = 3. Fenêtre légèrement élargie à 60 m pour tomber sur un multiple de 2. |
| `s1_asc` | STAC Planetary Computer `sentinel-1-rtc`, filtre orbite ascending | 2 (VV, VH en dB) | 10 m | GeoTIFF L93 | 6 × 6 px (60 m) | 2 | Idem `s2`. |
| `s1_des` | Idem, descending | 2 | 10 m | GeoTIFF L93 | 6 × 6 px (60 m) | 2 | Idem `s2`. |

Cette grille reproduit la philosophie FLAIR-HUB (toutes modalités sur la
même fenêtre physique) mais à l'échelle 50 m de PureForest. Les fenêtres
Sentinel sont volontairement élargies de 50 m à 60 m pour respecter la
contrainte « multiple de `patch_size.mae=2` » sans padding artificiel.

### 2.3 Alignement spatial et temporel

- **Spatial** : tout est ramené en EPSG:2154 (Lambert-93, IGN69). L'aérien
  IGN est natif L93, le LiDAR HD aussi, Sentinel est reprojeté depuis UTM
  vers L93 par `terra::project()`. Le ré-échantillonnage `bilinear` est
  conservé pour les couches continues (DEM, Sentinel) ; on utilise `near`
  pour les classifications (FLAIR, masques).
- **Temporel** : PureForest mélange des acquisitions avec jusqu'à
  3 ans d'écart entre LiDAR et orthos (fiche HF). Hypothèses retenues :
  - aérien IGN : millésime annuel le plus récent disponible sur l'AOI
  - LiDAR HD : pas de filtrage temporel (couche unique nationale, en cours
    de remplissage 2020–2025)
  - Sentinel : composite **saisonnier** (été par défaut, mars-mai pour
    feuillaison) sur 1 à 3 années centrées sur l'année de l'aérien. La
    dérive temporelle est acceptée, MAESTRO étant entraîné à la tolérer
    (modalités multitemporelles native dans la pré-formation FLAIR-HUB).

---

## 3. Stratégie LiDAR HD

PureForest contient des nuages LiDAR HD bruts (LAS/LAZ, ~10 pulses/m²,
classification ASPRS étendue : 1 = non classé, 2 = sol, 3-5 = végétation
basse/moyenne/haute, 6 = bâtiment, 9 = eau, 17 = pont, 64 = sur-sol pérenne,
65 = artefact, 66 = point virtuel ; cf. doc IGN). L'AOI utilisateur, elle,
n'a en général que les rasters dérivés disponibles via Géoplateforme.

### 3.1 Téléchargement des tuiles LiDAR HD

Deux entrées concurrentes selon les besoins :

1. **WMS-R Géoplateforme** (`https://data.geopf.fr/wms-r`) :
   - `ELEVATION.ELEVATIONGRIDCOVERAGE.HIGHRES` : MNT 1 m issu du LiDAR HD
     là où le LiDAR HD est passé, sinon RGE ALTI historique.
   - `IGNF_LIDAR-HD_MNS_ELEVATION.ELEVATIONGRIDCOVERAGE.LAMB93` : MNS 1 m
     du LiDAR HD (couverture partielle, en cours de complétion d'ici 2026).
   - Pas de couche officielle MNH/CHM 1 m via WMS-R à ce jour ; à dériver
     localement (`CHM = MNS - MNT`).
   - Avantages : pas de dépendance Python, latence acceptable pour des AOI
     de quelques km², pas de quota.
   - Limites : 4096 px par requête (déjà géré par `download_ign_tiled()`),
     pas de retours bruts (densité de retours, hauteur médiane par pixel,
     etc.) — uniquement la surface.

2. **Tuiles LAZ via le catalogue cartes.gouv.fr / S3 IGN** :
   - URL ATOM : `https://geoservices.ign.fr/services-web-experts-altimetrie`
     redirige aujourd'hui vers `cartes.gouv.fr`. Le catalogue expose des
     ensembles de tuiles 1 km × 1 km en LAZ classifiées (~150 Mo / tuile).
   - Avantages : accès aux retours bruts, calcul de statistiques par pixel
     (densité, hauteur 95e percentile, ratio sur-sol/végétation, etc.).
   - Limites : volume (~150 Mo/km²), latence, dépendance externe.

Le pipeline doit supporter les deux modes via un argument `lidar_source ∈
{wms, las}`. Le mode WMS est la valeur par défaut pour rester équivalent au
code existant ; le mode LAS est activé pour les AOI de recherche où la
hauteur de canopée brute apporte un gain métrologique notable.

### 3.2 Outils de traitement LAZ

| Outil | Langage | Forces | Faiblesses |
|-------|--------|--------|------------|
| **`lasR`** | R + C++ (r-universe) | Pipeline déclaratif C++ ultra-rapide, multi-tuile natif (`LAScatalog` + `buffer`), normalisation **TIN** via `transform_with(dtm_tri)` plus précise que la soustraction raster. | Distribué uniquement sur r-universe (`r-lidar.r-universe.dev`), API plus jeune. |
| `lidR` | R | Idiomatique pour le pipeline R, `pixel_metrics()` complet, debug interactif facile, lecture LAZ via `rlas`. | Single-threaded sur grosses tuiles, gourmand en RAM (~6 Go pour 1 km²). |
| `PDAL` | C++/CLI | Très rapide, pipelines JSON déclaratifs, parallélisme natif. | Dépendance externe à installer, pas R-natif (interface via `system2`). |
| `whitebox` (WhiteboxTools) | Rust/CLI | Algorithmes de filtrage du sol robustes (Cloth Simulation), CHM par interpolation. | Moins idiomatique R, communauté plus petite. |

Choix recommandé :
- **Phase 2 par défaut : `lasR`**. Le pattern d'usage est documenté dans le
  tutoriel `inst/tutorials/07-lidar-advanced/07-lidar-advanced.Rmd` du dépôt
  `pobsteta/nemeton`, qui produit MNT, MNS et MNH en un seul pipeline
  déclaratif (cf. §3.3). Installation :
  ```r
  install.packages("lasR", repos = "https://r-lidar.r-universe.dev")
  ```
- `lidR` reste utile pour le **debug interactif** et les opérations point-par-point
  hors pipeline (vérification visuelle, statistiques exploratoires).
- `PDAL` ou `whitebox` ne sont à considérer que si on dépasse les capacités
  de `lasR` (contraintes mémoire spécifiques, intégration outside-R).

### 3.3 Calcul du MNT, MNS et CHM via `lasR`

Pattern de référence issu de `pobsteta/nemeton`
(`inst/tutorials/07-lidar-advanced/07-lidar-advanced.Rmd`, section 3) :

```r
library(lasR)

# 1. Triangulation TIN sur les points classés sol (classe 2)
dtm_tri <- triangulate(filter = keep_ground())
dtm     <- rasterize(1, dtm_tri, ofile = "dtm_*.tif")

# 2. Normalisation via le TIN sol (interpolation exacte par point,
#    plus précise que la soustraction raster MNS - MNT)
normalize <- transform_with(dtm_tri)

# 3. Triangulation TIN sur les premiers retours pour le MNS
chm_tri    <- triangulate(filter = keep_first())
chm        <- rasterize(0.5, chm_tri, ofile = "chm_*.tif")
chm_filled <- pit_fill(chm, ofile = "chm_filled_*.tif")

# 4. Pipeline complet, parallélisé, avec buffer pour les effets de bord
pipeline <- reader_las() + dtm_tri + dtm + normalize +
            chm_tri + chm + chm_filled
exec(pipeline, on = ctg, buffer = 20, ncores = concurrent_files(4))
```

Points clés :

- **Normalisation TIN, pas raster**. `transform_with(dtm_tri)` interpole
  l'altitude sol pour chaque point individuellement avant de le rasteriser.
  C'est plus exact que `CHM = DSM - DTM` qui propage les artefacts de
  discrétisation des deux rasters intermédiaires.
- **MNT à 1 m, MNS/CHM à 0,5 m**. Le CHM bénéficie de la résolution
  finesse pour la canopée ; le MNT n'a pas besoin de plus que 1 m. Pour
  MAESTRO on ré-échantillonne ensuite à 0,2 m pour aligner sur la grille
  aérienne.
- **`pit_fill`** corrige les puits artefactuels (trous de profondeur ≥ 1 m
  causés par la rareté des premiers retours). À conserver, gain visible
  sur les forêts denses.
- **Buffer 20 m** sur le `LAScatalog` : évite les effets de bord aux
  coupures de tuiles (diamètre maximum des houppiers en France).
- **Filtrage par classe ASPRS** :
  - sol → classe 2 (`keep_ground()`)
  - végétation haute → classes 3, 4, 5 (utilisable via
    `keep_class(c(3, 4, 5))`)
  - bâtiment → classe 6 (à exclure du MNS si on veut un MNH végétal pur)

Quand on n'a pas accès aux LAZ (utilisateur final, AOI hors couverture
LiDAR HD complet) : fallback sur les couches WMS Géoplateforme
(`IGNF_LIDAR-HD_MNS_...` + `ELEVATION.ELEVATIONGRIDCOVERAGE.HIGHRES`),
qui sont elles-mêmes dérivées d'un pipeline équivalent côté IGN. La
modalité `dem` MAESTRO accepte les deux sources de manière transparente.

La modalité `dem` de MAESTRO peut être renseignée selon trois schémas
d'arbitrage à valider expérimentalement (cf. §9) :

1. `(DSM, DTM)` brut, normalisé min-max global (config par défaut FLAIR-HUB,
   le modèle « apprend » la différence).
2. `(CHM, DTM)` — variable de canopée explicite, plus interprétable.
3. `(CHM, density)` — où `density` = nombre de retours par pixel,
   uniquement disponible en mode LAS.

Recommandation Phase 2 : commencer par schéma 1 (équivalent à FLAIR-HUB),
ajouter le schéma 2 en ablation Phase 4. Le schéma 3 reste en R&D (LAS only).

### 3.4 Statistiques LiDAR optionnelles

Si on dispose des tuiles LAZ (mode `las`), on calcule par pixel 0,2 m × 0,2 m
au moins :
- `n_returns` : nombre total de retours (densité)
- `h_max` : hauteur max au-dessus du sol
- `h_mean`, `h_p95` : moyenne et 95e percentile des retours végétation
- `pct_canopy` : % de retours classés végétation haute / total

Ces canaux peuvent être empilés dans une modalité custom `lidar_stats` qui
sortirait du périmètre MAESTRO standard. Ne pas les intégrer en Phase 2 ;
les évaluer en Phase 4 comme **modalité auxiliaire** dans une variante
`MAESTRO + extra-modality` (extension du `patch_embed` ModuleDict).

### 3.5 Réalignement aux patches

Le patch MAESTRO `aerial` fait 256 × 256 px à 0,2 m (51,2 m × 51,2 m). Le
DEM (DSM, DTM) doit être ré-échantillonné sur **la même grille** (même
`terra::ext`, même `res`, même `crs`). Le code actuel `aligner_dem_sur_rgbi`
fait déjà ce travail correctement ; à réutiliser tel quel.

---

## 4. Augmentation de PureForest avec Sentinel

PureForest (`IGNF/PureForest`) ne contient nativement que :
- aérien IGN 4 bandes (NIR, R, G, B), 0,2 m, 250 × 250 px ;
- nuage LiDAR HD classifié (LAZ).

Pour fine-tuner MAESTRO multimodal, il faut **augmenter chaque patch** avec
des modalités Sentinel. Stratégie :

### 4.1 Extraction Sentinel par STAC sur les empreintes des patches

- Récupérer la géométrie de chaque patch PureForest (centre + emprise 50 m)
  et la liste de ses années d'acquisition (champ `metadata.year_aerial`,
  `metadata.year_lidar` quand disponible — sinon aérien comme référence).
- Pour chaque patch, requête STAC Planetary Computer :
  - bbox WGS84 issu de la géométrie L93 → WGS84
  - intervalle `datetime` = saison cible (mars-octobre par défaut)
  - filtre couverture nuageuse < 30 % pour S2
  - signing automatique `rstac::sign_planetary_computer`

Le code existant (`search_s2_stac`, `search_s1_stac`,
`build_date_ranges`) est réutilisable ; il faut juste le batchifier sur
135 569 patches (`group_by tile S2 + jour`) pour limiter le nombre de
requêtes. Ordre de grandeur : ~5 000 scènes Sentinel-2 distinctes pour
couvrir la France métropolitaine sur 3 ans.

### 4.2 Composite saisonnier vs série temporelle complète

| Approche | Forme du tenseur | Pour | Contre |
|----------|------------------|------|--------|
| **Composite médian saisonnier** (1 image par saison ou par année) | `(B, C, H, W)` | Simple, peu volumineux, robuste aux nuages, suit le code existant. | Perd la phénologie qui distingue feuillus / résineux et notamment Mélèze (caduc) vs Douglas (sempervirent). |
| **Série temporelle** (10–12 dates par an, ré-échantillonnée à un pas régulier) | `(B, T, C, H, W)` | C'est ce que MAESTRO attend pour `s2` / `s1_asc` / `s1_des` (modèle multitemporel) ; meilleure performance attendue sur les classes à phénologie distincte. | Volume × T, gestion des nuages plus délicate, encodeur temporel à activer dans la config Hydra (`temporal_encoding`). |

Décision Phase 1 : **composite médian saisonnier été (juin-septembre)**
à 1 image par patch. Décision Phase 3 : passage à la **série temporelle**
mensuelle pour exploiter pleinement la dimension `T` de MAESTRO. La
fonction `calculer_composite_median()` reste utile, mais on lui ajoute un
mode `output = "stack"` qui empile les scènes dans un axe T au lieu de
calculer la médiane.

### 4.3 Gestion du décalage temporel

PureForest indique pour chaque patch les années LiDAR et orthos, qui
peuvent différer jusqu'à 3 ans. Règles retenues :
- Année référence Sentinel = `year_aerial` quand disponible, sinon
  `year_lidar`.
- Si pas de scène S2 satisfaisante sur ±1 an, élargir à ±2 ans avec
  cloud cover ≤ 50 %.
- Si rien sur 5 ans : patch marqué `s2 = NA` ; MAESTRO accepte les
  modalités absentes (`mod_token` → ignoré dans `forward()`), pas besoin
  de masquage explicite.

### 4.4 Format de sortie

Pour rester compatible avec le DataLoader MAESTRO :
- aerial : `<patch_id>_aerial.tif` (4 bandes float32 normalisées 0..1)
- dem : `<patch_id>_dem.tif` (2 bandes float32, normalisées zscore par
  dataset)
- s2 : `<patch_id>_s2.tif` ou `.npy` (10 bandes float32, ou `(T, 10, 6, 6)`
  pour la série temporelle, normalisées 0..1)
- s1_asc / s1_des : `<patch_id>_s1_asc.tif` (2 bandes en dB)
- label : un fichier global `labels.csv` ou `.parquet` à 3 colonnes
  (`patch_id, class_code (0-12), split`) — split issu du fichier officiel
  PureForest.

Le tout sous une racine de dataset structurée comme :

```
data/pureforest_maestro/
  splits/
    train.txt        ← liste des patch_id
    val.txt
    test.txt
  patches/
    <patch_id>/
      aerial.tif
      dem.tif
      s2.tif
      s1_asc.tif
      s1_des.tif
  labels.parquet
  metadata.parquet   ← year_aerial, year_lidar, forest_id, geometry_l93
```

---

## 5. DataLoader PureForest pour MAESTRO

### 5.1 Contrat MAESTRO

D'après la fiche modèle `IGNF/MAESTRO_FLAIR-HUB_base` et le README du
dépôt `IGNF/MAESTRO`, un dataset MAESTRO :

- s'enregistre via Hydra dans `conf/datasets/<nom>.yaml` ;
- est sélectionné par `datasets.name_dataset=<nom>` ;
- fournit une classe Python qui hérite d'une `BaseDataset` (à inspecter en
  Phase 1 dans le fork local) ;
- retourne par `__getitem__` un dict `(inputs, target)` où `inputs` est un
  `dict[str, Tensor]` keys ⊆ `{aerial, dem, spot, s2, s1_asc, s1_des}` ;
- supporte le filtrage des modalités via
  `datasets.<nom>.filter_inputs=[aerial,s2,s1_asc,s1_des]` ;
- expose les statistiques de normalisation (mean / std par canal) dans la
  config Hydra ; la normalisation est appliquée par le DataLoader, pas
  côté modèle.

### 5.2 Différence mono-label vs multi-label

- **TreeSatAI-TS** (config existante) : multi-label (proportions de genres
  agrégées en vecteur) ; loss = `BCEWithLogitsLoss`.
- **PureForest** : **mono-label** (1 classe par patch, label entier 0..12) ;
  loss = `CrossEntropyLoss` avec poids de classe pour gérer le déséquilibre
  (fir = 0,14 % en train).

Le nouveau dataset doit signaler `task_type = "single_label_classification"`
et exposer `n_classes = 13`.

### 5.3 Fichiers à créer dans un fork de MAESTRO

Parcours minimal à valider en Phase 1 :

```
maestro/                              ← fork de IGNF/MAESTRO
  conf/
    datasets/
      pureforest.yaml                 ← nouveau
    experiment/
      pureforest_finetune.yaml        ← nouveau, hérite de treesatai_ts_finetune
  maestro/datasets/
    pureforest.py                     ← nouveau, classe PureForestDataset
    __init__.py                       ← register PureForestDataset
```

Squelette `pureforest.yaml` (pseudo-code Hydra) :

```yaml
# conf/datasets/pureforest.yaml
name: pureforest
class_path: maestro.datasets.pureforest.PureForestDataset
root_dir: ${oc.env:MAESTRO_DATA_ROOT}
rel_dir: pureforest_maestro
n_classes: 13
task_type: single_label_classification
filter_inputs: [aerial, dem, s2, s1_asc, s1_des]

modalities:
  aerial:
    in_channels: 4
    image_size: 256
    resolution: 0.2
    patch_size: { mae: 16 }
    norm: { mean: [...], std: [...] }   # à calculer sur le train
  dem:
    in_channels: 2
    image_size: 256
    resolution: 0.2
    patch_size: { mae: 32 }
    norm: { mean: [...], std: [...] }
  s2:
    in_channels: 10
    image_size: 6
    resolution: 10
    patch_size: { mae: 2 }
    norm: { mean: [...], std: [...] }
  s1_asc: { in_channels: 2, image_size: 6, resolution: 10, patch_size: {mae: 2} }
  s1_des: { in_channels: 2, image_size: 6, resolution: 10, patch_size: {mae: 2} }
```

Squelette `PureForestDataset.__getitem__` (pseudo-code) :

```python
def __getitem__(self, idx):
    patch_id = self.patch_ids[idx]
    inputs = {
        "aerial": self._load_tif(f"{patch_id}/aerial.tif"),  # (4, 256, 256)
        "dem":    self._load_tif(f"{patch_id}/dem.tif"),     # (2, 256, 256)
        "s2":     self._load_tif(f"{patch_id}/s2.tif"),      # (10, 6, 6)
        "s1_asc": self._load_tif(f"{patch_id}/s1_asc.tif"),  # (2, 6, 6)
        "s1_des": self._load_tif(f"{patch_id}/s1_des.tif"),  # (2, 6, 6)
    }
    inputs = {k: v for k, v in inputs.items() if k in self.filter_inputs}
    inputs = self._normalize(inputs)
    target = self.labels[idx]                                # int 0..12
    return inputs, target
```

### 5.4 Splits

Réutiliser la stratification officielle PureForest **au niveau forêt**
(449 forêts → 70/15/15 stratifié sur le label). Importer les fichiers
`splits/train.txt`, `splits/val.txt`, `splits/test.txt` qu'on aura
construits depuis le dataset HF (champ `split` dans le parquet officiel).
Ne **jamais** ré-échantillonner en aléatoire patch-level : cela introduit
de la fuite spatiale puisque les patches d'une même forêt partagent souvent
le même peuplement.

### 5.5 Statistiques de normalisation

À calculer une fois sur le split `train` du dataset pré-traité, par canal,
par modalité, en ignorant les NA et les valeurs hors quantile 1–99 % :

```
mean[aerial] = [μ_R, μ_G, μ_B, μ_NIR]
std[aerial]  = [σ_R, σ_G, σ_B, σ_NIR]
mean[dem]    = [μ_DSM, μ_DTM]
std[dem]     = [σ_DSM, σ_DTM]
mean[s2]     = [μ_B02, ..., μ_B12]
...
```

Stocker dans `conf/datasets/pureforest.yaml` (champ `modalities.<m>.norm`).
Cette normalisation **doit** correspondre à celle utilisée pour le pré-train
FLAIR-HUB : si écart fort, on observera une chute brutale de la métrique
de validation au début du fine-tuning. À monitorer.

---

## 6. Plan de fine-tuning

### 6.1 Étapes

Suivre la pratique MAESTRO (commande TreeSatAI-TS de la fiche HF) :

1. **Linear probe** : encodeur figé, head 13 classes entraînée seule.
   - LR head = 1e-3, 10 epochs, AdamW, weight_decay = 1e-4.
   - Sert à valider que le wiring (DataLoader, modalités, stats) est correct.
   - Métrique cible : `balanced_accuracy_val` ≥ 0,55 (sinon il y a un bug
     de normalisation ou d'alignement modalité).
2. **Fine-tune complet** : encodeur dégelé, LR différentielle (encodeur
   1e-5, head 1e-4), 50 epochs, scheduler cosine, early stopping patience
   = 5 sur `balanced_accuracy_val`.
3. **Évaluation finale** sur le split `test` officiel (52 935 patches).

Cette structure est cohérente avec la commande de la fiche modèle :

```
opt_pretrain.epochs=0 opt_probe.epochs=10 opt_finetune.epochs=50
opt_probe.batch_size=24 opt_finetune.batch_size=24
opt_finetune.monitor=pureforest/balanced_accuracy_val
```

### 6.2 Hyperparamètres de départ

| Param | Valeur | Source |
|-------|--------|--------|
| Optimiseur | AdamW | MAESTRO TreeSatAI-TS |
| LR encoder fine-tune | 1e-5 | TreeSatAI-TS |
| LR head | 1e-4 (fine-tune) / 1e-3 (probe) | TreeSatAI-TS |
| Weight decay | 1e-4 | TreeSatAI-TS |
| Batch size | 24 (L4 24 Go) ou 64 (H100 80 Go) | Doc Scaleway |
| Epochs probe | 10 | TreeSatAI-TS |
| Epochs fine-tune | 50 | TreeSatAI-TS |
| Scheduler | CosineAnnealingLR | `train_treesatai.py` actuel |
| Augmentations | Flip H/V, rotations 90°, jitter radiométrique léger | À valider |
| Class weights | inverse frequency normalisée sur train | TreeSatAI-TS |
| Loss | CrossEntropy avec poids | mono-label |

### 6.3 Métriques à logger

- **Overall accuracy** (proportion de patches correctement classés). Biaisé
  par la classe dominante (Deciduous oak 22,9 % en train).
- **Balanced accuracy** (moyenne de la précision par classe, ignore le
  déséquilibre). Métrique principale.
- **F1 macro** (moyenne harmonique précision/rappel par classe puis
  moyenne).
- **Matrice de confusion** par essence, à exporter en CSV à la fin de
  l'entraînement.
- Cas particulier : la classe `Fir` (Sapin) est sous-représentée à 0,14 %
  en train mais 5,32 % en val (cf. §1.4) ; tracer F1(Sapin) séparément
  est utile pour détecter le surapprentissage.

### 6.4 Déploiement Scaleway

| Instance | VRAM | Coût indicatif | Durée estimée (50 epochs PureForest probe+fine, batch 24) |
|----------|------|----------------|----------------------------------------------------------|
| `GPU-3070-S` | 8 Go | ~0,76 €/h | Probablement insuffisant pour le multi-modal complet (out-of-memory à batch 24). |
| `L4-1-24G` | 24 Go | ~0,92 €/h | ~12–18 h pour 60 epochs sur 70 k patches multimodal. Coût total ~12–18 €. |
| `H100-1-80G` | 80 Go | ~3,50 €/h | ~3–4 h, batch 64. Coût total ~12–14 €. |

Recommandation par défaut : **L4-1-24G** (le `deploy_scaleway.sh` actuel
prend déjà cette valeur). Passage à H100 pour les ablations Phase 4.
Volume `data` 100 Go suffit pour PureForest pré-traité (~50 Go aerial +
~10 Go dem + ~5 Go Sentinel composite).

---

## 7. Pipeline d'inférence

### 7.1 Pseudocode du nouveau `maestro_pipeline()`

```r
maestro_pipeline <- function(aoi_path, output_dir = "outputs",
                              checkpoint = NULL,
                              modalities = c("aerial", "dem", "s2",
                                             "s1_asc", "s1_des"),
                              window_size_m = 51.2,
                              gpu = FALSE) {
  aoi <- load_aoi(aoi_path)

  # 1. Téléchargement par modalité, indépendant
  rasters <- list()
  if ("aerial" %in% modalities) {
    rasters$aerial <- download_aerial(aoi, output_dir)   # RGBI 4 bandes 0,2 m
  }
  if ("dem" %in% modalities) {
    rasters$dem <- prepare_dem(aoi, output_dir,
                                source = "wms")           # DSM+DTM 2 bandes
  }
  if ("s2" %in% modalities) {
    rasters$s2 <- download_s2_for_aoi(aoi, output_dir)    # 10 bandes 10 m
  }
  if ("s1_asc" %in% modalities || "s1_des" %in% modalities) {
    s1 <- download_s1_for_aoi(aoi, output_dir)
    rasters$s1_asc <- s1$s1_asc
    rasters$s1_des <- s1$s1_des
  }

  # 2. Grille de patches — fenêtre 51,2 m, alignée au coin SW de l'AOI
  grille <- creer_grille_patches(aoi, window_size_m)

  # 3. Extraction multi-modale, dimensions par modalité
  specs <- modalite_specs()  # 256 px aerial/dem, 6 px s2/s1
  patches <- extraire_patches_multimodal(rasters, grille, specs)

  # 4. Inférence MAESTRO multi-modale
  predictions <- executer_inference_multimodal(
    patches, modalites = modalities, gpu = gpu, checkpoint = checkpoint
  )

  # 5. Export
  essences <- essences_pureforest()  # version corrigée 13 classes
  resultats <- assembler_resultats(grille, predictions,
                                    essences = essences,
                                    dossier_sortie = output_dir)
  carte <- creer_carte_raster(resultats, resolution = 0.2,
                               dossier_sortie = output_dir)

  invisible(list(grille = resultats, raster = carte))
}
```

### 7.2 Découpage en patches 51,2 m × 51,2 m

`creer_grille_patches()` doit être paramétrée par la `window_size_m` exacte
(51,2 m si on choisit 256 px à 0,2 m). Aucune division par 50 m fixe.
Optionnellement, prévoir un **overlap** (par défaut 0 ; 32 px = 6,4 m
recommandé pour atténuer les artefacts de bord en mode segmentation
post-process).

### 7.3 Mapping de classes corrigé

Voir §1.1 ligne `essences.R` : la nouvelle table doit être :

| Code | Classe (PureForest) | Latin |
|------|--------------------|-------|
| 0 | Chêne décidu | *Quercus robur*, *Q. petraea*, *Q. pubescens* |
| 1 | Chêne vert | *Quercus ilex* |
| 2 | Hêtre | *Fagus sylvatica* |
| 3 | Châtaignier | *Castanea sativa* |
| 4 | Robinier | *Robinia pseudoacacia* |
| 5 | Pin maritime | *Pinus pinaster* |
| 6 | Pin sylvestre | *Pinus sylvestris* |
| 7 | Pin noir | *Pinus nigra* |
| 8 | Pin d'Alep | *Pinus halepensis* |
| 9 | Sapin | *Abies alba* |
| 10 | Épicéa | *Picea abies* |
| 11 | Mélèze | *Larix decidua*, *L. kaempferi* |
| 12 | Douglas | *Pseudotsuga menziesii* |

Source : fiche dataset HF `IGNF/PureForest`. La table actuelle décale les
codes 4–12 et invente une classe Peuplier qui n'existe pas dans le dataset.

### 7.4 Sorties

- `essences_forestieres.tif` : raster L93 0,2 m, valeurs 0..12.
- `essences_forestieres.gpkg` : grille des patches avec colonnes
  `code_essence, classe, latin, type, score_max, score_top3`.
- `statistiques_essences.csv` : fréquence et surface par essence.
- `confidence.tif` : raster du `softmax_max` par patch, utile pour le
  filtrage downstream (zones où le modèle hésite).
- Pré-filtrage optionnel : appliquer FLAIR pour masquer toute classe non
  forestière (Bâtiment, Eau, Sol nu, Culture, Vigne). Géré par
  `flair_pipeline()` puis intersection raster post-MAESTRO.

---

## 8. Phasage

Quatre phases, chacune avec un critère de sortie observable et un
livrable testable. Pas de dépendance circulaire entre phases.

### Phase 0 — Corrections critiques (1 sprint)

Objectif : remettre le pipeline existant **dans un état cohérent**, sans
changement architectural, pour ne plus produire des résultats faussement
plausibles.

Tâches :
- Corriger la table `essences_pureforest()` (Robinier ajouté, Peuplier
  retiré, ordre Sapin/Épicéa, Pin laricio renommé Pin noir).
- Aligner toutes les valeurs `n_classes` dans `pipeline.R`,
  `executer_inference()`, `executer_inference_multimodal()` à 13 par défaut.
- Corriger `patch_size = 250L` → `256L` ou `240L` selon l'image cible.
  `taille_patch_modalite()` retourne 16, 32 ou 6 selon la modalité, pas une
  valeur magique 5.
- Aligner les noms de scripts et de checkpoints :
  `predict_treesatai.R`, `entrainer_treesatai.R`, `train_treesatai.py`
  archivés sous `inst/legacy/`. Référencer `pureforest_*` dans la doc.
- Mettre à jour le README pour refléter la table 13 classes correcte et
  enlever la mention « TreeSatAI 8 classes » dans `deploy_scaleway.sh`.

Critère de sortie :
- Test unitaire de `essences_pureforest()` qui vérifie 13 lignes,
  présence de Robinier au code 4, absence de Peuplier.
- `Rscript inst/scripts/test_pipeline.R` passe sur un mini-AOI sans
  erreur de dimension.

### Phase 1 — MVP `aerial` seul, fine-tune PureForest (2–3 sprints)

Objectif : un modèle MAESTRO fine-tuné PureForest, **mono-modal aerial**,
qui produit 13 classes avec un score baseline.

Tâches :
- Réécrire `extraire_patches_multimodal()` autour de specs par modalité.
- Pré-traiter PureForest pour générer `data/pureforest_maestro/` avec les
  images aerial à 256×256 px et les labels mono-classe.
- Ajouter le DataLoader `PureForestDataset` dans le fork MAESTRO local.
- Écrire `pureforest_finetune.py` (linear probe puis fine-tune complet),
  réutilisant la mécanique d'entraînement de `maestro_finetune.py`.
- Lancer 1 run sur Scaleway L4-1-24G, sauvegarder le `*.pt` et la matrice
  de confusion.
- Réécrire `maestro_pipeline()` pour appeler ce checkpoint sur une AOI
  réelle (sans modalités Sentinel).

**Statut réel (mis à jour Phase 2)** :

L'infrastructure (DataLoader, script de fine-tune, CLI Scaleway, pipeline R
inférence) a été livrée dans la première itération du commit
`5a32cc5`. Mais le pré-traitement `prepare_pureforest_aerial.py` reposait
sur `datasets.load_dataset("IGNF/PureForest")`, ce qui ne marche pas :
le dataset HF n'est pas formaté en parquet/arrow, c'est une collection de
36 ZIP files (`data/imagery-<species>.zip` × 18 et `data/lidar-<species>.zip` × 18)
plus `metadata/PureForest-patches.csv`. **Aucun fine-tune n'a donc été
effectivement lancé.** Le ticket P1-03 a été refait au début de Phase 2
pour télécharger les ZIP via `hf_hub_download`, parser le CSV pour les
splits/labels, et extraire les patches en `patches/<id>/aerial.tif`.
Smoke test validé localement sur Quercus_rubra (20 patches, 12 Mo).

Tickets P1-03 et P1-07 restent donc à valider en run réel avant de
considérer Phase 1 terminée. Phase 2 peut néanmoins avancer en parallèle
sur P2-03 (`prepare_pureforest_dem.py`) puisque l'architecture du nouveau
preprocessing aerial sert de patron.

Critère de sortie :
- `balanced_accuracy_test ≥ 0.50` (à confirmer comme cible réaliste à
  partir des baselines du papier PureForest).
- Pipeline R complet AOI → carte sans erreur, sans warnings sur
  dimensions de patch.

### Phase 2 — Modalité `dem` via CHM LiDAR HD (2 sprints)

Objectif : intégrer la hauteur de canopée comme seconde modalité MAESTRO.

Tâches :
- Implémenter `prepare_dem(aoi, source="wms")` qui construit `(DSM, DTM)`
  à partir des couches Géoplateforme, gère les zones non couvertes par
  LiDAR HD avec un fallback RGE ALTI 1 m + warning.
- Implémenter `prepare_dem(aoi, source="las")` (lecture LAZ via `lasR`,
  pipeline `triangulate(keep_ground)` + `transform_with(dtm_tri)` +
  `triangulate(keep_first)` + `pit_fill`, cf. §3.3) en mode optionnel.
- Lors du pré-traitement PureForest : générer le DEM de chaque patch à
  partir des nuages LAZ fournis avec PureForest (déjà disponibles, pas de
  téléchargement supplémentaire). Laisser un script `prepare_pureforest_dem.py`
  reproductible.
- Ajouter la modalité dans `pureforest.yaml`, relancer fine-tune.
- Comparer A/B avec la baseline aerial seul : ablation publiée dans le
  rapport interne.

Critère de sortie : gain ≥ 5 points de balanced accuracy sur les classes
résineuses sombres (Sapin, Épicéa, Douglas) où le CHM est le plus
discriminant.

### Phase 3 — Modalités Sentinel S2 puis S1 (2–3 sprints)

Objectif : ajouter les modalités Sentinel pour exploiter MAESTRO complet.

Tâches :
- Pré-traiter PureForest pour générer les composites Sentinel-2 saisonniers
  (été par défaut), batch STAC à grande échelle (~135 k patches,
  parallélisable).
- Ajouter `s2` au DataLoader, relancer fine-tune.
- Idem `s1_asc` puis `s1_des`. Couplage MAESTRO complet en dernier.
- Évaluer l'apport de chaque modalité (ablation) sur 4 sous-ensembles :
  feuillus, résineux clairs, résineux sombres, espèces rares
  (Sapin/Robinier).
- Optionnel : passer du composite à la **série temporelle** (modalité
  `s2_ts`) si gain non négligeable et VRAM disponible.

Critère de sortie : matrice de confusion stabilisée, F1 macro ≥ 0,55,
modèle final disponible sur Hugging Face (organisation utilisateur).

### Phase 4 — Optimisation, ablations, robustesse (1–2 sprints)

Objectif : diagnostiquer et fiabiliser le modèle pour usage opérationnel.

Tâches :
- Ablations : composite vs série temporelle pour Sentinel ; CHM seul vs
  CHM+stats LiDAR ; tailles de fenêtre 50,8 / 51,2 / 60 m.
- Tests croisés : application aux régions FRANCE entière hors PureForest
  (quelques AOI tests dans le Massif Central, le Nord, la Corse).
- Tests adversariaux : robustesse aux saisons hors été, aux orthos
  millésimées différentes.
- Optimisation inférence : batchage, fp16, ONNX si pertinent.
- Documentation utilisateur (vignette R Markdown).

Critère de sortie : rapport d'évaluation, modèle versionné v1.0, vignette
publique sur GitHub.

---

## 9. Risques et points ouverts

### 9.1 Risques techniques

| Risque | Impact | Mitigation |
|--------|--------|------------|
| Incompatibilité de versions PyTorch / safetensors entre Windows local et Linux Scaleway | Crash au chargement du checkpoint | Bloquer `torch==2.5.x`, `safetensors==0.4.x` dans `requirements.txt`. |
| Mémoire GPU insuffisante en multi-modal complet (PureForest + Sentinel TS) | OOM en train | Démarrer batch 8 puis ajuster ; activer gradient checkpointing dans MAESTRO si besoin (param Hydra). |
| Latence STAC Planetary Computer sur 135 k requêtes | Pré-traitement lent (jours) | Batchifier par tuile MGRS, paralléliser sur plusieurs workers, cacher localement, ne signer qu'une fois par scène. |
| Décalage de normalisation entre pré-train FLAIR-HUB et fine-tune PureForest | Effondrement de précision dès l'epoch 1 | Recalculer mean/std du train PureForest et les coller dans `pureforest.yaml` ; comparer aux stats FLAIR-HUB. |
| Bug silencieux des patches non-multiples de `patch_size.mae` | Padding implicite et fuite de signal | Tester unitairement les dimensions au chargement (`assert H % 16 == 0`). |
| Couverture LiDAR HD partielle 2026 (en cours de complétion) | DSM manquant sur certaines AOI utilisateurs | Fallback explicite RGE ALTI + warning dans `prepare_dem()`. |
| Perte de blob HF (Windows symlinks cassés) | Échec du téléchargement modèle | `reparer_symlink_hf()` et `_resoudre_chemin_hf()` actuels couvrent le cas, à conserver. |

### 9.2 Dépendances externes

- **Géoplateforme IGN** : pas de quota officiel pour le WMS-R public mais
  bonnes pratiques (ne pas dépasser 4096 px, retry exponentiel) ;
  documenté dans `download_ign.R`.
- **Indispo de tuiles LiDAR HD** : couverture nationale en cours
  (~90 % France métropolitaine attendu fin 2026). Sur AOI hors couverture,
  fallback `dem = (RGE ALTI 1 m, RGE ALTI 1 m)` avec un canal DSM=DTM —
  qui annule la modalité, mais ne casse pas le pipeline.
- **Rate limits Planetary Computer** : pas de limite documentée sur
  l'usage anonyme, mais recommandé d'utiliser un compte gratuit pour
  bénéficier de quotas explicites. Signing manuel disponible si bascule
  vers Copernicus DataSpace Ecosystem (CDSE).
- **Hugging Face** : gros checkpoints (≥ 300 Mo), résolution de symlinks
  problématique sous Windows ; déjà géré.

### 9.3 Décisions à arbitrer

Aucune ne bloque la Phase 0 ni la Phase 1.

| Décision | Options | Critère d'arbitrage |
|----------|---------|---------------------|
| Schéma `dem` | (DSM, DTM) | (CHM, DTM) | (CHM, density) | Mesurer les trois en Phase 4 ; recommandation initiale (DSM, DTM) pour rester aligné FLAIR-HUB. |
| Format Sentinel | composite saisonnier | série temporelle | Phase 3 : commencer composite ; passer en TS si gain de F1 macro > 3 points et VRAM disponible. |
| Fenêtre patch | 51,2 m (256 px @ 0,2 m) | 60 m (300 px @ 0,2 m) | 51,2 m est plus simple (entier de 16/32) ; 60 m colle mieux aux 60 m TreeSatAI mais oblige à un padding aérien. Trancher en Phase 1 sur la base d'un test à blanc. |
| Source LiDAR | WMS Géoplateforme seul | LAZ direct + dérivation | WMS suffit pour PureForest pré-traité (les LAZ sont déjà fournis) ; LAZ direct utile uniquement pour les AOI utilisateurs en mode `lidar_source = las`. |
| Nb classes inférence | 13 (PureForest natif) | 13 + classe « non forêt » | Dépend du pipeline FLAIR : si FLAIR pré-filtre, garder 13 ; sinon ajouter une 14e classe « hors forêt ». |

---

## 10. Backlog priorisé

### Tickets Phase 0

| ID | Titre | Phase | T-shirt | Fichiers / modules impactés |
|----|-------|-------|---------|-------------------------------|
| P0-01 | Corriger la table des 13 classes PureForest | P0 | S | `R/essences.R`, `inst/python/maestro_inference.py` (constante `ESSENCES`) |
| P0-02 | Bloc test unitaire `tests/testthat/test-essences.R` | P0 | S | `tests/testthat/`, `DESCRIPTION` |
| P0-03 | Aligner `n_classes` à 13 et patch_size à 256 partout | P0 | S | `R/pipeline.R`, `R/inference.R`, `R/patches.R`, `inst/scripts/maestro_cli.R` |
| P0-04 | Archiver les modules TreeSatAI dans `inst/legacy/` et purger NAMESPACE | P0 | S | `R/finetune.R`, `R/essences.R::essences_treesatai`, `inst/python/train_treesatai.py`, `inst/scripts/predict_treesatai.R`, `NAMESPACE` |
| P0-05 | Mettre à jour `README.md`, `deploy_scaleway.sh`, `cloud_train.sh` (sortir « TreeSatAI 8 classes ») | P0 | S | `README.md`, `inst/scripts/*` |

### Tickets Phase 1

| ID | Titre | Phase | T-shirt | Fichiers / modules impactés |
|----|-------|-------|---------|-------------------------------|
| P1-01 | Spec `modalite_specs()` et refactor de `extraire_patches_multimodal()` | P1 | M | `R/patches.R` |
| P1-02 | Réécrire `maestro_pipeline()` autour des modalités séparées | P1 | M | `R/pipeline.R`, `R/combine.R` (suppression `combine_rgbi_mnt`) |
| P1-03 | Script `inst/scripts/prepare_pureforest_aerial.py` (HF → patches 256×256 normalisés) | P1 | M | nouveau |
| P1-04 | `PureForestDataset` (Python) + config Hydra `pureforest.yaml` dans fork MAESTRO | P1 | L | fork séparé `IGNF/MAESTRO` |
| P1-05 | `pureforest_finetune.py` (linear probe + fine-tune) | P1 | M | nouveau, dérivé de `maestro_finetune.py` |
| P1-06 | Script Scaleway dédié `cloud_train_pureforest.sh` | P1 | S | nouveau, fork de `cloud_train.sh` |
| P1-07 | Run baseline aerial seul, run report (matrice de confusion) | P1 | M | `outputs/`, doc |
| P1-08 | Test E2E sur AOI Fontainebleau 1 km² | P1 | S | `inst/scripts/test_pipeline.R` étendu |

### Tickets Phase 2

| ID | Titre | Phase | T-shirt | Fichiers / modules impactés |
|----|-------|-------|---------|-------------------------------|
| P2-01 | `prepare_dem(aoi, source="wms")` couvrant DSM (LiDAR HD) + DTM (RGE ALTI) | P2 | M | `R/download_ign.R`, refactor `download_dem_for_aoi` |
| P2-02 | `prepare_dem(aoi, source="las")` via **lasR** (pipeline TIN sol + premiers retours, normalisation `transform_with(dtm_tri)`, `pit_fill`, buffer 20 m, multi-tuile via `LAScatalog`) — pattern repris de `pobsteta/nemeton` `inst/tutorials/07-lidar-advanced` | P2 | L | nouveau `R/lidar.R`, ajouter `Imports: lasR` (ou `Suggests:` si r-universe pose problème en CI) |
| P2-03 | Script `prepare_pureforest_dem.py` à partir des LAZ PureForest | P2 | M | nouveau |
| P2-04 | Ajout modalité `dem` à `pureforest.yaml` + relance fine-tune | P2 | M | fork MAESTRO |
| P2-05 | Ablation aerial vs aerial+dem | P2 | S | doc |

### Tickets Phase 3

| ID | Titre | Phase | T-shirt | Fichiers / modules impactés |
|----|-------|-------|---------|-------------------------------|
| P3-01 | Batch STAC Sentinel-2 sur 135 k patches (parallélisé par tuile MGRS) | P3 | L | nouveau `inst/python/prepare_pureforest_sentinel.py` |
| P3-02 | Idem Sentinel-1 ascending + descending | P3 | L | idem |
| P3-03 | Ajout `s2`, `s1_asc`, `s1_des` à `pureforest.yaml` + fine-tune complet | P3 | M | fork MAESTRO |
| P3-04 | Mode série temporelle (axe T) | P3 | L | adaptation DataLoader + config Hydra |
| P3-05 | Cohérence pipeline R inférence multi-modale complète | P3 | M | `R/pipeline.R`, `R/download_sentinel.R` |
| P3-06 | Publication checkpoint v0.5 sur HF Hub | P3 | S | doc |

### Tickets Phase 4

| ID | Titre | Phase | T-shirt | Fichiers / modules impactés |
|----|-------|-------|---------|-------------------------------|
| P4-01 | Ablation composite vs série temporelle | P4 | M | scripts d'eval |
| P4-02 | Ablation schémas DEM (DSM/DTM, CHM/DTM, CHM/density) | P4 | M | scripts d'eval |
| P4-03 | Cross-domain : tests Massif Central, Nord, Corse | P4 | M | `inst/scripts/cross_domain_eval.R` |
| P4-04 | Optimisation inférence (fp16, batching) | P4 | M | `inst/python/maestro_inference.py` |
| P4-05 | Vignette R Markdown utilisateur | P4 | M | `vignettes/maestro.Rmd` |
| P4-06 | Publication checkpoint v1.0 + tag GitHub | P4 | S | doc |

### Tickets transverses

| ID | Titre | Phase | T-shirt | Fichiers / modules impactés |
|----|-------|-------|---------|-------------------------------|
| TR-01 | Mettre `maestro_treesatai_best.pt` (344 Mo) hors dépôt (LFS ou stockage externe) | P0 | S | racine, `.gitignore`, `.gitattributes` |
| TR-02 | Mettre en place CI (R CMD check + lint Python) | P0/P1 | M | `.github/workflows/ci.yml` |
| TR-03 | Pin des versions Python (`torch`, `safetensors`, `tifffile`, `rasterio`) et R (`lasR` via r-universe) | P1 | S | `inst/python/requirements.txt`, `DESCRIPTION` (Additional_repositories) |
| TR-04 | Documenter la procédure HF token et Géoplateforme dans `README.md` | P0 | S | `README.md` |
| TR-05 | Mode `dry-run` dans `maestro_pipeline()` (skip Python, valider seulement les téléchargements) | P1 | S | `R/pipeline.R` |

---

## Annexe — Sources techniques

- Fiche modèle MAESTRO : <https://huggingface.co/IGNF/MAESTRO_FLAIR-HUB_base>
  (configs Hydra TreeSatAI-TS, FLAIR-HUB, PASTIS-HD reproduites en page).
- Fiche dataset PureForest : <https://huggingface.co/datasets/IGNF/PureForest>
  (taxonomie 13 classes, splits 70/15/15 stratifiés au niveau forêt,
  ratios de classe, structure aerial+LiDAR).
- Article PureForest : <https://arxiv.org/abs/2404.12064>
  (Gaydon & Roche, 2024).
- Article MAESTRO : <https://arxiv.org/abs/2508.10894>
  (Labatie *et al.*, WACV 2026).
- Dataset TreeSatAI-Time-Series : <https://huggingface.co/datasets/IGNF/TreeSatAI-Time-Series>
  (référence pour la stratégie d'augmentation Sentinel : H5 par patch,
  forme `(T, C, 6, 6)`, 10 m).
- Dépôt MAESTRO : <https://github.com/IGNF/MAESTRO>
  (configs Hydra, classes Dataset existantes — à inspecter en local en
  Phase 1).
- Géoplateforme IGN : <https://data.geopf.fr/>, layer
  `IGNF_LIDAR-HD_MNS_ELEVATION.ELEVATIONGRIDCOVERAGE.LAMB93` pour le MNS,
  `ELEVATION.ELEVATIONGRIDCOVERAGE.HIGHRES` pour le MNT.
- Catalogue LiDAR HD : <https://cartes.gouv.fr/rechercher-une-donnee/dataset/IGNF_NUAGES-DE-POINTS-LIDAR-HD>
  (tuiles LAZ 1 km × 1 km, classification ASPRS étendue, accès S3 / ATOM).
- STAC Planetary Computer : <https://planetarycomputer.microsoft.com/api/stac/v1>
  (collections `sentinel-2-l2a` et `sentinel-1-rtc`, signing automatique
  via `rstac::sign_planetary_computer`).
