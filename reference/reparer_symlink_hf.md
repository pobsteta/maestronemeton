# Reparer un symlink casse du cache HuggingFace (Windows)

Sur Windows sans privileges developpeur, hfhub ne peut pas creer de
symlinks. Le fichier retourne par hub_download() pointe vers un snapshot
inexistant. Cette fonction detecte ce cas et copie le blob reel a la
place du symlink casse.

## Usage

``` r
reparer_symlink_hf(chemin)
```

## Arguments

- chemin:

  Chemin retourne par `hfhub::hub_download()`

## Value

Chemin valide (le meme si OK, ou apres copie du blob)
