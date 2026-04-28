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
    dem_data <- prepare_dem(aoi, output_dir,
                             rgbi = rasters$aerial,
                             source = "wms")
    if (!is.null(dem_data)) {
      rasters$dem <- aligner_dem_sur_rgbi(dem_data$dem, rasters$aerial)
      message(sprintf("  dem    : 2 bandes (DSM source : %s, couverture LiDAR HD : %.1f %%)",
                       dem_data$dsm_source,
                       dem_data$lidar_hd_coverage_pct))
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
#' Pipeline de segmentation dense MAESTRO a 0.2m
#'
#' Pipeline complet : telecharge les donnees multimodales, charge le backbone
#' MAESTRO + decodeur de segmentation, et produit une carte d'essences
#' forestieres a 0.2m de resolution (classes NDP0, 10 classes).
#'
#' @param aoi_path Chemin vers le fichier GeoPackage de la zone d'interet
#' @param backbone_path Chemin vers le checkpoint MAESTRO pre-entraine (.ckpt)
#' @param decoder_path Chemin vers le decodeur de segmentation (.pt)
#' @param output_dir Repertoire de sortie (defaut: `"outputs"`)
#' @param millesime_ortho Millesime de l'ortho RVB (`NULL` = plus recent)
#' @param millesime_irc Millesime de l'ortho IRC (`NULL` = plus recent)
#' @param patch_size Taille des patches en pixels (defaut: 250)
#' @param resolution Resolution spatiale en metres (defaut: 0.2)
#' @param overlap_m Recouvrement entre patches en metres (defaut: 10)
#' @param use_s2 Inclure Sentinel-2 (defaut: FALSE)
#' @param use_s1 Inclure Sentinel-1 (defaut: FALSE)
#' @param date_sentinel Date cible pour les images Sentinel
#' @param annees_sentinel Vecteur d'annees pour un composite multi-annuel
#' @param saison Saison cible pour le composite multitemporel
#' @param dem_channels Vecteur de 2 noms de canaux DEM (defaut: `c("SLOPE", "TWI")`)
#' @param max_scenes_par_annee Nombre max de scenes par annee (defaut: 3)
#' @param gpu Utiliser le GPU CUDA (defaut: FALSE)
#' @param use_flair Logical. Appliquer la contrainte FLAIR feuillus/resineux
#'   sur la segmentation ? (defaut: `FALSE`). Si `TRUE`, execute l'inference
#'   FLAIR puis corrige les pixels incoherents.
#' @param model_flair Identifiant du modele FLAIR HuggingFace
#'   (defaut: `"IGNF/FLAIR-INC_rgbi_15cl_resnet34-unet"`).
#' @return SpatRaster mono-bande avec les codes NDP0 a 0.2m
#' @export
#' @examples
#' \dontrun{
#' # Segmentation avec aerial + DEM (pente + TWI)
#' maestro_segmentation_pipeline(
#'   "data/aoi.gpkg",
#'   backbone_path = "models/MAESTRO_pretrain.ckpt",
#'   decoder_path = "models/segmenter_ndp0_best.pt"
#' )
#'
#' # Avec DSM + DTM classique
#' maestro_segmentation_pipeline(
#'   "data/aoi.gpkg",
#'   backbone_path = "models/MAESTRO_pretrain.ckpt",
#'   decoder_path = "models/segmenter_ndp0_best.pt",
#'   dem_channels = c("DSM", "DTM")
#' )
#' }
maestro_segmentation_pipeline <- function(aoi_path = "data/aoi.gpkg",
                                            backbone_path,
                                            decoder_path,
                                            output_dir = "outputs",
                                            millesime_ortho = NULL,
                                            millesime_irc = NULL,
                                            patch_size = 250L,
                                            resolution = 0.2,
                                            overlap_m = 10,
                                            use_s2 = FALSE,
                                            use_s1 = FALSE,
                                            date_sentinel = NULL,
                                            annees_sentinel = NULL,
                                            saison = "ete",
                                            max_scenes_par_annee = 3L,
                                            dem_channels = c("SLOPE", "TWI"),
                                            gpu = FALSE,
                                            use_flair = FALSE,
                                            model_flair = "IGNF/FLAIR-INC_rgbi_15cl_resnet34-unet") {
  # --- Validation ---
  if (!file.exists(aoi_path)) {
    stop(sprintf("Fichier AOI introuvable: %s", aoi_path))
  }
  if (!file.exists(backbone_path)) {
    stop(sprintf("Checkpoint backbone introuvable: %s", backbone_path))
  }
  if (!file.exists(decoder_path)) {
    stop(sprintf("Decodeur segmentation introuvable: %s", decoder_path))
  }

  # Determiner les modalites
  modalites_noms <- c("aerial", "dem")
  if (use_s2) modalites_noms <- c(modalites_noms, "s2")
  if (use_s1) modalites_noms <- c(modalites_noms, "s1_asc", "s1_des")

  message("========================================================")
  message(" MAESTRO - Segmentation dense a 0.2m (NDP0)")
  message(sprintf(" Backbone: %s", basename(backbone_path)))
  message(sprintf(" Decodeur: %s", basename(decoder_path)))
  message(sprintf(" Modalites: %s", paste(modalites_noms, collapse = " + ")))
  if (!is.null(annees_sentinel)) {
    message(sprintf(" Mode multitemporel: %d annees", length(annees_sentinel)))
  }
  message("========================================================\n")

  # 1. Charger l'AOI
  aoi <- load_aoi(aoi_path)

  # 2. Telecharger les ortho IGN
  ortho <- download_ortho_for_aoi(
    aoi, output_dir,
    millesime_ortho = millesime_ortho,
    millesime_irc = millesime_irc
  )

  # 3. Combiner RVB + IRC -> RGBI
  rgbi <- combine_rvb_irc(ortho$rvb, ortho$irc)
  rgbi_path <- file.path(output_dir, "ortho_rgbi.tif")
  terra::writeRaster(rgbi, rgbi_path, overwrite = TRUE)

  # 4. Telecharger le DEM (2 canaux au choix, 1m natif)
  dem_data <- download_dem_for_aoi(aoi, output_dir, dem_channels = dem_channels)

  modalites <- list(aerial = rgbi)
  if (!is.null(dem_data)) {
    modalites$dem <- dem_data$dem
  }

  # 5. Sentinel-2
  if (use_s2) {
    s2 <- download_s2_for_aoi(aoi, output_dir,
                                date_cible = date_sentinel,
                                annees_sentinel = annees_sentinel,
                                saison = saison,
                                max_scenes_par_annee = max_scenes_par_annee)
    if (!is.null(s2)) {
      modalites$s2 <- aligner_sentinel(s2, rgbi, target_res = 10)
    }
  }

  # 6. Sentinel-1
  if (use_s1) {
    s1 <- download_s1_for_aoi(aoi, output_dir,
                                date_cible = date_sentinel,
                                annees_sentinel = annees_sentinel,
                                saison = saison,
                                max_scenes_par_annee = max_scenes_par_annee)
    if (!is.null(s1)) {
      if (!is.null(s1$s1_asc)) {
        modalites$s1_asc <- aligner_sentinel(s1$s1_asc, rgbi, target_res = 10)
      }
      if (!is.null(s1$s1_des)) {
        modalites$s1_des <- aligner_sentinel(s1$s1_des, rgbi, target_res = 10)
      }
    }
  }

  # 7. Configurer Python + charger le segmenter
  segmenter <- charger_segmenter(
    backbone_path = backbone_path,
    decoder_path = decoder_path,
    modalites = names(modalites),
    gpu = gpu
  )

  # 8. Segmentation dense
  raster_seg <- executer_segmentation(
    segmenter = segmenter,
    modalites = modalites,
    aoi = aoi,
    output_dir = output_dir,
    patch_size = patch_size,
    resolution = resolution,
    overlap_m = overlap_m,
    gpu = gpu
  )

  # 9. Contrainte FLAIR (optionnel)
  if (use_flair) {
    flair_result <- pipeline_flair_contrainte(
      raster_seg  = raster_seg,
      rgbi        = rgbi,
      dem         = if (!is.null(dem_data)) dem_data$dem else NULL,
      output_dir  = output_dir,
      model_flair = model_flair,
      gpu         = gpu
    )
    raster_seg <- flair_result$raster
  }

  message("\n========================================================")
  message(" Segmentation terminee !")
  message(sprintf(" Carte NDP0 a 0.2m: %s/segmentation_ndp0%s.tif",
                   output_dir, if (use_flair) "_flair" else ""))
  if (use_flair) {
    message(" Contrainte FLAIR appliquee (feuillus/resineux)")
  }
  message("========================================================")

  invisible(raster_seg)
}


#' Pipeline de preparation des donnees d'entrainement pour la segmentation
#'
#' Telecharge les donnees multimodales et la BD Foret V2 pour l'AOI,
#' rasterise les labels NDP0, et decoupe le tout en patches d'entrainement.
#'
#' @param aoi_path Chemin vers le fichier GeoPackage de la zone d'interet
#' @param output_dir Repertoire de sortie pour les patches
#' @param millesime_ortho Millesime de l'ortho RVB
#' @param millesime_irc Millesime de l'ortho IRC
#' @param patch_size Taille des patches en pixels (defaut: 250)
#' @param resolution Resolution en metres (defaut: 0.2)
#' @param val_ratio Proportion de validation (defaut: 0.15)
#' @param min_forest_pct Pourcentage minimum de foret par patch (defaut: 10)
#' @param use_s2 Inclure Sentinel-2 (defaut: FALSE)
#' @param use_s1 Inclure Sentinel-1 (defaut: FALSE)
#' @param date_sentinel Date cible pour Sentinel
#' @param annees_sentinel Vecteur d'annees pour composite
#' @param saison Saison cible
#' @param max_scenes_par_annee Nombre max de scenes par annee
#' @param dem_channels Vecteur de noms de canaux DEM parmi
#'   `c("DSM", "DTM", "SLOPE", "ASPECT", "TPI", "TWI")`. Defaut :
#'   `c("SLOPE", "TWI")`.
#' @return Liste avec n_train, n_val, n_skipped
#' @export
preparer_donnees_segmentation <- function(aoi_path = "data/aoi.gpkg",
                                            output_dir = "data/segmentation",
                                            millesime_ortho = NULL,
                                            millesime_irc = NULL,
                                            patch_size = 250L,
                                            resolution = 0.2,
                                            val_ratio = 0.15,
                                            min_forest_pct = 10,
                                            use_s2 = FALSE,
                                            use_s1 = FALSE,
                                            date_sentinel = NULL,
                                            annees_sentinel = NULL,
                                            saison = "ete",
                                            max_scenes_par_annee = 3L,
                                            dem_channels = c("SLOPE", "TWI")) {
  if (!file.exists(aoi_path)) {
    stop(sprintf("Fichier AOI introuvable: %s", aoi_path))
  }

  message("========================================================")
  message(" MAESTRO - Preparation donnees entrainement segmentation")
  message("========================================================\n")

  tmp_dir <- file.path(output_dir, "tmp_rasters")
  if (!dir.exists(tmp_dir)) dir.create(tmp_dir, recursive = TRUE)

  # 1. Charger l'AOI
  aoi <- load_aoi(aoi_path)

  # 2. Telecharger les ortho IGN
  ortho <- download_ortho_for_aoi(
    aoi, tmp_dir,
    millesime_ortho = millesime_ortho,
    millesime_irc = millesime_irc
  )
  rgbi <- combine_rvb_irc(ortho$rvb, ortho$irc)

  # 3. DEM (2 canaux au choix, 1m natif)
  dem_data <- download_dem_for_aoi(aoi, tmp_dir, dem_channels = dem_channels)

  modalites <- list(aerial = rgbi)
  if (!is.null(dem_data)) {
    modalites$dem <- dem_data$dem
  }

  # 4. Sentinel-2
  if (use_s2) {
    s2 <- download_s2_for_aoi(aoi, tmp_dir,
                                date_cible = date_sentinel,
                                annees_sentinel = annees_sentinel,
                                saison = saison,
                                max_scenes_par_annee = max_scenes_par_annee)
    if (!is.null(s2)) {
      modalites$s2 <- aligner_sentinel(s2, rgbi, target_res = 10)
    }
  }

  # 5. Sentinel-1
  if (use_s1) {
    s1 <- download_s1_for_aoi(aoi, tmp_dir,
                                date_cible = date_sentinel,
                                annees_sentinel = annees_sentinel,
                                saison = saison,
                                max_scenes_par_annee = max_scenes_par_annee)
    if (!is.null(s1)) {
      if (!is.null(s1$s1_asc)) {
        modalites$s1_asc <- aligner_sentinel(s1$s1_asc, rgbi, target_res = 10)
      }
      if (!is.null(s1$s1_des)) {
        modalites$s1_des <- aligner_sentinel(s1$s1_des, rgbi, target_res = 10)
      }
    }
  }

  # 6. Telecharger et rasteriser la BD Foret V2
  labels <- preparer_labels_ndp0(aoi, rgbi, tmp_dir)

  # 7. Decouper en patches
  result <- preparer_patches_entrainement(
    modalites = modalites,
    labels = labels,
    aoi = aoi,
    output_dir = output_dir,
    patch_size = patch_size,
    resolution = resolution,
    val_ratio = val_ratio,
    min_forest_pct = min_forest_pct
  )

  message("\n========================================================")
  message(" Donnees d'entrainement pretes !")
  message(sprintf(" %s/", output_dir))
  message("========================================================")

  invisible(result)
}
