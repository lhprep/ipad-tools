#!/bin/bash

REV=1.0.6

if test -x "`which tput`"; then
  ncolors=`tput colors`
  if test -n "$ncolors" && test $ncolors -ge 8; then
    BOLD="$(tput bold)"
    UNDERLINE="$(tput smul)"
    STANDOUT="$(tput smso)"
    NORMAL="$(tput sgr0)"
    BLACK="$(tput setaf 0)"
    RED="$(tput setaf 1)"
    GREEN="$(tput setaf 2)"
    YELLOW="$(tput setaf 3)"
    BLUE="$(tput setaf 4)"
    MAGENTA="$(tput setaf 5)"
    CYAN="$(tput setaf 6)"
    WHITE="$(tput setaf 7)"
  fi
fi

echo -e "${BOLD}**** libimobiledevice stack build script for macOS, revision $REV ****${NORMAL}"

if test -z "$CFLAGS"; then
  SDKDIR=`xcrun --sdk macosx --show-sdk-path`
  TESTARCHS="arm64 x86_64"
  USEARCHS=
  for ARCH in $TESTARCHS; do
    if echo "int main(int argc, char **argv) { return 0; }" |clang -arch $ARCH -o /dev/null -isysroot $SDKDIR -x c - 2>/dev/null; then
      USEARCHS="$USEARCHS -arch $ARCH"
    fi
  done
  export CFLAGS="$USEARCHS -isysroot $SDKDIR"
else
  echo -e "${YELLOW}NOTE: Using externally defined CFLAGS. If that's not what you want, run: unset CFLAGS${NORMAL}"
fi

if test -z "$PREFIX"; then
  PREFIX="/usr/local"
else
  echo -e "${YELLOW}NOTE: Using externally defined PREFIX. If that's not what you want, run: unset PREFIX${NORMAL}"
fi
echo -e "${BOLD}PREFIX:${NORMAL} ${GREEN}$PREFIX${NORMAL}"

if ! test -w "$PREFIX"; then
  echo -e "${YELLOW}NOTE: During the process you will be asked for your password, this is to allow installation of the built libraries and tools via ${MAGENTA}sudo${YELLOW}.${NORMAL}"
fi

###########################################################
VERS=`sw_vers -productVersion`
VMAJ=`echo $VERS |cut -d "." -f 1`
VMIN=`echo $VERS |cut -d "." -f 2`

############# DEPENDENCY URLS AND FILE DATA ###############
# autoconf
AUTOCONF_URL=https://ftpmirror.gnu.org/gnu/autoconf/autoconf-2.69.tar.gz
AUTOCONF_HASH=562471cbcb0dd0fa42a76665acf0dbb68479b78a

# automake
AUTOMAKE_URL=https://ftpmirror.gnu.org/gnu/automake/automake-1.16.3.tar.gz
AUTOMAKE_HASH=b36e3877d961c1344351cc97b35b683a4dfadc0c

# libtool
LIBTOOL_URL=https://ftpmirror.gnu.org/gnu/libtool/libtool-2.4.6.tar.gz
LIBTOOL_HASH=25b6931265230a06f0fc2146df64c04e5ae6ec33

# cmake
if [ $VMAJ -le 10 ] && [ $VMIN -lt 13 ]; then
  if [ $VMIN -lt 10 ]; then
    # < macOS 10.10
    CMAKE_URL=https://github.com/Kitware/CMake/releases/download/v3.18.6/cmake-3.18.6-Darwin-x86_64.tar.gz
    CMAKE_HASH=fe09f28c2bfe26a7b7daf0ff9444175f410bae36
  else
    # >= macOS 10.10
    CMAKE_URL=https://github.com/Kitware/CMake/releases/download/v3.20.1/cmake-3.20.1-macos10.10-universal.tar.gz
    CMAKE_HASH=668e554a7fa7ad57eaf73d374774afd7fd25f98f
  fi
