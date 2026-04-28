#!/bin/bash
cd /root/maestro_nemeton
CKPT=$(find /data/.cache/huggingface -name "pretrain-epoch=99.ckpt" 2>/dev/null | head -1)
if [ -z "$CKPT" ]; then
    echo "ERREUR: checkpoint non trouve"
    exit 1
fi
echo "Checkpoint: $CKPT"
HF_HOME=/data/hf_cache /data/venv_maestro/bin/python inst/python/train_treesatai.py \
    --checkpoint "$CKPT" \
    --data-dir /data/treesatai \
    --output-dir /data/outputs/training \
    --modalites aerial \
    --epochs 1 \
    --batch-size 64 \
    --lr 1e-3 \
    --gpu \
    --workers 4 2>&1
