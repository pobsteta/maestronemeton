# Tests unitaires sur extraire_patches_multimodal() avec rasters synthetiques.
# Ne fait AUCUN download IGN ni STAC : verifie uniquement le contrat de forme
# (image_size, in_channels) et la coherence de fenetre par modalite.

# Helper : raster synthetique en Lambert-93 couvrant un carre `size_m x size_m`
# centre sur `c(cx, cy)`, avec resolution `res_m` et `n_bands` bandes.
.fake_raster <- function(cx, cy, size_m, res_m, n_bands = 1L) {
  half <- size_m / 2
  ext <- terra::ext(cx - half, cx + half, cy - half, cy + half)
  r <- terra::rast(ext = ext, res = res_m, crs = "EPSG:2154",
                    nlyrs = n_bands)
  set.seed(42)
  terra::values(r) <- runif(terra::ncell(r) * n_bands)
  names(r) <- paste0("b", seq_len(n_bands))
  r
}

# Helper : grille a 1 patch (51,2 m, centre sur l'origine du raster)
.fake_grille_1patch <- function(cx, cy, taille_patch_m = 51.2) {
  half <- taille_patch_m / 2
  poly <- sf::st_polygon(list(matrix(c(
    cx - half, cy - half,
    cx + half, cy - half,
    cx + half, cy + half,
    cx - half, cy + half,
    cx - half, cy - half
  ), ncol = 2, byrow = TRUE)))
  sf::st_sf(id = 1L,
             geometry = sf::st_sfc(poly, crs = 2154))
}


test_that("extraire_patches_multimodal respecte image_size par modalite", {
  cx <- 652500
  cy <- 6812500

  rasters <- list(
    aerial = .fake_raster(cx, cy, size_m = 100, res_m = 0.2,  n_bands = 4L),
    dem    = .fake_raster(cx, cy, size_m = 100, res_m = 0.2,  n_bands = 2L),
    s2     = .fake_raster(cx, cy, size_m = 200, res_m = 10,   n_bands = 10L),
    s1_asc = .fake_raster(cx, cy, size_m = 200, res_m = 10,   n_bands = 2L),
    s1_des = .fake_raster(cx, cy, size_m = 200, res_m = 10,   n_bands = 2L)
  )
  grille <- .fake_grille_1patch(cx, cy)

  patches <- extraire_patches_multimodal(rasters, grille)

  expect_length(patches, 1L)
  patch <- patches[[1]]

  specs <- modalite_specs()
  for (mn in names(rasters)) {
    s <- specs[[mn]]
    expect_true(mn %in% names(patch),
                info = paste("modalite", mn, "manquante"))
    mat <- patch[[mn]]
    expect_equal(nrow(mat), s$image_size * s$image_size,
                 info = paste("modalite", mn, "lignes (H*W)"))
    expect_equal(ncol(mat), s$in_channels,
                 info = paste("modalite", mn, "canaux"))
  }
})


test_that("les fenetres Sentinel et aerial peuvent differer (60m vs 51,2m)", {
  cx <- 652500
  cy <- 6812500

  # Raster aerial qui couvre 100m x 100m, raster s2 qui couvre 200m x 200m
  rasters <- list(
    aerial = .fake_raster(cx, cy, size_m = 100, res_m = 0.2, n_bands = 4L),
    s2     = .fake_raster(cx, cy, size_m = 200, res_m = 10,  n_bands = 10L)
  )
  grille <- .fake_grille_1patch(cx, cy, taille_patch_m = 51.2)

  patches <- extraire_patches_multimodal(rasters, grille)
  patch <- patches[[1]]

  expect_equal(nrow(patch$aerial), 256L * 256L)
  expect_equal(ncol(patch$aerial), 4L)
  expect_equal(nrow(patch$s2), 6L * 6L)
  expect_equal(ncol(patch$s2), 10L)
})


test_that("modalite hors emprise produit un bloc NA de la bonne taille", {
  # Raster centre tres loin du patch -> aucune intersection
  cx <- 652500
  cy <- 6812500
  far_cx <- 652500 + 10000  # 10 km a l'est

  rasters <- list(
    aerial = .fake_raster(far_cx, cy, size_m = 100, res_m = 0.2, n_bands = 4L)
  )
  grille <- .fake_grille_1patch(cx, cy)

  patches <- suppressMessages(
    extraire_patches_multimodal(rasters, grille)
  )
  expect_length(patches, 1L)
  expect_equal(nrow(patches[[1]]$aerial), 256L * 256L)
  expect_equal(ncol(patches[[1]]$aerial), 4L)
  expect_true(all(is.na(patches[[1]]$aerial)))
})


test_that("modalite inconnue declenche une erreur", {
  cx <- 652500
  cy <- 6812500

  rasters <- list(
    inconnue = .fake_raster(cx, cy, size_m = 100, res_m = 1, n_bands = 3L)
  )
  grille <- .fake_grille_1patch(cx, cy)

  expect_error(extraire_patches_multimodal(rasters, grille),
                regexp = "non supportee")
})


test_that("creer_grille_patches genere un pas coherent avec la fenetre aerial", {
  aoi <- .fake_grille_1patch(652500, 6812500, taille_patch_m = 200)
  grille <- suppressMessages(
    creer_grille_patches(aoi, taille_patch_m = 51.2)
  )

  # AOI 200m x 200m, pas 51,2m -> 4 x 4 = 16 patches au max,
  # mais seuls ceux qui intersectent l'AOI sont conserves
  expect_gte(nrow(grille), 9L)
  expect_lte(nrow(grille), 16L)
  expect_true(all(c("id", "geometry") %in% names(grille)))
})
