# Tests unitaires sur prepare_dem() (P2-01).
# Aucun acces reseau : on stub `download_ign_tiled` via with_mocked_bindings()
# pour simuler la reponse Geoplateforme (DTM toujours present, DSM LiDAR HD
# selon le cas teste).

# --- Helpers ----------------------------------------------------------------

# AOI carre de 1 km, centree sur Fontainebleau (approximatif L93)
.aoi_test <- function(size_m = 1000) {
  cx <- 660000
  cy <- 6840000
  half <- size_m / 2
  poly <- sf::st_polygon(list(matrix(c(
    cx - half, cy - half,
    cx + half, cy - half,
    cx + half, cy + half,
    cx - half, cy + half,
    cx - half, cy - half
  ), ncol = 2, byrow = TRUE)))
  sf::st_sf(id = 1L, geometry = sf::st_sfc(poly, crs = 2154))
}

# Raster 1 m couvrant l'AOI ; `coverage_pct` = % de pixels finis non nuls
.fake_dem_raster <- function(aoi, coverage_pct = 100, base_value = 100) {
  bbox <- as.numeric(sf::st_bbox(aoi))
  r <- terra::rast(xmin = bbox[1], xmax = bbox[3],
                    ymin = bbox[2], ymax = bbox[4],
                    res = 1, crs = "EPSG:2154", nlyrs = 1)
  n <- terra::ncell(r)
  vals <- rep(base_value, n)
  if (coverage_pct < 100) {
    n_invalid <- round(n * (100 - coverage_pct) / 100)
    if (n_invalid > 0) vals[seq_len(n_invalid)] <- NA_real_
  }
  terra::values(r) <- vals
  r
}

.with_dem_mock <- function(dtm, dsm, code) {
  fake_tiled <- function(bbox, layer, res_m, output_dir, prefix, styles = "") {
    if (grepl("MNS", layer, fixed = FALSE)) dsm else dtm
  }
  testthat::with_mocked_bindings(
    code,
    download_ign_tiled = fake_tiled,
    .package = "maestro"
  )
}

# --- Tests ------------------------------------------------------------------

test_that("prepare_dem retourne un raster 2 bandes (DSM, DTM) quand LiDAR HD couvre", {
  aoi <- .aoi_test()
  dtm <- .fake_dem_raster(aoi, coverage_pct = 100, base_value = 100)
  dsm <- .fake_dem_raster(aoi, coverage_pct = 100, base_value = 120)
  out_dir <- withr::local_tempdir()

  res <- .with_dem_mock(dtm, dsm, suppressMessages(
    prepare_dem(aoi, out_dir, source = "wms")
  ))

  expect_type(res, "list")
  expect_s4_class(res$dem, "SpatRaster")
  expect_equal(terra::nlyr(res$dem), 2L)
  expect_equal(names(res$dem), c("DSM", "DTM"))
  expect_equal(res$dsm_source, "lidar_hd")
  expect_gte(res$lidar_hd_coverage_pct, 90)
  expect_true(file.exists(res$dem_path))
})

test_that("prepare_dem bascule en fallback DSM = DTM quand LiDAR HD insuffisant", {
  aoi <- .aoi_test()
  dtm <- .fake_dem_raster(aoi, coverage_pct = 100, base_value = 100)
  dsm <- .fake_dem_raster(aoi, coverage_pct = 2, base_value = 0)  # quasi vide
  out_dir <- withr::local_tempdir()
  call_run <- function() suppressMessages(
    prepare_dem(aoi, out_dir, source = "wms",
                coverage_threshold = 10,
                allow_dtm_only_fallback = TRUE)
  )

  expect_warning(
    .with_dem_mock(dtm, dsm, call_run()),
    regexp = "LiDAR HD insuffisante"
  )
  out_dir2 <- withr::local_tempdir()  # nouveau dossier pour eviter le cache
  call_run2 <- function() suppressMessages(suppressWarnings(
    prepare_dem(aoi, out_dir2, source = "wms",
                coverage_threshold = 10,
                allow_dtm_only_fallback = TRUE)
  ))
  res <- .with_dem_mock(dtm, dsm, call_run2())

  expect_equal(res$dsm_source, "rge_alti_fallback")
  expect_lt(res$lidar_hd_coverage_pct, 10)
  expect_equal(as.numeric(terra::values(res$dem[[1]])),
               as.numeric(terra::values(res$dem[[2]])))
})

