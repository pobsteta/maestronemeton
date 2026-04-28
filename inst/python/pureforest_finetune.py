#!/usr/bin/env python3
"""
pureforest_finetune.py
======================

Fine-tuning de MAESTRO sur le dataset PureForest (mono-label, 13 classes).

Strategie en deux temps (cf. DEV_PLAN.md sec. 6.1, fiche HF
`IGNF/MAESTRO_FLAIR-HUB_base`) :

  1. Linear probe : encodeur fige, head 13 classes entrainee seule
     (10 epochs, AdamW, LR_head = 1e-3, weight_decay = 1e-4).
  2. Fine-tune complet : encodeur degele, LR differentielle
     (encodeur 1e-5, head 1e-4), 50 epochs, scheduler cosine,
     early stopping patience = 5 sur balanced_accuracy_val.

Metrique principale : balanced_accuracy (compense le desequilibre
PureForest, e.g. Sapin = 0,14 % en train).

Sauvegarde un checkpoint `.pt` au format compatible avec
`maestro_inference.charger_modele_finetune()`.

Usage
-----

    # Smoke test 2 epochs sur CPU
    python pureforest_finetune.py \\
        --checkpoint /chemin/pretrain-epoch=99.ckpt \\
        --data-dir   data/pureforest_maestro \\
        --output     outputs/training/maestro_pureforest_smoke.pt \\
        --probe-epochs 2 --finetune-epochs 0 --batch-size 8

    # Run complet (Scaleway L4-1-24G ~12-18 h)
    python pureforest_finetune.py \\
        --checkpoint $CHECKPOINT --data-dir /data/pureforest_maestro \\
        --output    /data/outputs/training/maestro_pureforest_best.pt \\
        --modalities aerial \\
        --probe-epochs 10 --finetune-epochs 50 --batch-size 24 \\
        --gpu --workers 4
"""

from __future__ import annotations

import argparse
import io
import json
import logging
import sys
import warnings
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import DataLoader

# Architecture MAESTRO
sys.path.insert(0, str(Path(__file__).resolve().parent))
from maestro_inference import (
    MAESTROClassifier, MODALITIES, S1_ENCODER_KEY,
    _install_maestro_stubs, _resoudre_chemin_hf,
)
from pureforest_dataset import (
    PureForestDataset, PUREFOREST_CLASSES, N_CLASSES, collate_multimodal,
)

warnings.filterwarnings("ignore", message=".*GDAL_NODATA.*")
logging.getLogger("tifffile").setLevel(logging.ERROR)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--checkpoint", required=True,
                   help="Checkpoint MAESTRO pre-entraine (.ckpt / .safetensors)")
    p.add_argument("--data-dir", required=True,
                   help="Racine du dataset PureForest pre-traite "
                        "(sortie de prepare_pureforest_aerial.py)")
    p.add_argument("--output", required=True,
                   help="Chemin de sortie du checkpoint fine-tune (.pt)")
    p.add_argument("--modalities", nargs="+", default=["aerial"],
                   help="Modalites a utiliser (defaut: aerial). "
                        "Choix: aerial dem s2 s1_asc s1_des")
    p.add_argument("--probe-epochs", type=int, default=10,
                   help="Epochs linear probe (encodeur fige) [defaut: 10]")
    p.add_argument("--finetune-epochs", type=int, default=50,
                   help="Epochs fine-tune complet [defaut: 50]")
    p.add_argument("--batch-size", type=int, default=24,
                   help="Batch size [defaut: 24]")
    p.add_argument("--lr-head", type=float, default=1e-3,
                   help="LR head pendant le probe [defaut: 1e-3]")
    p.add_argument("--lr-finetune-head", type=float, default=1e-4,
                   help="LR head pendant le fine-tune [defaut: 1e-4]")
    p.add_argument("--lr-encoder", type=float, default=1e-5,
                   help="LR encodeur pendant le fine-tune [defaut: 1e-5]")
    p.add_argument("--weight-decay", type=float, default=1e-4,
                   help="Weight decay AdamW [defaut: 1e-4]")
    p.add_argument("--patience", type=int, default=5,
                   help="Early stopping patience [defaut: 5]")
    p.add_argument("--workers", type=int, default=4,
                   help="DataLoader num_workers [defaut: 4]")
    p.add_argument("--gpu", action="store_true",
                   help="Utiliser CUDA si disponible")
    p.add_argument("--no-augment", action="store_true",
                   help="Desactive l'augmentation flip H/V")
    p.add_argument("--seed", type=int, default=42)
    return p.parse_args()


