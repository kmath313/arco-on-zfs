#!/bin/bash

#*********************************************************************
# Edit these values before running the script!!!
#*********************************************************************
DISK=''
INST_VDEV= # Leave empy to use single disk, other options - mirror, raidz1, raidz2, raidz3
INST_PARTSIZE_ESP=4 # in GB
# INST_PARTSIZE_ESP=1 # if local recovery not required
INST_PARTSIZE_BPOOL=4 # increase if intending to use multiple kernels/distros
INST_PARTSIZE_SWAP=8 # If using hibernation set equal to RAM size, set to zero if swap not required
INST_PARTSIZE_RPOOL= # if not set root pool will use remaining disk space
INST_TZ='' # eg America/New York
INST_HOSTNAME='' # eg Arcolinux
INST_LOCALE='' # eg en_US.UTF-8
INST_KEYMAP='' # eg us
myUser='' # non-root username
#*********************************************************************

# Add archzfs repo to live environment
curl -L https://archzfs.com/archzfs.gpg |  pacman-key -a -
pacman-key --lsign-key $(curl -L https://git.io/JsfVS)
curl -L https://git.io/Jsfw2 > /etc/pacman.d/mirrorlist-archzfs

tee -a /etc/pacman.conf <<- 'EOF'

#[archzfs-testing]
#Include = /etc/pacman.d/mirrorlist-archzfs

[archzfs]
Include = /etc/pacman.d/mirrorlist-archzfs
EOF

pacman -Sy

# Install ZFS DKMS into live environment
INST_LINVAR=linux
INST_LINVER=$(pacman -Qi ${INST_LINVAR} | grep Version | awk '{ print $3 }')

if [ "${INST_LINVER}" = \
"$(pacman -Si ${INST_LINVAR}-headers | grep Version | awk '{ print $3 }')" ]; then
 pacman -S --noconfirm --needed ${INST_LINVAR}-headers
else
 pacman -U --noconfirm --needed \
 https://archive.archlinux.org/packages/l/${INST_LINVAR}-headers/${INST_LINVAR}-headers-${INST_LINVER}-x86_64.pkg.tar.zst
fi

pacman -Sy --needed --noconfirm zfs-dkms glibc
modprobe zfs
sed -i 's/#IgnorePkg/IgnorePkg/' /etc/pacman.conf
sed -i "/^IgnorePkg/ s/$/ ${INST_LINVAR} ${INST_LINVAR}-headers/" /etc/pacman.conf

# Start install
INST_UUID=$(dd if=/dev/urandom bs=1 count=100 2>/dev/null | tr -dc 'a-z0-9' | cut -c-6)
INST_ID=arch

# Wipe SSDs - skip if not using SSDs
for i in ${DISK}; do
blkdiscard -f $i &
done
wait

# Partition disks
for i in ${DISK}; do
sgdisk --zap-all $i
sgdisk -n1:1M:+${INST_PARTSIZE_ESP}G -t1:EF00 $i
sgdisk -n2:0:+${INST_PARTSIZE_BPOOL}G -t2:BE00 $i
if [ "${INST_PARTSIZE_SWAP}" != "" ]; then
    sgdisk -n4:0:+${INST_PARTSIZE_SWAP}G -t4:8200 $i
fi
if [ "${INST_PARTSIZE_RPOOL}" = "" ]; then
    sgdisk -n3:0:0   -t3:BF00 $i
else
    sgdisk -n3:0:+${INST_PARTSIZE_RPOOL}G -t3:BF00 $i
fi
sgdisk -a1 -n5:24K:+1000K -t5:EF02 $i
done

# Create boot pool
disk_num=0; for i in $DISK; do disk_num=$(( $disk_num + 1 )); done
if [ $disk_num -gt 1 ]; then INST_VDEV_BPOOL=mirror; fi

zpool create \
    -o compatibility=grub2 \
    -o ashift=12 \
    -o autotrim=on \
    -O acltype=posixacl \
    -O canmount=off \
    -O compression=lz4 \
    -O devices=off \
    -O normalization=formD \
    -O relatime=on \
    -O xattr=sa \
    -O mountpoint=/boot \
    -R /mnt \
    bpool_$INST_UUID \
     $INST_VDEV_BPOOL \
    $(for i in ${DISK}; do
       printf "$i-part2 ";
      done)

read -p "Check bpool got created"

# Create root pool
zpool create \
    -o ashift=12 \
    -o autotrim=on \
    -R /mnt \
    -O acltype=posixacl \
    -O canmount=off \
    -O compression=zstd \
    -O dnodesize=auto \
    -O normalization=formD \
    -O relatime=on \
    -O xattr=sa \
    -O mountpoint=/ \
    rpool_$INST_UUID \
    $INST_VDEV \
   $(for i in ${DISK}; do
      printf "$i-part3 ";
     done)

# Create root system dataset
# Unencrypted
zfs create -o canmount=off -o mountpoint=none rpool_$INST_UUID/$INST_ID
# Encrypted
# zfs create -o canmount=off -o mountpoint=none -o encryption=on -o keylocation=prompt -o keyformat=passphrase rpool_$INST_UUID/$INST_ID

# Create other system datasets
zfs create -o canmount=off -o mountpoint=none bpool_$INST_UUID/$INST_ID
zfs create -o canmount=off -o mountpoint=none bpool_$INST_UUID/$INST_ID/BOOT
zfs create -o canmount=off -o mountpoint=none rpool_$INST_UUID/$INST_ID/ROOT
zfs create -o canmount=off -o mountpoint=none rpool_$INST_UUID/$INST_ID/DATA
zfs create -o mountpoint=/boot -o canmount=noauto bpool_$INST_UUID/$INST_ID/BOOT/default
zfs create -o mountpoint=/ -o canmount=off    rpool_$INST_UUID/$INST_ID/DATA/default
zfs create -o mountpoint=/ -o canmount=noauto rpool_$INST_UUID/$INST_ID/ROOT/default
zfs mount rpool_$INST_UUID/$INST_ID/ROOT/default
zfs mount bpool_$INST_UUID/$INST_ID/BOOT/default
for i in {usr,var,var/lib};
do
    zfs create -o canmount=off rpool_$INST_UUID/$INST_ID/DATA/default/$i
done
for i in {home,root,srv,usr/local,var/log,var/spool};
do
    zfs create -o canmount=on rpool_$INST_UUID/$INST_ID/DATA/default/$i
done
zfs set recordsize=1m rpool_$INST_UUID/$INST_ID/DATA/default/home
chmod 750 /mnt/root

# Format and mount ESP
for i in ${DISK}; do
 mkfs.vfat -n EFI ${i}-part1
 mkdir -p /mnt/boot/efis/${i##*/}-part1
 mount -t vfat ${i}-part1 /mnt/boot/efis/${i##*/}-part1
done

mkdir -p /mnt/boot/efi
mount -t vfat ${INST_PRIMARY_DISK}-part1 /mnt/boot/efi

# Create other user datasets to omit from rollback
zfs create -o canmount=on rpool_$INST_UUID/$INST_ID/DATA/default/var/games
zfs create -o canmount=on rpool_$INST_UUID/$INST_ID/DATA/default/var/www
# for GNOME
zfs create -o canmount=on rpool_$INST_UUID/$INST_ID/DATA/default/var/lib/AccountsService
# for Docker
zfs create -o canmount=on rpool_$INST_UUID/$INST_ID/DATA/default/var/lib/docker
# for NFS
zfs create -o canmount=on rpool_$INST_UUID/$INST_ID/DATA/default/var/lib/nfs
# for LXC
zfs create -o canmount=on rpool_$INST_UUID/$INST_ID/DATA/default/var/lib/lxc
# for LibVirt
zfs create -o canmount=on rpool_$INST_UUID/$INST_ID/DATA/default/var/lib/libvirt

# Install Arch base
pacstrap /mnt base vi mandoc grub efibootmgr mkinitcpio

# Set kernel version from ZFS package
INST_LINVER=$(pacman -Si zfs-${INST_LINVAR} \
| grep 'Depends On' \
| sed "s|.*${INST_LINVAR}=||" \
| awk '{ print $1 }')

# Install kernel
if [ ${INST_LINVER} = \
$(pacman -Si ${INST_LINVAR} | grep Version | awk '{ print $3 }') ]; then
 pacstrap /mnt ${INST_LINVAR}
else
 pacstrap -U /mnt \
 https://archive.archlinux.org/packages/l/${INST_LINVAR}/${INST_LINVAR}-${INST_LINVER}-x86_64.pkg.tar.zst
fi

# Install zfs
pacstrap /mnt zfs-$INST_LINVAR zfs-utils

# Install firmware
pacstrap /mnt linux-firmware intel-ucode

# Set mkinitcpio zfs hook scan path
echo GRUB_CMDLINE_LINUX=\"zfs_import_dir=${INST_PRIMARY_DISK%/*}\" >> /mnt/etc/default/grub

# Generate fstab
genfstab -U /mnt | sed 's;zfs[[:space:]]*;zfs zfsutil,;g' | grep "zfs zfsutil" >> /mnt/etc/fstab
for i in ${DISK}; do
   echo UUID=$(blkid -s UUID -o value ${i}-part1) /boot/efis/${i##*/}-part1 vfat \
   x-systemd.idle-timeout=1min,x-systemd.automount,noauto,umask=0022,fmask=0022,dmask=0022 0 1 >> /mnt/etc/fstab
done
echo UUID=$(blkid -s UUID -o value ${INST_PRIMARY_DISK}-part1) /boot/efi vfat \
x-systemd.idle-timeout=1min,x-systemd.automount,noauto,umask=0022,fmask=0022,dmask=0022 0 1 >> /mnt/etc/fstab
if [ "${INST_PARTSIZE_SWAP}" != "" ]; then
 for i in ${DISK}; do
  echo ${i##*/}-part4-swap ${i}-part4 /dev/urandom swap,cipher=aes-cbc-essiv:sha256,size=256,discard >> /mnt/etc/crypttab
  echo /dev/mapper/${i##*/}-part4-swap none swap defaults 0 0 >> /mnt/etc/fstab
 done
fi

# Configure mkinitcpio
mv /mnt/etc/mkinitcpio.conf /mnt/etc/mkinitcpio.conf.original
tee /mnt/etc/mkinitcpio.conf <<EOF
HOOKS=(base udev autodetect modconf block keyboard zfs filesystems)
EOF

# Install Network Manager
pacstrap /mnt networkmanager
systemctl enable NetworkManager --root=/mnt

# Enable NTP
hwclock --systohc
systemctl enable systemd-timesyncd --root=/mnt

# Set locale, keymap, timezone, hostname and root password
rm -f /mnt/etc/localtime
systemd-firstboot --root=/mnt --force \
 --locale=$INST_LOCALE --locale-messages=$INST_LOCALE \
 --keymap=$INST_KEYMAP --timezone=$INST_TZ --hostname=$INST_HOSTNAME \
 --root-password=PASSWORD --root-shell=/bin/bash
 arch-chroot /mnt passwd

# Generate host ID
zgenhostid -f -o /mnt/etc/hostid

# Ignore kernel updates
sed -i 's/#IgnorePkg/IgnorePkg/' /mnt/etc/pacman.conf
sed -i "/^IgnorePkg/ s/$/ ${INST_LINVAR} ${INST_LINVAR}-headers zfs-${INST_LINVAR} zfs-utils/" /mnt/etc/pacman.conf

# Enable ZFS services
systemctl enable zfs-import-scan.service zfs-import.target zfs-zed zfs.target --root=/mnt
systemctl disable zfs-mount --root=/mnt

# Copy script to execute in chroot
chmod +x chroot.sh
cp chroot.sh /mnt/root

# chroot
echo "INST_PRIMARY_DISK=$INST_PRIMARY_DISK
INST_LINVAR=$INST_LINVAR
INST_UUID=$INST_UUID
INST_ID=$INST_ID
INST_VDEV=$INST_VDEV
DISK=$DISK
INST_LOCALE=$INST_LOCALE
myUser=$myUser" > /mnt/root/chroot
arch-chroot /mnt bash --login