test_that("prepare_dem retourne NULL quand LiDAR HD insuffisant et fallback desactive", {
  aoi <- .aoi_test()
  dtm <- .fake_dem_raster(aoi, coverage_pct = 100, base_value = 100)
  dsm <- .fake_dem_raster(aoi, coverage_pct = 0, base_value = 0)
  out_dir <- withr::local_tempdir()
  call_run <- function() suppressMessages(suppressWarnings(
    prepare_dem(aoi, out_dir, source = "wms",
                coverage_threshold = 10,
                allow_dtm_only_fallback = FALSE)
  ))

  res <- .with_dem_mock(dtm, dsm, call_run())
  expect_null(res)

  out_dir2 <- withr::local_tempdir()
  call_run2 <- function() suppressMessages(
    prepare_dem(aoi, out_dir2, source = "wms",
                coverage_threshold = 10,
                allow_dtm_only_fallback = FALSE)
  )
  expect_warning(
    .with_dem_mock(dtm, dsm, call_run2()),
    regexp = "LiDAR HD insuffisante"
  )
})

test_that("prepare_dem retourne NULL quand le DTM RGE ALTI ne descend pas", {
  aoi <- .aoi_test()
  fake_tiled <- function(bbox, layer, res_m, output_dir, prefix, styles = "") {
    NULL
  }
  run <- function(out_dir, ignore_warning = FALSE) {
    f <- function() suppressMessages(prepare_dem(aoi, out_dir, source = "wms"))
    if (ignore_warning) f <- function() suppressMessages(suppressWarnings(
      prepare_dem(aoi, out_dir, source = "wms")
    ))
    testthat::with_mocked_bindings(
      f(),
      download_ign_tiled = fake_tiled,
      .package = "maestro"
    )
  }

  out_dir <- withr::local_tempdir()
  expect_null(run(out_dir, ignore_warning = TRUE))

  out_dir2 <- withr::local_tempdir()
  expect_warning(run(out_dir2), regexp = "DTM RGE ALTI")
})

test_that("prepare_dem reechantillonne sur la grille rgbi a 0,2 m si fournie", {
  aoi <- .aoi_test(size_m = 100)  # plus petit pour test rapide
  dtm <- .fake_dem_raster(aoi, coverage_pct = 100, base_value = 100)
  dsm <- .fake_dem_raster(aoi, coverage_pct = 100, base_value = 120)
  bbox <- as.numeric(sf::st_bbox(aoi))
  rgbi <- terra::rast(xmin = bbox[1], xmax = bbox[3],
                       ymin = bbox[2], ymax = bbox[4],
                       res = 0.2, crs = "EPSG:2154", nlyrs = 4)
  terra::values(rgbi) <- runif(terra::ncell(rgbi) * 4)
  out_dir <- withr::local_tempdir()

  res <- .with_dem_mock(dtm, dsm, suppressMessages(
    prepare_dem(aoi, out_dir, rgbi = rgbi, source = "wms")
  ))

  expect_equal(terra::res(res$dem), c(0.2, 0.2))
  expect_equal(terra::ncol(res$dem), terra::ncol(rgbi))
  expect_equal(terra::nrow(res$dem), terra::nrow(rgbi))
})

test_that("prepare_dem source = 'las' rejette l'absence de las_files", {
  aoi <- .aoi_test()
  out_dir <- withr::local_tempdir()
  expect_error(
    prepare_dem(aoi, out_dir, source = "las"),
    regexp = "las_files"
  )
  expect_error(
    prepare_dem(aoi, out_dir, source = "las", las_files = character()),
    regexp = "las_files"
  )
})