else
  # >= macOS 10.13
  CMAKE_URL=https://github.com/Kitware/CMake/releases/download/v3.20.1/cmake-3.20.1-macos-universal.tar.gz
  CMAKE_HASH=43cc6b91ca2ec711f3a1a3eafb970f9389e795e2
fi

# libzip
LIBZIP_FILENAME=libzip-1.7.1.tar.gz
LIBZIP_HASH=22a7a9b13357015275d017d0ca1b75e69abe1db9

# macFUSE
if [ $VMAJ -le 10 ] && [ $VMIN -lt 12 ]; then
  # <= macOS 10.11
  MFUSE_URL=https://github.com/osxfuse/osxfuse/releases/download/macfuse-4.0.5/macfuse-4.0.5.dmg
  MFUSE_HASH=2056c833aa8996d03748687bc938ba9805cc77a5
else
  # macOS >= 10.12
  MFUSE_URL=https://github.com/osxfuse/osxfuse/releases/download/macfuse-4.1.0/macfuse-4.1.0.dmg
  MFUSE_HASH=786ffd74d28d2c1098182c1baaf7dab752bf7432
fi

############# CHECK REQUIRED COMMANDS #####################
if test -x "`which shasum`"; then
  SHA1SUM="`which shasum`"
  SHA256SUM="$SHA1SUM -a 256"
elif test -x "`which sha1sum`"; then
  SHA1SUM="`which sha1sum`"
fi
if test -z "$SHA1SUM"; then
  echo -e "${RED}FATAL: no shasum or sha1sum found.${NORMAL}"
  exit 1
fi
if test -z "$SHA256SUM"; then
  if test -x "`which sha256sum`"; then
    SHA256SUM="`which sha256sum`"
  fi
fi
if test -z "$SHA256SUM"; then
  echo -e "${RED}FATAL: no sha256sum found.${NORMAL}"
  exit 1
fi
TESTCOMMANDS="strings dirname cut grep find curl tar gunzip git make sudo"
for TESTCMD in ${TESTCOMMANDS}; do
  if ! test -x "`which $TESTCMD`"; then
    echo -e "${RED}FATAL: Required command '$TESTCMD' is not available.${NORMAL}"
    exit 1
  fi
done

CURL="`which curl`"
if test -x "/usr/bin/curl" && test "$CURL" != "/usr/bin/curl"; then
  CURL=/usr/bin/curl
fi

BREW_OR_PORTS_INSTALL=
if test -x "`which brew`"; then
  BREW_OR_PORTS_INSTALL="brew install"
elif test -x "`which port`"; then
  BREW_OR_PORTS_INSTALL="sudo port install"
fi

BASEDIR=`pwd`
DEPSDIR="$BASEDIR/deps"
mkdir -p "$DEPSDIR"
cd "$DEPSDIR"
rm -f "*.log"

export PATH="$PATH:$DEPSDIR/bin"

echo -e "${CYAN}######## INSTALLING REQUIRED TOOLS AND DEPENDENCIES ########${NORMAL}"

#################### autoconf ####################
if ! test -x "`which autoconf`"; then
  echo -e "${BOLD}*** Installing autoconf (in-tree)${NORMAL}"
  if test -z "$BREW_OR_PORTS_INSTALL"; then
    AUTOCONF_TGZ=`basename $AUTOCONF_URL`
    HASH=`$SHA1SUM "$AUTOCONF_TGZ" 2>/dev/null |cut -d " " -f 1`
    if test -z "$HASH" || test "$HASH" != "$AUTOCONF_HASH"; then
      echo "-- downloading autoconf"
      $CURL -Ls -o $AUTOCONF_TGZ $AUTOCONF_URL || exit 1
      HASH=`$SHA1SUM "$AUTOCONF_TGZ" 2>/dev/null |cut -d " " -f 1`
      if test -z "$HASH" || test "$HASH" != "$AUTOCONF_HASH"; then
        echo -e "${RED}FATAL: hash mismatch for $AUTOCONF_TGZ${NORMAL}"
        exit 1
      fi
    fi
    tar xzf $AUTOCONF_TGZ
    cd `basename $AUTOCONF_TGZ .tar.gz`
    echo "-- configuring autoconf"
    ./configure --prefix="$DEPSDIR" >> ../autoconf-configure.log || exit 1
    echo "-- building autoconf"
    make clean > /dev/null
    make >> ../autoconf-make.log|| exit 1
    echo "-- installing autoconf (in-tree)"
    make install >> ../autoconf-make_install.log || exit 1
    cd $DEPSDIR
  else
    $BREW_OR_PORTS_INSTALL autoconf || exit 1
  fi
  echo -e "${BOLD}* autoconf: ${GREEN}done${NORMAL}"
