# archgce

archgce is a bash shell script library for lightweight deployment to Google
Compute Engine from Arch Linux. It provides functions to create a raw disk
with Arch Linux installed, and to upload it as a GCE image.

It is heavily customized for myself, with my preferred packages, username, GS
bucket and some public keys hardcoded.

### Requirements

* An Arch Linux host, with:
    + [arch-install-scripts](https://www.archlinux.org/packages/extra/any/arch-install-scripts/)
    + [syslinux](https://www.archlinux.org/packages/core/x86_64/syslinux/)
    + gcloud/gsutil or [google-cloud-sdk (AUR)](https://aur.archlinux.org/packages/google-cloud-sdk/)
* For testing:
    + [qemu](https://www.archlinux.org/packages/extra/x86_64/qemu/)

### Usage

Create a deployment script (`deploy.sh` by convention).

    #!/bin/bash

    . ./archgce/archgce.sh

	export ROOT=$PWD/root

    SIZE=4G HOSTNAME=example.com gce_create

    # Install the program and run any configuration...
	sudo make install PREFIX=$ROOT/usr/local
	sudo arch-chroot $ROOT pacman -S libbsd
	sudo arch-chroot $ROOT systemctl enable program.service

    gce_unmount_all
	IMAGENAME=example gce_publish

Then authenticate and run it:

	$ gcloud auth login
	$ gcloud config set project example-id
	$ ./deploy.sh

This would create a timestamped GCE image in the `example-id` project:

    example.gfrh.net-2016-02-21-1456028317

