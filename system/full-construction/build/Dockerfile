FROM archlinux:base-devel
RUN pacman -Syu --noconfirm --needed \
    arch-install-scripts btrfs-progs dosfstools gptfdisk util-linux \
    curl xz zstd patch bc cpio pahole perl python openssl ncurses pkgconf flex bison \
    systemd mkinitcpio efibootmgr qemu-desktop edk2-ovmf dbus-broker
WORKDIR /src
ENTRYPOINT ["/src/build/assemble-image.sh"]