else
  echo -e "${BOLD}* autoconf: ${GREEN}found${NORMAL}"
fi

#################### automake ####################
if ! test -x "`which automake`"; then
  echo -e "${BOLD}*** Installing automake (in-tree)${NORMAL}"
  if test -z "$BREW_OR_PORTS_INSTALL"; then
    AUTOMAKE_TGZ=`basename $AUTOMAKE_URL`
    HASH=`$SHA1SUM "$AUTOMAKE_TGZ" 2>/dev/null |cut -d " " -f 1`
    if test -z "$HASH" || test "$HASH" != "$AUTOMAKE_HASH"; then
      echo "-- Downloading automake"
      $CURL -Ls -o $AUTOMAKE_TGZ $AUTOMAKE_URL || exit 1
      HASH=`$SHA1SUM "$AUTOMAKE_TGZ" 2>/dev/null |cut -d " " -f 1`
      if test -z "$HASH" || test "$HASH" != "$AUTOMAKE_HASH"; then
        echo -e "${RED}FATAL: hash mismatch for $AUTOMAKE_TGZ${NORMAL}"
        exit 1
      fi
    fi
    tar xzf $AUTOMAKE_TGZ
    cd `basename $AUTOMAKE_TGZ .tar.gz`
    echo "-- Configuring automake"
    ./configure --prefix="$DEPSDIR" >> ../automake-configure.log || exit 1
    echo "-- Building automake"
    make clean > /dev/null
    make >> ../automake-make.log || exit 1
    echo "-- Installing automake (in-tree)"
    make install >> ../automake-make_install.log || exit 1
    cd $DEPSDIR
  else
    $BREW_OR_PORTS_INSTALL automake || exit 1
  fi
  echo -e "${BOLD}* automake: ${GREEN}done${NORMAL}"
else
  echo -e "${BOLD}* automake: ${GREEN}found${NORMAL}"
fi

#################### libtool ####################
if ! test -x "`which libtool`" || ! test -x "`which libtoolize`" -o -x "`which glibtoolize`"; then
  echo -e "${BOLD}*** Installing libtool (in-tree)${NORMAL}"
  if test -z "$BREW_OR_PORTS_INSTALL"; then
    LIBTOOL_TGZ=`basename $LIBTOOL_URL`
    HASH=`$SHA1SUM "$LIBTOOL_TGZ" 2>/dev/null |cut -d " " -f 1`
    if test -z "$HASH" || test "$HASH" != "$LIBTOOL_HASH"; then
      echo "-- Downloading libtool"
      $CURL -Ls -o $LIBTOOL_TGZ $LIBTOOL_URL || exit 1
      HASH=`$SHA1SUM "$LIBTOOL_TGZ" 2>/dev/null |cut -d " " -f 1`
      if test -z "$HASH" || test "$HASH" != "$LIBTOOL_HASH"; then
        echo -e "${RED}FATAL: hash mismatch for $LIBTOOL_TGZ${NORMAL}"
        exit 1
      fi
    fi
    tar xzf $LIBTOOL_TGZ
    cd `basename $LIBTOOL_TGZ .tar.gz`
    echo "-- Configuring libtool"
    ./configure --prefix="$DEPSDIR" >> ../libtool-configure.log || exit 1
    echo "-- Building libtool"
    make clean > /dev/null
    make >> ../libtool-make.log|| exit 1
    echo "-- Installing libtool (in-tree)"
    make install >> ../libtool-make_install.log || exit 1
    cd $DEPSDIR
  else
    $BREW_OR_PORTS_INSTALL libtool || exit 1
  fi
  echo -e "${BOLD}* libtool: ${GREEN}done${NORMAL}"
