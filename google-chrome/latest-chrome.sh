#!/bin/bash
# latest-chrome Version 1.0RC8

# This script will find the latest Google Chrome binary package,
# download it and repackage it into Slackware format.

# I don't use Chrome for regular browsing but it is handy for
# comparative tests against Opera. :P

# Copyright 2013 Ruari Oedegaard, Olso, Norway
# All rights reserved.
#
# Redistribution and use of this script, with or without modification, is
# permitted provided that the following conditions are met:
#
# 1. Redistributions of this script must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# HOLDER BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# Use the architecture of the current machine or whatever the user has
# set externally
ARCH=${ARCH:-$(uname -m)}

if [ "$ARCH" = "x86_64" ]; then
  LIBDIRSUFFIX="64"
elif [[ "$ARCH" = i?86 ]]; then
  ARCH=i386
  LIBDIRSUFFIX=""
else
  echo "The architecture $ARCH is not supported." >&2
  exit 1
fi

# Work out the latest stable Google Chrome if VERSION is unset
VERSION=${VERSION:-$(wget -qO- https://dl.google.com/linux/direct/google-chrome-stable_current_i386.rpm | head -c96 | strings | rev | awk -F"[:-]" '/emorhc/ { print $1 "-" $2 }' | rev)}

# Error out if $VERISON is unset, e.g. because previous command failed
if [ -z $VERSION ]; then
  echo "Could not work out the latest version; exiting" >&2
  exit 1
fi

if echo $VERSION | grep -Fq '-'; then
  GOOGLEREVISION=${VERSION#*-}
  VERSION=${VERSION%-*}
else
  GOOGLEREVISION=""
fi

# Don't start repackaging if the same version is already installed
if /bin/ls /var/log/packages/google-chrome-$VERSION-* >/dev/null 2>&1 ; then
  echo "Google Chrome ($VERSION) is already installed; exiting"
  exit 0
fi

CWD=$(pwd)
TMP=${TMP:-/tmp}
OUTPUT=${OUTPUT:-/tmp}
BUILD=${BUILD:-1}
TAG=${TAG:-ro}
PKGTYPE=${PKGTYPE:-tgz}
PACKAGE="$OUTPUT/google-chrome-$VERSION-$ARCH-$BUILD$TAG.$PKGTYPE"

# If the package was made previously, no need to make it again. ;)
if [ -e "$PACKAGE" ]; then
  echo "$PACKAGE already exists; exiting"
  exit 0
fi

REPACKDIR=$TMP/repackage-google-chrome

# Define this script's name as we will copy into doc directory later on
SCRIPT="${0##*/}"

# This function can be used in place of Slackware's makepkg, with the
# added bonus that it is able to make packages with root owned files
# even when run as a regular user.
makepkg() {

  # Handle Slackware's makepkg options
  while [ 0 ]; do
    if [ "$1" = "-p" -o "$1" = "--prepend" ]; then
      # option ignored, links are always prepended
      shift 1
    elif [ "$1" = "--linkadd" -o "$1" = "-l" ]; then
      if [ "$2" = "n" ]; then
        echo "\"$1 $2\" ignored, links are always converted" >&2
      fi
      shift 2
    elif [ "$1" = "--chown" -o "$1" = "-c" ]; then
      SETPERMS="$2"
      shift 2
    else
      break
    fi
  done

  # Change any symlinks into shell script code
  find * -type l -printf '( cd %h ; rm -rf %f )\n( cd %h ; ln -sf %l %f )\n' -delete > doinst.symlinks
  if grep -q . doinst.symlinks; then
    mkdir -p install
    mv doinst.symlinks install/.
  else
    rm -f doinst.symlinks
  fi

  # Prepend symlink shell script to doinst.sh
  if [ -e install/doinst.sh -a -e install/doinst.symlinks ]; then
    printf "\n" | cat - install/doinst.sh >> install/doinst.symlinks
  fi
  if [ -e install/doinst.symlinks ]; then
    mv install/doinst.symlinks install/doinst.sh
  fi

  # Reset permissions and ownership
  if [ "${SETPERMS:-y}" = "y" ]; then
    find . -type d -exec chmod 755 {} \;
    TAROWNER="--group 0 --owner 0"
  else
    TAROWNER=""
  fi

  # Create package using tar 1.13 directory formatting
  tar $TAROWNER --format=gnu --transform="s,^\./\(.\),\1," --show-stored-names -cavvf "$1" .
  echo "Slackware package $1 created."

}

# Since packaging is about to begin errors become more important now,
# so exit if things fail.
set -eu

# If the repackage is already present from the past, clear it down
# and re-create it.
if [ -d "$REPACKDIR" ]; then
  rm -fr "$REPACKDIR"
fi

mkdir -p "$REPACKDIR"/{pkg/install,src}

# Save a copy if this script but remove execute persmissions as it will
# larer be moved into the doc directory.
install -m 644 "${0}" "$REPACKDIR/src/$SCRIPT"

# Check if the current directory contains the correct Google Chrome
# binary package, otherwise download it. Then check that it matches the
# version number defined.
if [ -e google-chrome-stable-${VERSION}-${GOOGLEREVISION}.${ARCH}.rpm ]; then
  (
    cd "$REPACKDIR/src/"
    ln -s "$CWD/google-chrome-stable-${VERSION}-${GOOGLEREVISION}.${ARCH}.rpm" google-chrome-stable-${VERSION}-${GOOGLEREVISION}.${ARCH}.rpm
  )
else
  echo "Downloading Google Chrome ${VERSION} for ${ARCH}"
  if echo $GOOGLEREVISION | grep -q .; then
    wget https://dl.google.com/linux/chrome/rpm/stable/${ARCH}/google-chrome-stable-${VERSION}-${GOOGLEREVISION}.${ARCH}.rpm -P "$REPACKDIR/src/"
  else
    wget https://dl.google.com/linux/direct/google-chrome-stable_current_${ARCH}.rpm -O "$REPACKDIR/src/google-chrome-stable_current_${ARCH}.rpm"
    DOWNLOADVERSION=$(head -c96 "$REPACKDIR/src/google-chrome-stable_current_${ARCH}.rpm" | strings | rev | awk -F"[:-]" '/emorhc/ { print $2 }' | rev)
    if [ ! "$VERSION" = "$DOWNLOADVERSION" ]; then
      echo "The version downloaded ($DOWNLOADVERSION) is different from the version defined ($VERSION)" >&2
      exit 1
    fi
  fi
fi

# Now we have all the sources in place, switch to the package directory
# and start setting things up.
cd "$REPACKDIR/pkg"

# Extract the contents of the Google Chrome binary package
if [ -x /usr/bin/bsdtar ]; then
  bsdtar xf ../src/google-chrome-stable*${ARCH}.rpm
elif [ -x /usr/bin/rpm2cpio ]; then
  rpm2cpio ../src/google-chrome-stable*${ARCH}.rpm | cpio --quiet -id
else
  # Since the user has not installed libarchive or rpm, use a hack to extract the rpm contents
  RPMHDRLGTH=$(LANG=C grep -abom1 '.7zXZ\|BZh9' ../src/google-chrome-stable*${ARCH}.rpm)
  case "$RPMHDRLGTH" in
    *7zXZ) COMPRESSOR=xz ;;
    *BZh9) COMPRESSOR=bzip2 ;;
    *)     echo "Unknown compression type in rpm!" >&2; exit 1 ;;
  esac
  tail -c+$[${RPMHDRLGTH%:*}+1] ../src/google-chrome-stable*${ARCH}.rpm | $COMPRESSOR -d | cpio --quiet -id
