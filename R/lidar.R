#' Pipeline LiDAR `lasR` pour deriver DSM + DTM d'une AOI
#'
#' Execute un pipeline `lasR` sur les nuages LAZ fournis : triangulation TIN
#' sur les points classes sol (ASPRS 2) pour le DTM, sur les premiers retours
#' (return_number == 1) pour le DSM, rasterisation a 1 m avec un buffer de
#' 20 m sur le `LAScatalog` pour gerer les effets de bord. Les rasters par
#' tuile sont ensuite mosaiques, croppes sur l'AOI puis ree-chantillonnes
#' sur la grille de la modalite `aerial` (resolution 0,2 m typiquement).
#'
#' Cette fonction est la voie `source = "las"` de [prepare_dem()] (cf. ticket
#' P2-02 du `DEV_PLAN.md`). Le pattern lasR est repris du tutoriel
#' `pobsteta/nemeton` `inst/tutorials/07-lidar-advanced` (cf. DEV_PLAN.md S3.3).
#'
#' Le telechargement automatique des tuiles LAZ depuis l'IGN
#' (catalogue cartes.gouv.fr / S3) est hors scope de cette fonction : les
#' chemins sont a fournir explicitement via `las_files`.
#'
#' @param aoi sf object en Lambert-93.
#' @param las_files Vecteur character de chemins vers des fichiers LAZ/LAS.
#' @param output_dir Repertoire de sortie (ecrit `dem_2bands.tif` et les
#'   tuiles intermediaires `lasr_dtm_*.tif`, `lasr_dsm_*.tif`).
#' @param rgbi SpatRaster aerial de reference pour le reechantillonnage a
#'   0,2 m (NULL = garde la resolution native 1 m).
#' @param buffer_m Buffer (m) applique au LAScatalog pour les effets de
#'   bord (defaut : 20, valeur recommandee dans DEV_PLAN.md S3.3).
#' @param ncores Nombre de coeurs paralleles (defaut : 2).
#' @param keep_tiles Si TRUE, conserve les rasters par tuile dans
#'   `output_dir`. Sinon (defaut), les supprime apres mosaiquage.
#' @return Liste avec
#'   - `dem` : SpatRaster 2 bandes nommees `DSM`, `DTM`
#'   - `dem_path` : chemin du GeoTIFF ecrit
#'   - `dsm_source` : `"lasR"`
#'   - `lidar_hd_coverage_pct` : NA (la mesure de couverture WMS n'a pas
#'     de sens en mode LAS ou les points sont par construction LiDAR)
#' @keywords internal
prepare_dem_las <- function(aoi, las_files, output_dir, rgbi = NULL,
                             buffer_m = 20, ncores = 2L,
                             keep_tiles = FALSE) {
  if (!requireNamespace("lasR", quietly = TRUE)) {
    stop("Le package 'lasR' est requis pour source = 'las'. ",
         "Installer avec : install.packages('lasR', ",
         "repos = 'https://r-lidar.r-universe.dev')")
  }

  if (length(las_files) == 0L) {
    stop("`las_files` est vide pour source = 'las'.")
  }
  missing <- las_files[!file.exists(las_files)]
  if (length(missing) > 0L) {
    stop("Fichiers LAZ introuvables : ",
         paste(missing, collapse = ", "))
  }

  fs::dir_create(output_dir)
  dem_path <- file.path(output_dir, "dem_2bands.tif")

  # --- Cache : si deja produit, on retourne directement ---
  if (file.exists(dem_path)) {
    message("\n=== DEM 2 bandes deja telecharge (cache lasR) ===")
    dem <- terra::rast(dem_path)
    names(dem) <- c("DSM", "DTM")
    return(list(dem = dem, dem_path = dem_path,
                dsm_source = "cache",
                lidar_hd_coverage_pct = NA_real_))
  }

  message("\n=== Preparation DEM MAESTRO (DSM + DTM via lasR) ===")
  message(sprintf("  %d tuile(s) LAZ, buffer %d m, %d coeur(s)",
                   length(las_files), buffer_m, ncores))

  dtm_glob <- file.path(output_dir, "lasr_dtm_*.tif")
  dsm_glob <- file.path(output_dir, "lasr_dsm_*.tif")

  read_stage    <- lasR::reader_las()
  dtm_tri_stage <- lasR::triangulate(filter = lasR::keep_ground())
  dtm_stage     <- lasR::rasterize(1, dtm_tri_stage, ofile = dtm_glob)
  dsm_tri_stage <- lasR::triangulate(filter = lasR::keep_first())
  dsm_stage     <- lasR::rasterize(1, dsm_tri_stage, ofile = dsm_glob)

  pipeline <- read_stage + dtm_tri_stage + dtm_stage +
              dsm_tri_stage + dsm_stage

  invisible(lasR::exec(pipeline, on = las_files, ncores = ncores,
                       with = list(buffer = buffer_m)))

  # Recuperer les rasters produits par glob : le format de retour de lasR
  # varie selon le nombre de tuiles et la version (SpatRaster vs chemins).
  # Lire depuis le disque est le plus robuste.
  dtm_files <- as.character(fs::dir_ls(output_dir, glob = "*lasr_dtm_*.tif"))
  dsm_files <- as.character(fs::dir_ls(output_dir, glob = "*lasr_dsm_*.tif"))

  if (length(dtm_files) == 0L || length(dsm_files) == 0L) {
    stop("Pipeline lasR n'a produit ni DTM ni DSM. ",
         "Verifier que les LAZ contiennent des points sol (classe 2) et ",
         "des premiers retours (return_number == 1).")
  }

  # --- Mosaiquer (terra::merge) ---
  message(sprintf("  Mosaiquage : %d DTM, %d DSM", length(dtm_files), length(dsm_files)))
  dtm_rasts <- lapply(dtm_files, terra::rast)
  dsm_rasts <- lapply(dsm_files, terra::rast)

  # Forcer le CRS Lambert-93 sur les rasters lasR (les LAZ PureForest n'ont
  # pas de CRS dans leur header, mais leurs coordonnees sont en EPSG:2154).
  for (r in dtm_rasts) terra::crs(r) <- "EPSG:2154"
  for (r in dsm_rasts) terra::crs(r) <- "EPSG:2154"

  dtm <- if (length(dtm_rasts) == 1L) dtm_rasts[[1]] else
    do.call(terra::merge, dtm_rasts)
  dsm <- if (length(dsm_rasts) == 1L) dsm_rasts[[1]] else
    do.call(terra::merge, dsm_rasts)
  terra::crs(dtm) <- "EPSG:2154"
  terra::crs(dsm) <- "EPSG:2154"

  # --- Crop sur l'AOI ---
  aoi_vect <- terra::vect(sf::st_union(aoi))
  dtm <- terra::crop(dtm, aoi_vect)
  dsm <- terra::crop(dsm, aoi_vect)
  names(dtm) <- "DTM"
  names(dsm) <- "DSM"

  # --- Reechantillonnage sur grille aerial 0,2 m si fournie ---
  if (!is.null(rgbi)) {
    message("Reechantillonnage DEM 1 m -> 0,2 m sur grille aerial...")
    dtm <- terra::resample(dtm, rgbi, method = "bilinear")
    dsm <- terra::resample(dsm, rgbi, method = "bilinear")
  }

  # --- Empilage DSM + DTM (ordre impose par MAESTRO) ---
  dem <- c(dsm, dtm)
  names(dem) <- c("DSM", "DTM")

  terra::writeRaster(dem, dem_path, overwrite = TRUE,
                     gdal = c("COMPRESS=LZW"))

  dtm_vals <- terra::values(dtm, na.rm = TRUE)
  if (length(dtm_vals) > 0 && any(is.finite(dtm_vals))) {
    message(sprintf("  Altitude DTM : %.0f - %.0f m",
                    min(dtm_vals, na.rm = TRUE),
                    max(dtm_vals, na.rm = TRUE)))
  }
  message(sprintf("DEM : %s (%d x %d px, %d bandes)",
                  dem_path, terra::ncol(dem), terra::nrow(dem),
                  terra::nlyr(dem)))

  if (!keep_tiles) {
    fs::file_delete(c(dtm_files, dsm_files))
  }

  dem <- terra::rast(dem_path)
  names(dem) <- c("DSM", "DTM")
  list(dem = dem, dem_path = dem_path,
       dsm_source = "lasR",
       lidar_hd_coverage_pct = NA_real_)
}
