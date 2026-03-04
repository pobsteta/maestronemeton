"""Script de test pour inspecter le checkpoint MAESTRO."""
import types
import sys
import torch

# Creer des faux modules maestro pour le unpickle
mod_paths = [
    "maestro",
    "maestro.conf",
    "maestro.conf.mask",
    "maestro.conf.model",
    "maestro.conf.data",
    "maestro.conf.train",
    "maestro.conf.experiment",
    "maestro.model",
    "maestro.model.mae",
]


class GenericConfig:
    """Classe stub qui accepte tout pour le unpickle."""

    def __init__(self, *args, **kwargs):
        self.__dict__.update(kwargs)

    def __repr__(self):
        return "GenericConfig(%s)" % self.__dict__

    def __setstate__(self, state):
        if isinstance(state, dict):
            self.__dict__.update(state)


for mod_path in mod_paths:
    if mod_path not in sys.modules:
        m = types.ModuleType(mod_path)
        sys.modules[mod_path] = m
        parts = mod_path.rsplit(".", 1)
        if len(parts) == 2 and parts[0] in sys.modules:
            setattr(sys.modules[parts[0]], parts[1], m)

# Ajouter les classes stub dans chaque sous-module
for mod_path in mod_paths:
    mod = sys.modules[mod_path]
    for attr in [
        "MaskConfig",
        "ModelConfig",
        "DataConfig",
        "TrainConfig",
        "ExperimentConfig",
        "Config",
        "MAE",
        "MaskedAutoencoder",
    ]:
        setattr(mod, attr, GenericConfig)

BLOB = (
    r"C:\Users\pascal.obstetar\.cache\huggingface\hub"
    r"\models--IGNF--MAESTRO_FLAIR-HUB_base\blobs"
    r"\2cc697d069bd6fe089e7e9e392cd7c810227a145a311107e493c9c7b7385e016"
)

checkpoint = torch.load(BLOB, map_location="cpu", weights_only=False)

print("TYPE:", type(checkpoint))
if isinstance(checkpoint, dict):
    print("KEYS:", list(checkpoint.keys())[:20])
    for k in checkpoint:
        v = checkpoint[k]
        if isinstance(v, dict):
            print("  %s: dict with %d keys, first keys: %s" % (k, len(v), list(v.keys())[:5]))
        elif isinstance(v, torch.Tensor):
            print("  %s: tensor %s" % (k, v.shape))
        else:
            print("  %s: %s" % (k, type(v).__name__))
elif hasattr(checkpoint, "__dict__"):
    print("ATTRS:", list(checkpoint.__dict__.keys())[:20])
else:
    print("VALUE:", repr(checkpoint)[:200])
