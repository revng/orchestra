#!/bin/bash

set -e

export DEBIAN_FRONTEND=noninteractive

apt-get -qq update

apt-get -qq install --no-install-recommends --yes \
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
  ninja-build \
  pkg-config \
  python \
  python3 \
  python3-pip \
  python3-dev \
  python3-cffi \
  python3-setuptools \
  rsync \
  sed \
  ssh \
  texinfo \
  valgrind \
  wget \
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

# Notes:
# * lit version should always match clang-release and llvm version
# * pydot is incompatible with recent versions of pyparsing:
#   https://github.com/pydot/pydot/issues/277
pip3 -q install --user --upgrade setuptools wheel mako meson==0.56.2 pyelftools lit==12.0.0 pyparsing==2.4.7 pydot grandiso jinja2

if ! which git-lfs &> /dev/null; then
  curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | bash
  apt-get -qq install --no-install-recommends --yes git-lfs
fi
