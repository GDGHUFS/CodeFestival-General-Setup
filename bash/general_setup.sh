#!/bin/bash
sudo mkdir -p /opt/cf-env/bin
sudo chown -R $USER:$USER /opt/cf-env

echo "export PATH=\"/opt/cf-env/bin:\$PATH\"" >> ~/.bashrc

sudo dnf update -y
sudo dnf upgrade -y
sudo dnf group install "development-tools" -y
sudo dnf install -y \
    ibm-plex-mono-fonts \
    libsqlite3x-devel \
    gcc \
    make \
    zlib-devel \
    bzip2-devel \
    xz-devel \
    libffi-devel \
    openssl-devel \
    ncurses-devel \
    readline-devel \
    sqlite-devel \
    gdbm-devel \
    tk-devel \
    libuuid-devel \
    libnsl2-devel \
    libtirpc-devel \
    expat-devel \
    libdb-devel \
    bluez-libs-devel \
    systemd-devel \
    libuuid-devel \
    xz-devel \
    lzma-sdk-devel \
    valgrind-devel \
    gmp-devel \
    mpdecimal-devel \
    dbus-devel \
    libblkid-devel \
    uuid-devel \
    python3-tkinter