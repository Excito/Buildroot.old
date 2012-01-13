#!/bin/bash
set -x
dir=$(mktemp -d)
cp board/excito/bubbatwo/{image.its,bubba.dtb} output/images/{rootfs.ext2.gz,uImage} output/build/linux-3.1.4/vmlinux.bin.gz $dir
(
cd $dir;
mkimage -f image.its installer.itb
)
cp $dir/installer.itb .
rm -rf $dir;