else
  echo -e "${BOLD}* libtool: ${GREEN}found${NORMAL}"
fi

TESTCOMMANDS="autoconf automake libtool" # pkg-config"
for TESTCMD in ${TESTCOMMANDS}; do
  if ! test -x "`which $TESTCMD`"; then
    echo -e "${RED}FATAL: required ${BOLD}$TESTCMD${RED} not found. Please install manually.${NORMAL}"
    err_cmd="$err_cmd $TESTCMD"
  fi
done
if test -n "$err_cmd"; then
  exit 1
fi

ACLOCALDIR=$(dirname `automake --print-libdir`)/aclocal
if ! test -f ${ACLOCALDIR}/pkg.m4; then
  $CURL -Ls -o "$DEPSDIR/pkg.m4" https://raw.githubusercontent.com/pkgconf/pkgconf/master/pkg.m4 || exit 1
  if test -w ${ACLOCALDIR}; then
    cp "$DEPSDIR/pkg.m4" "${ACLOCALDIR}/pkg.m4"
  else
    $INSTALL_SUDO cp "$DEPSDIR/pkg.m4" "${ACLOCALDIR}/pkg.m4"
  fi
  rm -f "$DEPSDIR/pkg.m4"
fi

############## CMAKE for building libzip ####################
if ! test -x "`which cmake`"; then
  echo -e "${BOLD}*** Installing cmake (in-tree)${NORMAL}"
  CMAKE_TGZ=`basename $CMAKE_URL`
  HASH=`$SHA1SUM "$CMAKE_TGZ" 2>/dev/null |cut -d " " -f 1`
  if test -z "$HASH" || test "$HASH" != "$CMAKE_HASH"; then
    echo "-- Downloading cmake"
    $CURL -Ls -o "$CMAKE_TGZ" "$CMAKE_URL" || exit 1
  fi
  CMAKE_PATH="$DEPSDIR/`basename $CMAKE_TGZ .tar.gz`/CMake.app/Contents/bin"
  CMAKE_BIN="$CMAKE_PATH/cmake"
  if ! test -x "$CMAKE_BIN"; then
    echo "-- Extracting cmake (in tree)"
    tar xzf "$CMAKE_TGZ"
  fi
  echo "-- Updating \$PATH"
  export PATH="$PATH:$CMAKE_PATH"
  if ! test -x "`which cmake`"; then
    echo -e "${RED}FATAL: cmake not found in \$PATH after trying to install it locally?!${NORMAL}"
    exit 1
  fi
  echo -e "${BOLD}* cmake: ${GREEN}done${NORMAL}"
else
  echo -e "${BOLD}* cmake: ${GREEN}found${NORMAL}"
fi

############ lzma headers for libzip #############
if ! test -f "$DEPSDIR/xz-5.0.5/src/liblzma/api/lzma.h"; then
  echo -e "${BOLD}*** Installing lzma headers (in-tree)${NORMAL}"
  XZ_URL=https://sourceforge.net/projects/lzmautils/files/xz-5.0.5.tar.gz/download
  XZ_HASH=26fec2c1e409f736e77a85e4ab314dc74987def0
  XZ_TGZ="xz-5.0.5.tar.gz"
  HASH=`$SHA1SUM "$XZ_TGZ" 2>/dev/null |cut -d " " -f 1`
  if test -z "$HASH" || test "$HASH" != "$XZ_HASH"; then
    echo "-- Downloading xz"
    $CURL -Ls "$XZ_URL" > "$XZ_TGZ" || exit 1
  fi
  echo "-- Extracting xz"
  tar xzf "$XZ_TGZ"
  LZMA_INCLUDES="$DEPSDIR/xz-5.0.5/src/liblzma/api"
  if ! test -f "$LZMA_INCLUDES/lzma.h"; then
    echo -e "${RED}FATAL: lzma.h not found${NORMAL}"
    exit 1
  fi
  echo -e "${BOLD}* lzma headers: ${GREEN}done${NORMAL}"
