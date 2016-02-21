#!/bin/bash
    
. ./archgce.sh

SIZE=4G HOSTNAME=mkgr8.us gce_create
gce_unmount_all
IMAGENAME=mkgr8 gce_publish