# ---------------------------------------------------------------------------
# Chargement du backbone MAESTRO pre-entraine
# ---------------------------------------------------------------------------

def load_pretrained_backbone(checkpoint_path: Path,
                              modalities: list[str],
                              device: torch.device) -> MAESTROClassifier:
    """Construit MAESTROClassifier et charge les poids du backbone uniquement."""
    mod_config = {m: MODALITIES[m] for m in modalities if m in MODALITIES}
    if not mod_config:
        raise ValueError(f"Aucune modalite valide dans {modalities}. "
                          f"Choix : {list(MODALITIES)}")

    model = MAESTROClassifier(
        embed_dim=768, encoder_depth=9, inter_depth=3,
        num_heads=12, n_classes=N_CLASSES,
        modalities=mod_config,
    )

    chemin = Path(checkpoint_path)
    if chemin.suffix == ".safetensors":
        from safetensors.torch import load_file
        state_dict = load_file(str(chemin), device=str(device))
    else:
        _install_maestro_stubs()
        chemin_reel = _resoudre_chemin_hf(chemin)
        with open(str(chemin_reel), "rb") as f:
            buffer = io.BytesIO(f.read())
        ckpt = torch.load(buffer, map_location=device, weights_only=False)
        if isinstance(ckpt, dict):
            state_dict = ckpt.get("state_dict",
                                    ckpt.get("model", ckpt))
        else:
            state_dict = ckpt

    # Filtrer les cles backbone (encodeur + patch_embed des modalites demandees)
    prefixes = ["model.encoder_inter."]
    for m in modalities:
        prefixes.append(f"model.patch_embed.{m}.")
        enc = S1_ENCODER_KEY if m.startswith("s1_") else m
        prefixes.append(f"model.encoder.{enc}.")
    prefix_tuple = tuple(prefixes)

    filtered = {k: v for k, v in state_dict.items()
                 if k.startswith(prefix_tuple)}
    missing, unexpected = model.load_state_dict(filtered, strict=False)
    head_missing  = [k for k in missing if k.startswith("head.")]
    other_missing = [k for k in missing if not k.startswith("head.")]
    print(f"  Backbone : {len(filtered)} cles chargees, "
          f"head : {len(head_missing)} cles aleatoires (attendu)")
    if other_missing:
        print(f"  [WARN] Cles backbone manquantes : {len(other_missing)}")
        for k in other_missing[:5]:
            print(f"    - {k}")

    return model.to(device)


# ---------------------------------------------------------------------------
# Class weights & metriques
# ---------------------------------------------------------------------------

def inverse_frequency_weights(targets: list[int],
                                n_classes: int = N_CLASSES) -> torch.Tensor:
    counts = np.bincount(targets, minlength=n_classes).astype(np.float64)
    counts = np.maximum(counts, 1.0)
    weights = 1.0 / counts
    weights = weights / weights.sum() * n_classes
    return torch.tensor(weights, dtype=torch.float32)


def balanced_accuracy(preds: list[int], labels: list[int],
                        n_classes: int = N_CLASSES) -> float:
    correct_per_class = np.zeros(n_classes, dtype=np.float64)
    total_per_class   = np.zeros(n_classes, dtype=np.float64)
    for p, l in zip(preds, labels):
        if 0 <= l < n_classes:
            total_per_class[l] += 1
            if p == l:
                correct_per_class[l] += 1
    valid = total_per_class > 0
    if not valid.any():
        return 0.0
    per_class_acc = np.zeros(n_classes)
    per_class_acc[valid] = correct_per_class[valid] / total_per_class[valid]
    return float(per_class_acc[valid].mean())


def f1_macro(preds: list[int], labels: list[int],
              n_classes: int = N_CLASSES) -> float:
    f1s = []
    preds_arr  = np.asarray(preds)
    labels_arr = np.asarray(labels)
    for c in range(n_classes):
        tp = int(((preds_arr == c) & (labels_arr == c)).sum())
        fp = int(((preds_arr == c) & (labels_arr != c)).sum())
        fn = int(((preds_arr != c) & (labels_arr == c)).sum())
        if tp + fp == 0 or tp + fn == 0:
            continue
        precision = tp / (tp + fp)
        recall    = tp / (tp + fn)
        if precision + recall == 0:
            continue
        f1s.append(2 * precision * recall / (precision + recall))
    return float(np.mean(f1s)) if f1s else 0.0