else
  echo -e "${BOLD}* lzma headers: ${GREEN}found${NORMAL}"
fi

############ libzip ###################
LIBZIP_DIR=`basename $LIBZIP_FILENAME .tar.gz`
if ! test -f $DEPSDIR/$LIBZIP_DIR/build/lib/libzip.a; then
  echo -e "${BOLD}*** Installing libzip (static, in-tree)${NORMAL}"
  HASH=`$SHA1SUM "LIBZIP_FILENAME" 2>/dev/null |cut -d " " -f 1`
  if test -z "$HASH" || test "$HASH" != "$LIBZIP_HASH"; then
    echo "-- Downloading libzip"
    $CURL -Ls "https://libzip.org/download/$LIBZIP_FILENAME" > "$LIBZIP_FILENAME" || exit 1
  fi
  echo "-- Extracting libzip"
  tar xzf "$LIBZIP_FILENAME"
  if test -z "$SDKDIR"; then
    SDKDIR=`xcrun --sdk macosx --show-sdk-path`
  fi
  CURDIR=`pwd`
  cd "$LIBZIP_DIR"
  rm -rf build
  mkdir build
  cd build
  echo "-- Configuring libzip (cmake)"
  cmake -DCMAKE_OSX_SYSROOT="${SDKDIR}" -DBUILD_SHARED_LIBS=OFF -DBUILD_DOC=OFF -DBUILD_EXAMPLES=OFF -DBUILD_REGRESS=OFF -DBUILD_TOOLS=OFF -DCMAKE_POLICY_DEFAULT_CMP0063=NEW -DCMAKE_LIBRARY_PATH="$SDKDIR/usr/lib" -DLIBLZMA_INCLUDE_DIR="$LZMA_INCLUDES" .. >> ../../libzip-cmake.log || exit 1
  echo "-- Bulding libzip"
  make clean > /dev/null
  make >> ../../libzip-make.log || exit 1
  cd "$CURDIR"
  echo -e "${BOLD}* libzip: ${GREEN}done${NORMAL}"
else
  echo -e "${BOLD}* libzip: ${GREEN}found${NORMAL}"
fi
LIBZIP_CFLAGS="-I$DEPSDIR/$LIBZIP_DIR/lib -I$DEPSDIR/$LIBZIP_DIR/build"
LIBZIP_LIBS="$DEPSDIR/$LIBZIP_DIR/build/lib/libzip.a -Xlinker /usr/lib/libbz2.dylib -Xlinker /usr/lib/liblzma.dylib -lz"

############ LibreSSL ##############
if ! test -f "$LIBCRYPTO" || ! test -f "$LIBSSL"; then
  mkdir -p lib
  if ! test -f "lib/libssl.35.tbd"; then
    $CURL -o "lib/libssl.35.tbd" -Ls \
        https://gist.github.com/nikias/94c99fd145a75a5104415e5117b0cafa/raw/5209dfbff5a871a14272afe4794e76eb4cf6f062/libssl.35.tbd || exit 1
  fi
  if ! test -f "lib/libcrypto.35.tbd"; then
    $CURL -o "lib/libcrypto.35.tbd" -Ls \
        https://gist.github.com/nikias/94c99fd145a75a5104415e5117b0cafa/raw/5209dfbff5a871a14272afe4794e76eb4cf6f062/libcrypto.35.tbd || exit 1
  fi
  LIBSSL=$DEPSDIR/lib/libssl.35.tbd
  LIBCRYPTO=$DEPSDIR/lib/libcrypto.35.tbd
  LIBRESSL_VER=2.2.7
fi

if ! test -f "$LIBCRYPTO"; then
  echo -e "${RED}ERROR: Could not find $LIBCRYPTO. Cannot continue.${NORMAL}"
  exit 1
else
  echo -e "${BOLD}* LibreSSL `basename $LIBSSL`: ${GREEN}found${NORMAL}"
