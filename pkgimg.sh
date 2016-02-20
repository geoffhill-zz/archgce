#!/bin/bash

HNAME="${HNAME:-arch.gfrh.net}"

BUCKET=gs://gfrh-gce-images
IMG=disk.raw
IMAGE="$HNAME-$(date -u +'%F-%s')"
TARBALL="$IMAGE.tar.gz"

rm -f $TARBALL
tar -Sczf $TARBALL $IMG
gsutil cp $TARBALL $BUCKET
gcloud compute images create $IMAGE --source-uri $BUCKET/$TARBALL
