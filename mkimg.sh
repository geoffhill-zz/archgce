#!/bin/bash

HNAME="${HNAME:-arch.gfrh.net}"
USERKEY=/home/geoff/.ssh/id_rsa.pub
SIZE="${SIZE:-4G}"

randpass() {
    cat /dev/urandom | tr -dc "A-Fa-f0-9" | fold -w 32 | head -n 1
}

# Ensure the required utilities are installed.
pacman -Q util-linux
pacman -Q arch-install-scripts
pacman -Q syslinux

IMG=disk.raw
rm -f $IMG
truncate -s $SIZE $IMG
chmod 666 $IMG
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
pacstrap -c -M $ROOT base syslinux openssh ntp sudo mg git tmux
set -e

cat >> $ROOT/etc/fstab <<'EOF'
/dev/sda2  /       ext4    rw,relatime,data=ordered    0 1
/dev/sda1  /boot   ext4    rw,relatime,data=ordered    0 2
EOF

sed -i "s#root=[^ ]*#root=/dev/sda2 loglevel=5#g" $ROOT/boot/syslinux/syslinux.cfg
sed -i "s#DEFAULT arch#DEFAULT archfallback#" $ROOT/boot/syslinux/syslinux.cfg

echo $HNAME > $ROOT/etc/hostname
ln -s ../usr/share/zoneinfo/UTC $ROOT/etc/localtime
echo en_US.UTF-8 UTF-8 >> $ROOT/etc/locale.gen
echo "LANG=en_US.UTF-8" > $ROOT/etc/locale.conf

cat > $ROOT/etc/pacman.d/mirrorlist <<'EOF'
Server = http://lug.mtu.edu/archlinux/$repo/os/$arch
Server = http://mirror.rit.edu/archlinux/$repo/os/$arch
EOF

sed -i '/server /d' $ROOT/etc/ntp.conf
echo server 169.254.169.254 iburst >> $ROOT/etc/ntp.conf

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
EOF

# GCE times out TCP connections longer than 10m.
echo ServerAliveInterval 450 >> $ROOT/etc/ssh/ssh_config
echo ClientAliveInterval 450 >> $ROOT/etc/ssh/sshd_config

echo "geoff ALL=(ALL) ALL" >> $ROOT/etc/sudoers
syslinux-install_update -i -a -m -c $ROOT/

arch-chroot $ROOT <<'EOF'
locale-gen
systemctl enable dhcpcd.service
systemctl enable sshd.service
systemctl enable iptables.service
systemctl enable ntpd.service
pacman -Syy
useradd --shell /bin/bash --create-home geoff
mkinitcpio -p linux
#usermod -L root
EOF

SSHDIR=$ROOT/home/geoff/.ssh
mkdir $SSHDIR
chmod 700 $SSHDIR
cp $USERKEY $SSHDIR/authorized_keys
chmod 600 $SSHDIR/authorized_keys
chown -R 1000:1000 $SSHDIR

umount -R $ROOT
sync
losetup -d $LOOPDEV
sync

rmdir $ROOT
