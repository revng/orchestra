#!/bin/bash

set -e

export DEBIAN_FRONTEND=noninteractive

source /etc/os-release

# Required for wine32
dpkg --add-architecture i386

apt-get -qq update
apt-get -qq install --no-install-recommends --yes ca-certificates curl gpg

curl -fsSL https://deb.nodesource.com/gpgkey/nodesource.gpg.key | gpg --dearmor > /usr/share/keyrings/nodesource.gpg
curl -fsSL https://dl.yarnpkg.com/debian/pubkey.gpg | gpg --dearmor > /usr/share/keyrings/yarnkey.gpg
echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_14.x $VERSION_CODENAME main" \
  > /etc/apt/sources.list.d/nodesource.list
echo "deb [signed-by=/usr/share/keyrings/yarnkey.gpg] https://dl.yarnpkg.com/debian stable main" \
  > /etc/apt/sources.list.d/yarn.list
apt-get -qq update

# Notes about installed packages:
#
# * winbind: `mspdb100.dll` tries to make some kind of connection that requires
#   this package. Without it, the following command will fail:
#
#       orc install --test toolchain/win32-vc16/vc

apt-get -qq install --no-install-recommends --yes \
  aufs-tools \
  autoconf \
  automake \
  bison \
  build-essential \
  cmake \
  doxygen \
  flex \
  g++-multilib \
  gawk \
  git \
  graphviz \
  graphviz-dev \
  jq \
  libc-dev \
  libexpat1-dev \
  libglib2.0-dev \
  liblzma-dev \
  libncurses5-dev \
  libreadline-dev \
  libtool \
  m4 \
  msitools \
  ninja-build \
  nodejs \
  p7zip-full \
  pkg-config \
  python \
  python3 \
  python3-cffi \
  python3-dev \
  python3-pip \
  python3-setuptools \
  rsync \
  sed \
  shellcheck \
  ssh \
  sudo \
  texinfo \
  unzip \
  valgrind \
  wget \
  yarn \
  wine \
  winbind \
  wine32 \
  zlib1g-dev

# Dependencies for Qt
apt-get -qq install --no-install-recommends --yes \
  gperf \
  libcap-dev \
  libfontconfig1-dev \
  libfreetype6-dev \
  libgl-dev \
  libgl1-mesa-dev \
  libgles2-mesa-dev \
  libinput-dev \
  libmount-dev \
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

if ! which git-lfs &> /dev/null; then
  curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | bash
  apt-get -qq install --no-install-recommends --yes git-lfs
fi
