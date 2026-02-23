# ARKLinux reproducible build container
# Usage:
#   docker build -t arklinux-builder .
#   docker run --privileged -v $(pwd):/src -v /tmp/out:/out arklinux-builder
#
# The --privileged flag is required because mkarchiso needs loop devices
# to build the squashfs and ISO filesystem.
#
# Pinned to the 2026-02-01 Arch Linux Archive snapshot via ARCH_SNAPSHOT ARG.
# To upgrade the snapshot:
#   1. Change ARCH_SNAPSHOT below
#   2. Run build/scripts/pin-packages.sh <NEW_DATE> to regenerate packages.lock
#   3. Update ARCH_SNAPSHOT in .github/workflows/build-release.yml
#   4. Commit all three changes together

ARG ARCH_SNAPSHOT=2026/02/01

FROM archlinux:base

ARG ARCH_SNAPSHOT

# Override mirror to pinned snapshot
RUN echo '[options]' > /etc/pacman.conf && \
    echo 'HoldPkg = pacman glibc' >> /etc/pacman.conf && \
    echo 'Architecture = auto' >> /etc/pacman.conf && \
    echo 'CheckSpace' >> /etc/pacman.conf && \
    echo 'SigLevel = Required DatabaseOptional' >> /etc/pacman.conf && \
    echo 'LocalFileSigLevel = Optional' >> /etc/pacman.conf && \
    echo '' >> /etc/pacman.conf && \
    echo "[core]" >> /etc/pacman.conf && \
    echo "Server = https://archive.archlinux.org/repos/${ARCH_SNAPSHOT}/\$repo/os/\$arch" >> /etc/pacman.conf && \
    echo '' >> /etc/pacman.conf && \
    echo "[extra]" >> /etc/pacman.conf && \
    echo "Server = https://archive.archlinux.org/repos/${ARCH_SNAPSHOT}/\$repo/os/\$arch" >> /etc/pacman.conf

# Initialise keyring and install build tools
RUN pacman-key --init && \
    pacman-key --populate archlinux && \
    pacman -Sy --noconfirm && \
    pacman -S --noconfirm --needed \
      archiso \
      mkinitcpio-archiso \
      squashfs-tools \
      dosfstools \
      libisoburn \
      git \
      curl \
      shellcheck \
      python \
      python-pip && \
    pacman -Scc --noconfirm

WORKDIR /src

# Build script — runs mkarchiso against the archiso/ profile
COPY build/docker/entrypoint.sh /usr/local/bin/build-arklinux
RUN chmod +x /usr/local/bin/build-arklinux

ENTRYPOINT ["/usr/local/bin/build-arklinux"]
CMD []
