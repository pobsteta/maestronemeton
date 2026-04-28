# inst/legacy/ — Code archive

Modules TreeSatAI (8 classes regroupees) deplacés ici en phase 0 du plan
de reprise (cf. `DEV_PLAN.md` a la racine). Ils ne sont plus exportes par
le package `maestronemeton` et ne font plus partie de la chaine de production.

Ils sont conserves uniquement pour :

- garder la tracabilite avec les checkpoints `*.pt` fine-tunes sur
  TreeSatAI deja produits avant la migration vers PureForest 13 classes ;
- permettre la reproduction d'experiences anciennes si necessaire.

## Inventaire

| Fichier | Origine | Role |
|---------|---------|------|
| `finetune.R` | `R/finetune.R` | telechargement TreeSatAI HF + Zenodo, `finetune_maestro()` |
| `train_treesatai.py` | `inst/python/train_treesatai.py` | entrainement TreeSatAI 8 classes (mapping 15 -> 8) |
| `predict_treesatai.R` | `inst/scripts/predict_treesatai.R` | wrapper `maestro_pipeline()` sur checkpoint TreeSatAI |
| `entrainer_treesatai.R` | `inst/scripts/entrainer_treesatai.R` | wrapper `Rscript` du fine-tune |
| `finetune_cli.R` | `inst/scripts/finetune_cli.R` | CLI optparse du fine-tune |
| `test_train_remote.sh` | `inst/scripts/test_train_remote.sh` | smoke test 1 epoch sur GPU Scaleway |

## Cible Phase 1

Le fine-tuning est repris dans le cadre du dataset PureForest (13 classes
mono-label) avec un nouveau DataLoader Hydra dans un fork de
`IGNF/MAESTRO`. Voir le DEV_PLAN section 5 et tickets P1-04 / P1-05.

Le fichier `inst/python/maestro_finetune.py` (non archive) reste en place
comme reference pour la mecanique d'entrainement (early stopping, LR
differentielle, class weights cosine) qui sera reutilisee pour PureForest.
