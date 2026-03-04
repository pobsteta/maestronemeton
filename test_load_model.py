"""Test de chargement du modele MAESTRO multi-modal."""
import torch
from maestro_inference import charger_modele

BLOB = (
    r"C:\Users\pascal.obstetar\.cache\huggingface\hub"
    r"\models--IGNF--MAESTRO_FLAIR-HUB_base\blobs"
    r"\2cc697d069bd6fe089e7e9e392cd7c810227a145a311107e493c9c7b7385e016"
)

# Test 1: aerial seul
print("=" * 60)
print("TEST 1: aerial seul")
print("=" * 60)
modele = charger_modele(BLOB, n_classes=13, device="cpu",
                         modalites=["aerial"])

dummy = torch.randn(1, 4, 256, 256)
with torch.no_grad():
    logits = modele(dummy)
print("  Output shape:", logits.shape)
print("  OK!\n")

# Test 2: aerial + DEM
print("=" * 60)
print("TEST 2: aerial + DEM")
print("=" * 60)
modele2 = charger_modele(BLOB, n_classes=13, device="cpu",
                          modalites=["aerial", "dem"])

inputs = {
    "aerial": torch.randn(1, 4, 256, 256),
    "dem": torch.randn(1, 2, 256, 256),
}
with torch.no_grad():
    logits2 = modele2(inputs)
print("  Output shape:", logits2.shape)
print("  OK!\n")

# Test 3: toutes les modalites
print("=" * 60)
print("TEST 3: toutes les modalites")
print("=" * 60)
modele3 = charger_modele(BLOB, n_classes=13, device="cpu")

inputs_all = {
    "aerial": torch.randn(1, 4, 256, 256),
    "dem": torch.randn(1, 2, 256, 256),
    "spot": torch.randn(1, 3, 256, 256),
    "s1_asc": torch.randn(1, 2, 32, 32),
    "s1_des": torch.randn(1, 2, 32, 32),
    "s2": torch.randn(1, 10, 32, 32),
}
with torch.no_grad():
    logits3 = modele3(inputs_all)
print("  Output shape:", logits3.shape)
print("  OK!\n")

print("Tous les tests passes!")
