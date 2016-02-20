#!/bin/bash

qemu-system-x86_64 --enable-kvm -smp 1 -m 2048M -net nic,model=virtio -net user -device virtio-scsi-pci,id=scsi -device scsi-hd,drive=hd,physical_block_size=4096 -drive if=none,id=hd,file=root.fs,cache=none
