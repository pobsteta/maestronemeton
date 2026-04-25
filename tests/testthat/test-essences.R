test_that("essences_pureforest retourne 13 classes ordonnees 0..12", {
  ess <- essences_pureforest()

  expect_s3_class(ess, "data.frame")
  expect_equal(nrow(ess), 13L)
  expect_equal(ess$code, 0:12)
  expect_named(ess, c("code", "classe", "nom_latin", "type"),
               ignore.order = TRUE)
})

test_that("le mapping PureForest correspond a la fiche IGN/PureForest", {
  ess <- essences_pureforest()

  expect_equal(ess$classe[ess$code == 0L], "Chene decidu")
  expect_equal(ess$classe[ess$code == 4L], "Robinier")
  expect_equal(ess$classe[ess$code == 5L], "Pin maritime")
  expect_equal(ess$classe[ess$code == 9L], "Sapin")
  expect_equal(ess$classe[ess$code == 10L], "Epicea")
  expect_equal(ess$classe[ess$code == 12L], "Douglas")

  expect_equal(ess$nom_latin[ess$code == 4L], "Robinia pseudoacacia")
  expect_equal(ess$nom_latin[ess$code == 9L], "Abies alba")
  expect_equal(ess$nom_latin[ess$code == 10L], "Picea abies")
  expect_equal(ess$nom_latin[ess$code == 12L], "Pseudotsuga menziesii")
})

test_that("Robinier est present et Peuplier (absent de PureForest) ne l'est pas", {
  ess <- essences_pureforest()

  expect_true("Robinier" %in% ess$classe)
  expect_false("Peuplier" %in% ess$classe)
  expect_false(any(grepl("Populus", ess$nom_latin)))
})

test_that("la repartition feuillus/resineux est coherente", {
  ess <- essences_pureforest()

  feuillus <- ess$classe[ess$type == "feuillu"]
  resineux <- ess$classe[ess$type == "resineux"]

  expect_setequal(feuillus,
                   c("Chene decidu", "Chene vert", "Hetre",
                     "Chataignier", "Robinier"))
  expect_setequal(resineux,
                   c("Pin maritime", "Pin sylvestre", "Pin noir",
                     "Pin d'Alep", "Sapin", "Epicea", "Meleze", "Douglas"))
})
