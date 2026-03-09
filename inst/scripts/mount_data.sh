#!/bin/bash
# mount_data.sh - Detecte et monte le volume data Scaleway sur /data
set -e

# Le volume additionnel peut apparaitre comme /dev/sdb, /dev/vdb ou /dev/xvdb
DEVICE=""
for d in /dev/sdb /dev/vdb /dev/xvdb; do
    if [ -b "$d" ]; then
        # Verifier que ce n'est pas deja monte
        if ! mount | grep -q "^$d "; then
            DEVICE="$d"
            break
        fi
    fi
done

if [ -z "$DEVICE" ]; then
    echo "ERREUR: aucun disque data trouve"
    lsblk
    exit 1
fi

echo "Device detecte: $DEVICE"

# Formater seulement si pas deja en ext4
if ! blkid "$DEVICE" 2>/dev/null | grep -q ext4; then
    echo "Formatage de $DEVICE en ext4..."
    mkfs.ext4 -q "$DEVICE"
fi

mkdir -p /data
mount "$DEVICE" /data
echo "Volume monte:"
df -h /data
