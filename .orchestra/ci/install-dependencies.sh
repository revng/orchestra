#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source /etc/os-release

DISTRO_ID="${ID:-linux}"
DISTRO_VERSION="${VERSION_ID:-}"
if [[ ! ( "$DISTRO_ID" = "ubuntu" && "$DISTRO_VERSION" = "22.04" ) ]]; then
  echo "This script is meant for Ubuntu 22.04" >&2
  echo "Current system: $DISTRO_ID $DISTRO_VERSION" >&2
  echo "Bailing!" >&2
  exit 1
fi

# If not running as root, re-run this script under sudo
if [ "$EUID" -ne 0 ]; then
    exec sudo "${BASH_SOURCE[0]}" "$@"
fi

function help() {
  echo "${BASH_SOURCE[0]} [--minimal|--full]" >&2
  exit "$1"
}

if [[ "$#" -eq 1 && ("$1" == "-h" || "$1" == "--help") ]]; then
  help 0
elif [[ "$#" -ge 2 ]]; then
  help 1
elif [[ "$#" -eq 0 ]]; then
  INSTALL_TYPE=standard
elif [[ "$1" == "--minimal" ]]; then
  INSTALL_TYPE=minimal
elif [[ "$1" == "--full" ]]; then
  INSTALL_TYPE=full
else
  help 1
fi


#
# Beginning of definition of package lists
#

# Array of "minimal" dependencies, these are the dependencies needed for:
# * Successfully running `orc`
# * Successfully running `orc install --test revng` where the revng component
#   might require to be built from source
MINIMAL_PACKAGES=()

# Array of "typical developer" dependencies to install additionally on top of
# MINIMAL_PACKAGE. These allow to built the `revng` component completely from
# source.
PACKAGES=()

# Array of additional dependencies that are required to:
# * Build packages that are downstream of `revng` (e.g. `revng-ui`) or packages
#   which the typical developer is not expected to build (e.g.
#   llvm-documentation)
# * Required by CI script to perform CI-specific tasks (e.g. building the
#   `revng` image with podman)
# This is the set of packages which is installed by the CI
FULL_PACKAGES=()

#
# Base system tools
#
MINIMAL_PACKAGES+=(curl)
MINIMAL_PACKAGES+=(ca-certificates)
MINIMAL_PACKAGES+=(python3)
MINIMAL_PACKAGES+=(python3-pip)
MINIMAL_PACKAGES+=(python3-setuptools)
MINIMAL_PACKAGES+=(python3-yaml)
MINIMAL_PACKAGES+=(gawk)
MINIMAL_PACKAGES+=(ssh)
MINIMAL_PACKAGES+=(wget)
PACKAGES+=(jq)
PACKAGES+=(sed)
PACKAGES+=(zip)
PACKAGES+=(unzip)
FULL_PACKAGES+=(rsync)
FULL_PACKAGES+=(sudo)

#
# Basic build tools
#
MINIMAL_PACKAGES+=(cmake)
MINIMAL_PACKAGES+=(git)
MINIMAL_PACKAGES+=(libc-dev)
MINIMAL_PACKAGES+=(pkgconf)
PACKAGES+=(autoconf)
PACKAGES+=(automake)
PACKAGES+=(bison)
PACKAGES+=(build-essential)
PACKAGES+=(flex)
PACKAGES+=(g++-multilib)
PACKAGES+=(gettext)
PACKAGES+=(libtool)
PACKAGES+=(m4)
PACKAGES+=(texinfo)
PACKAGES+=(zlib1g-dev)

#
# revng-orchestra build dependencies
#
# This is needed for python-Levenshtein
MINIMAL_PACKAGES+=(python3-dev)

#
# llvm-documentation dependencies
#
FULL_PACKAGES+=(doxygen)
FULL_PACKAGES+=(graphviz)

