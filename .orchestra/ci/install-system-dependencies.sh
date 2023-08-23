#!/bin/bash

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

source /etc/os-release

# Wine
dpkg --add-architecture i386

apt-get -qq update

PACKAGES=()

#
# Base system tools
#
PACKAGES+=(aria2)
PACKAGES+=(curl)
PACKAGES+=(ca-certificates)
PACKAGES+=(python3)
PACKAGES+=(python3-pip)
PACKAGES+=(python3-setuptools)
PACKAGES+=(gawk)
PACKAGES+=(jq)
PACKAGES+=(rsync)
PACKAGES+=(sed)
PACKAGES+=(ssh)
PACKAGES+=(sudo)
PACKAGES+=(unzip)
PACKAGES+=(wget)

#
# Basic build tools
#
PACKAGES+=(autoconf)
PACKAGES+=(automake)
PACKAGES+=(bison)
PACKAGES+=(build-essential)
PACKAGES+=(cmake)
PACKAGES+=(flex)
PACKAGES+=(g++-multilib)
PACKAGES+=(git)
PACKAGES+=(gettext)
PACKAGES+=(libc-dev)
PACKAGES+=(libtool)
PACKAGES+=(m4)
PACKAGES+=(pkg-config)
PACKAGES+=(texinfo)
PACKAGES+=(zlib1g-dev)

#
# revng-orchestra build dependencies
#
# This is needed for python-Levenshtein
PACKAGES+=(python3-dev)

#
# llvm-documentation dependencies
#
PACKAGES+=(doxygen)
PACKAGES+=(graphviz)

#
# qemu dependencies
#
PACKAGES+=(python2)

#
# revng dependencies
#
PACKAGES+=(doxygen)
PACKAGES+=(shellcheck)

#
# repackage-apple-sdk dependencies
#
PACKAGES+=(p7zip-full)

#
# vs toolchains dependencies
#
PACKAGES+=(msitools)
PACKAGES+=(p7zip-full)
# winbind: `mspdb100.dll` tries to make some kind of connection that requires
# this package. Without it, the following command will fail:
#
#     orc install --test toolchain/win32-vc16/vc
#
PACKAGES+=(winbind)
PACKAGES+=(wine)
PACKAGES+=(wine32)
PACKAGES+=(wine64)

#
# vscode-web runtime dependencies
#
PACKAGES+=(ripgrep)

apt-get -qq install --no-install-recommends --yes "${PACKAGES[@]}"

if ! command -v git-lfs &> /dev/null; then
  LFS_URL="https://github.com/git-lfs/git-lfs/releases/download/v3.3.0/git-lfs-linux-amd64-v3.3.0.tar.gz"
  curl -sL "$LFS_URL" | tar -xzf - -C'/usr/local/bin' --strip-components=1 'git-lfs-3.3.0/git-lfs'
  echo "8c86bfbedd644e7b5d26c58bb858bc4478c5672b974d4a94cbc88cada4926b05 /usr/local/bin/git-lfs" | \
    sha256sum --quiet -c -
  git lfs install --skip-repo --system &> /dev/null
fi
