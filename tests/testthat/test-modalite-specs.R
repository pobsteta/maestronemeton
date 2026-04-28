test_that("modalite_specs liste les 5 modalites MAESTRO", {
  specs <- modalite_specs()

  expect_type(specs, "list")
  expect_named(specs, c("aerial", "dem", "s2", "s1_asc", "s1_des"),
               ignore.order = TRUE)
})

test_that("image_size est multiple de patch_size_mae pour chaque modalite", {
  specs <- modalite_specs()

  for (m in names(specs)) {
    s <- specs[[m]]
    expect_equal(s$image_size %% s$patch_size_mae, 0L,
                 info = sprintf(
                   "modalite %s : image_size=%d doit etre multiple de patch_size_mae=%d",
                   m, s$image_size, s$patch_size_mae))
  }
})

test_that("window_m est coherent avec image_size * resolution", {
  specs <- modalite_specs()

  for (m in names(specs)) {
    s <- specs[[m]]
    expect_equal(s$window_m, s$image_size * s$resolution, tolerance = 1e-9,
                 info = paste("modalite", m))
  }
})

test_that("aerial et dem partagent la meme fenetre physique", {
  specs <- modalite_specs()

  expect_equal(specs$aerial$window_m, specs$dem$window_m)
  expect_equal(specs$aerial$resolution, specs$dem$resolution)
})

test_that("s1_asc, s1_des, s2 partagent la meme fenetre Sentinel", {
  specs <- modalite_specs()

  expect_equal(specs$s2$window_m, specs$s1_asc$window_m)
  expect_equal(specs$s2$window_m, specs$s1_des$window_m)
  expect_equal(specs$s2$resolution, 10)
  expect_equal(specs$s1_asc$resolution, 10)
})

test_that("nombre de canaux MAESTRO conforme au modele de base", {
  specs <- modalite_specs()

  expect_equal(specs$aerial$in_channels, 4L)   # NIR, R, G, B
  expect_equal(specs$dem$in_channels,    2L)   # DSM, DTM
  expect_equal(specs$s2$in_channels,     10L)  # B02..B12
  expect_equal(specs$s1_asc$in_channels, 2L)   # VV, VH
  expect_equal(specs$s1_des$in_channels, 2L)   # VV, VH
})

test_that("taille_patch_modalite est coherent avec modalite_specs", {
  specs <- modalite_specs()
  for (m in names(specs)) {
    expect_equal(taille_patch_modalite(m), specs[[m]]$image_size,
                 info = paste("modalite", m))
  }
  # fallback inconnu
  expect_equal(taille_patch_modalite("inexistante"), 256L)
})