def confusion_matrix(preds: list[int], labels: list[int],
                      n_classes: int = N_CLASSES) -> np.ndarray:
    cm = np.zeros((n_classes, n_classes), dtype=np.int64)
    for p, l in zip(preds, labels):
        if 0 <= l < n_classes and 0 <= p < n_classes:
            cm[l, p] += 1
    return cm


# ---------------------------------------------------------------------------
# Boucle d'entrainement
# ---------------------------------------------------------------------------

def run_epoch(model, loader, criterion, optimizer, device,
                augment: bool = False, train: bool = True) -> tuple[float, list[int], list[int]]:
    if train:
        model.train()
    else:
        model.eval()

    total_loss = 0.0
    n_seen = 0
    all_preds, all_labels = [], []

    ctx = torch.enable_grad() if train else torch.no_grad()
    with ctx:
        for batch_idx, (inputs, targets) in enumerate(loader):
            inputs = {k: v.to(device, non_blocking=True)
                       for k, v in inputs.items()}
            targets = targets.to(device, non_blocking=True)

            if train and augment:
                if torch.rand(1).item() > 0.5:
                    inputs = {k: torch.flip(v, dims=[-1])
                               for k, v in inputs.items()}
                if torch.rand(1).item() > 0.5:
                    inputs = {k: torch.flip(v, dims=[-2])
                               for k, v in inputs.items()}

            if train:
                optimizer.zero_grad()
            logits = model(inputs)
            loss = criterion(logits, targets)

            if train:
                loss.backward()
                optimizer.step()

            preds = logits.argmax(dim=1)
            total_loss += loss.item() * targets.size(0)
            n_seen     += targets.size(0)
            all_preds.extend(preds.cpu().tolist())
            all_labels.extend(targets.cpu().tolist())

            if train and (batch_idx + 1) % 50 == 0:
                running = sum(p == l for p, l in zip(all_preds, all_labels))
                running_acc = running / max(n_seen, 1) * 100
                print(f"    batch {batch_idx + 1}/{len(loader)} | "
                      f"loss={loss.item():.4f} | acc={running_acc:.1f}%",
                      flush=True)

    avg_loss = total_loss / max(n_seen, 1)
    return avg_loss, all_preds, all_labels