#
# revng dependencies
#
MINIMAL_PACKAGES+=(doxygen)
MINIMAL_PACKAGES+=(shellcheck)

#
# repackage-apple-sdk dependencies
#
FULL_PACKAGES+=(p7zip-full)

#
# vs toolchains dependencies
#
PACKAGES+=(aria2)
PACKAGES+=(msitools)
PACKAGES+=(p7zip-full)
# winbind: `mspdb100.dll` tries to make some kind of connection that requires
# this package. Without it, the following command will fail:
#
#     orc install --test toolchain/win32-vc16/vc
#
PACKAGES+=(winbind)
PACKAGES+=("wine-devel-amd64=9.8~$UBUNTU_CODENAME-1")
PACKAGES+=("wine-devel-i386=9.8~$UBUNTU_CODENAME-1")
PACKAGES+=("wine-devel=9.8~$UBUNTU_CODENAME-1")
PACKAGES+=("winehq-devel=9.8~$UBUNTU_CODENAME-1")

#
# vscode-web runtime dependencies
#
FULL_PACKAGES+=(ripgrep)

#
# binary-archives-hook.sh dependencies
#
FULL_PACKAGES+=(s3cmd)
FULL_PACKAGES+=(podman)

#
# flamegraph.pl runtime dependencies
#
FULL_PACKAGES+=(perl)

#
# Needed by `revng mass-testing test-harness`
#
FULL_PACKAGES+=(time)

#
# Needed by `revng mass-testing generate-report`
#
FULL_PACKAGES+=(inkscape)


#
# Actual installation of packages
#
if [ "$INSTALL_TYPE" = "minimal" ]; then
  PACKAGES_TO_INSTALL=("${MINIMAL_PACKAGES[@]}")
elif [ "$INSTALL_TYPE" = "standard" ]; then
  PACKAGES_TO_INSTALL=("${MINIMAL_PACKAGES[@]}" "${PACKAGES[@]}")
elif [ "$INSTALL_TYPE" = "full" ]; then
  PACKAGES_TO_INSTALL=("${MINIMAL_PACKAGES[@]}" "${PACKAGES[@]}" "${FULL_PACKAGES[@]}")
else
  echo "Unknown install type: $INSTALL_TYPE" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get -qq update

if [[ "$INSTALL_TYPE" = "standard" || "$INSTALL_TYPE" = "full" ]]; then
  # Add the official wine APT repo for it to be installed later
  apt-get -qq install --no-install-recommends --yes ca-certificates wget
  dpkg --add-architecture i386
  mkdir -p /etc/apt/keyrings
  chmod 755 /etc/apt/keyrings
  wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key
  WINE_SOURCES="https://dl.winehq.org/wine-builds/ubuntu/dists/$UBUNTU_CODENAME/winehq-$UBUNTU_CODENAME.sources"
  wget -NP /etc/apt/sources.list.d/ "$WINE_SOURCES"
  apt-get -qq update
fi

apt-get -qq install --no-install-recommends --yes --allow-downgrades "${PACKAGES_TO_INSTALL[@]}"

# Install twine manually, as the version provided by the ubuntu
# repositories is too old
if [[ "$INSTALL_TYPE" = "full" ]]; then
  pip3 install twine
fi

# git-lfs on jammy is out-of-date, install it manually from the official github releases
if ! command -v git-lfs &> /dev/null; then
  LFS_URL="https://github.com/git-lfs/git-lfs/releases/download/v3.3.0/git-lfs-linux-amd64-v3.3.0.tar.gz"
  curl -sL "$LFS_URL" | tar -xzf - -C'/usr/local/bin' --strip-components=1 'git-lfs-3.3.0/git-lfs'
  echo "8c86bfbedd644e7b5d26c58bb858bc4478c5672b974d4a94cbc88cada4926b05 /usr/local/bin/git-lfs" | \
    sha256sum --quiet -c -
  git lfs install --skip-repo --system &> /dev/null
fi
