#!/bin/bash

set -e

IMG=disk.raw
LOOPDEV=$(losetup --find --show --partscan $IMG)

BOOTDEV=${LOOPDEV}p1
ROOTDEV=${LOOPDEV}p2

ROOT=$PWD/root
BOOT=$ROOT/boot

rm -rf $ROOT
mkdir $ROOT

set +e
mount $ROOTDEV $ROOT
FS_EXISTS=$?
set -e

if [[ $FS_EXISTS -ne 0 ]]; then
    mkfs.ext4 -b 4096 -L root $ROOTDEV
    mkfs.ext4 -b 4096 -L boot $BOOTDEV
    mount $ROOTDEV $ROOT
fi

if [[ ! -e $BOOT ]]; then
    mkdir $BOOT
fi

mount $BOOTDEV $BOOT

echo $LOOPDEV