def save_checkpoint(model, output_path: Path, *, epoch: int, val_acc: float,
                     val_bacc: float, modalities: list[str],
                     extra: dict | None = None) -> None:
    payload = {
        "state_dict":   model.state_dict(),
        "epoch":        int(epoch),
        "val_acc":      float(val_acc),
        "val_bacc":     float(val_bacc),
        "n_classes":    int(N_CLASSES),
        "classes":      list(PUREFOREST_CLASSES),
        "modalites":    list(modalities),
        "dataset":      "pureforest",
    }
    if extra:
        payload.update(extra)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    torch.save(payload, str(output_path))


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    args = parse_args()

    torch.manual_seed(args.seed)
    np.random.seed(args.seed)

    device = torch.device("cuda" if args.gpu and torch.cuda.is_available()
                           else "cpu")
    print(f"Device : {device}")
    if device.type == "cuda":
        props = torch.cuda.get_device_properties(0)
        print(f"  GPU  : {props.name}, VRAM {props.total_memory / 1e9:.1f} Go")

    print(f"Modalites : {args.modalities}")
    print(f"Output    : {args.output}")

    # --- Datasets ---
    print("\n=== Chargement PureForest ===")
    train_ds = PureForestDataset(
        args.data_dir, split="train",
        modalities=args.modalities, normalize=True)
    val_ds = PureForestDataset(
        args.data_dir, split="validation",
        modalities=args.modalities, normalize=True)

    if len(train_ds) == 0:
        print("ERREUR: split train vide.", file=sys.stderr)
        return 1

    train_loader = DataLoader(
        train_ds, batch_size=args.batch_size, shuffle=True,
        num_workers=args.workers, collate_fn=collate_multimodal,
        pin_memory=(device.type == "cuda"), drop_last=True)
    val_loader = DataLoader(
        val_ds, batch_size=args.batch_size, shuffle=False,
        num_workers=args.workers, collate_fn=collate_multimodal,
        pin_memory=(device.type == "cuda"))

    # --- Class weights (sur le split train) ---
    train_targets = [lbl for _, lbl in train_ds.samples]
    class_weights = inverse_frequency_weights(train_targets).to(device)
    print(f"  Distribution : {np.bincount(train_targets, minlength=N_CLASSES).tolist()}")
    print(f"  Class weights : {class_weights.cpu().round(decimals=2).tolist()}")

    criterion = nn.CrossEntropyLoss(weight=class_weights)

    # --- Modele ---
    print("\n=== Chargement backbone MAESTRO ===")
    model = load_pretrained_backbone(args.checkpoint, args.modalities, device)
    n_params = sum(p.numel() for p in model.parameters())
    print(f"  Parametres totaux : {n_params:,}")

    history = {"phase": [], "epoch": [], "train_loss": [], "val_loss": [],
                "train_acc": [], "val_acc": [],
                "val_bacc": [], "val_f1": []}

    best_val_bacc = 0.0
    best_epoch = 0
    output_path = Path(args.output)

    # ------------------------------------------------------------------
    # Phase A : Linear probe (encodeur fige)
    # ------------------------------------------------------------------
    if args.probe_epochs > 0:
        print("\n=== Phase A : Linear probe (encodeur fige) ===")
        for n, p in model.named_parameters():
            p.requires_grad = n.startswith("head.")
        n_trainable = sum(p.numel() for p in model.parameters()
                            if p.requires_grad)
        print(f"  Parametres entrainables : {n_trainable:,}")

        optimizer = optim.AdamW(
            filter(lambda p: p.requires_grad, model.parameters()),
            lr=args.lr_head, weight_decay=args.weight_decay)
        scheduler = optim.lr_scheduler.CosineAnnealingLR(
            optimizer, T_max=args.probe_epochs)

        for epoch in range(1, args.probe_epochs + 1):
            print(f"\n  --- Probe epoch {epoch}/{args.probe_epochs} ---")
            tr_loss, _, _ = run_epoch(model, train_loader, criterion,
                                          optimizer, device,
                                          augment=not args.no_augment, train=True)
            v_loss, v_preds, v_labels = run_epoch(model, val_loader, criterion,
                                                       None, device, train=False)
            scheduler.step()

            v_acc  = sum(p == l for p, l in zip(v_preds, v_labels)) / max(len(v_labels), 1) * 100
            v_bacc = balanced_accuracy(v_preds, v_labels) * 100
            v_f1   = f1_macro(v_preds, v_labels) * 100

            history["phase"].append("probe")
            history["epoch"].append(epoch)
            history["train_loss"].append(tr_loss)
            history["val_loss"].append(v_loss)
            history["val_acc"].append(v_acc)
            history["val_bacc"].append(v_bacc)
            history["val_f1"].append(v_f1)

            print(f"  train_loss={tr_loss:.4f} | val_loss={v_loss:.4f} | "
                  f"acc={v_acc:.1f}% | bacc={v_bacc:.1f}% | f1={v_f1:.1f}%")

            if v_bacc > best_val_bacc:
                best_val_bacc = v_bacc
                best_epoch    = epoch
                save_checkpoint(model, output_path,
                                  epoch=epoch, val_acc=v_acc, val_bacc=v_bacc,
                                  modalities=args.modalities,
                                  extra={"phase": "probe", "history": history})
                print(f"    -> meilleur (bacc={v_bacc:.1f}%) sauvegarde")

    # ------------------------------------------------------------------
    # Phase B : Fine-tune complet (encodeur degele, LR differentielle)
    # ------------------------------------------------------------------
    if args.finetune_epochs > 0:
        print("\n=== Phase B : Fine-tune complet ===")
        for p in model.parameters():
            p.requires_grad = True

        head_params    = [p for n, p in model.named_parameters()
                            if n.startswith("head.")]
        encoder_params = [p for n, p in model.named_parameters()
                            if not n.startswith("head.")]
        optimizer = optim.AdamW([
            {"params": head_params,    "lr": args.lr_finetune_head},
            {"params": encoder_params, "lr": args.lr_encoder},
        ], weight_decay=args.weight_decay)
        scheduler = optim.lr_scheduler.CosineAnnealingLR(
            optimizer, T_max=args.finetune_epochs)

        patience_counter = 0
        for epoch in range(1, args.finetune_epochs + 1):
            print(f"\n  --- Fine-tune epoch {epoch}/{args.finetune_epochs} ---")
            tr_loss, _, _ = run_epoch(model, train_loader, criterion,
                                          optimizer, device,
                                          augment=not args.no_augment, train=True)
            v_loss, v_preds, v_labels = run_epoch(model, val_loader, criterion,
                                                       None, device, train=False)
            scheduler.step()

            v_acc  = sum(p == l for p, l in zip(v_preds, v_labels)) / max(len(v_labels), 1) * 100
            v_bacc = balanced_accuracy(v_preds, v_labels) * 100
            v_f1   = f1_macro(v_preds, v_labels) * 100

            history["phase"].append("finetune")
            history["epoch"].append(epoch + args.probe_epochs)
            history["train_loss"].append(tr_loss)
            history["val_loss"].append(v_loss)
            history["val_acc"].append(v_acc)
            history["val_bacc"].append(v_bacc)
            history["val_f1"].append(v_f1)

            print(f"  train_loss={tr_loss:.4f} | val_loss={v_loss:.4f} | "
                  f"acc={v_acc:.1f}% | bacc={v_bacc:.1f}% | f1={v_f1:.1f}%")

            if v_bacc > best_val_bacc:
                best_val_bacc = v_bacc
                best_epoch    = epoch + args.probe_epochs
                patience_counter = 0
                save_checkpoint(model, output_path,
                                  epoch=best_epoch, val_acc=v_acc, val_bacc=v_bacc,
                                  modalities=args.modalities,
                                  extra={"phase": "finetune",
                                            "history": history})
                print(f"    -> meilleur (bacc={v_bacc:.1f}%) sauvegarde")
            else:
                patience_counter += 1
                if patience_counter >= args.patience:
                    print(f"  Early stopping (patience={args.patience})")
                    break

    # ------------------------------------------------------------------
    # Evaluation finale sur le test
    # ------------------------------------------------------------------
    print("\n=== Evaluation finale sur test ===")
    try:
        test_ds = PureForestDataset(
            args.data_dir, split="test",
            modalities=args.modalities, normalize=True)
        test_loader = DataLoader(
            test_ds, batch_size=args.batch_size, shuffle=False,
            num_workers=args.workers, collate_fn=collate_multimodal,
            pin_memory=(device.type == "cuda"))

        # Recharger le meilleur checkpoint
        best = torch.load(str(output_path), map_location=device,
                            weights_only=False)
        model.load_state_dict(best["state_dict"])

        _, t_preds, t_labels = run_epoch(model, test_loader, criterion,
                                              None, device, train=False)
        t_acc  = sum(p == l for p, l in zip(t_preds, t_labels)) / max(len(t_labels), 1) * 100
        t_bacc = balanced_accuracy(t_preds, t_labels) * 100
        t_f1   = f1_macro(t_preds, t_labels) * 100
        cm     = confusion_matrix(t_preds, t_labels)

        print(f"  test_acc={t_acc:.1f}% bacc={t_bacc:.1f}% f1={t_f1:.1f}%")
        print("\n  Per-class accuracy :")
        for c in range(N_CLASSES):
            n = int(cm[c].sum())
            if n == 0:
                continue
            acc_c = cm[c, c] / n * 100
            print(f"    {c:2d} {PUREFOREST_CLASSES[c]:20s}: {acc_c:5.1f}% "
                  f"({cm[c, c]}/{n})")

        report_path = output_path.with_suffix(".report.json")
        report_path.write_text(json.dumps({
            "best_epoch":  best_epoch,
            "best_val_bacc": best_val_bacc,
            "test_acc":    t_acc,
            "test_bacc":   t_bacc,
            "test_f1":     t_f1,
            "confusion_matrix": cm.tolist(),
            "classes":     PUREFOREST_CLASSES,
            "modalities":  args.modalities,
            "history":     history,
        }, indent=2))
        print(f"  Rapport : {report_path}")
    except Exception as e:
        print(f"  [WARN] Evaluation test echouee : {e}")

    print(f"\nMeilleur checkpoint : {output_path} (bacc={best_val_bacc:.1f}%)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
