# =============================================================================
# predict_treesatai.R
# Prediction des essences forestieres avec le modele fine-tune TreeSatAI
#
# Pre-requis :
#   - maestro_treesatai_best.pt (modele entraine)
#   - data/aoi.gpkg (zone d'interet en Lambert-93)
#   - conda env maestro avec torch, numpy, safetensors, tifffile, Pillow
# =============================================================================

library(maestro)

# --- Parametres ---
aoi_path   <- "data/aoi.gpkg"
checkpoint <- "maestro_treesatai_best.pt"
output_dir <- "outputs"
use_gpu    <- FALSE

# --- Lancer le pipeline complet ---
# Telecharge les orthos IGN + DEM, decoupe en patches, inference, export
resultats <- maestro_pipeline(
  aoi_path   = aoi_path,
  checkpoint = checkpoint,
  output_dir = output_dir,
  gpu        = use_gpu
)

# --- Resultats ---
# outputs/essences_forestieres.gpkg  -> carte vectorielle
# outputs/essences_forestieres.tif   -> carte raster
# outputs/statistiques.csv           -> stats par classe
