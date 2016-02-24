#!/bin/sh

pacman -Q arch-install-scripts
pacman -Q syslinux
which gsutil >/dev/null || exit 1
which gcloud >/dev/null || exit 1

# GCE requires this name be used for the image file.
IMG=disk.raw

ROOT=${ROOT:-$PWD/root}
IMAGEHOSTNAME=${IMAGEHOSTNAME:-archlinux}
IMAGENAME=${IMAGENAME:-archlinux}
SIZE=${SIZE:-6G}

gce_mount() {
    local loopdev=$(sudo losetup --find --show --partscan $IMG)
    local rootdev=${loopdev}p1

    sudo rm -rf --preserve-root $ROOT
    sudo mkdir $ROOT

    sudo mount $rootdev $ROOT
    local fs_exists=$?
    echo "fs_exists: $fs_exists"

    if [[ $fs_exists -ne 0 ]]; then
	sudo mkfs.ext4 -b 4096 -L root $rootdev
	sudo mount $rootdev $ROOT
    fi
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
start=2048,type=83,bootable
EOF

    gce_mount
    sudo pacstrap -c -M $ROOT base syslinux nginx openssh ntp sudo mg git tmux

    sudo tee -a $ROOT/etc/fstab <<'EOF'
/dev/sda1  /       ext4    rw,relatime,data=ordered    0 1
EOF
    sudo sed -i "s#root=[^ ]*#root=/dev/sda1 loglevel=5#g" $ROOT/boot/syslinux/syslinux.cfg
    sudo sed -i "s#DEFAULT [^ ]*#DEFAULT archfallback#" $ROOT/boot/syslinux/syslinux.cfg
    sudo sed -i "s#TIMEOUT [^ ]*#TIMEOUT 20#" $ROOT/boot/syslinux/syslinux.cfg

    echo $IMAGEHOSTNAME | sudo tee $ROOT/etc/hostname
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

    sudo tee $ROOT/etc/nginx/nginx.conf <<'EOF'
worker_processes 4;
events {
  worker_connections 1024;
}

http {
  include gfrh.include;

  server {
    listen 80;
    location / {
        return 404;
    }
  }
}
EOF

    sudo tee $ROOT/etc/nginx/gfrh.include <<'EOF'
include mime.types;
default_type application/octet-stream;
keepalive_timeout 25s;
sendfile on;
gzip on;

add_header X-Frame-Options DENY;
add_header X-Content-Type-Options nosniff;
server_tokens off;

log_format http 'HTTP [$status] $remote_addr:$remote_port -> $server_name:$server_port; request "$request"; length $request_length; accept "$http_accept"; referrer "$http_referer"; user agent "$http_user_agent"; sent $bytes_sent bytes';
log_format https 'HTTPS [$status] $remote_addr:$remote_port -> $server_name:$server_port; protocol $ssl_protocol; cipher $ssl_cipher; request "$request"; length $request_length; accept "$http_accept"; referrer "$http_referer"; user agent "$http_user_agent"; sent $bytes_sent bytes';

error_log syslog:server=unix:/dev/log warn;
access_log syslog:server=unix:/dev/log http;

ssl_session_timeout 5m;
ssl_session_cache shared:SSL:50m;

ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
ssl_ciphers 'ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-DSS-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA:DHE-RSA-AES256-SHA:ECDHE-RSA-DES-CBC3-SHA:ECDHE-ECDSA-DES-CBC3-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:AES:CAMELLIA:DES-CBC3-SHA:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!MD5:!PSK:!aECDH:!EDH-DSS-DES-CBC3-SHA:!EDH-RSA-DES-CBC3-SHA:!KRB5-DES-CBC3-SHA';
ssl_prefer_server_ciphers on;
EOF

    echo "geoff ALL=(ALL) NOPASSWD: ALL" | sudo tee -a $ROOT/etc/sudoers
    sudo syslinux-install_update -i -a -m -c $ROOT/

    sudo arch-chroot $ROOT <<'EOF'
locale-gen
systemctl enable dhcpcd.service
systemctl enable sshd.service
systemctl enable iptables.service
systemctl enable ntpd.service
# nginx not started by default
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
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCxLYZE9F8hbdPEYufT3fRZIb5Q0e0D9ZLe5aYRvW5IMTp8pq692v2hFgbQ7r/1CuJ55woNDgfGVhY6O/fcxjt83mX69wA9osEnliVYpLKx+4W/iGA/4kK6WyDsUNAyVUq9glrrllTfTF8M9bxrMIA+UmUVG3ZZ+09Vjoyh5WteEHVZwlJ/F1wKAzAp9857xbAgvuRS9064IGPiM3R+UPIiZR1lFDyVXo9mDYpEj5ZmXZwQDjzmrC0CTxmxYT/5bhrEeUdi6SKaINJJ2qzmli7e8qi7RkbLjNlusM56Juy8AzTAPnWB26LpBszspeGT4bedQLMloMjfK/E5yc3cG6wlq/WlJf36VvveDRgdz/hbnYCteTiBNf9UOpco8Atp6n1ANwSO8GtInmZCC3r0y7bauVV1htGleasIOyKIw4Erj9XfENxyxDzvlzl8e2rPE6iRH2/DZFliHDVXcwpGFkrNvS24y9jvrxsgB1x6oVM8rQgITPSF24tatbDZb6wqVk905uf3h7TM8xxzs0u8jjYam3Jr93CPSfcwk+qytYxGB8IZCssIBsd7WRpUG5QNnpXp8nT1V9iUwqkabAFBLAIgYBKUWepA5/2TwcWwSDuPNIYNix82KtV2+mYJHRfPjR571j9zbMxVIXAduI14oAORR7GNr3sU8NWvADK2NqZi9w== geoff@tinker
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCf8jxOGcOHk2SrFtDhJTJnIsyOQ5X27Fwf4mCAz43X0am5qKUccA3Jtw6Cz/IilJjcKY0R6RKM+wodkwxYqMSNQcHspN35HKIg0atqDc7Pe5SH3PzPJsmSEkH0egpuNEviz2Y8rCYZkpEKPmGHTNv1F9op6H14KG+n85NVSahBIgRPlkHcots4X3I4srdgtuoi1eDXus0LMbLIVmN1COLuJzzlqsYMQZAo78j9BuqFjXMNvEt2kVaNq8VlCvlDs4YVGk2OEcQKv7gnuPwHTq/9YFVbG3j4ObOBlnBewmIrvBz/B7h34/5nIBmyRKzaC2npGIFrloJtZq9QN0Um4qdUa3ibgjfGZXue+g7p5jHWjWAbhsgwC+snpaAuTeJztZWlrPonK8/obDTo7+ImKzlMLeVukeQyAzLaFJozrM9iOj2Ofdd/fnK4iqvsp9VpiIO26847ken/RZbXR3XYOEkJbNqZx8AZQdDmxBWGaZ/34SpRs/uMpQsLmJmkO+bdKqZ52SxdNd4tWL2F1uMB71XIPX7YYBXtF6/5aFBx8ZhRegi2oPTSMH5dQ8t+SDwjWJb08JB4V/xuabgrR6eBoAMTzFEuYAHllRmJ+lfYfG85Y/uY5z2jY6Rr/J7W0cFmetuICcDzgpTnOWPbnVtZrAmdLI3zuBhxyVcph8Ss0uwnzQ== geoff@tiny
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQD2FtwBSFQfo6YYmFkUvqR4Pv2rB2f2trs8l7KcOfDRy4rBEmKxAbZK7wUTPDOXaL9rO86LYIygT/Rjgo6kP694xOhkoqeomn+/hj5LgZwLYFT/Fh4IW+58d+GrDuyob3lBq3H3OOVorDgTJRiGW9V62qzR/TO2jNzYAeYzrVp2RICYxCh4K0J/+eQQ/CLd0kbUnGfLX5BlpwYetHp8U78pBrMjBsY8mZ0FU5dROFAdFgGapD6/Koai5tSpxGhxaS3qNynR81tv538wmq4yESqpF79nfPIrD+YJVqfK67m4BrE1ZX5oqGaZaDG+zvefN+zXEJtzat95KW4xIy5JoyMNFthau7qMjLoz4NHoNH8nfi6IM7wIhsObmh0Wk8AKL8zyOoFGWC6H8tssC97h6j/wfQPsNbNdHFR9ioUrZtl8IOhewujM7h5GsrfLB3cv1/+5yqYaEnuQeODhK/Vu920+8Lng+5tjtMwnwJSwoblpOTXRSXX4OzENHbETNobsFlLCD//E0id5C3TiIrW24hX8JqiebMZ+/KkYKmrKTHwM3QMKuxJrpWwfgTd3oh1o5atbuHBkhvL/z9SlEJ5lZogzqS9YPd87KWZg0hjaxfmbzG6y4PExgVSX7+2zcDMHbG328vpw7FVicDEykOE7m8+FUaQjO3z7NV3CP7ojdfui1Q== geoffhill@bristleback
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDDKDPkN46mo4eCqq8w8+T6FTaffQ+zvY2zpKJj0jZlELBzGsV3lp1r57em9JhLoGBTB49/q/c4vEnIelXD2SazqLhHyNGpwiDzPHHhJ7ErG5FBLvsLeS8LNbWAxNjppG7hHTpbEPZCEEdtBJseUaAHilW7zreswHyOJxIm4uWUBQoxWfCwx7kKdlnnsEfyRCxDD4OuvmMIVwtJk6zjgAFQmTMJHvnXfVfKjhhZvv9rVaTwI8eN3DaAs0vibUu0L/hBMEpt9vGsdIM41ISQH1+Vd7/2kPaIOY5y9guVto1ym7zXOHYLVsLJpmjlTLhpvcsfCmsZ+hGschTC0vmh/LgtI4UY7UogbltydM5HHGn+5xw1HXKQG1OT28Pf5coqoeWlzVhQzocEsSs0VBqiMqx5OqUglrJRgB79CVwIV7nnkCHeLkBLahUTNg6GL6CUiuCWb+NaGd9YFL6zDDcmHPtrtjFmZFNP3xy0+GoiBKdHD0LOlnDhjigpI3J917OXv5a3bXEhzHQBJUZvNXQPE/6SUYNYdw03o/1xKA0drwwnBjJLDPS3i1M9vQ7FjqNQjufqATiftmhtw1Bq34m2AYhV/Q/d5+wgyBZVle1UIwXRjS2AjPAjOh2v5hMiXhDtw1Ksba38aUHE4949yQ+ewIPQh6IpDylAcCHl6Wywco1QEQ== geoffhill@kotl
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