fi

# Remove ./etc as it contains a cron job for updating rpm systems
rm -fr etc

# Move any man directories to the correct Slackware location
if [ -d usr/share/man ]; then
  mv usr/share/man usr/
fi

# Compress any uncompressed man pages
find usr/man -type f -name "*.1" -exec gzip -9 {} \;
for link in $(find usr/man -type l) ; do
  ln -s $(readlink $link).gz $link.gz
  rm $link
done

# Move any doc directory to the correct Slackware location
if [ -d usr/share/doc ]; then
  mv usr/share/doc usr/
  find usr/doc -type d -name "google-chrome*" -maxdepth 1 -exec mv {} usr/doc/tmp \;
fi
mkdir -p usr/doc/tmp
mv usr/doc/tmp usr/doc/google-chrome-$VERSION

# Copy this script into the doc directory
cp ../src/$SCRIPT usr/doc/google-chrome-$VERSION/$SCRIPT

# Replace google-chrome executable symlink, with a relative one
if [ -h usr/bin/google-chrome ]; then
  rm usr/bin/google-chrome
  (
    cd usr/bin
    ln -fs ../../opt/google/chrome/google-chrome google-chrome
  )
fi

# Symlink desktop file
if [ ! -e usr/share/applications/google-chrome.desktop ]; then
  mkdir -p usr/share/applications
  (
    cd usr/share/applications
    ln -s ../../../opt/google/chrome/google-chrome.desktop google-chrome.desktop
  )
fi

# Symlink desktop environment icons
for png in opt/google/chrome/product_logo_*.png; do
  pngsize="${png##*/product_logo_}"
  mkdir -p usr/share/icons/hicolor/${pngsize%.png}x${pngsize%.png}/apps
  (
    cd usr/share/icons/hicolor/${pngsize%.png}x${pngsize%.png}/apps/
    ln -s ../../../../../../opt/google/chrome/product_logo_${pngsize} google-chrome.png
  )
done

# Now create the post-install to register the desktop file and icons.
cat <<EOS> install/doinst.sh
# Setup menu entries
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database -q usr/share/applications
fi

# Setup icons
touch -c usr/share/icons/hicolor
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -tq usr/share/icons/hicolor
fi
EOS

# Create a description file inside the package.
cat <<EOD> install/slack-desc
               |-----handy-ruler------------------------------------------------------|
google-chrome: google-chrome (Google Chrome web browser)
google-chrome:
google-chrome: Google Chrome is a web browser that combines a minimal design with
google-chrome: sophisticated technology to make the web faster, safer, and easier.
google-chrome:
google-chrome:
google-chrome:
google-chrome:
google-chrome:
google-chrome: Homepage:  http://www.google.com/chrome
google-chrome:
EOD

# Make sure the file permissions are ok
chmod -R u+w,go+r-w,a-s .

# chrome-sandbox needs to be setuid root for Google Chrome to run
chmod 4711 opt/google/chrome/chrome-sandbox

# Create the Slackware package
makepkg --linkadd y --prepend --chown y "$PACKAGE"
