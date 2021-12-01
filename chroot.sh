#!/bin/bash

# Source variables
source /root/chroot

# Apply locale changes
echo "${INST_LOCALE} UTF-8" >> /etc/locale.gen
locale-gen

# Enable parallel downloads for pacman
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf

# Add archzfs repo
curl -L https://archzfs.com/archzfs.gpg |  pacman-key -a -
pacman-key --lsign-key $(curl -L https://git.io/JsfVS)
curl -L https://git.io/Jsfw2 > /etc/pacman.d/mirrorlist-archzfs
tee -a /etc/pacman.conf <<- 'EOF'

#[archzfs-testing]
#Include = /etc/pacman.d/mirrorlist-archzfs

[archzfs]
Include = /etc/pacman.d/mirrorlist-archzfs
EOF

# Add git and base devel so that can pull Arcolinux Spices Application
pacman -Sy --needed --noconfirm git base-devel

# Add arcolinux repositories
mkdir -p /root/spices
git clone https://github.com/arcolinux/arcolinux-spices /root/spices
bash /root/spices/usr/share/arcolinux-spices/scripts/get-the-keys-and-repos.sh

pacman -Sy --needed --noconfirm - < /root/arch-arcod_packages #paru-bin arcolinux-paru-git arcolinux-root-git arcolinux-meta-fun neofetch arcolinux-neofetch-git

# add live iso to grub menu
mkdir /boot/efi/iso
cd /boot/efi/iso
curl -O https://mirrors.ocf.berkeley.edu/archlinux/iso/2021.11.01/archlinux-2021.11.01-x86_64.iso
curl -O https://archlinux.org/iso/2021.11.01/archlinux-2021.11.01-x86_64.iso.sig
gpg --auto-key-retrieve --verify archlinux-2021.11.01-x86_64.iso.sig
curl -L https://git.io/Jsfr3 > /etc/grub.d/43_archiso
chmod +x /etc/grub.d/43_archiso

# Add grub probe fix
echo 'export ZPOOL_VDEV_NAME_PATH=YES' >> /etc/profile.d/zpool_vdev_name_path.sh
source /etc/profile.d/zpool_vdev_name_path.sh
echo 'Defaults env_keep += "ZPOOL_VDEV_NAME_PATH"' >> /etc/sudoers

# Fix pool name missing
sed -i "s|rpool=.*|rpool=\`zdb -l \${GRUB_DEVICE} \| grep -E '[[:blank:]]name' \| cut -d\\\' -f 2\`|"  /etc/grub.d/10_linux

# Install grub
rm -f /etc/zfs/zpool.cache
touch /etc/zfs/zpool.cache
chmod a-w /etc/zfs/zpool.cache
chattr +i /etc/zfs/zpool.cache
mkinitcpio -P
mkdir -p /boot/efi/EFI/arch
mkdir -p /boot/grub
grub-install --boot-directory /boot/efi/EFI/arch --efi-directory /boot/efi/
grub-install --boot-directory /boot/efi/EFI/arch --efi-directory /boot/efi/ --removable

if [[ ! -z $SEPARATEESP ]]; then
  for i in ${ESPDISK}; do
    echo ${i##*/} && read -p "check grub disk"
    efibootmgr -cgp 1 -l "\EFI\arch\grubx64.efi" \
    -L "arch-${i##*/}" -d ${i}
  done
else
  for i in ${DISK}; do
    efibootmgr -cgp 1 -l "\EFI\arch\grubx64.efi" \
    -L "arch-${i##*/}" -d ${i}
  done
fi
grub-mkconfig -o /boot/efi/EFI/arch/grub/grub.cfg
cp /boot/efi/EFI/arch/grub/grub.cfg /boot/grub/grub.cfg
ESP_MIRROR=$(mktemp -d)
cp -r /boot/efi/EFI $ESP_MIRROR
for i in /boot/efis/*; do
 cp -r $ESP_MIRROR/EFI $i
done

# create user account
useradd -MUd /home/${myUser} -c 'My Name' ${myUser}
zfs allow -u ${myUser} mount,snapshot,destroy $(df --output=source /home | tail -n +2)/${myUser}
chown -R ${myUser}:${myUser} /home/${myUser}
chmod 700 /home/${myUser}
echo "Set password for $myUser"
passwd ${myUser}
usermod -aG audio,video,optical,storage,network,wheel ${myUser}
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/20-installer
cp -arf /etc/skel/* /home/${myUser}

mkdir -p /home/${myUser}/arco-leftwm
git clone https://github.com/arcolinuxd/arco-leftwm /home/${myUser}/arco-leftwm
chown -R ${myUser}:${myUser} /home/${myUser}/arco-leftwm


# Leave chroot
exit
