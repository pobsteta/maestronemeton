#!/bin/bash
# mount_data.sh - Detecte et monte le volume data Scaleway sur /data
set -e

# Le volume additionnel est un disque sans partitions, non monte
DEVICE=""
for d in /dev/sda /dev/sdb /dev/vdb /dev/vda /dev/xvdb; do
    if [ -b "$d" ]; then
        # Ignorer les disques qui ont des partitions (disque systeme)
        if ls "${d}"[0-9]* "${d}p"[0-9]* 2>/dev/null | grep -q .; then
            continue
        fi
        # Ignorer les disques deja montes
        if mount | grep -q "^$d "; then
            continue
        fi
        DEVICE="$d"
        break
    fi
done

# Si /data est deja monte, rien a faire
if mountpoint -q /data 2>/dev/null; then
    echo "/data deja monte:"
    df -h /data
    exit 0
fi

if [ -z "$DEVICE" ]; then
    echo "ERREUR: aucun disque data trouve"
    lsblk
    exit 1
fi

echo "Device detecte: $DEVICE"

# Formater seulement si pas deja en ext4
if ! blkid "$DEVICE" 2>/dev/null | grep -q ext4; then
    echo "Formatage de $DEVICE en ext4..."
    mkfs.ext4 -q -F "$DEVICE"
fi

mkdir -p /data
mount "$DEVICE" /data
echo "Volume monte:"
df -h /data
