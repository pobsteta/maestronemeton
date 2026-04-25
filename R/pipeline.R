#' Executer le pipeline MAESTRO de reconnaissance d'essences forestieres
#'
#' Pipeline de bout en bout : charge l'AOI, telecharge les modalites
#' demandees (aerien IGN, DEM, Sentinel-2, Sentinel-1), construit une
#' grille de patches alignee sur la modalite aerienne, extrait les
#' fenetres centrees par modalite (cf. [modalite_specs()]) et execute
#' l'inference multi-modale MAESTRO.
#'
#' Modalites supportees (cf. fiche modele HF `IGNF/MAESTRO_FLAIR-HUB_base`) :
#'   - `aerial` : RGBI 4 bandes a 0,2 m, fenetre 51,2 m (256 x 256 px,
#'     `patch_size.mae=16`)
#'   - `dem`    : DSM+DTM 2 bandes a 0,2 m, meme fenetre 51,2 m
#'     (`patch_size.mae=32`)
#'   - `s2`     : Sentinel-2 L2A 10 bandes a 10 m, fenetre 60 m (6 x 6 px,
#'     `patch_size.mae=2`)
#'   - `s1_asc` / `s1_des` : Sentinel-1 RTC VV+VH a 10 m, fenetre 60 m
#'
#' Les modalites Sentinel utilisent une fenetre legerement elargie (60 m
#' au lieu de 51,2 m) pour respecter le multiple de `patch_size.mae=2`.
#'
#' @param aoi_path Chemin vers le fichier GeoPackage de la zone d'interet
#' @param output_dir Repertoire de sortie (defaut: `"outputs"`)
#' @param model_id Identifiant Hugging Face du modele de base
#'   (defaut: `"IGNF/MAESTRO_FLAIR-HUB_base"`). Ignore si `checkpoint` est
#'   fourni.
#' @param checkpoint Chemin vers un checkpoint fine-tune (`*.pt`).
#'   Lorsque fourni, les modalites et le nombre de classes sont lus du
#'   checkpoint et imposes au pipeline. Ex.
#'   `"outputs/training/maestro_pureforest_best.pt"`.
#' @param modalites Vecteur de modalites a utiliser parmi
#'   `c("aerial", "dem", "s2", "s1_asc", "s1_des")`
#'   (defaut: `"aerial"`, MVP phase 1).
#' @param millesime_ortho Millesime de l'ortho RVB (`NULL` = plus recent)
#' @param millesime_irc Millesime de l'ortho IRC (`NULL` = plus recent)
#' @param n_classes Nombre de classes en sortie. Defaut 13 (PureForest).
#'   Ecrase par `checkpoint$n_classes` si un checkpoint fine-tune est
#'   fourni.
#' @param date_sentinel Date cible pour Sentinel (`"YYYY-MM-DD"`, NULL =
#'   ete de l'annee courante). Ignore si `annees_sentinel` est fourni.
#' @param annees_sentinel Vecteur d'annees pour un composite multi-annuel
#'   (ex. `2021:2024`). Active le mode multitemporel.
#' @param saison Saison du composite : `"ete"`, `"printemps"`, `"automne"`,
#'   `"annee"`, ou vecteur `c(mois_debut, mois_fin)`.
#' @param max_scenes_par_annee Nombre max de scenes par annee pour le
#'   composite (defaut : 3, les moins nuageuses).
#' @param gpu Utiliser le GPU CUDA (defaut: FALSE).
#' @param token Token Hugging Face (optionnel).
#' @return Liste invisible avec `grille` (sf), `raster` (SpatRaster) et
#'   `modalites` (character) effectivement utilisees.
#' @export
#' @examples
#' \dontrun{
#' # MVP : aerial seul, modele de base PureForest 13 classes
#' maestro_pipeline("data/aoi.gpkg")
#'
#' # Aerial + DEM (Phase 2)
#' maestro_pipeline("data/aoi.gpkg", modalites = c("aerial", "dem"))
#'
#' # Toutes les modalites avec composite Sentinel multi-annuel (Phase 3)
#' maestro_pipeline("data/aoi.gpkg",
#'                   modalites = c("aerial", "dem", "s2", "s1_asc", "s1_des"),
#'                   annees_sentinel = 2022:2024, saison = "ete")
#'
#' # Avec checkpoint fine-tune PureForest
#' maestro_pipeline("data/aoi.gpkg",
#'                   checkpoint = "outputs/training/maestro_pureforest_best.pt")
#' }
maestro_pipeline <- function(aoi_path = "data/aoi.gpkg",
                              output_dir = "outputs",
                              model_id = "IGNF/MAESTRO_FLAIR-HUB_base",
                              checkpoint = NULL,
                              modalites = c("aerial"),
                              millesime_ortho = NULL,
                              millesime_irc = NULL,
                              n_classes = 13L,
                              date_sentinel = NULL,
                              annees_sentinel = NULL,
                              saison = "ete",
                              max_scenes_par_annee = 3L,
                              gpu = FALSE,
                              token = NULL) {
  is_finetune <- !is.null(checkpoint)
  specs <- modalite_specs()
  modalites <- intersect(modalites, names(specs))
  if (length(modalites) == 0L) {
    stop("Aucune modalite valide. Choix : ",
         paste(names(specs), collapse = ", "))
  }

  message("========================================================")
  message(" MAESTRO - Reconnaissance des essences forestieres")
  if (is_finetune) {
    message(sprintf(" Checkpoint fine-tune : %s", basename(checkpoint)))
  } else {
    message(sprintf(" Modele de base : %s", model_id))
  }
  message(sprintf(" Modalites demandees : %s",
                   paste(modalites, collapse = ", ")))
  if (!is.null(annees_sentinel)) {
    saison_label <- if (is.character(saison)) saison else
      paste(saison, collapse = "-")
    message(sprintf(
      " Composite Sentinel multitemporel : %d annees (%s-%s, saison %s)",
      length(annees_sentinel), min(annees_sentinel), max(annees_sentinel),
      saison_label))
  }
  message("========================================================\n")

  # 1. Charger l'AOI
  aoi <- load_aoi(aoi_path)

  # 2. Telecharger les modalites demandees, separement
  rasters <- list()

  if ("aerial" %in% modalites) {
    ortho <- download_ortho_for_aoi(
      aoi, output_dir,
      millesime_ortho = millesime_ortho,
      millesime_irc = millesime_irc
    )
    rasters$aerial <- combine_rvb_irc(ortho$rvb, ortho$irc)
    rgbi_path <- file.path(output_dir, "ortho_rgbi.tif")
    terra::writeRaster(rasters$aerial, rgbi_path, overwrite = TRUE,
                        gdal = c("COMPRESS=LZW"))
    message(sprintf("  aerial : %s", rgbi_path))
  }

  if ("dem" %in% modalites) {
    if (!"aerial" %in% names(rasters)) {
      stop("La modalite 'dem' doit etre extraite sur la grille aerial : ",
           "demande aussi aerial dans `modalites`.")
    }
    dem_data <- download_dem_for_aoi(aoi, output_dir,
                                       rgbi = rasters$aerial)
    if (!is.null(dem_data)) {
      rasters$dem <- aligner_dem_sur_rgbi(dem_data$dem, rasters$aerial)
      message(sprintf("  dem    : 2 bandes (DSM source : %s)",
                       dem_data$dsm_source))
    } else {
      modalites <- setdiff(modalites, "dem")
      warning("DEM indisponible, modalite 'dem' retiree du pipeline")
    }
  }

  if ("s2" %in% modalites) {
    s2 <- download_s2_for_aoi(
      aoi, output_dir,
      date_cible = date_sentinel,
      annees_sentinel = annees_sentinel,
      saison = saison,
      max_scenes_par_annee = max_scenes_par_annee
    )
    if (!is.null(s2)) {
      rasters$s2 <- s2
      message(sprintf("  s2     : %d bandes a 10 m", terra::nlyr(s2)))
    } else {
      modalites <- setdiff(modalites, "s2")
      warning("Sentinel-2 indisponible, modalite 's2' retiree")
    }
  }

  if (any(c("s1_asc", "s1_des") %in% modalites)) {
    s1 <- download_s1_for_aoi(
      aoi, output_dir,
      date_cible = date_sentinel,
      annees_sentinel = annees_sentinel,
      saison = saison,
      max_scenes_par_annee = max_scenes_par_annee
    )
    if (!is.null(s1)) {
      if (!is.null(s1$s1_asc) && "s1_asc" %in% modalites) {
        rasters$s1_asc <- s1$s1_asc
        message("  s1_asc : 2 bandes (VV, VH) a 10 m")
      }
      if (!is.null(s1$s1_des) && "s1_des" %in% modalites) {
        rasters$s1_des <- s1$s1_des
        message("  s1_des : 2 bandes (VV, VH) a 10 m")
      }
    }
    modalites <- intersect(modalites, names(rasters))
  }

  if (length(rasters) == 0L) {
    stop("Aucune modalite n'a pu etre telechargee.")
  }

  # 3. Charger le modele de base ou utiliser un checkpoint local
  fichiers_modele <- NULL
  if (!is_finetune) {
    if (file.exists(model_id) &&
        grepl("\\.(pt|pth|ckpt|safetensors)$", model_id)) {
      message(sprintf("  Checkpoint local : %s", model_id))
      fichiers_modele <- list(weights = model_id)
    } else {
      fichiers_modele <- telecharger_modele(model_id, token)
    }
  }

  # 4. Configurer Python
  configurer_python()

  # 5. Si fine-tune, lire les modalites et n_classes du checkpoint
  if (is_finetune) {
    py_path <- python_module_path()
    maestro_py <- reticulate::import_from_path(
      "maestro_inference", path = py_path)
    torch <- reticulate::import("torch")
    ckpt <- torch$load(checkpoint, map_location = "cpu",
                        weights_only = FALSE)
    ckpt_modalites <- if (!is.null(ckpt$modalites)) {
      unlist(ckpt$modalites)
    } else {
      c("aerial")
    }
    n_classes <- if (!is.null(ckpt$n_classes)) {
      as.integer(ckpt$n_classes)
    } else {
      n_classes
    }
    message(sprintf("  Checkpoint : %d classes, modalites %s",
                     n_classes, paste(ckpt_modalites, collapse = ", ")))

    modalites_filtrees <- intersect(modalites, ckpt_modalites)
    if (length(modalites_filtrees) < length(modalites)) {
      message(sprintf("  Modalites retirees (absentes du checkpoint) : %s",
                       paste(setdiff(modalites, modalites_filtrees),
                             collapse = ", ")))
    }
    modalites <- modalites_filtrees
    rasters <- rasters[modalites]
  }

  if (length(modalites) == 0L) {
    stop("Aucune modalite restante apres filtrage par checkpoint.")
  }

  # 6. Grille de patches alignee sur la modalite aerial (si presente)
  ref_mod <- if ("aerial" %in% modalites) "aerial" else modalites[1]
  taille_patch_m <- specs[[ref_mod]]$window_m
  grille <- creer_grille_patches(aoi, taille_patch_m = taille_patch_m)

  # 7. Extraction multi-modale
  patches <- extraire_patches_multimodal(rasters, grille, specs)

  # 8. Inference
  predictions <- executer_inference_multimodal(
    patches, fichiers_modele = fichiers_modele,
    n_classes = n_classes,
    modalites = modalites,
    utiliser_gpu = gpu,
    checkpoint = checkpoint
  )

  # 9. Choix de la table d'essences (PureForest 13 par defaut, TreeSatAI 7
  #    pour les checkpoints legacy fine-tunes avant la migration phase 0)
  essences <- if (n_classes == 7L && is_finetune) {
    essences_treesatai()
  } else {
    essences_pureforest()
  }

  # 10. Assembler & exporter
  resultats <- assembler_resultats(grille, predictions,
                                    essences = essences,
                                    dossier_sortie = output_dir)
  raster_carte <- creer_carte_raster(
    resultats,
    resolution = specs[[ref_mod]]$resolution,
    dossier_sortie = output_dir
  )

  message("\n========================================================")
  message(" Traitement termine.")
  message(sprintf(" Modalites utilisees : %s",
                   paste(modalites, collapse = ", ")))
  message(sprintf(" Resultats : %s/", output_dir))
  message("========================================================")

  invisible(list(grille = resultats,
                  raster = raster_carte,
                  modalites = modalites))
}
