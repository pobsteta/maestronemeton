#' Executer le pipeline complet de reconnaissance des essences forestieres
#'
#' Pipeline de bout en bout : charge l'AOI, telecharge les donnees IGN
#' (ortho RVB, IRC, MNT), combine les bandes, telecharge le modele MAESTRO,
#' decoupe en patches, execute l'inference et exporte les resultats.
#'
#' @param aoi_path Chemin vers le fichier GeoPackage de la zone d'interet
#' @param output_dir Repertoire de sortie (defaut: `"resultats"`)
#' @param model_id Identifiant du modele Hugging Face
#'   (defaut: `"IGNF/MAESTRO_FLAIR-HUB_base"`)
#' @param millesime_ortho Millesime de l'ortho RVB (`NULL` = plus recent)
#' @param millesime_irc Millesime de l'ortho IRC (`NULL` = plus recent)
#' @param patch_size Taille des patches en pixels (defaut: 250)
#' @param resolution Resolution spatiale en metres (defaut: 0.2)
#' @param gpu Utiliser le GPU CUDA (defaut: FALSE)
#' @param token Token Hugging Face (optionnel)
#' @return Liste invisible avec `grille` (sf) et `raster` (SpatRaster)
#' @export
#' @examples
#' \dontrun{
#' # Millesime par defaut
#' maestro_pipeline("aoi.gpkg")
#'
#' # Millesime specifique
#' maestro_pipeline("aoi.gpkg",
#'                   millesime_ortho = 2023,
#'                   millesime_irc = 2023)
#' }
maestro_pipeline <- function(aoi_path = "aoi.gpkg",
                              output_dir = "resultats",
                              model_id = "IGNF/MAESTRO_FLAIR-HUB_base",
                              millesime_ortho = NULL,
                              millesime_irc = NULL,
                              patch_size = 250L,
                              resolution = 0.2,
                              gpu = FALSE,
                              token = NULL) {
  message("========================================================")
  message(" MAESTRO - Reconnaissance des essences forestieres")
  message(" Modele IGNF via Hugging Face (hfhub)")
  message(" Donnees ortho + MNT via Geoplateforme IGN (WMS-R)")
  message("========================================================\n")

  # 1. Charger l'AOI
  aoi <- load_aoi(aoi_path)

  # 2. Telecharger les donnees IGN
  ortho <- download_ortho_for_aoi(
    aoi, output_dir,
    millesime_ortho = millesime_ortho,
    millesime_irc = millesime_irc
  )

  # 3. Combiner RVB + IRC -> RGBI
  rgbi <- combine_rvb_irc(ortho$rvb, ortho$irc)

  rgbi_path <- file.path(output_dir, "ortho_rgbi.tif")
  terra::writeRaster(rgbi, rgbi_path, overwrite = TRUE)
  message(sprintf("RGBI sauvegarde: %s", rgbi_path))

  # 4. Telecharger le MNT
  mnt_data <- download_mnt_for_aoi(aoi, output_dir, rgbi = rgbi)

  # 5. Combiner RGBI + MNT -> 5 bandes
  if (!is.null(mnt_data)) {
    image_finale <- combine_rgbi_mnt(rgbi, mnt_data$mnt)
    n_bands <- 5L
  } else {
    message("  MNT non disponible, utilisation des 4 bandes RGBI seules")
    image_finale <- rgbi
    n_bands <- 4L
  }

  finale_path <- file.path(output_dir, "image_finale.tif")
  terra::writeRaster(image_finale, finale_path, overwrite = TRUE,
                     gdal = c("COMPRESS=LZW"))
  message(sprintf("Image finale: %s (%d bandes)", finale_path, n_bands))

  # 6. Telecharger le modele
  fichiers_modele <- telecharger_modele(model_id, token)

  # 7. Configurer Python
  configurer_python()

  # 8. Grille de patches
  taille_patch_m <- patch_size * resolution
  grille <- creer_grille_patches(aoi, taille_patch_m)

  # 9. Extraire les patches
  patches_data <- extraire_patches_raster(image_finale, grille, patch_size)

  # 10. Inference
  predictions <- executer_inference(
    patches_data, fichiers_modele,
    n_classes = 13L, n_bands = n_bands,
    utiliser_gpu = gpu
  )

  # 11. Assembler et exporter
  resultats <- assembler_resultats(grille, predictions,
                                    dossier_sortie = output_dir)

  # 12. Carte raster
  raster_carte <- creer_carte_raster(resultats, resolution, output_dir)

  message("\n========================================================")
  message(" Traitement termine !")
  message(sprintf(" Resultats dans : %s/", output_dir))
  message("========================================================")

  invisible(list(grille = resultats, raster = raster_carte))
}