fi

if ! test -f "$LIBSSL"; then
  echo -e "${RED}ERROR: Could not find $LIBSSL. Cannot continue.${NORMAL}"
  exit 1
else
  echo -e "${BOLD}* LibreSSL `basename $LIBCRYPTO`: ${GREEN}found${NORMAL}"
fi

if test -z "$LIBRESSL_VER"; then
  if LIBRESSL_VER_TMP=`strings "$LIBCRYPTO" |grep "^LibreSSL .\..\.."`; then
    LIBRESSL_VER=`echo $LIBRESSL_VER_TMP |cut -d " " -f 2`
  fi
fi
echo "  ${YELLOW}LibreSSL version requirment: $LIBRESSL_VER${NORMAL}"
if ! test -f "$DEPSDIR/libressl-$LIBRESSL_VER/include/openssl/opensslv.h"; then
  echo -e "${BOLD}*** Installing LibreSSL headers (in-tree)${NORMAL}"
  rm -rf libressl-$LIBRESSL_VER
  FILENAME="libressl-$LIBRESSL_VER.tar.gz"
  $CURL -Ls "https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/SHA256" > "libressl.sha256.txt" || exit 1
  CHKSUM=`cat "libressl.sha256.txt" |grep "($FILENAME)" |cut -d " " -f 4`
  rm -f "libressl.sha256.txt"
  if test -z "$CHKSUM"; then
    echo -e "${RED}ERROR: Failed to get checksum from server for $FILENAME${NORMAL}"
    exit 1
  fi
  if test -f "$FILENAME"; then
    CALCSUM=`$SHA256SUM "$FILENAME" |cut -d " " -f 1`
  fi
  if test -z "$CALCSUM" -o "$CALCSUM" != "$CHKSUM"; then
    echo "-- Downloading $FILENAME${NORMAL}"
    $CURL -Ls "https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/$FILENAME" > "$FILENAME" || exit 1
    CALCSUM=`$SHA256SUM "$FILENAME" |cut -d " " -f 1`
    if test "$CALCSUM" != "$CHKSUM"; then
      echo -e "${RED}ERROR: Failed to verify $FILENAME (checksum mismatch).${NORMAL}"
      exit 1
    fi
  else
    echo "-- Using cached $FILENAME"
  fi
  echo "-- Extracting $FILENAME"
  tar xzf "$FILENAME" || exit 1
  echo -e "${BOLD}* LibreSSL headers: ${GREEN}done${NORMAL}"
else
  echo -e "${BOLD}* LibreSSL headers: ${GREEN}found${NORMAL}"
fi
cd "$BASEDIR"

############ macFUSE ##############
HAVE_MACFUSE=no
if ! test -f "/usr/local/lib/libfuse.dylib" || ! test -f "/usr/local/include/fuse/fuse.h"; then
  INSTALL_MACFUSE=no
  if test -n "$DONTASK"; then
    INSTALL_MACFUSE=yes
  else
    read -r -p "${BOLD}Install macFUSE? This is required for ifuse to work. [Y/n]${NORMAL} " response
    case "$response" in
      [yY][eE][sS]|[yY]|"")
        INSTALL_MACFUSE=yes
        ;;
      *)
        INSTALL_MACFUSE=no
        ;;
    esac
  fi
  if test "$INSTALL_MACFUSE" == "yes"; then
    echo -e "${BOLD}*** Installing macFUSE${NORMAL}"
    MFUSE_DMG=$DEPSDIR/`basename $MFUSE_URL`
    HASH=`$SHA1SUM "$MFUSE_DMG" 2>/dev/null |cut -d " " -f 1`
    if test -z "$HASH" || test "$HASH" != "$MFUSE_HASH"; then
      echo "-- Downloading macFUSE"
      $CURL -Ls -o "$MFUSE_DMG" "$MFUSE_URL" || exit 1
    fi
    hdiutil attach "$MFUSE_DMG" -quiet || exit 1
    MOUNTP="/Volumes/macFUSE"
    INSTPKG="$MOUNTP/Install macFUSE.pkg"
    echo "-- Installing macFUSE (runs with sudo, enter your password when asked for it)"
    sudo /usr/sbin/installer -pkg "$INSTPKG" -target /
    INSTRES=$?
    hdiutil detach "$MOUNTP" -quiet
    if test $INSTRES != 0; then exit 1; fi
    echo -e "${BOLD}* macFUSE: ${GREEN}done${NORMAL}"
    HAVE_MACFUSE=yes
  else
    echo "Skipping installation of macFUSE."
  fi