test_that("prepare_dem source = 'las' rejette les fichiers inexistants", {
  aoi <- .aoi_test()
  out_dir <- withr::local_tempdir()
  fake <- file.path(out_dir, "absent.laz")

  if (requireNamespace("lasR", quietly = TRUE)) {
    expect_error(
      prepare_dem(aoi, out_dir, source = "las", las_files = fake),
      regexp = "introuvables"
    )
  } else {
    expect_error(
      prepare_dem(aoi, out_dir, source = "las", las_files = fake),
      regexp = "lasR"
    )
  }
})

test_that("prepare_dem source = 'las' produit DSM + DTM via lasR sur un LAZ reel", {
  skip_if_not_installed("lasR")
  laz_dir <- "/tmp/laz_test"
  laz_files <- list.files(laz_dir, pattern = "\\.laz$", full.names = TRUE)
  skip_if(length(laz_files) == 0L,
          "Aucun LAZ disponible dans /tmp/laz_test (smoke test optionnel).")

  # AOI englobant le patch Quercus_rubra (bbox connue : ~961900, 6793650, 50 m x 50 m).
  aoi <- sf::st_sf(geometry = sf::st_sfc(
    sf::st_polygon(list(matrix(c(
      961880, 6793630,
      961970, 6793630,
      961970, 6793720,
      961880, 6793720,
      961880, 6793630
    ), ncol = 2, byrow = TRUE))), crs = 2154))

  out_dir <- withr::local_tempdir()
  res <- suppressMessages(prepare_dem(
    aoi = aoi,
    output_dir = out_dir,
    source = "las",
    las_files = laz_files[1],
    ncores = 1L
  ))

  expect_s4_class(res$dem, "SpatRaster")
  expect_equal(terra::nlyr(res$dem), 2L)
  expect_equal(names(res$dem), c("DSM", "DTM"))
  expect_equal(res$dsm_source, "lasR")
  expect_true(is.na(res$lidar_hd_coverage_pct))

  # Verifier que le DSM est >= au DTM (canopee >= sol partout)
  vals <- terra::values(res$dem)
  finite <- is.finite(vals[, 1]) & is.finite(vals[, 2])
  expect_true(any(vals[finite, 1] >= vals[finite, 2]))
})

test_that("prepare_dem rejette une source inconnue", {
  aoi <- .aoi_test()
  out_dir <- withr::local_tempdir()
  expect_error(
    prepare_dem(aoi, out_dir, source = "ftp"),
    regexp = "should be one of"
  )
})

test_that("prepare_dem reutilise le fichier en cache sans appeler le WMS", {
  aoi <- .aoi_test()
  out_dir <- withr::local_tempdir()

  # Ecrire un cache valide a la main : raster 2 bandes
  bbox <- as.numeric(sf::st_bbox(aoi))
  cache <- terra::rast(xmin = bbox[1], xmax = bbox[3],
                        ymin = bbox[2], ymax = bbox[4],
                        res = 1, crs = "EPSG:2154", nlyrs = 2)
  terra::values(cache) <- 1
  names(cache) <- c("DSM", "DTM")
  cache_path <- file.path(out_dir, "dem_2bands.tif")
  terra::writeRaster(cache, cache_path, overwrite = TRUE)

  # Si le cache est utilise, le mock ne doit jamais etre appele : on le rend
  # explosif pour le verifier.
  fake_tiled <- function(bbox, layer, res_m, output_dir, prefix, styles = "") {
    stop("le cache n'a pas ete utilise")
  }
  res <- testthat::with_mocked_bindings(
    suppressMessages(prepare_dem(aoi, out_dir, source = "wms")),
    download_ign_tiled = fake_tiled,
    .package = "maestro"
  )

  expect_equal(res$dsm_source, "cache")
  expect_equal(terra::nlyr(res$dem), 2L)
})
