# =============================================================================
# .Rprofile - Configuration automatique de l'environnement MAESTRO
# Charge au demarrage de RStudio dans ce projet
# =============================================================================

.First <- function() {
  # Eviter le conflit OpenMP sur Windows
  Sys.setenv(KMP_DUPLICATE_LIB_OK = "TRUE")

  # Detecter le Python de l'environnement conda maestronemeton
  envname <- "maestronemeton"
  conda_dirs <- if (.Platform$OS.type == "windows") {
    home <- Sys.getenv("USERPROFILE", Sys.getenv("HOME"))
    c(file.path(home, "miniforge3"),
      file.path(home, "mambaforge"),
      file.path(home, "miniconda3"),
      file.path(home, "anaconda3"))
  } else {
    home <- Sys.getenv("HOME")
    c(file.path(home, "miniforge3"),
      file.path(home, "mambaforge"),
      file.path(home, "miniconda3"),
      file.path(home, "anaconda3"),
      "/opt/miniforge3", "/opt/miniconda3")
  }

  py_suffix <- if (.Platform$OS.type == "windows") {
    file.path("envs", envname, "python.exe")
  } else {
    file.path("envs", envname, "bin", "python")
  }

  for (d in conda_dirs) {
    py <- file.path(d, py_suffix)
    if (file.exists(py)) {
      Sys.setenv(RETICULATE_PYTHON = py)
      message("[maestronemeton] Python: ", py)
      break
    }
  }

  # NB: Ne PAS appeler py_config() ou py_module_available() ici !
  # Cela forcerait l'initialisation de Python avec le mauvais interpreteur
  # (uv/reticulate au lieu de conda maestronemeton). La verification des
  # modules se fait dans configurer_python() au moment de l'inference.

  message("[maestronemeton] Environnement configure. Token HF: ",
          if (nchar(Sys.getenv("HUGGING_FACE_HUB_TOKEN")) > 0) "OK" else "MANQUANT")
}
