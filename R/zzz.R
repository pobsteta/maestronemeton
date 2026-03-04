# =============================================================================
# Package-level configuration and constants
# =============================================================================

# --- IGN Geoplateforme WMS-R ---
.ign_config <- new.env(parent = emptyenv())
.ign_config$WMS_URL      <- "https://data.geopf.fr/wms-r"
.ign_config$LAYER_ORTHO  <- "ORTHOIMAGERY.ORTHOPHOTOS"
.ign_config$LAYER_IRC    <- "ORTHOIMAGERY.ORTHOPHOTOS.IRC"
.ign_config$LAYER_MNT    <- "ELEVATION.ELEVATIONGRIDCOVERAGE.HIGHRES"
.ign_config$WMS_MAX_PX   <- 4096L
.ign_config$RES_IGN      <- 0.2

#' @importFrom utils read.csv write.csv
NULL

.onLoad <- function(libname, pkgname) {
  # Nothing special needed at load time
}
