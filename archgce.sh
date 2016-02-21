#!/bin/sh

pacman -Q arch-install-scripts
pacman -Q syslinux
which gsutil >/dev/null || exit 1
which gcloud >/dev/null || exit 1

# GCE requires this name be used for the image file.
IMG=disk.raw

ROOT=${ROOT:-$PWD/root}
HOSTNAME=${HOSTNAME:-archlinux}
IMAGENAME=${IMAGENAME:-archlinux}
SIZE=${SIZE:-6G}

gce_mount() {
    local loopdev=$(sudo losetup --find --show --partscan $IMG)
    local bootdev=${loopdev}p1
    local rootdev=${loopdev}p2

    sudo rm -rf --preserve-root $ROOT
    sudo mkdir $ROOT

    sudo mount $rootdev $ROOT
    local fs_exists=$?
    echo "fs_exists: $fs_exists"

    if [[ $fs_exists -ne 0 ]]; then
	sudo mkfs.ext4 -b 4096 -L root $rootdev
	sudo mkfs.ext4 -b 4096 -L boot $bootdev
	sudo mount $rootdev $ROOT
    fi

    if [[ ! -e $ROOT/boot ]]; then
	sudo mkdir $ROOT/boot
    fi

    sudo mount $bootdev $ROOT/boot
}

gce_unmount_all() {
    sudo umount -R $ROOT
    sudo losetup -D
}

gce_create() {
    local userkey=/home/geoff/.ssh/id_rsa.pub

    rm -f $IMG
    truncate -s $SIZE $IMG
    sudo sfdisk $IMG <<'EOF'
label: dos
start=2048,size=128M,type=83,bootable
type=83
EOF

    gce_mount
    sudo pacstrap -c -M $ROOT base syslinux openssh ntp sudo mg git tmux

    sudo tee -a $ROOT/etc/fstab <<'EOF'
/dev/sda2  /       ext4    rw,relatime,data=ordered    0 1
/dev/sda1  /boot   ext4    rw,relatime,data=ordered    0 2
EOF
    sudo sed -i "s#root=[^ ]*#root=/dev/sda2 loglevel=5#g" $ROOT/boot/syslinux/syslinux.cfg
    sudo sed -i "s#DEFAULT arch#DEFAULT archfallback#" $ROOT/boot/syslinux/syslinux.cfg

    echo $HOSTNAME | sudo tee $ROOT/etc/hostname
    sudo ln -s ../usr/share/zoneinfo/UTC $ROOT/etc/localtime
    echo en_US.UTF-8 UTF-8 | sudo tee -a $ROOT/etc/locale.gen
    echo "LANG=en_US.UTF-8" | sudo tee $ROOT/etc/locale.conf

    sudo tee $ROOT/etc/pacman.d/mirrorlist <<'EOF'
Server = http://lug.mtu.edu/archlinux/$repo/os/$arch
Server = http://mirror.rit.edu/archlinux/$repo/os/$arch
EOF

    sudo sed -i '/server /d' $ROOT/etc/ntp.conf
    echo server 169.254.169.254 iburst | sudo tee -a $ROOT/etc/ntp.conf

    sudo tee $ROOT/etc/iptables/iptables.rules <<'EOF'
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
    echo ServerAliveInterval 450 | sudo tee -a $ROOT/etc/ssh/ssh_config
    echo ClientAliveInterval 450 | sudo tee -a $ROOT/etc/ssh/sshd_config

    echo "geoff ALL=(ALL) NOPASSWD: ALL" | sudo tee -a $ROOT/etc/sudoers
    sudo syslinux-install_update -i -a -m -c $ROOT/

    sudo arch-chroot $ROOT <<EOF
locale-gen
systemctl enable dhcpcd.service
systemctl enable sshd.service
systemctl enable iptables.service
systemctl enable ntpd.service
pacman -Syy
useradd --shell /bin/bash --create-home geoff
mkinitcpio -p linux
EOF
    sudo rm -f $ROOT/root/.bash_history

    local sshdir=$ROOT/home/geoff/.ssh
    mkdir $sshdir
    chmod 700 $sshdir
    cat >$sshdir/authorized_keys <<'EOF'
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDxj7kvN/DzrJiPiokMLS1O8HkAMg4AW8K2WJXHL/6Oa5psurVqIff0v9GJZvpeljZU0UIQ0QxFiUC9WXuuaJ2S9mVZRMzTZWJYvS2ZTM1T+qtWr/qW8IehDjL1FrOxaK89QhUATAh/KZH5wiyBUkSbywnTUSGdopUVEW2CuDF9d1jVydUvO6t94GmxjrzWoaT6y2Mx7VWWNctz6AB3vJwDFbv8fotI4kNn9xO3Jv91k62L7wMpfxVK68Nv/6L1EZoFJoEtaziCX1TCKilyIzjPtrbG5MySDMuKZZO0kJcxdfzASFFEeUYMgnQrVVHukE8kkLMIq+dIbfWBZlU/sFbFmKXCWEflLKcC/v1XWrA8QQtuKiNY0ScfkJy9omPFo/sCb2F33qlVzYUdI5ztHPmcNu2q3w1qPZY0Cnpl9dif+rLuC7oJmaue3JqieJ+yez4/PfNdZ1wQ+aPTpKk8BVs6g00cXNkkJhqF89eEAVyW1hVlg0FoYRsmBLkFutdfBEBPzVezeeuVIW9kt/XlPDztEnfBTC1KreFFEfyuwb1hSELZgAExeISVUx3qaOmb55YDFFy1trQEdyFaTqU6rWyBzZso/3mJZV7FTY9h4sZMkGiN9M4DyiEIn/1RmRo2YHiMchgf2V37q+GxV1mBSNJBaYSFh6jTBGW8FuEi8F/PdQ== geoff@dazzle
EOF
    chmod 600 $sshdir/authorized_keys
}

gce_publish() {
    local bucket=gs://gfrh-gce-images
    local gceimage="$IMAGENAME-$(date -u +'%F-%s')"
    local tarball="$gceimage.tar.gz"

    rm -f $tarball
    echo "Creating tarball..."
    tar -Sczf $tarball $IMG
    gsutil cp $tarball $bucket
    gcloud compute images create $gceimage --source-uri $bucket/$tarball
}

gce_qemu_test() {
    qemu-system-x86_64 \
	--enable-kvm -smp 1 -m 2048M \
	-net nic,model=virtio -net user -redir tcp:5555::22 \
	-device virtio-scsi-pci,id=scsi \
	-device scsi-hd,drive=hd,physical_block_size=4096 \
	-drive if=none,id=hd,file=$IMG,format=raw,cache=none
}
