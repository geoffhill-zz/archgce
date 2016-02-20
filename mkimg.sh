#!/bin/bash

HOSTNAME="${HOSTNAME:-arch.gfrh.net}"
SIZE="${SIZE:-4G}"

set -e

# Ensure the required utilities are installed.
pacman -Q util-linux
pacman -Q arch-install-scripts
pacman -Q syslinux

IMG=root.fs
rm -f $IMG
truncate -s $SIZE $IMG
sfdisk $IMG <<'EOF'
label: dos
start=2048,size=128M,type=83,bootable
type=83
EOF

LOOPDEV="$(losetup --find --show --partscan $IMG)"

BOOTDEV=${LOOPDEV}p1
ROOTDEV=${LOOPDEV}p2

mkfs.ext4 -q -b 4096 -L boot $BOOTDEV
mkfs.ext4 -q -b 4096 -L root $ROOTDEV

ROOT=$PWD/root
BOOT=$ROOT/boot
rm -rf $ROOT; mkdir $ROOT
mount $ROOTDEV $ROOT
mkdir $BOOT
mount $BOOTDEV $BOOT

set +e

pacstrap -c -M $ROOT base base-devel syslinux openssh sudo mg

echo $HOSTNAME > $ROOT/etc/hostname
ln -s ../usr/share/zoneinfo/UTC $ROOT/etc/localtime
echo en_US.UTF-8 UTF-8 >> $ROOT/etc/locale.gen
echo "LANG=en_US.UTF-8" > $ROOT/etc/locale.conf

cat >> $ROOT/etc/pacman.d/mirrorlist <<'EOF'
Server = http://lug.mtu.edu/archlinux/$repo/os/$arch
Server = http://mirror.rit.edu/archlinux/$repo/os/$arch
EOF

cat > $ROOT/etc/iptables/iptables.rules <<'EOF'
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
:TCP - [0:0]
:UDP - [0:0]
-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A INPUT -m conntrack --ctstate INVALID -j DROP
-A INPUT -p icmp -m icmp --icmp-type 8 -m conntrack --ctstate NEW -j ACCEPT
-A INPUT -p udp -m conntrack --ctstate NEW -j UDP
-A INPUT -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j TCP
-A INPUT -p udp -j REJECT --reject-with icmp-port-unreachable
-A INPUT -p tcp -j REJECT --reject-with tcp-reset
-A INPUT -j REJECT --reject-with icmp-proto-unreachable
-A TCP -p tcp -m tcp --dport 22 -j ACCEPT
COMMIT

echo "geoff ALL=(ALL) ALL" >> $ROOT/etc/sudoers
syslinux-install_update -i -a -m -c $ROOT/

arch-chroot <<'EOF'
locale-gen
systemctl enable dhcpcd@enp1s0
systemctl enable sshd.service
systemctl enable iptables.service
EOF

umount -R $ROOT
losetup -d $ROOTDEV
losetup -d $BOOTDEV