else
  echo -e "${BOLD}* macFUSE: ${GREEN}found${NORMAL}"
  HAVE_MACFUSE=yes
fi



#############################################################################
COMPONENTS="
  libplist:master \
  libusbmuxd:master \
  libimobiledevice:master  \
  libirecovery:master \
  idevicerestore:master \
  libideviceactivation:master \
  ideviceinstaller:master \
"
if test "$HAVE_MACFUSE" == "yes"; then
  COMPONENTS="$COMPONENTS ifuse:master"
fi
if test -z "$NO_CLONE"; then
echo
echo -e "${CYAN}######## UPDATING SOURCES ########${NORMAL}"
echo
for I in $COMPONENTS; do
  COMP=`echo $I |cut -d ":" -f 1`;
  CVER=`echo $I |cut -d ":" -f 2`;
  rm -rf $COMP
  if test "$CVER" != "master"; then
    echo "Cloning $COMP (release $CVER)";
    git clone --depth 1 -b $CVER https://github.com/libimobiledevice/$COMP 2>/dev/null || (echo "Failed to clone $COMP" ; exit 1)
  else
    echo "Cloning $COMP (master)";
    git clone --depth 1 https://github.com/libimobiledevice/$COMP 2>/dev/null || (echo "Failed to clone $COMP" ; exit 1)
  fi
done
fi

#############################################################################
echo
echo -e "${CYAN}######## STARTING BUILD ########${NORMAL}"
echo
#############################################################################
CURDIR=`pwd`

export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
INSTALL_SUDO=
POSTINSTALL=
if ! test -w $PREFIX; then
  INSTALL_SUDO="sudo"
fi

#############################################################################
echo -e "${BOLD}#### Building libplist ####${NORMAL}"
cd libplist
./autogen.sh --prefix="$PREFIX" --without-cython || exit 1
make || exit 1
$INSTALL_SUDO make install || exit 1
LIBPLIST_CFLAGS="-I$PREFIX/include"
LIBPLIST_LIBS="-L$PREFIX/lib -lplist-2.0"
cd "$CURDIR"

#############################################################################
echo -e "${BOLD}#### Building libusbmuxd ####${NORMAL}"
cd libusbmuxd
./autogen.sh --prefix="$PREFIX" libplist_CFLAGS="$LIBPLIST_CFLAGS" libplist_LIBS="$LIBPLIST_LIBS" || exit 1
make || exit 1
$INSTALL_SUDO make install || exit 1
LIBUSBMUXD_CFLAGS="-I$PREFIX/include"
LIBUSBMUXD_LIBS="-L$PREFIX/lib -lusbmuxd-2.0"
cd "$CURDIR"

#############################################################################
echo -e "${BOLD}#### Building libimobiledevice ####${NORMAL}"
cd libimobiledevice
./autogen.sh --prefix="$PREFIX" --enable-debug --without-cython openssl_CFLAGS="-I$DEPSDIR/libressl-$LIBRESSL_VER/include" openssl_LIBS="-Xlinker $LIBSSL -Xlinker $LIBCRYPTO" libplist_CFLAGS="$LIBPLIST_CFLAGS" libplist_LIBS="$LIBPLIST_LIBS" libusbmuxd_CFLAGS="$LIBUSBMUXD_CFLAGS" libusbmuxd_LIBS="$LIBUSBMUXD_LIBS" || exit 1
make || exit 1
$INSTALL_SUDO make install || exit 1
LIMD_CFLAGS="-I$PREFIX/include"
LIMD_LIBS="-L$PREFIX/lib -limobiledevice-1.0 -lplist-2.0"
cd "$CURDIR"

