#!/bin/bash

set -e

export DEBIAN_FRONTEND=noninteractive

apt-get update

apt-get install --no-install-recommends --yes \
  aufs-tools \
  autoconf \
  automake \
  bison \
  build-essential \
  ca-certificates \
  cmake \
  curl \
  doxygen \
  flex \
  g++-multilib \
  gawk \
  git \
  libc-dev \
  libexpat1-dev \
  libglib2.0-dev \
  liblzma-dev \
  libncurses5-dev \
  libreadline-dev \
  libtool \
  m4 \
  meson \
  ninja-build \
  pkg-config \
  python \
  python-pyelftools \
  python3 \
  python3-pip \
  python3-dev \
  python3-cffi \
  python3-pyelftools \
  python3-pygraphviz \
  python3-setuptools \
  sed \
  texinfo \
  valgrind \
  wget \
  zlib1g-dev

# Dependencies for Qt
apt install --no-install-recommends --yes \
  libfontconfig1-dev \
  libfreetype6-dev \
  libgl-dev \
  libgl1-mesa-dev \
  libgles2-mesa-dev \
  libinput-dev \
  libssl-dev \
  libx11-dev \
  libx11-xcb-dev \
  libxcb-glx0-dev \
  libxcb1-dev \
  libxext-dev \
  libxfixes-dev \
  libxi-dev \
  libxkbcommon-dev \
  libxkbcommon-x11-dev \
  libxrender-dev

pip3 install setuptools wheel

if ! which git-lfs >& /dev/null; then
  curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | bash
  apt-get install --no-install-recommends --yes git-lfs
fi
