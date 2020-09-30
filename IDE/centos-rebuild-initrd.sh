#!/bin/bash

file_name=$1

qemu-nbd -d /dev/nbd12
qemu-nbd -c /dev/nbd12 -P 1 $file_name -f raw
mount /dev/nbd12 ./sys

version=`ls initrd-*.img`
version=${version%.*}
version=${version#*-}

umount ./sys
qemu-nbd -d /dev/nbd12

qemu-nbd -c /dev/nbd12 -P 3 $file_name -f raw
mount /dev/nbd12 ./sys

chroot sys
mkinitrd --with=virtio --with=virtio_blk --with=virtio_net --with=virtio_pci --with=virtio_balloon /boot/initrd-$version.img $version
exit
mv ./sys/boot/initrd*.img ./
umount ./sys
qemu-nbd -d /dev/nbd12

qemu-nbd -c /dev/nbd12 -P 1 $file_name -f raw
mount /dev/nbd12 ./sys
ori_initrd=`ls ./sys/initrd*.img`
mv ./sys/$ori_initrd ./sys/$ori_initrd.bak
mv ./inird*.img ./sys
umount ./sys
qemu-nbd -d /dev/nbd12
