#!/usr/bin/env Rscript
# =============================================================================
# test_pipeline.R - validation E2E du wiring MAESTRO multi-modal
#
# Couvre :
#   - Test 1 : configuration Python (conda env maestro)
#   - Test 2 : chargement du modele MAESTRO_FLAIR-HUB_base
#   - Test 3 : forward pass avec tenseurs synthetiques pour chaque combinaison
#              de modalites (aerial seul, aerial+dem, multi-modal complet)
#   - Test 4 : pipeline complet sur AOI Fontainebleau (RUN_E2E=1, lent,
#              telecharge ~50 Mo d'orthos IGN)
#
# Usage :
#   Rscript inst/scripts/test_pipeline.R              # tests 1-3 (rapide, ~1 min)
#   RUN_E2E=1 Rscript inst/scripts/test_pipeline.R    # ajoute le test 4
# =============================================================================

suppressPackageStartupMessages({
  if (file.exists("DESCRIPTION") &&
      requireNamespace("devtools", quietly = TRUE)) {
    devtools::load_all(quiet = TRUE)
  } else {
    library(maestro)
  }
})

run_e2e <- !identical(Sys.getenv("RUN_E2E"), "")

# --- Test 1 : configuration Python ---
message("\n=== TEST 1 : Configuration Python ===")
configurer_python()

# --- Test 2 : chargement du modele ---
message("\n=== TEST 2 : Chargement du modele MAESTRO ===")
py_path <- if (file.exists("inst/python/maestro_inference.py")) {
  normalizePath("inst/python")
} else {
  python_module_path()
}
maestro_py <- reticulate::import_from_path("maestro_inference", path = py_path)
np <- reticulate::import("numpy")

fichiers <- telecharger_modele("IGNF/MAESTRO_FLAIR-HUB_base")
chemin_poids <- fichiers$weights %||% fichiers$snapshot
stopifnot(!is.null(chemin_poids))

# --- Test 3 : forward pass synthetique par combinaison de modalites ---
message("\n=== TEST 3 : Forward pass multi-modal synthetique ===")
specs <- modalite_specs()

# Generateur de tenseur (B, C, H, W) aleatoire pour une modalite
fake_input <- function(mod_name, batch = 1L) {
  s <- specs[[mod_name]]
  np$array(
    np$random$randn(as.integer(batch),
                      as.integer(s$in_channels),
                      as.integer(s$image_size),
                      as.integer(s$image_size)),
    dtype = np$float32
  )
}

cas_tests <- list(
  "aerial seul"           = c("aerial"),
  "aerial + dem"          = c("aerial", "dem"),
  "aerial + s2"           = c("aerial", "s2"),
  "aerial + dem + s2 + s1" = c("aerial", "dem", "s2", "s1_asc", "s1_des")
)

for (nom in names(cas_tests)) {
  mods <- cas_tests[[nom]]
  message(sprintf("\n--- %s (%s) ---", nom, paste(mods, collapse = ", ")))

  modele <- maestro_py$charger_modele(
    chemin_poids = chemin_poids,
    n_classes = 13L,
    device = "cpu",
    modalites = as.list(mods)
  )

  donnees <- setNames(lapply(mods, fake_input), mods)

  result <- maestro_py$predire_multimodal(modele, donnees, device = "cpu")
  classe_idx <- result$classes[[1]]
  essence    <- result$essences[[1]]
  message(sprintf("  Prediction : classe %d -> %s (random input, valeur indicative)",
                   classe_idx, essence))

  # Verifications de forme
  stopifnot(length(result$classes) == 1L)
  stopifnot(length(result$probabilites[[1]]) == 13L)
}

message("\n  Toutes les combinaisons de modalites passent.")

# --- Test 4 : pipeline complet sur AOI ---
message("\n=== TEST 4 : Pipeline complet AOI Fontainebleau ===")

aoi_path <- "data/aoi.gpkg"

if (!run_e2e) {
  message("  IGNORE (RUN_E2E non defini).")
  message("  Pour lancer le test E2E reel : RUN_E2E=1 Rscript inst/scripts/test_pipeline.R")
  message("  (telecharge ~50 Mo d'orthos IGN, dure ~3 min sur CPU)")
} else if (!file.exists(aoi_path)) {
  message(sprintf("  IGNORE : %s introuvable.", aoi_path))
  message("  Pour creer l'AOI Fontainebleau : Rscript inst/scripts/creer_aoi_exemple.R")
} else {
  message(sprintf("  AOI : %s", aoi_path))
  result <- maestro_pipeline(
    aoi_path   = aoi_path,
    output_dir = "outputs_test",
    modalites  = c("aerial"),     # MVP phase 1 : aerial seul
    gpu        = FALSE
  )

  stopifnot(!is.null(result$grille))
  stopifnot(!is.null(result$raster))
  stopifnot("aerial" %in% result$modalites)

  message(sprintf("  Resultat : %d patches, modalites = %s",
                   nrow(result$grille),
                   paste(result$modalites, collapse = ", ")))
  message("  outputs_test/essences_forestieres.gpkg + .tif + statistiques.csv")
}

message("\n=== TOUS LES TESTS PASSES ===")