#############################################################################
echo -e "${BOLD}#### Building libirecovery ####${NORMAL}"
cd libirecovery
./autogen.sh --prefix="$PREFIX" || exit 1
make || exit 1
$INSTALL_SUDO make install || exit 1
IRECV_CFLAGS="-I$PREFIX/include"
IRECV_LIBS="-L$PREFIX/lib -lirecovery-1.0"
cd "$CURDIR"

#############################################################################
echo -e "${BOLD}#### Building idevicerestore ####${NORMAL}"
cd idevicerestore
./autogen.sh --prefix="$PREFIX" openssl_CFLAGS="-I$DEPSDIR/libressl-$LIBRESSL_VER/include" openssl_LIBS="-Xlinker $LIBSSL -Xlinker $LIBCRYPTO" libcurl_CFLAGS="-I$SDKDIR/usr/include" libcurl_LIBS="-lcurl" libzip_CFLAGS="$LIBZIP_CFLAGS" libzip_LIBS="$LIBZIP_LIBS" zlib_CFLAGS="-I$SDKDIR/usr/include" zlib_LIBS="-lz" libimobiledevice_CFLAGS="$LIMD_CFLAGS" libimobiledevice_LIBS="$LIMD_LIBS" libirecovery_CFLAGS="$IRECV_CFLAGS" libirecovery_LIBS="$IRECV_LIBS" libplist_CFLAGS="$LIBPLIST_CFLAGS" libplist_LIBS="$LIBPLIST_LIBS" || exit 1
make || exit 1
$INSTALL_SUDO make install || exit 1
cd "$CURDIR"

#############################################################################
echo -e "${BOLD}#### Building libideviceactivation ####${NORMAL}"
cd libideviceactivation
./autogen.sh --prefix="$PREFIX" libcurl_CFLAGS="-I$SDKDIR/usr/include" libcurl_LIBS="-lcurl" libxml2_CFLAGS="-I$SDKDIR/usr/include" libxml2_LIBS="-lxml2" libimobiledevice_CFLAGS="$LIMD_CFLAGS" libimobiledevice_LIBS="$LIMD_LIBS" libplist_CFLAGS="$LIBPLIST_CFLAGS" libplist_LIBS="$LIBPLIST_LIBS" || exit 1
cd "$CURDIR"

#############################################################################
echo -e "${BOLD}#### Building ideviceinstaller ####${NORMAL}"
cd ideviceinstaller
./autogen.sh --prefix="$PREFIX" libzip_CFLAGS="$LIBZIP_CFLAGS" libzip_LIBS="$LIBZIP_LIBS" libimobiledevice_CFLAGS="$LIMD_CFLAGS" libimobiledevice_LIBS="$LIMD_LIBS" libplist_CFLAGS="$LIBPLIST_CFLAGS" libplist_LIBS="$LIBPLIST_LIBS" || exit 1
make || exit 1
$INSTALL_SUDO make install || exit 1
cd "$CURDIR"

#############################################################################
if test "$HAVE_MACFUSE" == "yes"; then
  echo -e "${BOLD}#### Building ifuse ####${NORMAL}"
  cd ifuse
  ./autogen.sh --prefix="$PREFIX" libfuse_CFLAGS="-I/usr/local/include/fuse -D_FILE_OFFSET_BITS=64" libfuse_LIBS="-L/usr/local/lib -lfuse -pthread" libimobiledevice_CFLAGS="$LIMD_CFLAGS" libimobiledevice_LIBS="$LIMD_LIBS" libplist_CFLAGS="$LIBPLIST_CFLAGS" libplist_LIBS="$LIBPLIST_LIBS" || exit 1
  make || exit 1
  $INSTALL_SUDO make install || exit 1
  cd "$CURDIR"
fi

#############################################################################
echo
echo -e "${CYAN}######## BUILD COMPLETE ########${NORMAL}"
echo
#############################################################################

