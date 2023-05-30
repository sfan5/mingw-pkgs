#!/bin/bash -eu

. ./common.sh
common_init "$@"

pkgver=13.2
pkgver_gmp=6.2.1
fetch_web "https://ftp.gnu.org/gnu/gdb/gdb-$pkgver.tar.xz" \
	fd5bebb7be1833abdb6e023c2f498a354498281df9d05523d8915babeb893f0a
unpack_tar "gdb-$pkgver.tar.xz" --strip-components=1
fetch_web "https://gmplib.org/download/gmp/gmp-$pkgver_gmp.tar.xz" \
	fd4829912cddd12f84181c3451cc752be224643e87fac497b69edddadc49b4f2
unpack_tar "gmp-$pkgver_gmp.tar.xz"

# include gmp statically for convenience reasons
mkdir -p gmp
pushd "gmp-$pkgver_gmp"
# (????)
CC=$MINGW_CC CC_FOR_BUILD=cc ./configure --host=$MINGW_PREFIX --prefix=/
make
make DESTDIR=$PWD/../gmp install
popd

>gdb/doc/gdb.texinfo # skip building documentation
CC=$MINGW_CC CXX=$MINGW_CXX ./configure --host=$MINGW_PREFIX --prefix=/ \
	--with-libgmp-prefix=$PWD/gmp \
	--disable-nls --disable-source-highlight
make

make DESTDIR=$INSTALL_DIR install
common_tidy

package $pkgver
